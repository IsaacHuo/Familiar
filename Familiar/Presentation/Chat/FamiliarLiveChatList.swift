import SwiftUI

/// Activity changes do not rebuild the home page's sorted/grouped base projection.
struct FamiliarLiveChatPager: View {
    let coordinator: FamiliarChatSessionCoordinator
    let rowsByFilter: [FamiliarChatListFilter: [FamiliarConversationListSnapshot]]
    let projects: [FamiliarProject]
    @Binding var filter: FamiliarChatListFilter
    let editing: Bool
    @Binding var selection: Set<UUID>
    let counts: [UUID: Int]
    let specialRowsByFilter: [FamiliarChatListFilter: AnyView]
    let specialRowsRevision: Int
    let onManage: () -> Void
    let onOpen: (UUID) -> Void
    let onAction: (UUID, FamiliarConversationListAction) -> Void
    let preview: (UUID) -> [FamiliarMessageSnapshot]

    var body: some View {
        var rows = rowsByFilter
        if let active = coordinator.activeSession, let id = active.selectedConversationID {
            let attention = !active.pendingConfirmations.isEmpty || !active.pendingClarifications.isEmpty
            for key in Array(rows.keys) {
                if let index = rows[key]?.firstIndex(where: { $0.id == id }), let row = rows[key]?[index] {
                    rows[key]?[index] = .init(id: row.id, title: row.title,
                        preview: row.hasDraft ? row.preview : String(localized: attention ? "chat.needs_attention" : "chat.running"),
                        projectName: row.projectName, date: row.date, isPinned: row.isPinned,
                        isUnread: row.isUnread, isArchived: row.isArchived, hasDraft: row.hasDraft,
                        isRunning: true, needsAttention: attention, hasFailure: row.hasFailure, projectID: row.projectID)
                }
            }
        }
        return FamiliarChatProjectPager(rowsByFilter: rows, projects: projects, filter: $filter,
            editing: editing, selection: $selection, counts: counts, specialRowsByFilter: specialRowsByFilter,
            specialRowsRevision: specialRowsRevision, onManage: onManage, onOpen: onOpen, onAction: onAction, preview: preview)
    }
}

struct FamiliarActiveRunStatusLabel: View {
    let controller: FamiliarChatController
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(String(localized: controller.pendingConfirmations.isEmpty && controller.pendingClarifications.isEmpty
                ? "chat.running" : "chat.needs_attention"))
                .font(.subheadline.weight(.medium)).lineLimit(1)
        }.padding(.horizontal, 12).frame(minHeight: 44)
    }
}
