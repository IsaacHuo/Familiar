import Foundation

nonisolated private enum FamiliarEventKitToolSupport {
    static func string(_ description: String) -> FamiliarJSONSchema { .init(type: .string, description: description) }
    static func bool(_ description: String) -> FamiliarJSONSchema { .init(type: .boolean, description: description) }
    static func integer(_ description: String) -> FamiliarJSONSchema { .init(type: .integer, description: description) }
    static func object(_ properties: [String: FamiliarJSONSchema], required: [String]) -> FamiliarJSONSchema {
        .init(type: .object, properties: properties, required: required)
    }
    static func encode<T: Encodable>(_ value: T) throws -> FamiliarToolExecutionResult {
        let data = try JSONEncoder().encode(value)
        let content = String(decoding: data, as: UTF8.self)
        return FamiliarToolExecutionResult(modelContent: content, displayContent: content)
    }
}

nonisolated struct FamiliarCalendarEventsTool: FamiliarTool {
    struct Input: Decodable, Sendable { let startISO8601: String; let endISO8601: String; let limit: Int }
    let service: any FamiliarEventKitServicing
    init(service: any FamiliarEventKitServicing) { self.service = service }
    let manifest = FamiliarToolManifest(
        name: "calendar_events", title: String(localized: "tool.calendar_query"),
        description: "按严格 ISO8601 时间范围读取日历事件；结果最多 200 条，超限直接失败。",
        parameters: FamiliarEventKitToolSupport.object(["startISO8601": FamiliarEventKitToolSupport.string("包含起点，严格 ISO8601"), "endISO8601": FamiliarEventKitToolSupport.string("不晚于终点，严格 ISO8601"), "limit": FamiliarEventKitToolSupport.integer("1-200")], required: ["startISO8601", "endISO8601", "limit"]),
        effect: .read, risk: .sensitive, requirements: [.calendarFullAccess]
    )
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        .result(try FamiliarEventKitToolSupport.encode(await service.events(from: input.startISO8601, to: input.endISO8601, limit: input.limit)))
    }
}

nonisolated struct FamiliarRemindersTool: FamiliarTool {
    struct Input: Decodable, Sendable { let startISO8601: String?; let endISO8601: String?; let text: String?; let limit: Int }
    let service: any FamiliarEventKitServicing
    init(service: any FamiliarEventKitServicing) { self.service = service }
    let manifest = FamiliarToolManifest(
        name: "reminders", title: String(localized: "tool.reminders_query"),
        description: "按严格 ISO8601 截止时间范围和标题/备注文字查询提醒事项；结果最多 200 条。",
        parameters: FamiliarEventKitToolSupport.object(["startISO8601": FamiliarEventKitToolSupport.string("可选，严格 ISO8601"), "endISO8601": FamiliarEventKitToolSupport.string("可选，严格 ISO8601"), "text": FamiliarEventKitToolSupport.string("可选，匹配标题或备注"), "limit": FamiliarEventKitToolSupport.integer("1-200")], required: ["limit"]),
        effect: .read, risk: .sensitive, requirements: [.remindersFullAccess]
    )
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        .result(try FamiliarEventKitToolSupport.encode(await service.reminders(from: input.startISO8601, to: input.endISO8601, text: input.text, limit: input.limit)))
    }
}

nonisolated struct FamiliarCreateCalendarEventTool: FamiliarTool {
    typealias Input = FamiliarEventWriteRequest
    let service: any FamiliarEventKitServicing
    init(service: any FamiliarEventKitServicing) { self.service = service }
    let manifest = FamiliarToolManifest(
        name: "create_calendar_event", title: String(localized: "tool.calendar_create"),
        description: "创建日历事件。执行前由 Familiar 展示结构化预览并逐次确认。",
        parameters: FamiliarEventKitToolSupport.object(["title": FamiliarEventKitToolSupport.string("非空标题"), "startISO8601": FamiliarEventKitToolSupport.string("严格 ISO8601"), "endISO8601": FamiliarEventKitToolSupport.string("严格 ISO8601"), "isAllDay": FamiliarEventKitToolSupport.bool("是否全天"), "location": FamiliarEventKitToolSupport.string("可选地点"), "notes": FamiliarEventKitToolSupport.string("可选备注"), "urlString": FamiliarEventKitToolSupport.string("可选 URL"), "calendarIdentifier": FamiliarEventKitToolSupport.string("可选日历 identifier")], required: ["title", "startISO8601", "endISO8601", "isAllDay"]),
        effect: .reversibleWrite, risk: .sensitive, requirements: [.calendarFullAccess]
    )
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        try Task.checkCancellation()
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FamiliarEventKitError.emptyTitle }
        try FamiliarISO8601ForTools.validate(start: input.startISO8601, end: input.endISO8601)
        let request = FamiliarPendingWriteRequest.event(input)
        let target = try await service.targetDescription(for: request)
        return .action(FamiliarActionProposal(
            title: manifest.title,
            fields: FamiliarEventKitPreview.fields(for: request),
            target: target,
            idempotencyKey: context.idempotencyKey,
            execute: {
                try await service.request(.calendarFullAccess)
                let commit = try await service.commit(request, idempotencyKey: context.idempotencyKey)
                let encoded = try FamiliarEventKitToolSupport.encode(commit)
                return FamiliarToolExecutionResult(modelContent: encoded.modelContent, displayContent: String(localized: "tool.write_succeeded"), artifactIdentifier: commit.identifier)
            },
            undo: { try await service.undoCommit(idempotencyKey: context.idempotencyKey) }
        ))
    }
}

nonisolated struct FamiliarCreateReminderTool: FamiliarTool {
    typealias Input = FamiliarReminderWriteRequest
    let service: any FamiliarEventKitServicing
    init(service: any FamiliarEventKitServicing) { self.service = service }
    let manifest = FamiliarToolManifest(
        name: "create_reminder", title: String(localized: "tool.reminder_create"),
        description: "创建提醒事项。执行前由 Familiar 展示结构化预览并逐次确认。",
        parameters: FamiliarEventKitToolSupport.object(["title": FamiliarEventKitToolSupport.string("非空标题"), "dueISO8601": FamiliarEventKitToolSupport.string("可选截止时间，严格 ISO8601"), "listIdentifier": FamiliarEventKitToolSupport.string("可选提醒列表 identifier"), "priority": FamiliarEventKitToolSupport.integer("0-9"), "notes": FamiliarEventKitToolSupport.string("可选备注")], required: ["title", "priority"]),
        effect: .reversibleWrite, risk: .sensitive, requirements: [.remindersFullAccess]
    )
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        try Task.checkCancellation()
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FamiliarEventKitError.emptyTitle }
        guard (0...9).contains(input.priority) else { throw FamiliarEventKitError.invalidRange }
        if let dueISO8601 = input.dueISO8601 { _ = try FamiliarISO8601ForTools.date(dueISO8601) }
        let request = FamiliarPendingWriteRequest.reminder(input)
        let target = try await service.targetDescription(for: request)
        return .action(FamiliarActionProposal(
            title: manifest.title,
            fields: FamiliarEventKitPreview.fields(for: request),
            target: target,
            idempotencyKey: context.idempotencyKey,
            execute: {
                try await service.request(.remindersFullAccess)
                let commit = try await service.commit(request, idempotencyKey: context.idempotencyKey)
                let encoded = try FamiliarEventKitToolSupport.encode(commit)
                return FamiliarToolExecutionResult(modelContent: encoded.modelContent, displayContent: String(localized: "tool.write_succeeded"), artifactIdentifier: commit.identifier)
            },
            undo: { try await service.undoCommit(idempotencyKey: context.idempotencyKey) }
        ))
    }
}

nonisolated enum FamiliarEventKitPreview {
    static func fields(for request: FamiliarPendingWriteRequest) -> [String: String] {
        switch request {
        case .event(let event):
            var fields = [String(localized: "eventkit.field.title"): event.title, String(localized: "eventkit.field.start"): event.startISO8601, String(localized: "eventkit.field.end"): event.endISO8601, String(localized: "eventkit.field.all_day"): event.isAllDay ? String(localized: "common.yes") : String(localized: "common.no")]
            if let value = event.location, !value.isEmpty { fields[String(localized: "eventkit.field.location")] = value }
            if let value = event.notes, !value.isEmpty { fields[String(localized: "eventkit.field.notes")] = value }
            return fields
        case .reminder(let reminder):
            var fields = [String(localized: "eventkit.field.title"): reminder.title, String(localized: "eventkit.field.priority"): String(reminder.priority)]
            if let value = reminder.dueISO8601 { fields[String(localized: "eventkit.field.due")] = value }
            if let value = reminder.notes, !value.isEmpty { fields[String(localized: "eventkit.field.notes")] = value }
            return fields
        }
    }
}

nonisolated private enum FamiliarISO8601ForTools {
    static func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        throw FamiliarEventKitError.invalidISO8601(value)
    }
    static func validate(start: String, end: String) throws {
        guard try date(start) < date(end) else { throw FamiliarEventKitError.invalidRange }
    }
}
