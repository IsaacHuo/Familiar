import SwiftData
import SwiftUI

nonisolated extension FamiliarAgentRunStatus {
    var localizedTitle: String {
        switch self {
        case .running: String(localized: "project.run.status.running")
        case .completed: String(localized: "project.run.status.completed")
        case .failed: String(localized: "project.run.status.failed")
        case .cancelled: String(localized: "project.run.status.cancelled")
        }
    }
}

struct FamiliarRunResultSection: View {
    @Query private var messages: [FamiliarMessage]
    @State private var expanded = false
    init(messageID: UUID?) {
        if let id = messageID { _messages = Query(filter: #Predicate<FamiliarMessage> { $0.id == id }) }
        else { _messages = Query(filter: #Predicate<FamiliarMessage> { _ in false }) }
    }
    var body: some View {
        Section(String(localized: "settings.runs.result")) {
            if let message = messages.first {
                DisclosureGroup(isExpanded: $expanded) {
                    if expanded {
                        let snapshot = FamiliarMessageSnapshot(previewing: message)
                        FamiliarMarkdownWebView(markdown: message.content, sources: snapshot.citedSources)
                    }
                } label: {
                    Text(FamiliarChatListStore.summary(message)).font(.subheadline).lineLimit(3)
                }
            } else {
                Text(String(localized: "settings.runs.no_reply")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct FamiliarRunTechnicalContext: View {
    let run: FamiliarAgentRun
    let provider: String
    let model: String
    let resources: [FamiliarContextResourceReference]
    let skills: [FamiliarRunSkillSnapshotRecord]
    let tools: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent(String(localized: "settings.provider"), value: provider)
            LabeledContent(String(localized: "settings.model"), value: model)
            LabeledContent(String(localized: "settings.runs.scope"), value: run.project?.displayName ?? run.conversation?.title ?? String(localized: "common.unknown"))
            LabeledContent("Run ID", value: run.runtimeID).textSelection(.enabled)
            if let reason = run.finishReason { LabeledContent(String(localized: "settings.runs.result"), value: reason).textSelection(.enabled) }
            Divider()
            Text(String(localized: "project.run.resources")).font(.subheadline.weight(.semibold))
            if resources.isEmpty { Text(String(localized: "project.run.resources.empty")).foregroundStyle(.secondary) }
            ForEach(resources, id: \.id) { resource in
                Text(resource.filename)
                Text("v\(resource.version) · \(resource.contentHash)").font(.caption.monospaced()).textSelection(.enabled)
            }
            Divider()
            Text(String(localized: "project.run.skills")).font(.subheadline.weight(.semibold))
            if skills.isEmpty { Text(String(localized: "project.run.skills.empty")).foregroundStyle(.secondary) }
            ForEach(skills) { skill in
                Text(skill.name)
                Text("\(skill.stableID) · v\(skill.version) · \(skill.contentHash)").font(.caption.monospaced()).textSelection(.enabled)
                if !skill.allowedTools.isEmpty { Text(skill.allowedTools.joined(separator: ", ")).foregroundStyle(.secondary) }
            }
            Divider()
            Text(String(localized: "project.run.tools")).font(.subheadline.weight(.semibold))
            if tools.isEmpty { Text(String(localized: "project.run.tools.empty")).foregroundStyle(.secondary) }
            ForEach(tools, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
        }.font(.caption).padding(.vertical, 8)
    }
}
