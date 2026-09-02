import Foundation
import HealthKit
import MusicKit
import NaturalLanguage

// MARK: - NaturalLanguage

nonisolated struct FamiliarNaturalLanguageAnalysis: Codable, Equatable, Sendable {
    let dominantLanguage: String?
    let languageHypotheses: [String: Double]
    let sentimentScore: Double?
    let people: [String]
    let places: [String]
    let organizations: [String]
}

nonisolated protocol FamiliarNaturalLanguageServicing: Sendable {
    func analyze(_ text: String) throws -> FamiliarNaturalLanguageAnalysis
}

struct FamiliarNaturalLanguageService: FamiliarNaturalLanguageServicing {
    func analyze(_ text: String) throws -> FamiliarNaturalLanguageAnalysis {
        let bounded = String(text.prefix(FamiliarToolDefaults.NaturalLanguage.maximumCharacters))
        guard !bounded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FamiliarAppleNativeToolError.emptyQuery
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(bounded)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        let tagger = NLTagger(tagSchemes: [.nameType, .sentimentScore])
        tagger.string = bounded
        let range = bounded.startIndex..<bounded.endIndex
        var people: [String] = []
        var places: [String] = []
        var organizations: [String] = []
        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, tokenRange in
            guard let tag else { return true }
            let value = String(bounded[tokenRange])
            switch tag {
            case .personalName: people.append(value)
            case .placeName: places.append(value)
            case .organizationName: organizations.append(value)
            default: break
            }
            return people.count + places.count + organizations.count < FamiliarToolDefaults.NaturalLanguage.maximumEntities
        }
        let sentiment = tagger.tag(at: bounded.startIndex, unit: .paragraph, scheme: .sentimentScore).0
            .flatMap { Double($0.rawValue) }
        return FamiliarNaturalLanguageAnalysis(
            dominantLanguage: recognizer.dominantLanguage?.rawValue,
            languageHypotheses: Dictionary(uniqueKeysWithValues: hypotheses.map { ($0.key.rawValue, $0.value) }),
            sentimentScore: sentiment,
            people: people.uniquedPreservingOrder(),
            places: places.uniquedPreservingOrder(),
            organizations: organizations.uniquedPreservingOrder()
        )
    }
}

nonisolated struct FamiliarNaturalLanguageAnalyzeTool: FamiliarTool {
    struct Input: Decodable, Sendable { let text: String }
    let service: any FamiliarNaturalLanguageServicing
    let manifest = FamiliarToolManifest(
        name: "natural_language_analyze",
        title: "分析文本",
        description: "使用 Apple NaturalLanguage 在设备上识别语言、情感分数以及人物、地点和组织实体。适合文件处理前的本地文本分析，不需要 iSH。结果是概率性分析。",
        parameters: .object(
            ["text": .string("需要分析的文本，只处理前 \(FamiliarToolDefaults.NaturalLanguage.maximumCharacters) 个字符。")],
            required: ["text"]
        ),
        effect: .read,
        risk: .low,
        requirements: [],
        dataDomains: ["provided-text"],
        privacyLabels: ["on-device"],
        supportsParallelism: true,
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let analysis = try service.analyze(input.text)
        let records: [FamiliarToolPresentationPayload.Record] = [
            .init(id: "people", fields: [.init(name: "people", value: analysis.people.joined(separator: ", "))]),
            .init(id: "places", fields: [.init(name: "places", value: analysis.places.joined(separator: ", "))]),
            .init(id: "organizations", fields: [.init(name: "organizations", value: analysis.organizations.joined(separator: ", "))])
        ]
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: analysis,
            presentation: .recordCollection(.init(
                summary: "已在设备上完成 NaturalLanguage 分析。",
                recordType: "namedEntityGroup",
                records: records
            ))
        )))
    }
}

// MARK: - HealthKit

nonisolated struct FamiliarHealthActivitySummary: Codable, Equatable, Sendable {
    let startISO8601: String
    let endISO8601: String
    let stepCount: Double?
    let activeEnergyKilocalories: Double?
    let walkingRunningDistanceMeters: Double?
    let authorizationDoesNotRevealReadDenials: Bool
}

nonisolated protocol FamiliarHealthServicing: Sendable {
    func availability() async -> FamiliarCapabilityAvailability
    func requestAccess() async throws
    func activitySummary(days: Int) async throws -> FamiliarHealthActivitySummary
}

/// Single definition of the HealthKit read scope, shared by the tool and the
/// permissions surface so the UI can never claim a scope the tool does not request.
nonisolated enum FamiliarHealthReadScope {
    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceWalkingRunning)
    ]

    /// HealthKit deliberately never reveals read denials, so the only honest
    /// states are "not requested yet" and "already requested".
    enum RequestState: Sendable, Equatable {
        case unavailable(reason: String)
        case notRequested
        case requested
    }

    static func requestState(store: HKHealthStore = HKHealthStore()) async -> RequestState {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable(reason: "这台设备不支持 HealthKit。")
        }
        do {
            let status: HKAuthorizationRequestStatus = try await withCheckedThrowingContinuation { continuation in
                store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: status) }
                }
            }
            return status == .shouldRequest ? .notRequested : .requested
        } catch {
            return .unavailable(reason: "无法检查 HealthKit 授权状态：\(error.localizedDescription)")
        }
    }
}

actor FamiliarHealthService: FamiliarHealthServicing {
    private let store = HKHealthStore()

    func availability() async -> FamiliarCapabilityAvailability {
        switch await FamiliarHealthReadScope.requestState(store: store) {
        case .unavailable(let reason): .unavailable(reason: reason)
        case .notRequested: .requestable
        case .requested: .available
        }
    }

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw FamiliarToolRegistryError.capabilityUnavailable("这台设备不支持 HealthKit。")
        }
        try await store.requestAuthorization(toShare: [], read: FamiliarHealthReadScope.readTypes)
    }

    func activitySummary(days: Int) async throws -> FamiliarHealthActivitySummary {
        let boundedDays = min(
            max(days, FamiliarToolDefaults.HealthActivity.minimumDays),
            FamiliarToolDefaults.HealthActivity.maximumDays
        )
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -boundedDays, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let steps = try await sum(type: .stepCount, unit: .count(), predicate: predicate)
        let energy = try await sum(type: .activeEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        let distance = try await sum(type: .distanceWalkingRunning, unit: .meter(), predicate: predicate)
        return FamiliarHealthActivitySummary(
            startISO8601: start.ISO8601Format(),
            endISO8601: end.ISO8601Format(),
            stepCount: steps,
            activeEnergyKilocalories: energy,
            walkingRunningDistanceMeters: distance,
            authorizationDoesNotRevealReadDenials: true
        )
    }

    private func sum(
        type identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate
    ) async throws -> Double? {
        let type = HKQuantityType(identifier)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        return try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit)
    }
}

nonisolated struct FamiliarHealthActivitySummaryTool: FamiliarTool {
    struct Input: Decodable, Sendable { let days: Int? }
    let service: any FamiliarHealthServicing
    let manifest = FamiliarToolManifest(
        name: "health_activity_summary",
        title: "读取健康活动摘要",
        description: "经明确授权后，从 HealthKit 汇总最近 1 到 31 天的步数、活动能量和步行跑步距离。HealthKit 不会向 App 揭示用户是否拒绝了某项读取权限；空值不得解释为零。",
        parameters: .object(
            ["days": .integer(
                "统计最近多少天。",
                minimum: FamiliarToolDefaults.HealthActivity.minimumDays,
                maximum: FamiliarToolDefaults.HealthActivity.maximumDays,
                defaultValue: FamiliarToolDefaults.HealthActivity.days
            )],
            required: []
        ),
        effect: .read,
        risk: .high,
        requirements: [.healthActivityRead],
        dataDomains: ["health.activity"],
        privacyLabels: ["health-data", "minimum-aggregation"],
        supportsParallelism: false,
        executionClass: .native
    )

    /// Surfaces the concrete window and metric list in the confirmation card. The
    /// manifest description alone would not tell the user what is about to be read.
    func preflight(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolAuthorizationAssessment {
        let days = min(
            max(input.days ?? FamiliarToolDefaults.HealthActivity.days, FamiliarToolDefaults.HealthActivity.minimumDays),
            FamiliarToolDefaults.HealthActivity.maximumDays
        )
        return .init(
            disposition: .requiresApproval,
            effect: manifest.effect,
            risk: manifest.risk,
            reason: manifest.description,
            fields: [
                .init(id: "window", label: String(localized: "approval.field.window", defaultValue: "Window"), type: .text, value: String(format: String(localized: "approval.value.recent_days", defaultValue: "Last %lld days"), days)),
                .init(id: "metrics", label: String(localized: "approval.field.metrics", defaultValue: "Metrics"), type: .text, value: "stepCount, activeEnergyBurned, distanceWalkingRunning"),
                .init(id: "scope", label: String(localized: "approval.field.scope", defaultValue: "Scope"), type: .text, value: String(localized: "approval.value.health_aggregate", defaultValue: "Daily totals only, no individual samples"))
            ],
            consequence: String(localized: "approval.consequence.health_read", defaultValue: "Familiar reads aggregated activity totals for this window. Results may be sent to the selected model provider as a tool result."),
            targetKey: "health-activity"
        )
    }

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let summary = try await service.activitySummary(days: input.days ?? FamiliarToolDefaults.HealthActivity.days)
        let fields: [FamiliarToolPresentationPayload.RecordField] = [
            .init(name: "steps", value: summary.stepCount.map { String($0) } ?? "unavailable"),
            .init(name: "activeEnergyKilocalories", value: summary.activeEnergyKilocalories.map { String($0) } ?? "unavailable"),
            .init(name: "walkingRunningDistanceMeters", value: summary.walkingRunningDistanceMeters.map { String($0) } ?? "unavailable")
        ]
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: summary,
            presentation: .recordCollection(.init(
                summary: "已读取 HealthKit 活动摘要。空值可能表示没有样本或未授权。",
                recordType: "healthActivitySummary",
                records: [.init(id: summary.startISO8601, fields: fields)]
            ))
        )))
    }
}

// MARK: - MusicKit

nonisolated struct FamiliarMusicSong: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let artistName: String
    let albumTitle: String?
    let durationSeconds: Double?
    let url: String?
}

nonisolated protocol FamiliarMusicServicing: Sendable {
    func availability() async -> FamiliarCapabilityAvailability
    func requestAccess() async throws
    func searchSongs(term: String, limit: Int) async throws -> [FamiliarMusicSong]
}

actor FamiliarMusicService: FamiliarMusicServicing {
    func availability() -> FamiliarCapabilityAvailability {
        switch MusicAuthorization.currentStatus {
        case .authorized: .available
        case .notDetermined: .requestable
        case .denied, .restricted: .unavailable(reason: "Apple Music 权限不可用，请在系统设置中允许访问。")
        @unknown default: .unavailable(reason: "Apple Music 权限状态未知。")
        }
    }

    func requestAccess() async throws {
        guard await MusicAuthorization.request() == .authorized else {
            throw FamiliarToolRegistryError.capabilityUnavailable("用户未允许 Apple Music 访问。")
        }
    }

    func searchSongs(term: String, limit: Int) async throws -> [FamiliarMusicSong] {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw FamiliarAppleNativeToolError.emptyQuery }
        var request = MusicCatalogSearchRequest(term: normalized, types: [Song.self])
        request.limit = min(
            max(limit, FamiliarToolDefaults.MusicSearch.minimumLimit),
            FamiliarToolDefaults.MusicSearch.maximumLimit
        )
        let response = try await request.response()
        return response.songs.map { song in
            FamiliarMusicSong(
                id: song.id.rawValue,
                title: song.title,
                artistName: song.artistName,
                albumTitle: song.albumTitle,
                durationSeconds: song.duration,
                url: song.url?.absoluteString
            )
        }
    }
}

nonisolated struct FamiliarMusicCatalogSearchTool: FamiliarTool {
    struct Input: Decodable, Sendable { let query: String; let limit: Int? }
    let service: any FamiliarMusicServicing
    let manifest = FamiliarToolManifest(
        name: "music_catalog_search",
        title: "搜索 Apple Music",
        description: "使用 MusicKit 搜索 Apple Music 目录中的歌曲。只返回目录元数据，不自动播放、不修改音乐资料库。",
        parameters: .object(
            [
                "query": .string("歌曲、艺人或专辑搜索词。"),
                "limit": .integer(
                    "返回的歌曲数量。",
                    minimum: FamiliarToolDefaults.MusicSearch.minimumLimit,
                    maximum: FamiliarToolDefaults.MusicSearch.maximumLimit,
                    defaultValue: FamiliarToolDefaults.MusicSearch.limit
                )
            ],
            required: ["query"]
        ),
        effect: .read,
        risk: .sensitive,
        requirements: [.musicCatalogRead],
        dataDomains: ["music.catalog"],
        networkDomains: ["apple-music"],
        privacyLabels: ["music-search-query"],
        supportsParallelism: false,
        executionClass: .native,
        maximumExecutionDuration: 25
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let songs = try await service.searchSongs(
            term: input.query,
            limit: input.limit ?? FamiliarToolDefaults.MusicSearch.limit
        )
        let records = songs.map { song in
            var fields: [FamiliarToolPresentationPayload.RecordField] = [
                .init(name: "title", value: song.title),
                .init(name: "artist", value: song.artistName)
            ]
            if let album = song.albumTitle { fields.append(.init(name: "album", value: album)) }
            if let url = song.url { fields.append(.init(name: "url", value: url)) }
            return FamiliarToolPresentationPayload.Record(id: song.id, fields: fields)
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: songs,
            presentation: .recordCollection(.init(
                summary: "MusicKit 找到 \(songs.count) 首歌曲。",
                recordType: "musicSong",
                records: records
            ))
        )))
    }
}

private extension Sequence where Element: Hashable {
    nonisolated func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
