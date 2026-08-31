import CoreLocation
import Foundation
import MapKit
import WeatherKit

// MARK: - MapKit

nonisolated struct FamiliarMapPlace: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let phoneNumber: String?
    let url: String?
}

@MainActor
protocol FamiliarMapServicing: AnyObject, Sendable {
    func search(query: String, near: FamiliarLocationSnapshot?, limit: Int) async throws -> [FamiliarMapPlace]
}

@MainActor
final class FamiliarMapService: FamiliarMapServicing, @unchecked Sendable {
    func search(query: String, near: FamiliarLocationSnapshot?, limit: Int) async throws -> [FamiliarMapPlace] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw FamiliarAppleNativeToolError.emptyQuery }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = normalized
        if let near {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude),
                latitudinalMeters: 100_000,
                longitudinalMeters: 100_000
            )
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(min(max(limit, 1), 10)).map { item in
            let coordinate = item.placemark.coordinate
            let name = item.name ?? item.placemark.title ?? normalized
            return FamiliarMapPlace(
                id: "\(coordinate.latitude),\(coordinate.longitude):\(name)",
                name: name,
                address: item.placemark.title,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                phoneNumber: item.phoneNumber,
                url: item.url?.absoluteString
            )
        }
    }
}

nonisolated struct FamiliarMapSearchTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let query: String
        let limit: Int?
        let nearLatitude: Double?
        let nearLongitude: Double?
    }

    let service: any FamiliarMapServicing
    let manifest = FamiliarToolManifest(
        name: "map_search",
        title: "搜索地点",
        description: "使用 Apple MapKit 搜索地点并返回可供 WeatherKit、路线或报告继续使用的坐标。公开地点优先使用此工具，不使用网页猜测坐标。",
        parameters: .init(type: .object, properties: [
            "query": .init(type: .string, description: "地点、地址或设施名称"),
            "limit": .init(type: .integer, description: "返回 1 到 10 个结果"),
            "nearLatitude": .init(type: .number, description: "可选的搜索中心纬度，必须和经度同时提供"),
            "nearLongitude": .init(type: .number, description: "可选的搜索中心经度，必须和纬度同时提供")
        ], required: ["query"]),
        effect: .read,
        risk: .low,
        requirements: [],
        dataDomains: ["maps.public-places"],
        networkDomains: ["apple-mapkit"],
        privacyLabels: ["public-place-query"],
        supportsParallelism: false,
        executionClass: .native,
        maximumExecutionDuration: 20
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let near: FamiliarLocationSnapshot?
        switch (input.nearLatitude, input.nearLongitude) {
        case (nil, nil):
            near = nil
        case (.some(let latitude), .some(let longitude)):
            try FamiliarAppleNativeValidation.validateCoordinate(latitude: latitude, longitude: longitude)
            near = .init(latitude: latitude, longitude: longitude, horizontalAccuracy: 0, timestamp: Date())
        default:
            throw FamiliarAppleNativeToolError.invalidCoordinate
        }
        let places = try await service.search(query: input.query, near: near, limit: input.limit ?? 5)
        let records = places.map { place in
            var fields: [FamiliarToolPresentationPayload.RecordField] = [
                .init(name: "name", value: place.name),
                .init(name: "latitude", value: String(place.latitude)),
                .init(name: "longitude", value: String(place.longitude))
            ]
            if let address = place.address { fields.append(.init(name: "address", value: address)) }
            if let phone = place.phoneNumber { fields.append(.init(name: "phone", value: phone)) }
            if let url = place.url { fields.append(.init(name: "url", value: url)) }
            return FamiliarToolPresentationPayload.Record(id: place.id, fields: fields)
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: places,
            presentation: .recordCollection(.init(
                summary: "MapKit 找到 \(places.count) 个地点。",
                recordType: "mapPlace",
                records: records
            ))
        )))
    }
}

// MARK: - WeatherKit

nonisolated struct FamiliarWeatherDay: Codable, Equatable, Sendable {
    let dateISO8601: String
    let condition: String
    let symbolName: String
    let highCelsius: Double
    let lowCelsius: Double
    let precipitationChance: Double
    let uvIndex: Int
    let windKilometersPerHour: Double
}

nonisolated struct FamiliarWeatherSnapshot: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let retrievedAtISO8601: String
    let currentTemperatureCelsius: Double
    let currentApparentTemperatureCelsius: Double
    let currentCondition: String
    let currentHumidity: Double
    let dailyForecast: [FamiliarWeatherDay]
    let attributionServiceName: String
    let attributionLegalURL: String
}

nonisolated protocol FamiliarWeatherServicing: Sendable {
    func forecast(latitude: Double, longitude: Double, days: Int) async throws -> FamiliarWeatherSnapshot
}

actor FamiliarWeatherService: FamiliarWeatherServicing {
    private let service = WeatherService.shared

    func forecast(latitude: Double, longitude: Double, days: Int) async throws -> FamiliarWeatherSnapshot {
        try FamiliarAppleNativeValidation.validateCoordinate(latitude: latitude, longitude: longitude)
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let weather = try await service.weather(for: location)
        let attribution = try await service.attribution
        let daily = weather.dailyForecast.prefix(min(max(days, 1), 10)).map { day in
            FamiliarWeatherDay(
                dateISO8601: day.date.ISO8601Format(),
                condition: day.condition.rawValue,
                symbolName: day.symbolName,
                highCelsius: day.highTemperature.converted(to: .celsius).value,
                lowCelsius: day.lowTemperature.converted(to: .celsius).value,
                precipitationChance: day.precipitationChance,
                uvIndex: day.uvIndex.value,
                windKilometersPerHour: day.wind.speed.converted(to: .kilometersPerHour).value
            )
        }
        let current = weather.currentWeather
        return FamiliarWeatherSnapshot(
            latitude: latitude,
            longitude: longitude,
            retrievedAtISO8601: current.date.ISO8601Format(),
            currentTemperatureCelsius: current.temperature.converted(to: .celsius).value,
            currentApparentTemperatureCelsius: current.apparentTemperature.converted(to: .celsius).value,
            currentCondition: current.condition.rawValue,
            currentHumidity: current.humidity,
            dailyForecast: daily,
            attributionServiceName: attribution.serviceName,
            attributionLegalURL: attribution.legalPageURL.absoluteString
        )
    }
}

nonisolated struct FamiliarWeatherForecastTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let latitude: Double
        let longitude: Double
        let days: Int?
    }

    let service: any FamiliarWeatherServicing
    let manifest = FamiliarToolManifest(
        name: "weather_forecast",
        title: "查询天气预报",
        description: "使用 Apple WeatherKit 查询指定坐标的当前天气与最多十天预报。地点名称先用 map_search 解析坐标；当前位置先用 current_location。天气任务优先使用此工具，网页只用于 WeatherKit 无法提供的补充资料。",
        parameters: .init(type: .object, properties: [
            "latitude": .init(type: .number, description: "map_search 或 current_location 返回的纬度"),
            "longitude": .init(type: .number, description: "map_search 或 current_location 返回的经度"),
            "days": .init(type: .integer, description: "预报天数，1 到 10")
        ], required: ["latitude", "longitude"]),
        effect: .read,
        risk: .low,
        requirements: [.weatherKit],
        dataDomains: ["weather.forecast", "location.coordinate"],
        networkDomains: ["apple-weatherkit"],
        privacyLabels: ["coordinate-sent-to-apple-weather"],
        supportsParallelism: false,
        executionClass: .native,
        maximumExecutionDuration: 25
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let snapshot = try await service.forecast(
            latitude: input.latitude,
            longitude: input.longitude,
            days: input.days ?? 3
        )
        let records = snapshot.dailyForecast.map { day in
            FamiliarToolPresentationPayload.Record(id: day.dateISO8601, fields: [
                .init(name: "date", value: day.dateISO8601),
                .init(name: "condition", value: day.condition),
                .init(name: "highCelsius", value: String(format: "%.1f", day.highCelsius)),
                .init(name: "lowCelsius", value: String(format: "%.1f", day.lowCelsius)),
                .init(name: "precipitationChance", value: String(format: "%.0f%%", day.precipitationChance * 100)),
                .init(name: "uvIndex", value: String(day.uvIndex)),
                .init(name: "windKilometersPerHour", value: String(format: "%.1f", day.windKilometersPerHour))
            ])
        }
        let source = FamiliarSource(
            id: "weatherkit-\(snapshot.retrievedAtISO8601)",
            kind: .providerNative,
            title: snapshot.attributionServiceName,
            url: URL(string: snapshot.attributionLegalURL)!,
            siteName: "Apple Weather",
            snippet: "WeatherKit forecast for \(snapshot.latitude), \(snapshot.longitude)",
            retrievedAt: Date()
        )
        return .result(.init(
            envelope: try FamiliarToolResultEnvelope(
                model: snapshot,
                presentation: .recordCollection(.init(
                    summary: "已通过 WeatherKit 获取 \(snapshot.dailyForecast.count) 天预报。",
                    recordType: "weatherDay",
                    records: records
                ))
            ),
            sources: [source]
        ))
    }
}

nonisolated enum FamiliarAppleNativeToolError: LocalizedError, Sendable {
    case emptyQuery
    case invalidCoordinate

    var errorDescription: String? {
        switch self {
        case .emptyQuery: "查询内容不能为空。"
        case .invalidCoordinate: "坐标超出有效范围。"
        }
    }
}

nonisolated enum FamiliarAppleNativeValidation {
    static func validateCoordinate(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else { throw FamiliarAppleNativeToolError.invalidCoordinate }
    }
}
