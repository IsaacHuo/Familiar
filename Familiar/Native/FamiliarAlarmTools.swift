import Foundation
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

// MARK: - AlarmKit

/// A scheduled alarm as Familiar reports it to the model and the UI.
nonisolated struct FamiliarScheduledAlarm: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let fireAtISO8601: String?
    let state: String
}

nonisolated enum FamiliarAlarmError: LocalizedError, FamiliarStructuredToolError, Sendable {
    case unsupportedSystemVersion
    case notAuthorized
    case invalidLabel
    case invalidFireDate
    case unknownAlarm(String)
    case serviceFailed(String)

    var code: String {
        switch self {
        case .unsupportedSystemVersion: "alarmkit_unsupported"
        case .notAuthorized: "alarmkit_not_authorized"
        case .invalidLabel: "invalid_alarm_label"
        case .invalidFireDate: "invalid_future_date"
        case .unknownAlarm: "alarm_not_found"
        case .serviceFailed: "alarmkit_failed"
        }
    }

    var isRetryable: Bool {
        switch self {
        // A transient daemon or system failure can clear on its own.
        case .serviceFailed: true
        // Everything else is a fixed platform limit, a denied permission, or bad
        // arguments, so the identical call cannot succeed.
        case .unsupportedSystemVersion, .notAuthorized, .invalidLabel, .invalidFireDate, .unknownAlarm: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedSystemVersion:
            "这台设备的系统版本不支持 AlarmKit（需要 iOS 26.1 或更高版本）。需要持续响铃的闹钟请改用 notification_schedule 安排普通通知。"
        case .notAuthorized:
            "用户未允许 Familiar 安排闹钟。"
        case .invalidLabel:
            "闹钟标签为空或超过 \(FamiliarToolDefaults.Alarm.maximumLabelCharacters) 个字符。"
        case .invalidFireDate:
            "闹钟时间必须是有效且晚于当前时间的 ISO8601 日期。"
        case .unknownAlarm(let id):
            "没有找到由 Familiar 安排的闹钟：\(id)。"
        case .serviceFailed(let detail):
            "AlarmKit 操作失败：\(detail)"
        }
    }
}

nonisolated protocol FamiliarAlarmServicing: Sendable {
    func availability() async -> FamiliarCapabilityAvailability
    func requestAccess() async throws
    func schedule(id: UUID, label: String, fireAt: Date) async throws -> FamiliarScheduledAlarm
    func cancel(id: UUID) async throws
    func alarms() async throws -> [FamiliarScheduledAlarm]
}

/// AlarmKit exists only on iOS 26 and later, while Familiar deploys to iOS 18.
///
/// The gate is iOS 26.1 rather than 26.0 because the non-deprecated
/// `AlarmPresentation.Alert(title:secondaryButton:secondaryButtonBehavior:)`
/// initializer only exists from 26.1. The 26.0 alternative is deprecated and
/// requires supplying a stop button the system now provides itself, so it is not
/// kept as a compatibility path.
///
/// The façade is unconditional and the framework use is gated, so on an older
/// system `availability()` reports `.unavailable`. `FamiliarToolRegistry.manifests()`
/// filters unavailable tools out, which means the alarm tools simply never appear
/// in the model's tool list rather than being offered and then failing.
actor FamiliarAlarmService: FamiliarAlarmServicing {
    func availability() async -> FamiliarCapabilityAvailability {
#if canImport(AlarmKit)
        guard #available(iOS 26.1, *) else {
            return .unavailable(reason: "AlarmKit 需要 iOS 26.1 或更高版本。")
        }
        switch AlarmManager.shared.authorizationState {
        case .authorized: return .available
        case .notDetermined: return .requestable
        case .denied: return .unavailable(reason: "闹钟权限不可用，请在系统设置中允许 Familiar 安排闹钟。")
        @unknown default: return .unavailable(reason: "闹钟权限状态未知。")
        }
#else
        return .unavailable(reason: "此构建不包含 AlarmKit。")
#endif
    }

    func requestAccess() async throws {
#if canImport(AlarmKit)
        guard #available(iOS 26.1, *) else { throw FamiliarAlarmError.unsupportedSystemVersion }
        let state: AlarmManager.AuthorizationState
        do {
            state = try await AlarmManager.shared.requestAuthorization()
        } catch {
            throw FamiliarAlarmError.serviceFailed(error.localizedDescription)
        }
        guard state == .authorized else { throw FamiliarAlarmError.notAuthorized }
#else
        throw FamiliarAlarmError.unsupportedSystemVersion
#endif
    }

    func schedule(id: UUID, label: String, fireAt: Date) async throws -> FamiliarScheduledAlarm {
#if canImport(AlarmKit)
        guard #available(iOS 26.1, *) else { throw FamiliarAlarmError.unsupportedSystemVersion }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= FamiliarToolDefaults.Alarm.maximumLabelCharacters else {
            throw FamiliarAlarmError.invalidLabel
        }
        guard fireAt > Date() else { throw FamiliarAlarmError.invalidFireDate }
        // Alert-only presentation on purpose. Apple documents that an app supporting
        // a countdown presentation must ship a widget extension, otherwise the system
        // may dismiss alarms and fail to alert. Familiar schedules one-shot alerts, so
        // it declares neither countdown nor paused state.
        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: trimmed))
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: FamiliarAlarmMetadata(),
            tintColor: Color.accentColor
        )
        do {
            _ = try await AlarmManager.shared.schedule(
                id: id,
                configuration: AlarmManager.AlarmConfiguration.alarm(
                    schedule: .fixed(fireAt),
                    attributes: attributes
                )
            )
        } catch {
            throw FamiliarAlarmError.serviceFailed(error.localizedDescription)
        }
        return FamiliarScheduledAlarm(
            id: id.uuidString,
            label: trimmed,
            fireAtISO8601: FamiliarISO8601.string(fireAt),
            state: "scheduled"
        )
#else
        throw FamiliarAlarmError.unsupportedSystemVersion
#endif
    }

    func cancel(id: UUID) async throws {
#if canImport(AlarmKit)
        guard #available(iOS 26.1, *) else { throw FamiliarAlarmError.unsupportedSystemVersion }
        do {
            try AlarmManager.shared.cancel(id: id)
        } catch {
            throw FamiliarAlarmError.serviceFailed(error.localizedDescription)
        }
#else
        throw FamiliarAlarmError.unsupportedSystemVersion
#endif
    }

    func alarms() async throws -> [FamiliarScheduledAlarm] {
#if canImport(AlarmKit)
        guard #available(iOS 26.1, *) else { throw FamiliarAlarmError.unsupportedSystemVersion }
        do {
            // AlarmKit only returns alarms owned by this client, so this never
            // exposes alarms created by the system Clock app or other apps.
            return try AlarmManager.shared.alarms.map { alarm in
                FamiliarScheduledAlarm(
                    id: alarm.id.uuidString,
                    label: "",
                    fireAtISO8601: Self.fireDate(of: alarm).map(FamiliarISO8601.string),
                    state: String(describing: alarm.state)
                )
            }
        } catch {
            throw FamiliarAlarmError.serviceFailed(error.localizedDescription)
        }
#else
        throw FamiliarAlarmError.unsupportedSystemVersion
#endif
    }

#if canImport(AlarmKit)
    @available(iOS 26.1, *)
    private static func fireDate(of alarm: Alarm) -> Date? {
        guard case .fixed(let date) = alarm.schedule else { return nil }
        return date
    }
#endif
}

#if canImport(AlarmKit)
/// Familiar attaches no custom alarm UI data. `AlarmMetadata` explicitly allows an
/// empty implementation.
@available(iOS 26.1, *)
nonisolated struct FamiliarAlarmMetadata: AlarmMetadata {
    init() {}
}
#endif

nonisolated struct FamiliarAlarmScheduleTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let label: String
        let fireAtISO8601: String
    }

    private struct UndoOutput: Encodable {
        let cancelled: Bool
        let alarmID: String
    }

    let service: any FamiliarAlarmServicing
    let manifest = FamiliarToolManifest(
        name: "alarm_schedule",
        title: "安排闹钟",
        description: "经确认后使用 Apple AlarmKit 安排一个会持续响铃的闹钟，即使设备处于静音或专注模式也会提醒。只适合真正需要唤醒或强提醒的时刻；普通提醒请使用 notification_schedule，待办事项请使用 create_reminder。",
        parameters: .object(
            [
                "label": .string("闹钟响起时显示的标签，最多 \(FamiliarToolDefaults.Alarm.maximumLabelCharacters) 个字符。"),
                "fireAtISO8601": .string("带时区的 ISO8601 触发时间，必须晚于当前时间。")
            ],
            required: ["label", "fireAtISO8601"]
        ),
        effect: .reversibleWrite,
        risk: .sensitive,
        requirements: [.alarmKit],
        dataDomains: ["alarms.scheduled"],
        privacyLabels: ["alarm-content"],
        supportsIdempotency: true,
        supportsParallelism: false,
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let label = input.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= FamiliarToolDefaults.Alarm.maximumLabelCharacters else {
            throw FamiliarAlarmError.invalidLabel
        }
        let fireAt = try FamiliarISO8601.date(input.fireAtISO8601)
        guard fireAt > Date() else { throw FamiliarAlarmError.invalidFireDate }
        let alarmID = UUID()
        return .action(.init(
            title: manifest.title,
            fields: [
                .init(id: "label", label: String(localized: "approval.field.alarm_label", defaultValue: "Label"), type: .text, value: label),
                .init(id: "fireAt", label: String(localized: "approval.field.alarm_time", defaultValue: "Rings at"), type: .date, value: FamiliarISO8601.string(fireAt))
            ],
            target: alarmID.uuidString,
            targetKey: alarmID.uuidString,
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: String(localized: "approval.consequence.alarm_schedule", defaultValue: "This alarm rings at the scheduled time and can break through silent mode and Focus. You can undo it later from this run."),
            // Durable rather than session-scoped: an alarm's entire purpose is to fire
            // later, very likely after the app has been relaunched. A session-only undo
            // would promise a reversal that no longer exists when the user wants it.
            undoPolicy: .durable,
            idempotencyKey: context.idempotencyKey,
            // A new alarm identity is minted per call, so a reusable authorization
            // would never match anyway. Keep it explicit: every alarm is confirmed once.
            allowedAuthorizationDurations: [.once],
            commit: {
                let scheduled = try await service.schedule(id: alarmID, label: label, fireAt: fireAt)
                return FamiliarCommittedAction(
                    result: .init(
                        envelope: try FamiliarToolResultEnvelope(
                            model: scheduled,
                            presentation: .mutationReceipt(.init(
                                summary: String(localized: "alarm.receipt.scheduled", defaultValue: "Alarm scheduled"),
                                operation: "alarmSchedule",
                                targetIdentifier: scheduled.id,
                                succeeded: true,
                                undoAvailable: true
                            ))
                        ),
                        // Carries the alarm identity to the durable undo recorder.
                        artifactIdentifier: scheduled.id
                    ),
                    undo: {
                        try await service.cancel(id: alarmID)
                        return .init(envelope: try FamiliarToolResultEnvelope(
                            model: UndoOutput(cancelled: true, alarmID: alarmID.uuidString),
                            presentation: .mutationReceipt(.init(
                                summary: String(localized: "alarm.receipt.cancelled", defaultValue: "Alarm cancelled"),
                                operation: "alarmCancel",
                                targetIdentifier: alarmID.uuidString,
                                succeeded: true,
                                undoAvailable: false
                            ))
                        ))
                    }
                )
            }
        ))
    }
}

nonisolated struct FamiliarAlarmCancelTool: FamiliarTool {
    struct Input: Decodable, Sendable { let alarmID: String }
    private struct Output: Encodable { let cancelled: Bool; let alarmID: String }

    let service: any FamiliarAlarmServicing
    let manifest = FamiliarToolManifest(
        name: "alarm_cancel",
        title: "取消闹钟",
        description: "经确认后取消一个由 Familiar 安排的闹钟。只能取消 alarm_list 返回的闹钟，无法访问系统时钟 App 或其他 App 的闹钟。取消后无法自动恢复。",
        parameters: .object(
            ["alarmID": .string("alarm_list 返回的闹钟 identifier。")],
            required: ["alarmID"]
        ),
        effect: .destructiveWrite,
        risk: .sensitive,
        requirements: [.alarmKit],
        dataDomains: ["alarms.scheduled"],
        supportsIdempotency: true,
        supportsParallelism: false,
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let alarmID = UUID(uuidString: input.alarmID) else {
            throw FamiliarAlarmError.unknownAlarm(input.alarmID)
        }
        // Verified against this client's own alarms so a hallucinated identifier
        // fails before the confirmation card is ever shown.
        let existing = try await service.alarms()
        guard existing.contains(where: { $0.id == alarmID.uuidString }) else {
            throw FamiliarAlarmError.unknownAlarm(input.alarmID)
        }
        return .action(.init(
            title: manifest.title,
            fields: [
                .init(id: "alarmID", label: String(localized: "approval.field.alarm_id", defaultValue: "Alarm"), type: .text, value: alarmID.uuidString)
            ],
            target: alarmID.uuidString,
            targetKey: alarmID.uuidString,
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: String(localized: "approval.consequence.alarm_cancel", defaultValue: "This alarm will no longer ring. Cancelling cannot be undone automatically."),
            undoPolicy: .unavailable,
            idempotencyKey: context.idempotencyKey,
            allowedAuthorizationDurations: [.once],
            commit: {
                try await service.cancel(id: alarmID)
                return FamiliarCommittedAction(result: .init(
                    envelope: try FamiliarToolResultEnvelope(
                        model: Output(cancelled: true, alarmID: alarmID.uuidString),
                        presentation: .mutationReceipt(.init(
                            summary: String(localized: "alarm.receipt.cancelled", defaultValue: "Alarm cancelled"),
                            operation: "alarmCancel",
                            targetIdentifier: alarmID.uuidString,
                            succeeded: true,
                            undoAvailable: false
                        ))
                    )
                ))
            }
        ))
    }
}

nonisolated struct FamiliarAlarmListTool: FamiliarTool {
    struct Input: Decodable, Sendable {}

    let service: any FamiliarAlarmServicing
    let manifest = FamiliarToolManifest(
        name: "alarm_list",
        title: "列出闹钟",
        description: "列出由 Familiar 安排的闹钟。AlarmKit 只返回本 App 自己的闹钟，不包含系统时钟 App 或其他 App 的闹钟。",
        parameters: .object([:]),
        effect: .read,
        risk: .low,
        requirements: [.alarmKit],
        dataDomains: ["alarms.scheduled"],
        supportsParallelism: true,
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let alarms = try await service.alarms()
        let records = alarms.map { alarm in
            var fields: [FamiliarToolPresentationPayload.RecordField] = [
                .init(name: "alarmID", value: alarm.id),
                .init(name: "state", value: alarm.state)
            ]
            if let fireAt = alarm.fireAtISO8601 { fields.append(.init(name: "fireAt", value: fireAt)) }
            return FamiliarToolPresentationPayload.Record(id: alarm.id, fields: fields)
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: alarms,
            presentation: .recordCollection(.init(
                summary: String(
                    format: String(localized: "alarm.list.summary", defaultValue: "%lld Familiar alarms"),
                    alarms.count
                ),
                recordType: "scheduledAlarm",
                records: records
            ))
        )))
    }
}
