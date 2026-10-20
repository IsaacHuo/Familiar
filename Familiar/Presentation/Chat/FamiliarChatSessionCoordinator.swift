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
    @ObservationIgnored private var recency: [UUID: UInt64] = [:]
    @ObservationIgnored private var clock: UInt64 = 0
    @ObservationIgnored private var trimID = UUID()
    @ObservationIgnored private var retained: Set<UUID> = []
    @ObservationIgnored private var bookmarks: [UUID: FamiliarChatReadingBookmark] = [:]
    @ObservationIgnored private var bookmarkOrder: [UUID] = []

    init(dependencies: FamiliarAppDependencies) { self.dependencies = dependencies }

    var activeSession: FamiliarChatController? {
        sessions.values.first { $0.isSending || $0.isCompacting }
    }

    func existingSession(id: UUID, in context: ModelContext) throws -> FamiliarChatController? {
        if sessions[id] != nil { return session(id: id, in: context) }
        var descriptor = FetchDescriptor<FamiliarConversation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).first != nil || FamiliarChatListStore.draft(id, in: context) != nil else { return nil }
        return session(id: id, in: context)
    }

    func session(id: UUID, in context: ModelContext) -> FamiliarChatController {
        clock &+= 1; recency[id] = clock
        if let session = sessions[id] { return session }
        let controller = FamiliarChatController(dependencies: dependencies)
        controller.draftConversationID = id
        if let bookmark = bookmarks.removeValue(forKey: id) { controller.scrollSession.restore(bookmark) }
        bookmarkOrder.removeAll { $0 == id }
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
        clock &+= 1; recency[id] = clock
        return id
    }

    func checkpoint(in context: ModelContext) async {
        for session in Array(sessions.values) { await session.checkpointDraft(in: context) }
    }

    func canRelease(_ session: FamiliarChatController) -> Bool {
        !session.isSending && !session.isCompacting && !session.hasPendingPostprocessing &&
            session.pendingAttachmentImports == 0 && session.draftRewriteRequestID == nil &&
            dependencies.foregroundExecution.ownerID != session.executionID
    }

    /// Keep navigation, execution, title/follow-up work and import owners; retain
    /// only two additional idle sessions. A failed/stale checkpoint never evicts.
    func trim(retaining ids: Set<UUID>, idleLimit: Int = 2, in context: ModelContext) async {
        retained = ids
        let generation = UUID(); trimID = generation
        let candidates = sessions.keys.filter { id in
            !ids.contains(id) && sessions[id].map(canRelease) == true
        }.sorted { (recency[$0] ?? 0) < (recency[$1] ?? 0) }
        for id in candidates.prefix(max(0, candidates.count - max(0, idleLimit))) {
            guard !Task.isCancelled, trimID == generation, !retained.contains(id), let session = sessions[id], canRelease(session) else { continue }
            let stamp = recency[id]
            session.draftSaveTask?.cancel()
            guard await session.checkpointDraft(in: context), !Task.isCancelled, trimID == generation,
                  !retained.contains(id), sessions[id] === session, recency[id] == stamp, canRelease(session) else { continue }
            session.draftSaveTask?.cancel()
            session.isDiscarded = true
            session.scrollSession.cancel()
            bookmarks[id] = session.scrollSession.bookmark
            bookmarkOrder.removeAll { $0 == id }; bookmarkOrder.append(id)
            while bookmarkOrder.count > 128 { bookmarks.removeValue(forKey: bookmarkOrder.removeFirst()) }
            sessions.removeValue(forKey: id); recency.removeValue(forKey: id)
        }
    }

    /// Owner-authorized removal of conversations created before AI summary titles.
    /// New records always have an origin, so subsequent launches do not delete them.
    func removePreSummaryHistory(in context: ModelContext) -> String? {
        do {
            let legacy = try context.fetch(FetchDescriptor<FamiliarConversation>()).filter { $0.titleOrigin == nil }
            guard !legacy.isEmpty else { return nil }
            return deleteChats(legacy, in: context)
        } catch { return error.localizedDescription }
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
        recency[id] = recency.removeValue(forKey: oldID)
    }

    func invalidate(_ ids: Set<UUID>) {
        for id in ids { bookmarks.removeValue(forKey: id) }
        bookmarkOrder.removeAll { ids.contains($0) }
        for id in ids where sessions[id]?.isSending != true && sessions[id]?.isCompacting != true {
            sessions[id]?.draftSaveTask?.cancel()
            sessions[id]?.isDiscarded = true
            sessions.removeValue(forKey: id)
            recency.removeValue(forKey: id)
        }
    }
}
