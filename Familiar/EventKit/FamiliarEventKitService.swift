import EventKit
import Foundation

nonisolated public enum FamiliarEventKitAccessKind: String, Codable, Sendable {
    case events
    case reminders
}

nonisolated public enum FamiliarEventKitAuthorization: String, Codable, Sendable {
    case notDetermined
    case restricted
    case denied
    case writeOnly
    case fullAccess

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .writeOnly: self = .writeOnly
        case .fullAccess: self = .fullAccess
        @unknown default: self = .denied
        }
    }
}

nonisolated public struct FamiliarEventKitPermissionStatus: Codable, Sendable {
    public let events: FamiliarEventKitAuthorization
    public let reminders: FamiliarEventKitAuthorization

    public var canReadEvents: Bool { events == .fullAccess }
    public var canReadReminders: Bool { reminders == .fullAccess }
}

nonisolated public enum FamiliarEventKitError: LocalizedError, Sendable {
    case permissionRequired(FamiliarEventKitAccessKind, FamiliarEventKitAuthorization)
    case invalidISO8601(String)
    case invalidRange
    case emptyTitle
    case resultLimitExceeded
    case invalidResultLimit
    case missingCalendar
    case idempotencyKeyEmpty
    case undoUnavailable

    public var errorDescription: String? {
        switch self {
        case .permissionRequired(let kind, let status):
            return "需要\(kind == .events ? "日历" : "提醒事项")完整访问权限（当前状态：\(status.rawValue)）。"
        case .invalidISO8601(let value): return "不是严格有效的 ISO8601 日期：\(value)"
        case .invalidRange: return "开始时间必须早于结束时间。"
        case .emptyTitle: return "标题不能为空。"
        case .resultLimitExceeded: return "查询结果超过允许的上限。"
        case .invalidResultLimit: return "结果上限必须在 1 到 200 之间。"
        case .missingCalendar: return "找不到指定的日历或提醒列表。"
        case .idempotencyKeyEmpty: return "幂等键不能为空。"
        case .undoUnavailable: return "这次操作已经撤销，或撤销已失效。"
        }
    }
}

nonisolated public struct FamiliarCalendarEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let startISO8601: String
    public let endISO8601: String
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?
    public let calendarIdentifier: String
    public let calendarTitle: String
}

nonisolated public struct FamiliarReminder: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let dueISO8601: String?
    public let isCompleted: Bool
    public let priority: Int
    public let notes: String?
    public let listIdentifier: String
    public let listTitle: String
}

nonisolated public struct FamiliarEventWriteRequest: Codable, Sendable {
    public let title: String
    public let startISO8601: String
    public let endISO8601: String
    public let isAllDay: Bool
    public let location: String?
    public let notes: String?
    public let urlString: String?
    public let calendarIdentifier: String?
}

nonisolated public struct FamiliarReminderWriteRequest: Codable, Sendable {
    public let title: String
    public let dueISO8601: String?
    public let listIdentifier: String?
    public let priority: Int
    public let notes: String?
}

nonisolated public enum FamiliarPendingWriteRequest: Codable, Sendable {
    case event(FamiliarEventWriteRequest)
    case reminder(FamiliarReminderWriteRequest)
}

nonisolated public struct FamiliarWriteCommitResult: Codable, Sendable {
    public let idempotencyKey: String
    public let kind: FamiliarEventKitAccessKind
    public let identifier: String
}

nonisolated private struct FamiliarUndoResult: Codable, Sendable {
    let undone: Bool
    let identifier: String
}

nonisolated public protocol FamiliarEventKitWriteExecutor: Sendable {
    func commit(
        _ request: FamiliarPendingWriteRequest,
        idempotencyKey: String
    ) async throws -> FamiliarWriteCommitResult
}

nonisolated protocol FamiliarEventKitServicing: FamiliarEventKitWriteExecutor, FamiliarCapabilityProviding {
    func targetDescription(for request: FamiliarPendingWriteRequest) async throws -> String
    func events(from startISO8601: String, to endISO8601: String, limit: Int) async throws -> [FamiliarCalendarEvent]
    func reminders(from startISO8601: String?, to endISO8601: String?, text: String?, limit: Int) async throws -> [FamiliarReminder]
    func undoCommit(idempotencyKey: String) async throws -> FamiliarToolExecutionResult
    func undo(kind: FamiliarEventKitAccessKind, identifier: String) async throws -> FamiliarToolExecutionResult
}

nonisolated extension FamiliarEventKitServicing {
    func undo(kind: FamiliarEventKitAccessKind, identifier: String) async throws -> FamiliarToolExecutionResult {
        throw FamiliarEventKitError.undoUnavailable
    }
}

public actor FamiliarEventKitService: FamiliarEventKitServicing {
    private let store = EKEventStore()
    private var committedKeys: [String: FamiliarWriteCommitResult] = [:]
    private var undoneKeys: Set<String> = []

    public init() {}

    public func permissionStatus() -> FamiliarEventKitPermissionStatus {
        FamiliarEventKitPermissionStatus(
            events: FamiliarEventKitAuthorization(EKEventStore.authorizationStatus(for: .event)),
            reminders: FamiliarEventKitAuthorization(EKEventStore.authorizationStatus(for: .reminder))
        )
    }

    public func authorization(for kind: FamiliarEventKitAccessKind) -> FamiliarEventKitAuthorization {
        switch kind {
        case .events:
            FamiliarEventKitAuthorization(EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            FamiliarEventKitAuthorization(EKEventStore.authorizationStatus(for: .reminder))
        }
    }

    public func requestFullAccess(for kind: FamiliarEventKitAccessKind) async throws {
        switch kind {
        case .events:
            try await store.requestFullAccessToEvents()
        case .reminders:
            try await store.requestFullAccessToReminders()
        }
    }

    public func requestFullAccessToEvents() async throws {
        try await requestFullAccess(for: .events)
    }

    public func requestFullAccessToReminders() async throws {
        try await requestFullAccess(for: .reminders)
    }

    func availability(for requirement: FamiliarCapabilityRequirement) -> FamiliarCapabilityAvailability {
        let authorization: FamiliarEventKitAuthorization
        switch requirement {
        case .calendarFullAccess: authorization = FamiliarEventKitAuthorization(EKEventStore.authorizationStatus(for: .event))
        case .remindersFullAccess: authorization = FamiliarEventKitAuthorization(EKEventStore.authorizationStatus(for: .reminder))
        case .contactsRead, .locationWhenInUse:
            return .unavailable(reason: "此设备能力需要对应的 Native Service。")
        }
        switch authorization {
        case .fullAccess: return .available
        case .notDetermined, .writeOnly: return .requestable
        case .restricted, .denied: return .unavailable(reason: "系统权限不可用，请在设置中允许访问。")
        }
    }

    func request(_ requirement: FamiliarCapabilityRequirement) async throws {
        switch availability(for: requirement) {
        case .available: return
        case .unavailable(let reason): throw FamiliarToolRegistryError.capabilityUnavailable(reason)
        case .requestable:
            switch requirement {
            case .calendarFullAccess: try await requestFullAccess(for: .events)
            case .remindersFullAccess: try await requestFullAccess(for: .reminders)
            case .contactsRead, .locationWhenInUse:
                throw FamiliarToolRegistryError.capabilityUnavailable("此设备能力需要对应的 Native Service。")
            }
        }
    }

    public func targetDescription(for request: FamiliarPendingWriteRequest) throws -> String {
        switch request {
        case .event(let input):
            if authorization(for: .events) != .fullAccess, input.calendarIdentifier == nil {
                return String(localized: "eventkit.default_calendar")
            }
            return try eventCalendar(identifier: input.calendarIdentifier).title
        case .reminder(let input):
            if authorization(for: .reminders) != .fullAccess, input.listIdentifier == nil {
                return String(localized: "eventkit.default_reminder_list")
            }
            return try reminderCalendar(identifier: input.listIdentifier).title
        }
    }

    public func events(
        from startISO8601: String,
        to endISO8601: String,
        limit: Int
    ) async throws -> [FamiliarCalendarEvent] {
        try Task.checkCancellation()
        guard (1...200).contains(limit) else { throw FamiliarEventKitError.invalidResultLimit }
        let start = try FamiliarISO8601.date(startISO8601)
        let end = try FamiliarISO8601.date(endISO8601)
        guard start < end else { throw FamiliarEventKitError.invalidRange }
        try require(.events)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let values = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        try Task.checkCancellation()
        return values.prefix(limit).map { FamiliarCalendarEvent($0) }
    }

    public func reminders(
        from startISO8601: String?,
        to endISO8601: String?,
        text: String?,
        limit: Int
    ) async throws -> [FamiliarReminder] {
        try Task.checkCancellation()
        guard (1...200).contains(limit) else { throw FamiliarEventKitError.invalidResultLimit }
        let start = try startISO8601.map(FamiliarISO8601.date)
        let end = try endISO8601.map(FamiliarISO8601.date)
        if let start, let end { guard start < end else { throw FamiliarEventKitError.invalidRange } }
        try require(.reminders)
        let predicate = store.predicateForReminders(in: nil)
        let all = await fetchReminders(matching: predicate)
        try Task.checkCancellation()
        let query = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let values = all.filter { candidate in
            let due = candidate.dueDate
            let inRange = (start == nil || (due != nil && due! >= start!)) && (end == nil || (due != nil && due! <= end!))
            let matchesText = query.map { !$0.isEmpty && candidate.searchableText.contains($0) } ?? true
            return inRange && matchesText
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        return values.prefix(limit).map(\.reminder)
    }

    public func commit(_ request: FamiliarPendingWriteRequest, idempotencyKey: String) async throws -> FamiliarWriteCommitResult {
        try Task.checkCancellation()
        guard !idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FamiliarEventKitError.idempotencyKeyEmpty }
        if let existing = committedKeys[idempotencyKey] { return existing }
        let result: FamiliarWriteCommitResult
        switch request {
        case .event(let input): result = try saveEvent(input, key: idempotencyKey)
        case .reminder(let input): result = try saveReminder(input, key: idempotencyKey)
        }
        committedKeys[idempotencyKey] = result
        return result
    }

    func undoCommit(idempotencyKey: String) async throws -> FamiliarToolExecutionResult {
        try Task.checkCancellation()
        guard !undoneKeys.contains(idempotencyKey),
              let committed = committedKeys[idempotencyKey]
        else { throw FamiliarEventKitError.undoUnavailable }
        switch committed.kind {
        case .events:
            guard let event = store.event(withIdentifier: committed.identifier) else {
                throw FamiliarEventKitError.undoUnavailable
            }
            try store.remove(event, span: .thisEvent, commit: true)
        case .reminders:
            guard let reminder = store.calendarItem(withIdentifier: committed.identifier) as? EKReminder else {
                throw FamiliarEventKitError.undoUnavailable
            }
            try store.remove(reminder, commit: true)
        }
        undoneKeys.insert(idempotencyKey)
        return FamiliarToolExecutionResult(
            envelope: try FamiliarToolResultEnvelope(
                model: FamiliarUndoResult(undone: true, identifier: committed.identifier),
                presentation: .mutationReceipt(.init(summary: "已撤销", operation: "undo", targetIdentifier: committed.identifier, succeeded: true, undoAvailable: false))
            ),
            artifactIdentifier: committed.identifier
        )
    }

    func undo(kind: FamiliarEventKitAccessKind, identifier: String) async throws -> FamiliarToolExecutionResult {
        try Task.checkCancellation()
        switch kind {
        case .events:
            guard let event = store.event(withIdentifier: identifier) else { throw FamiliarEventKitError.undoUnavailable }
            try store.remove(event, span: .thisEvent, commit: true)
        case .reminders:
            guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { throw FamiliarEventKitError.undoUnavailable }
            try store.remove(reminder, commit: true)
        }
        return FamiliarToolExecutionResult(
            envelope: try FamiliarToolResultEnvelope(
                model: FamiliarUndoResult(undone: true, identifier: identifier),
                presentation: .mutationReceipt(.init(summary: String(localized: "tool.undone", defaultValue: "Undone"), operation: "undo", targetIdentifier: identifier, succeeded: true, undoAvailable: false))
            ),
            artifactIdentifier: identifier
        )
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [FamiliarReminderCandidate] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let candidates = (reminders ?? []).map { reminder in
                    FamiliarReminderCandidate(
                        reminder: FamiliarReminder(reminder),
                        dueDate: reminder.dueDateComponents?.date,
                        searchableText: "\(reminder.title.lowercased())\n\((reminder.notes ?? "").lowercased())"
                    )
                }
                continuation.resume(returning: candidates)
            }
        }
    }

    private func require(_ kind: FamiliarEventKitAccessKind) throws {
        let status = kind == .events ? FamiliarEventKitAuthorization(EKEventStore.authorizationStatus(for: .event)) : FamiliarEventKitAuthorization(EKEventStore.authorizationStatus(for: .reminder))
        guard status == .fullAccess else { throw FamiliarEventKitError.permissionRequired(kind, status) }
    }

    private func saveEvent(_ input: FamiliarEventWriteRequest, key: String) throws -> FamiliarWriteCommitResult {
        try require(.events)
        let start = try FamiliarISO8601.date(input.startISO8601)
        let end = try FamiliarISO8601.date(input.endISO8601)
        guard start < end else { throw FamiliarEventKitError.invalidRange }
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FamiliarEventKitError.emptyTitle }
        let event = EKEvent(eventStore: store)
        event.title = input.title
        event.startDate = start
        event.endDate = end
        event.isAllDay = input.isAllDay
        event.location = input.location
        event.notes = input.notes
        event.url = input.urlString.flatMap(URL.init(string:))
        event.calendar = try eventCalendar(identifier: input.calendarIdentifier)
        try store.save(event, span: .thisEvent, commit: true)
        return FamiliarWriteCommitResult(idempotencyKey: key, kind: .events, identifier: event.eventIdentifier)
    }

    private func saveReminder(_ input: FamiliarReminderWriteRequest, key: String) throws -> FamiliarWriteCommitResult {
        try require(.reminders)
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FamiliarEventKitError.emptyTitle }
        guard (0...9).contains(input.priority) else { throw FamiliarEventKitError.invalidRange }
        let reminder = EKReminder(eventStore: store)
        reminder.title = input.title
        reminder.notes = input.notes
        reminder.priority = input.priority
        if let due = input.dueISO8601 { reminder.dueDateComponents = try FamiliarISO8601.components(due) }
        reminder.calendar = try reminderCalendar(identifier: input.listIdentifier)
        try store.save(reminder, commit: true)
        return FamiliarWriteCommitResult(idempotencyKey: key, kind: .reminders, identifier: reminder.calendarItemIdentifier)
    }

    private func eventCalendar(identifier: String?) throws -> EKCalendar {
        if let identifier, let calendar = store.calendar(withIdentifier: identifier) { return calendar }
        guard identifier == nil, let calendar = store.defaultCalendarForNewEvents else { throw FamiliarEventKitError.missingCalendar }
        return calendar
    }

    private func reminderCalendar(identifier: String?) throws -> EKCalendar {
        if let identifier, let calendar = store.calendar(withIdentifier: identifier) { return calendar }
        guard identifier == nil, let calendar = store.defaultCalendarForNewReminders() else { throw FamiliarEventKitError.missingCalendar }
        return calendar
    }
}

nonisolated private enum FamiliarISO8601 {
    static func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        throw FamiliarEventKitError.invalidISO8601(value)
    }

    static func components(_ value: String) throws -> DateComponents {
        let date = try date(value)
        var components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return components
    }
}

private extension FamiliarCalendarEvent {
    nonisolated init(_ event: EKEvent) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.init(id: event.eventIdentifier, title: event.title, startISO8601: formatter.string(from: event.startDate), endISO8601: formatter.string(from: event.endDate), isAllDay: event.isAllDay, location: event.location, notes: event.notes, calendarIdentifier: event.calendar.calendarIdentifier, calendarTitle: event.calendar.title)
    }
}

nonisolated private struct FamiliarReminderCandidate: Sendable {
    let reminder: FamiliarReminder
    let dueDate: Date?
    let searchableText: String
}

private extension FamiliarReminder {
    nonisolated init(_ reminder: EKReminder) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.init(id: reminder.calendarItemIdentifier, title: reminder.title, dueISO8601: reminder.dueDateComponents?.date.map(formatter.string), isCompleted: reminder.isCompleted, priority: reminder.priority, notes: reminder.notes, listIdentifier: reminder.calendar.calendarIdentifier, listTitle: reminder.calendar.title)
    }
}
