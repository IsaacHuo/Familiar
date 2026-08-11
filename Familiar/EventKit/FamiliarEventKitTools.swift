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
    struct Input: Decodable, Sendable {
        let startISO8601: String
        let endISO8601: String
        let limit: Int
    }
    let service: FamiliarEventKitService
    init(service: FamiliarEventKitService = FamiliarEventKitService()) { self.service = service }
    let definition = FamiliarToolDefinition(name: "calendar_events", description: "按严格 ISO8601 时间范围读取日历事件；结果最多 200 条，超限直接失败。", parameters: FamiliarEventKitToolSupport.object(["startISO8601": FamiliarEventKitToolSupport.string("包含起点，严格 ISO8601"), "endISO8601": FamiliarEventKitToolSupport.string("不晚于终点，严格 ISO8601"), "limit": FamiliarEventKitToolSupport.integer("1-200")], required: ["startISO8601", "endISO8601", "limit"]))

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolExecutionResult {
        let result = try await service.events(from: input.startISO8601, to: input.endISO8601, limit: input.limit)
        return try FamiliarEventKitToolSupport.encode(result)
    }
}

nonisolated struct FamiliarRemindersTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let startISO8601: String?
        let endISO8601: String?
        let text: String?
        let limit: Int
    }
    let service: FamiliarEventKitService
    init(service: FamiliarEventKitService = FamiliarEventKitService()) { self.service = service }
    let definition = FamiliarToolDefinition(name: "reminders", description: "按严格 ISO8601 截止时间范围和标题/备注文字查询提醒事项；结果最多 200 条。", parameters: FamiliarEventKitToolSupport.object(["startISO8601": FamiliarEventKitToolSupport.string("可选，严格 ISO8601"), "endISO8601": FamiliarEventKitToolSupport.string("可选，严格 ISO8601"), "text": FamiliarEventKitToolSupport.string("可选，匹配标题或备注"), "limit": FamiliarEventKitToolSupport.integer("1-200")], required: ["limit"]))

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolExecutionResult {
        let result = try await service.reminders(from: input.startISO8601, to: input.endISO8601, text: input.text, limit: input.limit)
        return try FamiliarEventKitToolSupport.encode(result)
    }
}

nonisolated struct FamiliarCreateCalendarEventTool: FamiliarTool {
    typealias Input = FamiliarEventWriteRequest
    let definition = FamiliarToolDefinition(name: "create_calendar_event", description: "创建日历事件的待确认计划；execute 不写入 EventKit，确认后由 FamiliarEventKitWriteExecutor.commit 执行。", parameters: FamiliarEventKitToolSupport.object(["title": FamiliarEventKitToolSupport.string("非空标题"), "startISO8601": FamiliarEventKitToolSupport.string("严格 ISO8601"), "endISO8601": FamiliarEventKitToolSupport.string("严格 ISO8601"), "isAllDay": FamiliarEventKitToolSupport.bool("是否全天"), "location": FamiliarEventKitToolSupport.string("可选地点"), "notes": FamiliarEventKitToolSupport.string("可选备注"), "urlString": FamiliarEventKitToolSupport.string("可选 URL"), "calendarIdentifier": FamiliarEventKitToolSupport.string("可选日历 identifier")], required: ["title", "startISO8601", "endISO8601", "isAllDay"]))

    init() {}
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolExecutionResult {
        try Task.checkCancellation()
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FamiliarEventKitError.emptyTitle }
        try FamiliarISO8601ForTools.validate(start: input.startISO8601, end: input.endISO8601)
        return try FamiliarEventKitToolSupport.encode(FamiliarPendingWriteRequest.event(input))
    }
}

nonisolated struct FamiliarCreateReminderTool: FamiliarTool {
    typealias Input = FamiliarReminderWriteRequest
    let definition = FamiliarToolDefinition(name: "create_reminder", description: "创建提醒事项的待确认计划；execute 不写入 EventKit，确认后由 FamiliarEventKitWriteExecutor.commit 执行。", parameters: FamiliarEventKitToolSupport.object(["title": FamiliarEventKitToolSupport.string("非空标题"), "dueISO8601": FamiliarEventKitToolSupport.string("可选截止时间，严格 ISO8601"), "listIdentifier": FamiliarEventKitToolSupport.string("可选提醒列表 identifier"), "priority": FamiliarEventKitToolSupport.integer("0-9；0 无优先级，1 最高，5 中等，9 最低"), "notes": FamiliarEventKitToolSupport.string("可选备注")], required: ["title", "priority"]))

    init() {}
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolExecutionResult {
        try Task.checkCancellation()
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FamiliarEventKitError.emptyTitle }
        guard (0...9).contains(input.priority) else { throw FamiliarEventKitError.invalidRange }
        if let dueISO8601 = input.dueISO8601 { _ = try FamiliarISO8601ForTools.date(dueISO8601) }
        return try FamiliarEventKitToolSupport.encode(FamiliarPendingWriteRequest.reminder(input))
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
        let startDate = try date(start)
        let endDate = try date(end)
        guard startDate < endDate else { throw FamiliarEventKitError.invalidRange }
    }
}
