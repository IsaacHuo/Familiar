import Foundation

/// One product catalog for discovery, default capability selection and core exceptions.
nonisolated enum FamiliarToolGroup: String, CaseIterable, Sendable {
    case base, web, calendar, places, files, memory, skills, shell, device, presentation

    static let baseToolNames: Set<String> = ["current_date_time", "ask_user", "tools_load"]

    var title: String {
        switch self {
        case .base: String(localized: "tool.category.basics", defaultValue: "Basics")
        case .web: String(localized: "tool.group.web", defaultValue: "Web")
        case .calendar: String(localized: "tool.group.calendar", defaultValue: "Calendar & Reminders")
        case .places: String(localized: "tool.group.places", defaultValue: "Places & Weather")
        case .files: String(localized: "tool.group.files", defaultValue: "Files")
        case .memory: String(localized: "tool.group.memory", defaultValue: "Memory")
        case .skills: String(localized: "tool.group.skills", defaultValue: "Skills")
        case .shell: String(localized: "tool.group.shell", defaultValue: "Environment & Shell")
        case .device: String(localized: "tool.group.device", defaultValue: "Other Device Tools")
        case .presentation: String(localized: "tool.group.presentation", defaultValue: "Presentation")
        }
    }

    var summary: String {
        switch self {
        case .base: "Base interaction and tool discovery."
        case .web: "Search public information and read web pages."
        case .calendar: "Read or propose changes to calendars and reminders."
        case .places: "Find places and coordinates, then query native weather."
        case .files: "Read, save, revise and share files in the current Project."
        case .memory: "Read frozen memories or propose a confirmed memory."
        case .skills: "Read explicitly attached guidance; installation requires approval."
        case .shell: "Read environment status, prepare dependencies and run controlled computation."
        case .device: "Additional explicitly enabled native device capabilities."
        case .presentation: "Optional checklists, recommendations and charts."
        }
    }

    static func group(for name: String) -> FamiliarToolGroup {
        if baseToolNames.contains(name) { return .base }
        switch name {
        case "web_search", "web_fetch": return .web
        case "calendar_events", "create_calendar_event", "update_calendar_event", "delete_calendar_event",
             "reminders", "create_reminder", "update_reminder", "delete_reminder": return .calendar
        case "map_search", "weather_forecast", "weather_history", "current_location": return .places
        case "file_list", "file_search", "workspace_list", "workspace_read",
             "workspace_search", "workspace_write", "workspace_image_list", "prepare_share", "prepare_file_export": return .files
        case "file_write", "file_edit", "file_read", "file_publish": return .files
        case "memory_search", "memory_remember": return .memory
        case "skill_list", "skill_read", "skill_install": return .skills
        case "environment_status", "environment_prepare", "shell_execute": return .shell
        case "task_plan", "present_recommendation", "present_insight": return .presentation
        default: return .device
        }
    }

    static func isDefaultEnabled(_ name: String) -> Bool {
        if baseToolNames.contains(name) { return true }
        if ["skill_list", "skill_read"].contains(name) { return true }
        if ["workspace_write", "file_publish"].contains(name) { return false }
        switch group(for: name) {
        case .web, .calendar, .places, .files, .memory: return true
        default: return false
        }
    }

    static func allows(_ name: String, skill: FamiliarSkillSnapshot?) -> Bool {
        guard let skill else { return true }
        return baseToolNames.contains(name) || skill.allowedTools.isEmpty || skill.allowedTools.contains(name)
    }

    static func directory(for manifests: [FamiliarToolManifest]) -> [FamiliarToolGroupSummary] {
        allCases.compactMap { group in
            guard group != .base else { return nil }
            let members = manifests.filter { Self.group(for: $0.name) == group }
            guard !members.isEmpty else { return nil }
            return .init(id: group.rawValue, title: group.title, summary: group.summary)
        }
    }
}

nonisolated struct FamiliarToolGroupSummary: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let summary: String
}

/// A frozen, user-enabled discovery source. Credentials stay inside this closure,
/// never in the group summary or persisted ContextSnapshot.
nonisolated struct FamiliarDeferredToolGroup: Sendable {
    let summary: FamiliarToolGroupSummary
    let discover: @Sendable () async throws -> [AnyFamiliarTool]
}

nonisolated struct FamiliarToolLoadResult: Sendable {
    struct ToolSummary: Codable, Sendable {
        let name: String
        let title: String
        let description: String
    }
    struct Report: Codable, Sendable {
        let groups: [String]
        let activeTools: [String]
        let availableTools: [ToolSummary]
        let nextOffset: Int?
        let unavailable: [FamiliarUnavailableTool]
    }
    let manifests: [FamiliarToolManifest]
    let report: Report
}

nonisolated struct FamiliarToolsLoadTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let groups: [String]
        let toolNames: [String]?
        let offset: Int?
    }
    static let definition = FamiliarToolManifest(
        name: "tools_load", title: "Load tools",
        description: "Load only the tool groups needed now. This replaces the active extension tools for the next request; it does not execute actions or grant permission. Use [] to return to base tools. Remote groups first return a paged directory; select exact toolNames on another call to expose their schemas.",
        parameters: .object([
            "groups": .stringArray("Up to two group IDs from the frozen tool_groups directory.", itemDescription: "Tool group ID", maxItems: 2),
            "toolNames": .stringArray("Optional exact tool names to select; required to activate remote tools.", itemDescription: "Model-facing tool name", maxItems: 16),
            "offset": .integer("Directory page offset, starting at zero.", minimum: 0)
        ], required: ["groups"]), effect: .read, risk: .low, supportsParallelism: false
    )
    let manifest = definition

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let load = context.loadTools else { throw FamiliarToolLoadError("Tool loading is unavailable in this run.") }
        let value = try await load(input.groups, input.toolNames, input.offset ?? 0, context.activeSkill)
        let summary: String
        let detail: String
        if !value.report.unavailable.isEmpty {
            summary = String(localized: "tool.load.partial", defaultValue: "Some tools are unavailable")
            detail = value.report.unavailable.map { $0.title + ": " + $0.reason }.joined(separator: "\n")
        } else if !input.groups.isEmpty, value.report.activeTools.allSatisfy(FamiliarToolGroup.baseToolNames.contains) {
            summary = String(localized: "tool.load.directory", defaultValue: "Available tools checked")
            detail = String(localized: "tool.load.directory.detail", defaultValue: "Only the tools needed for this task will be used.")
        } else {
            summary = String(localized: "tool.load.complete", defaultValue: "Tools prepared")
            detail = String(localized: "tool.load.detail", defaultValue: "The tools needed for this step are ready.")
        }
        return .result(.init(envelope: try .init(model: value.report,
            presentation: .scalar(.init(summary: summary, value: detail))),
            loadedTools: value.manifests))
    }
}

nonisolated struct FamiliarToolLoadError: LocalizedError, FamiliarStructuredToolError {
    let detail: String
    init(_ detail: String) { self.detail = detail }
    var errorDescription: String? { detail }
    var code: String { "tool_load_failed" }
    var isRetryable: Bool { false }
}
