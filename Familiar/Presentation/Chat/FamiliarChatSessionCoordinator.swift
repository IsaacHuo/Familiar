import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class FamiliarForegroundExecution {
    private(set) var ownerID: UUID?
    var isBusy: Bool { ownerID != nil }
    func claim(_ id: UUID) -> Bool {
        guard ownerID == nil else { return false }
        ownerID = id
        return true
    }
    func release(_ id: UUID) { if ownerID == id { ownerID = nil } }
}

nonisolated enum FamiliarAppTab: Hashable { case files, chats, settings }
nonisolated enum FamiliarChatListFilter: Hashable { case recent, project(UUID) }
nonisolated enum FamiliarChatRoute: Hashable {
    case chat(UUID)
    case archive
    case drafts(UUID?)
    case projects
    case project(UUID)
    case message(UUID, UUID)
}

/// Retains foreground sessions across navigation; all sessions share one execution lease.
@MainActor @Observable
final class FamiliarChatSessionCoordinator {
    let dependencies: FamiliarAppDependencies
    private(set) var sessions: [UUID: FamiliarChatController] = [:]

    init(dependencies: FamiliarAppDependencies) { self.dependencies = dependencies }

    var activeSession: FamiliarChatController? {
        sessions.values.first { $0.isSending || $0.isCompacting }
    }

    func session(id: UUID, in context: ModelContext) -> FamiliarChatController {
        if let session = sessions[id] { return session }
        let controller = FamiliarChatController(dependencies: dependencies)
        controller.draftConversationID = id
        do {
            var descriptor = FetchDescriptor<FamiliarConversation>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if try context.fetch(descriptor).first != nil { controller.select(id, in: context) }
            try controller.restoreDraft(id: id, in: context)
        } catch { controller.errorMessage = error.localizedDescription }
        sessions[id] = controller
        return controller
    }

    func newDraft(projectID: UUID?, in context: ModelContext) -> UUID {
        let id = UUID()
        let controller = FamiliarChatController(dependencies: dependencies)
        controller.draftConversationID = id
        controller.selectedProjectID = projectID
        sessions[id] = controller
        return id
    }

    func checkpoint(in context: ModelContext) async {
        for session in Array(sessions.values) { await session.checkpointDraft(in: context) }
    }

    func deleteChats(_ chats: [FamiliarConversation], in context: ModelContext) -> String? {
        if let active = activeSession?.selectedConversationID, chats.contains(where: { $0.id == active }) {
            return String(localized: "chat.execution.busy")
        }
        let controller = FamiliarChatController(dependencies: dependencies)
        controller.delete(chats, in: context)
        if let error = controller.errorMessage { return error }
        invalidate(Set(chats.map(\.id)))
        return nil
    }

    func reconcileProjects(_ validIDs: Set<UUID>, in context: ModelContext) {
        for session in sessions.values where !session.isSending && !session.isCompacting {
            if let id = session.selectedProjectID, !validIDs.contains(id) {
                session.selectedProjectID = nil
                session.reloadMessages(in: context)
                session.scheduleDraftCheckpoint(in: context)
            }
        }
    }

    func rekey(_ oldID: UUID, to id: UUID) {
        guard oldID != id, let session = sessions.removeValue(forKey: oldID) else { return }
        sessions[id] = session
    }

    func invalidate(_ ids: Set<UUID>) {
        for id in ids where sessions[id]?.isSending != true && sessions[id]?.isCompacting != true {
            sessions[id]?.draftSaveTask?.cancel()
            sessions[id]?.isDiscarded = true
            sessions.removeValue(forKey: id)
        }
    }
}
