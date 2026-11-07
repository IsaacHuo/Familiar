import Foundation
import SwiftData

nonisolated enum FamiliarHistoryReadError: LocalizedError {
    case scopeChanged
    var errorDescription: String? { String(localized: "history.scope_changed") }
}

nonisolated struct FamiliarHistoryReadResult: Sendable {
    let index: FamiliarConversationHistoryIndex
    let page: FamiliarConversationHistoryPage
    let anchor: String?
    let scope: FamiliarWorkScope
}

/// Only value snapshots leave this actor. A fresh context avoids retaining old
/// registered objects after another context saves or moves the conversation.
@ModelActor actor FamiliarChatHistoryReader {
    func load(conversationID: UUID, cachedIndex: FamiliarConversationHistoryIndex?, anchor: String?,
              messageID: UUID?, activeRunID: String?) throws -> FamiliarHistoryReadResult {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var query = FetchDescriptor<FamiliarConversation>(predicate: #Predicate { $0.id == conversationID })
        query.fetchLimit = 1
        guard let conversation = try context.fetch(query).first else { throw CocoaError(.fileReadNoSuchFile) }
        let index = try cachedIndex ?? FamiliarChatHistoryStore.index(conversationID: conversationID, in: context)
        guard index.conversationID == conversationID else { throw CocoaError(.coderInvalidValue) }
        let target: String?
        if let messageID {
            guard let value = index.messageEntries[messageID] else { throw CocoaError(.fileReadNoSuchFile) }
            target = value
        } else if let anchor, index.positions[anchor] != nil { target = anchor }
        else {
            guard anchor == nil || cachedIndex == nil else { throw CocoaError(.fileReadNoSuchFile) }
            target = nil
        }
        try Task.checkCancellation()
        let page = try FamiliarChatHistoryStore.page(conversation: conversation,
            references: Array(index.entries[index.range(anchor: target)]), activeRunID: activeRunID, in: context)
        try Task.checkCancellation()
        return .init(index: index, page: page, anchor: target,
            scope: conversation.project.map { .project($0.id) } ?? .conversation(conversationID))
    }

    func messages(conversationID: UUID, beforeSequence: Int?) throws -> [FamiliarMessageSnapshot] {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        return try FamiliarChatHistoryStore.messages(conversationID: conversationID, beforeSequence: beforeSequence, in: context)
    }

    @concurrent static func read(container: ModelContainer, conversationID: UUID,
        cachedIndex: FamiliarConversationHistoryIndex? = nil, anchor: String? = nil,
        messageID: UUID? = nil, activeRunID: String? = nil) async throws -> FamiliarHistoryReadResult {
        let reader = FamiliarChatHistoryReader(modelContainer: container)
        return try await reader.load(conversationID: conversationID, cachedIndex: cachedIndex,
            anchor: anchor, messageID: messageID, activeRunID: activeRunID)
    }

    @concurrent static func readMessages(container: ModelContainer, conversationID: UUID,
                                        beforeSequence: Int?) async throws -> [FamiliarMessageSnapshot] {
        let reader = FamiliarChatHistoryReader(modelContainer: container)
        return try await reader.messages(conversationID: conversationID, beforeSequence: beforeSequence)
    }
}
