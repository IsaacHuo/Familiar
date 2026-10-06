import Foundation

/// Presentation-only state: tool execution and authorization never depend on it.
nonisolated enum FamiliarRuntimeDisplayStatus: Equatable, Sendable {
    case running, completed, warning, failed, waiting, cancelled, undone

    var isActive: Bool { self == .running || self == .waiting }
}

nonisolated enum FamiliarRuntimeStageKind: Equatable, Sendable {
    case search, sources, files, execution, analysis, tools, preparation

    static func kind(for name: String?) -> Self {
        switch name {
        case "web_search": .search
        case "web_fetch": .sources
        case "resource_list", "resource_read", "resource_search", "workspace_list", "workspace_read",
             "workspace_search", "file_read", "workspace_image_list", "vision_recognition": .files
        case "shell_execute", "environment_prepare", "workspace_write": .execution
        case "natural_language_analyze": .analysis
        case "tools_load", "current_date_time": .preparation
        default: .tools
        }
    }

    var title: String {
        switch self {
        case .search: String(localized: "runtime.ui.stage.search")
        case .sources: String(localized: "runtime.ui.stage.sources")
        case .files: String(localized: "runtime.ui.stage.files")
        case .execution: String(localized: "runtime.ui.stage.execution")
        case .analysis: String(localized: "runtime.ui.stage.analysis")
        case .tools: String(localized: "runtime.ui.stage.tools")
        case .preparation: String(localized: "runtime.ui.stage.preparation")
        }
    }

    var activeTitle: String {
        switch self {
        case .search: String(localized: "runtime.ui.active.search")
        case .sources: String(localized: "runtime.ui.active.sources")
        case .files: String(localized: "runtime.ui.active.files")
        case .execution: String(localized: "runtime.ui.active.execution")
        case .analysis: String(localized: "runtime.ui.active.analysis")
        case .tools: String(localized: "runtime.ui.active.tools")
        case .preparation: String(localized: "runtime.ui.active.preparation")
        }
    }
}

nonisolated struct FamiliarAssistantTextBlock: Identifiable, Equatable, Sendable {
    let id: String
    let order: Int
    let content: String
    let isStreaming: Bool
    let state: FamiliarResponseBlockState

    init(_ block: FamiliarLiveResponseBlock) {
        id = "text:\(block.id.uuidString)"
        order = block.order
        content = block.content
        isStreaming = block.isStreaming
        state = .completed
    }

    init(_ block: FamiliarResponseBlockSnapshot) {
        id = "text:\(block.id.uuidString)"
        order = block.order
        content = block.content
        isStreaming = false
        state = block.state
    }

    init(message: FamiliarMessageSnapshot, order: Int) {
        id = "text:\(message.id.uuidString)"
        self.order = order
        content = message.content
        isStreaming = false
        state = .completed
    }
}

nonisolated struct FamiliarRuntimeStage: Identifiable, Equatable, Sendable {
    var id: String { activities[0].id }
    let kind: FamiliarRuntimeStageKind
    var activities: [FamiliarSurfaceDescriptor]
    var status: FamiliarRuntimeDisplayStatus { FamiliarRuntimeActivityGroup.status(activities) }
    var searchResults: [FamiliarToolPresentationPayload.SearchResult] {
        var seen = Set<URL>()
        return activities.flatMap { activity -> [FamiliarToolPresentationPayload.SearchResult] in
            guard case .searchResults(let result)? = activity.resultEnvelope?.presentation.content else { return [] }
            return result.results.filter { result in
                guard let url = URL(string: result.url) else { return false }
                return seen.insert(url).inserted
            }
        }
    }
}

nonisolated struct FamiliarRuntimeActivityGroup: Identifiable, Equatable, Sendable {
    var id: String { "runtime:\(activities[0].id)" }
    var order: Int { activities[0].sequence }
    let activities: [FamiliarSurfaceDescriptor]
    let notices: [FamiliarSurfaceDescriptor]

    var stages: [FamiliarRuntimeStage] {
        var result: [FamiliarRuntimeStage] = []
        for activity in activities where !Self.isUtility(activity) {
            let kind = FamiliarRuntimeStageKind.kind(for: activity.toolName)
            if result.last?.kind == kind {
                result[result.count - 1].activities.append(activity)
            } else {
                result.append(.init(kind: kind, activities: [activity]))
            }
        }
        if result.isEmpty { result = [.init(kind: .preparation, activities: activities)] }
        return result
    }

    var status: FamiliarRuntimeDisplayStatus {
        let value = Self.status(activities)
        return value == .completed && notices.contains { $0.id.contains(":budgetExhausted:") } ? .warning : value
    }
    var activeTitle: String {
        if let waiting = activities.first(where: { $0.phase == .awaitingApproval || $0.phase == .awaitingClarification }) {
            return waiting.title
        }
        if status == .waiting { return String(localized: "runtime.ui.waiting") }
        return stages.last(where: { $0.status.isActive })?.kind.activeTitle ?? String(localized: "runtime.ui.completed")
    }

    var searchURLs: Set<URL> {
        Set(activities.flatMap { activity -> [URL] in
            guard activity.phase == .succeeded,
                  case .searchResults(let result)? = activity.resultEnvelope?.presentation.content else { return [] }
            return result.results.compactMap { URL(string: $0.url) }
        })
    }

    var readURLs: Set<URL> {
        Set(activities.compactMap { activity in
            guard activity.toolName == "web_fetch", activity.phase == .succeeded,
                  case .document(let result)? = activity.resultEnvelope?.presentation.content else { return nil }
            return result.url.flatMap(URL.init(string:))
        })
    }

    var failedCount: Int { activities.filter { Self.displayStatus($0) == .warning || Self.displayStatus($0) == .failed }.count }
    var callCount: Int { activities.filter { !Self.isUtility($0) }.count }

    var summary: String {
        var parts: [String] = []
        if !searchURLs.isEmpty { parts.append(String(format: String(localized: "runtime.ui.found_count"), searchURLs.count)) }
        if !readURLs.isEmpty { parts.append(String(format: String(localized: "runtime.ui.read_count"), readURLs.count)) }
        if parts.isEmpty && callCount > 0 {
            let completed = activities.filter { !Self.isUtility($0) && Self.displayStatus($0) == .completed }.count
            parts.append(String(format: String(localized: "runtime.ui.operation_count"), completed, callCount))
        }
        let failedReads = activities.filter { $0.toolName == "web_fetch" && Self.displayStatus($0) == .warning }.count
        if failedReads > 0 { parts.append(String(format: String(localized: "runtime.ui.read_failure_count"), failedReads)) }
        if failedCount > failedReads { parts.append(String(format: String(localized: "runtime.ui.failure_count"), failedCount - failedReads)) }
        if notices.contains(where: { $0.id.contains(":budgetExhausted:") }) { parts.append(String(localized: "runtime.ui.budget_reached")) }
        let skipped = activities.filter { $0.phase == .cancelled && $0.approvalDecision == .cancelled }.count
        if skipped > 0 { parts.append(String(format: String(localized: "runtime.ui.skipped_count"), skipped)) }
        if activities.contains(where: { $0.phase == .cancelled && $0.approvalDecision != .cancelled }) {
            parts.append(String(localized: "runtime.ui.stopped"))
        }
        if activities.contains(where: { $0.phase == .undone }) { parts.append(String(localized: "common.undone")) }
        return parts.isEmpty ? stages[0].kind.title : parts.joined(separator: " · ")
    }

    static func isUtility(_ surface: FamiliarSurfaceDescriptor) -> Bool {
        surface.toolName == "tools_load" || surface.toolName == "current_date_time"
    }

    static func displayStatus(_ surface: FamiliarSurfaceDescriptor) -> FamiliarRuntimeDisplayStatus {
        switch surface.phase {
        case .awaitingApproval, .awaitingClarification: return .waiting
        case .queued: return .waiting
        case .planning, .running: return .running
        case .failed: return surface.effect == .read && !requiresUserAction(surface) ? .warning : .failed
        case .cancelled: return .cancelled
        case .undone: return .undone
        case .succeeded:
            switch surface.resultEnvelope?.presentation.content {
            case .shellExecution(let shell) where shell.status != "succeeded" || (shell.exitCode ?? 0) != 0: return .warning
            case .mutationReceipt(let receipt) where !receipt.succeeded: return .failed
            default: return .completed
            }
        }
    }

    static func requiresUserAction(_ surface: FamiliarSurfaceDescriptor) -> Bool {
        surface.phase == .failed && ["missing_search_api_key", "authentication_failed", "permission_denied", "tool_unavailable"].contains(surface.failureCode ?? "")
    }

    static func status(_ activities: [FamiliarSurfaceDescriptor]) -> FamiliarRuntimeDisplayStatus {
        let statuses = activities.map(displayStatus)
        if statuses.contains(.failed) { return .failed }
        if statuses.contains(.running) { return .running }
        if statuses.contains(.waiting) { return .waiting }
        if statuses.contains(.warning) { return .warning }
        if statuses.contains(.cancelled) { return .cancelled }
        if statuses.contains(.undone) { return .undone }
        return .completed
    }
}

nonisolated enum FamiliarAssistantContentBlock: Identifiable, Equatable, Sendable {
    case text(FamiliarAssistantTextBlock)
    case runtime(FamiliarRuntimeActivityGroup)
    case surface(FamiliarSurfaceDescriptor)

    var id: String {
        switch self {
        case .text(let block): block.id
        case .runtime(let activity): activity.id
        case .surface(let surface): "surface:\(surface.id)"
        }
    }
    var order: Int {
        switch self {
        case .text(let block): block.order
        case .runtime(let activity): activity.order
        case .surface(let surface): surface.sequence
        }
    }
}

/// One deterministic projection for live and reopened replies. Text deltas are
/// supplied separately; aggregating tool state never requires parsing model text.
nonisolated enum FamiliarAssistantResponseProjection {
    static func blocks(text: [FamiliarAssistantTextBlock], surfaces: [FamiliarSurfaceDescriptor]) -> [FamiliarAssistantContentBlock] {
        let clarificationCalls = Set(surfaces.filter { $0.kind == .clarification }.compactMap(\.toolCallID))
        var seen = Set<String>()
        var entries = text.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(FamiliarAssistantContentBlock.text)
        entries += surfaces.filter { surface in
            guard surface.kind != .runStatus,
                  surface.kind != .activityTrace || surface.id.hasPrefix("notice:") else { return false }
            if surface.kind != .clarification, let call = surface.toolCallID, clarificationCalls.contains(call) { return false }
            return seen.insert(surface.id).inserted
        }.map(FamiliarAssistantContentBlock.surface)
        entries.sort { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }

        var blocks: [FamiliarAssistantContentBlock] = []
        var activities: [FamiliarSurfaceDescriptor] = []
        var notices: [FamiliarSurfaceDescriptor] = []
        func flush() {
            if !activities.isEmpty {
                let onlyUtilitySuccess = activities.allSatisfy { FamiliarRuntimeActivityGroup.isUtility($0) && $0.phase == .succeeded }
                if !onlyUtilitySuccess || notices.contains(where: { $0.id.contains(":budgetExhausted:") }) { blocks.append(.runtime(.init(activities: activities, notices: notices))) }
            } else {
                // Budget limits remain visible even if no tool interval owns them.
                blocks += notices.filter { $0.id.contains(":budgetExhausted:") }.map(FamiliarAssistantContentBlock.surface)
            }
            activities = []
            notices = []
        }
        for entry in entries {
            switch entry {
            case .text:
                flush()
                blocks.append(entry)
            case .surface(let surface):
                if surface.kind == .activityTrace {
                    notices.append(surface)
                } else if isStandalone(surface) {
                    flush()
                    if FamiliarRuntimeActivityGroup.requiresUserAction(surface) {
                        var failure = surface
                        failure.kind = .failure
                        blocks.append(.surface(failure))
                    } else {
                        blocks.append(entry)
                    }
                } else if !surface.approvalFields.isEmpty && !surface.automaticAuthorization {
                    // Keep the consent boundary after a sensitive read resolves.
                    flush()
                    activities.append(surface)
                    flush()
                } else {
                    activities.append(surface)
                }
            case .runtime: break
            }
        }
        flush()
        return blocks
    }

    static func isStandalone(_ surface: FamiliarSurfaceDescriptor) -> Bool {
        if FamiliarRuntimeActivityGroup.requiresUserAction(surface) { return true }
        if surface.effect != nil && surface.effect != .read,
           surface.toolName != "shell_execute", surface.toolName != "environment_prepare" { return true }
        return switch surface.kind {
        case .approval, .clarification, .file, .mutationReceipt, .taskList, .recommendation, .insight, .code, .share, .diff: true
        case .failure: surface.effect != .read
        default: false
        }
    }
}

nonisolated enum FamiliarRuntimeTechnicalText {
    static func redacted(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?i)(\"(?:api[_-]?key|access[_-]?token|authorization|password|secret)\"\s*:\s*)\"[^\"]*\""#,
            with: "$1\"[REDACTED]\"", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)bearer\s+[a-z0-9._-]+|sk-[a-z0-9_-]+"#, with: "[REDACTED]", options: .regularExpression)
    }
}
