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
        let bounded = min(
            max(limit, FamiliarToolDefaults.MapSearch.minimumLimit),
            FamiliarToolDefaults.MapSearch.maximumLimit
        )
        return response.mapItems.prefix(bounded).map { item in
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
        parameters: .object(
            [
                "query": .string("地点、地址或设施名称。"),
                "limit": .integer(
                    "返回的地点数量。",
                    minimum: FamiliarToolDefaults.MapSearch.minimumLimit,
                    maximum: FamiliarToolDefaults.MapSearch.maximumLimit,
                    defaultValue: FamiliarToolDefaults.MapSearch.limit
                ),
                "nearLatitude": .number("可选的搜索中心纬度，必须和经度同时提供。", minimum: -90, maximum: 90),
                "nearLongitude": .number("可选的搜索中心经度，必须和纬度同时提供。", minimum: -180, maximum: 180)
            ],
            required: ["query"]
        ),
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
        let places = try await service.search(
            query: input.query,
            near: near,
            limit: input.limit ?? FamiliarToolDefaults.MapSearch.limit
        )
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

/// A closed set of past days. Separate from `FamiliarWeatherSnapshot` because a
/// historical range has no "current conditions" and must not be presented as if
/// it did.
nonisolated struct FamiliarWeatherHistory: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let startISO8601: String
    let endISO8601: String
    let days: [FamiliarWeatherDay]
    let attributionServiceName: String
    let attributionLegalURL: String
}

nonisolated protocol FamiliarWeatherServicing: Sendable {
    func forecast(latitude: Double, longitude: Double, days: Int) async throws -> FamiliarWeatherSnapshot

    /// Daily weather for a closed past range. `end` is exclusive, matching
    /// WeatherKit's own range semantics.
    func history(
        latitude: Double,
        longitude: Double,
        start: Date,
        end: Date
    ) async throws -> FamiliarWeatherHistory
}

/// WeatherKit needs a signed `com.apple.developer.weatherkit` entitlement and a
/// live Apple Weather service call. An app cannot inspect either at runtime, so a
/// real failure must reach the model as a specific code instead of a generic
/// runtime error the model would "fix" by falling back to web guesses.
nonisolated enum FamiliarWeatherError: LocalizedError, FamiliarStructuredToolError, Sendable {
    case serviceFailed(String)
    case historyBeforeCoverage
    case historyRangeInvalid
    case historyRangeTooLong

    var code: String {
        switch self {
        case .serviceFailed: "weatherkit_unavailable"
        case .historyBeforeCoverage: "weather_history_before_coverage"
        case .historyRangeInvalid: "weather_history_range_invalid"
        case .historyRangeTooLong: "weather_history_range_too_long"
        }
    }

    var isRetryable: Bool {
        switch self {
        // A signing, quota, or network problem can clear on its own.
        case .serviceFailed: true
        // The range came from the model's arguments; the identical call cannot succeed.
        case .historyBeforeCoverage, .historyRangeInvalid, .historyRangeTooLong: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .serviceFailed(let detail):
            "WeatherKit 未能返回天气数据：\(detail)。这可能是签名 entitlement、配额或网络问题；不要用网页猜测代替天气数据。"
        case .historyBeforeCoverage:
            "WeatherKit 的历史数据从 \(FamiliarToolDefaults.WeatherHistory.earliestDateDescription) 开始，更早的日期无法查询。"
        case .historyRangeInvalid:
            "历史查询的开始时间必须早于结束时间，且结束时间为不含端点的上界。"
        case .historyRangeTooLong:
            "WeatherKit 单次历史查询最多返回 \(FamiliarToolDefaults.WeatherHistory.maximumDays) 天，请分段查询。"
        }
    }
}

actor FamiliarWeatherService: FamiliarWeatherServicing {
    private let service = WeatherService.shared

    func forecast(latitude: Double, longitude: Double, days: Int) async throws -> FamiliarWeatherSnapshot {
        try FamiliarAppleNativeValidation.validateCoordinate(latitude: latitude, longitude: longitude)
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let weather: Weather
        let attribution: WeatherAttribution
        do {
            weather = try await service.weather(for: location)
            attribution = try await service.attribution
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FamiliarWeatherError.serviceFailed(error.localizedDescription)
        }
        let boundedDays = min(
            max(days, FamiliarToolDefaults.WeatherForecast.minimumDays),
            FamiliarToolDefaults.WeatherForecast.maximumDays
        )
        let daily = weather.dailyForecast.prefix(boundedDays).map(FamiliarWeatherDay.init)
        let current = weather.currentWeather
        return FamiliarWeatherSnapshot(
            latitude: latitude,
            longitude: longitude,
            retrievedAtISO8601: FamiliarISO8601.string(current.date),
            currentTemperatureCelsius: current.temperature.converted(to: .celsius).value,
            currentApparentTemperatureCelsius: current.apparentTemperature.converted(to: .celsius).value,
            currentCondition: current.condition.rawValue,
            currentHumidity: current.humidity,
            dailyForecast: daily,
            attributionServiceName: attribution.serviceName,
            attributionLegalURL: attribution.legalPageURL.absoluteString
        )
    }

    func history(
        latitude: Double,
        longitude: Double,
        start: Date,
        end: Date
    ) async throws -> FamiliarWeatherHistory {
        try FamiliarAppleNativeValidation.validateCoordinate(latitude: latitude, longitude: longitude)
        guard start < end else { throw FamiliarWeatherError.historyRangeInvalid }
        guard start >= FamiliarToolDefaults.WeatherHistory.earliestDate else {
            throw FamiliarWeatherError.historyBeforeCoverage
        }
        // WeatherKit returns at most 10 days per daily range request. Rejecting an
        // oversized range is required, because silently truncating would let the
        // model believe it received days it never got.
        let span = end.timeIntervalSince(start)
        guard span <= Double(FamiliarToolDefaults.WeatherHistory.maximumDays) * 86_400 else {
            throw FamiliarWeatherError.historyRangeTooLong
        }
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let forecast: Forecast<DayWeather>
        let attribution: WeatherAttribution
        do {
            forecast = try await service.weather(
                for: location,
                including: .daily(startDate: start, endDate: end)
            )
            attribution = try await service.attribution
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FamiliarWeatherError.serviceFailed(error.localizedDescription)
        }
        return FamiliarWeatherHistory(
            latitude: latitude,
            longitude: longitude,
            startISO8601: FamiliarISO8601.string(start),
            endISO8601: FamiliarISO8601.string(end),
            days: forecast.map(FamiliarWeatherDay.init),
            attributionServiceName: attribution.serviceName,
            attributionLegalURL: attribution.legalPageURL.absoluteString
        )
    }
}

private extension FamiliarWeatherDay {
    nonisolated init(_ day: DayWeather) {
        self.init(
            dateISO8601: FamiliarISO8601.string(day.date),
            condition: day.condition.rawValue,
            symbolName: day.symbolName,
            highCelsius: day.highTemperature.converted(to: .celsius).value,
            lowCelsius: day.lowTemperature.converted(to: .celsius).value,
            precipitationChance: day.precipitationChance,
            uvIndex: day.uvIndex.value,
            windKilometersPerHour: day.wind.speed.converted(to: .kilometersPerHour).value
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
        parameters: .object(
            [
                "latitude": .number("map_search 或 current_location 返回的纬度。", minimum: -90, maximum: 90),
                "longitude": .number("map_search 或 current_location 返回的经度。", minimum: -180, maximum: 180),
                "days": .integer(
                    "预报天数。",
                    minimum: FamiliarToolDefaults.WeatherForecast.minimumDays,
                    maximum: FamiliarToolDefaults.WeatherForecast.maximumDays,
                    defaultValue: FamiliarToolDefaults.WeatherForecast.days
                )
            ],
            required: ["latitude", "longitude"]
        ),
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
            days: input.days ?? FamiliarToolDefaults.WeatherForecast.days
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

/// Past weather for a closed day range, which `weather_forecast` cannot answer:
/// `dailyForecast` only starts at the current day. This is the tool the
/// photo -> location -> weather -> report chain depends on, because a photo taken
/// last week needs the weather as it actually was.
nonisolated struct FamiliarWeatherHistoryTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let latitude: Double
        let longitude: Double
        let startISO8601: String
        let endISO8601: String
    }

    let service: any FamiliarWeatherServicing
    let manifest = FamiliarToolManifest(
        name: "weather_history",
        title: "查询历史天气",
        description: "使用 Apple WeatherKit 查询指定坐标在过去某个日期区间的每日天气。适合为照片、日历事件或已发生的行程还原当时天气；未来天气请使用 weather_forecast。历史数据从 \(FamiliarToolDefaults.WeatherHistory.earliestDateDescription) 开始，单次最多 \(FamiliarToolDefaults.WeatherHistory.maximumDays) 天，超出范围会明确失败而不会截断。",
        parameters: .object(
            [
                "latitude": .number("map_search、photos_recent_metadata 或 current_location 返回的纬度。", minimum: -90, maximum: 90),
                "longitude": .number("map_search、photos_recent_metadata 或 current_location 返回的经度。", minimum: -180, maximum: 180),
                "startISO8601": .string("包含起点的 ISO8601 时间。不得早于 \(FamiliarToolDefaults.WeatherHistory.earliestDateDescription)。"),
                "endISO8601": .string("不含端点的 ISO8601 上界，必须晚于起点。")
            ],
            required: ["latitude", "longitude", "startISO8601", "endISO8601"]
        ),
        effect: .read,
        risk: .low,
        requirements: [.weatherKit],
        dataDomains: ["weather.history", "location.coordinate"],
        networkDomains: ["apple-weatherkit"],
        privacyLabels: ["coordinate-sent-to-apple-weather"],
        supportsParallelism: false,
        executionClass: .native,
        maximumExecutionDuration: 25
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let range = try FamiliarISO8601.validateRange(start: input.startISO8601, end: input.endISO8601)
        let history = try await service.history(
            latitude: input.latitude,
            longitude: input.longitude,
            start: range.start,
            end: range.end
        )
        let records = history.days.map { day in
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
            id: "weatherkit-history-\(history.startISO8601)-\(history.endISO8601)",
            kind: .providerNative,
            title: history.attributionServiceName,
            url: URL(string: history.attributionLegalURL) ?? URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
            siteName: "Apple Weather",
            snippet: "WeatherKit history for \(history.latitude), \(history.longitude)",
            retrievedAt: Date()
        )
        return .result(.init(
            envelope: try FamiliarToolResultEnvelope(
                model: history,
                presentation: .recordCollection(.init(
                    summary: "已通过 WeatherKit 获取 \(history.days.count) 天历史天气。",
                    recordType: "weatherDay",
                    records: records
                ))
            ),
            sources: [source]
        ))
    }
}

nonisolated enum FamiliarAppleNativeToolError: LocalizedError, FamiliarStructuredToolError, Sendable {
    case emptyQuery
    case invalidCoordinate

    var code: String {
        switch self {
        case .emptyQuery: "invalid_query"
        case .invalidCoordinate: "invalid_coordinate"
        }
    }

    /// Both cases are caused by the arguments the model supplied, so retrying the
    /// identical call cannot succeed.
    var isRetryable: Bool { false }

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
