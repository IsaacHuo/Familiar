import SwiftData
import SwiftUI

struct FamiliarComposerDraftList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FamiliarComposerDraftRecord.updatedAt, order: .reverse) private var drafts: [FamiliarComposerDraftRecord]
    let coordinator: FamiliarChatSessionCoordinator
    let projectID: UUID?
    let onOpen: (UUID) -> Void
    @State private var pendingDelete: UUID?
    @State private var errorMessage: String?
    private var visible: [FamiliarComposerDraftRecord] {
        drafts.filter { $0.conversationID == nil && (projectID == nil || $0.projectID == projectID) }
    }
    var body: some View {
        List {
            ForEach(visible) { draft in
                Button { onOpen(draft.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.pencil").foregroundStyle(FamiliarTheme.accent)
                            .frame(width: 36, height: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(draft.text.isEmpty ? String(localized: "chat.draft") : draft.text)
                                .foregroundStyle(.primary).lineLimit(2)
                            Text(draft.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("chats.draft." + draft.id.uuidString)
                    .contextMenu {
                        Button(String(localized: "common.delete"), systemImage: "trash", role: .destructive) { pendingDelete = draft.id }
                            .disabled(isRunning(draft.id))
                    }
            }
        }
        .navigationTitle(String(localized: "chat.drafts"))
        .overlay { if visible.isEmpty { ContentUnavailableView(String(localized: "chat.drafts.empty"), systemImage: "square.and.pencil").allowsHitTesting(false) } }
        .confirmationDialog(String(localized: "draft.discard.title"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button(String(localized: "draft.discard.action"), role: .destructive) { removeDraft() }
            Button(String(localized: "common.cancel"), role: .cancel) { pendingDelete = nil }
        }
        .alert(String(localized: "app.name"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
    private func isRunning(_ id: UUID) -> Bool {
        coordinator.sessions[id]?.isSending == true || coordinator.sessions[id]?.isCompacting == true
    }
    private func removeDraft() {
        guard let id = pendingDelete else { return }
        pendingDelete = nil
        guard !isRunning(id) else { errorMessage = String(localized: "chat.execution.busy"); return }
        do {
            guard let record = try FamiliarChatListStore.draft(id, in: context), record.conversationID == nil else { return }
            let paths = try record.retainedAttachments().map(\.relativePath)
            context.delete(record)
            try context.save()
            coordinator.invalidate([id])
            FamiliarAttachmentStore.remove(relativePaths: paths)
        } catch { context.rollback(); errorMessage = error.localizedDescription }
    }
}
