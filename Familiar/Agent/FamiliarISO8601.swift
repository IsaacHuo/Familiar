import Foundation

/// Errors produced while parsing or validating an ISO8601 argument supplied by
/// the model. These are always caused by the arguments themselves, so retrying
/// the identical call cannot succeed.
nonisolated enum FamiliarISO8601Error: LocalizedError, FamiliarStructuredToolError, Sendable {
    case invalidDate(String)
    case invalidRange

    var code: String {
        switch self {
        case .invalidDate: "invalid_iso8601"
        case .invalidRange: "invalid_range"
        }
    }

    var isRetryable: Bool { false }

    var errorDescription: String? {
        switch self {
        case .invalidDate(let value): "不是严格有效的 ISO8601 日期：\(value)"
        case .invalidRange: "开始时间必须早于结束时间。"
        }
    }
}

/// The single ISO8601 boundary for tool arguments and tool results.
///
/// There used to be three near-identical private implementations plus five bare
/// `ISO8601DateFormatter()` uses. They disagreed: the EventKit parsers accepted
/// fractional seconds while `notification_schedule` did not, so the same model
/// timestamp worked in one tool and failed in another. Parsing accepts both
/// forms; formatting always emits fractional seconds.
nonisolated enum FamiliarISO8601 {
    static func string(_ date: Date) -> String {
        formatter(fractionalSeconds: true).string(from: date)
    }

    static func date(_ value: String) throws -> Date {
        if let date = formatter(fractionalSeconds: true).date(from: value) { return date }
        if let date = formatter(fractionalSeconds: false).date(from: value) { return date }
        throw FamiliarISO8601Error.invalidDate(value)
    }

    /// A UTC `DateComponents` carrying its calendar and time zone, as EventKit
    /// requires for reminder due dates.
    static func components(_ value: String) throws -> DateComponents {
        let parsed = try date(value)
        let utc = TimeZone(secondsFromGMT: 0) ?? .gmt
        var components = Calendar(identifier: .gregorian).dateComponents(in: utc, from: parsed)
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = utc
        return components
    }

    @discardableResult
    static func validateRange(start: String, end: String) throws -> (start: Date, end: Date) {
        let startDate = try date(start)
        let endDate = try date(end)
        guard startDate < endDate else { throw FamiliarISO8601Error.invalidRange }
        return (startDate, endDate)
    }

    private static func formatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
