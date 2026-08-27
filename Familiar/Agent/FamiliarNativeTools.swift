import Foundation

nonisolated struct FamiliarCurrentDateTimeTool: FamiliarTool {
    struct Input: Decodable, Sendable {}

    let manifest = FamiliarToolManifest(
        name: "current_date_time",
        title: String(localized: "tool.date_time"),
        description: "读取 iPhone 当前的本地日期、时间、时区、地区和日历信息。涉及‘今天’、‘现在’、本地时间或时区的问题应优先调用此工具，不要自行猜测。",
        parameters: FamiliarJSONSchema(type: .object, properties: [:], required: []),
        effect: .read,
        risk: .low,
        requirements: [],
        supportsParallelism: true,
        executionClass: .native
    )

    func execute(
        _ input: Input,
        context: FamiliarToolContext
    ) async throws -> FamiliarToolOutcome {
        let now = Date()
        let timeZone = TimeZone.autoupdatingCurrent
        let locale = Locale.autoupdatingCurrent
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = timeZone

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = timeZone

        let localFormatter = DateFormatter()
        localFormatter.locale = locale
        localFormatter.timeZone = timeZone
        localFormatter.calendar = calendar
        localFormatter.dateStyle = .full
        localFormatter.timeStyle = .long

        let payload = Output(
            iso8601: isoFormatter.string(from: now),
            localDescription: localFormatter.string(from: now),
            timeZoneIdentifier: timeZone.identifier,
            secondsFromGMT: timeZone.secondsFromGMT(for: now)
        )
        return .result(FamiliarToolExecutionResult(
            envelope: try FamiliarToolResultEnvelope(
                model: payload,
                presentation: .scalar(.init(summary: payload.localDescription, label: "localDateTime", value: payload.localDescription))
            )
        ))
    }

    private struct Output: Encodable {
        let iso8601: String
        let localDescription: String
        let timeZoneIdentifier: String
        let secondsFromGMT: Int

    }
}

nonisolated struct FamiliarAppInformationTool: FamiliarTool {
    struct Input: Decodable, Sendable {}

    let manifest = FamiliarToolManifest(
        name: "app_information",
        title: String(localized: "tool.app_information"),
        description: "读取当前 Familiar App 的名称、版本号和 build 编号。仅在用户询问当前 App 版本或 build 时调用。",
        parameters: FamiliarJSONSchema(type: .object, properties: [:], required: []),
        effect: .read,
        risk: .low,
        requirements: [],
        supportsParallelism: true,
        executionClass: .native
    )

    func execute(
        _ input: Input,
        context: FamiliarToolContext
    ) async throws -> FamiliarToolOutcome {
        let bundle = Bundle.main
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Familiar"
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "未知"
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "未知"
        let payload = Output(name: name, version: version, build: build)
        return .result(FamiliarToolExecutionResult(
            envelope: try FamiliarToolResultEnvelope(
                model: payload,
                presentation: .scalar(.init(summary: "\(name) \(version) (\(build))", label: "appVersion", value: "\(version) (\(build))"))
            )
        ))
    }

    private struct Output: Encodable {
        let name: String
        let version: String
        let build: String
    }
}
