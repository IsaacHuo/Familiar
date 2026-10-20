import Foundation
import Observation
import SwiftData

nonisolated struct FamiliarLocalSearchRequest: Equatable, Sendable {
    let query: String
    /// nil searches all conversations; an empty array deliberately matches nothing.
    let conversationIDs: [UUID]?
    var includeTitles = true
}

nonisolated struct FamiliarLocalSearchHit: Identifiable, Equatable, Sendable {
    let id: UUID
    let conversationID: UUID
    let title: String
    let excerpt: String
    let date: Date
    let isArchived: Bool
}

nonisolated struct FamiliarLocalSearchPage: Sendable {
    var conversations: [FamiliarLocalSearchHit] = []
    var messages: [FamiliarLocalSearchHit] = []
    var conversationCount = 0
    var messageCount = 0
    static let size = 50
}

@ModelActor actor FamiliarLocalSearchStore {
    func search(_ request: FamiliarLocalSearchRequest, offset: Int) throws -> FamiliarLocalSearchPage {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, request.conversationIDs?.isEmpty != true else { return .init() }
        try Task.checkCancellation()
        let messagePredicate: Predicate<FamiliarMessage>
        let chatPredicate: Predicate<FamiliarConversation>
        if let ids = request.conversationIDs {
            messagePredicate = #Predicate { $0.content.localizedStandardContains(query) && ($0.conversation.flatMap { ids.contains($0.id) } ?? false) }
            chatPredicate = #Predicate { $0.title.localizedStandardContains(query) && ids.contains($0.id) }
        } else {
            messagePredicate = #Predicate { $0.content.localizedStandardContains(query) && $0.conversation != nil }
            chatPredicate = #Predicate { $0.title.localizedStandardContains(query) }
        }
        var result = FamiliarLocalSearchPage()
        result.messageCount = try modelContext.fetchCount(FetchDescriptor(predicate: messagePredicate))
        var messages = FetchDescriptor(predicate: messagePredicate,
            sortBy: [SortDescriptor(\FamiliarMessage.createdAt, order: .reverse), SortDescriptor(\FamiliarMessage.sequence, order: .reverse)])
        messages.fetchOffset = offset
        messages.fetchLimit = FamiliarLocalSearchPage.size
        let archived = Set(try modelContext.fetch(FetchDescriptor<FamiliarConversationListStateRecord>(predicate: #Predicate { $0.isArchived })).map(\.conversationID))
        for message in try modelContext.fetch(messages) {
            try Task.checkCancellation()
            guard let chat = message.conversation else { continue }
            result.messages.append(.init(id: message.id, conversationID: chat.id, title: chat.title,
                excerpt: FamiliarSearchText.excerpt(message.content, query: query), date: message.createdAt, isArchived: archived.contains(chat.id)))
        }
        if request.includeTitles {
            result.conversationCount = try modelContext.fetchCount(FetchDescriptor(predicate: chatPredicate))
            var chats = FetchDescriptor(predicate: chatPredicate, sortBy: [SortDescriptor(\FamiliarConversation.updatedAt, order: .reverse)])
            chats.fetchOffset = offset
            chats.fetchLimit = FamiliarLocalSearchPage.size
            for chat in try modelContext.fetch(chats) {
                try Task.checkCancellation()
                result.conversations.append(.init(id: chat.id, conversationID: chat.id, title: chat.title,
                    excerpt: chat.project?.displayName ?? "", date: chat.updatedAt, isArchived: archived.contains(chat.id)))
            }
        }
        return result
    }
}

nonisolated enum FamiliarSearchText {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
    static func excerpt(_ text: String, query: String) -> String {
        guard let hit = text.range(of: query, options: options, locale: .current) else { return String(text.prefix(240)) }
        let start = text.index(hit.lowerBound, offsetBy: -70, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(hit.upperBound, offsetBy: 150, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…") + text[start..<end] + (end == text.endIndex ? "" : "…")
    }
}

/// Owns only a view's local query snapshot. No network, history writes or Runtime.
@MainActor @Observable final class FamiliarLocalSearchModel {
    private(set) var request: FamiliarLocalSearchRequest?
    private(set) var result = FamiliarLocalSearchPage()
    private(set) var loading = false
    private(set) var error: String?
    private var generation = UUID()
    private var nextOffset = 0
    var hasMore: Bool { nextOffset < max(result.messageCount, result.conversationCount) }

    func update(_ request: FamiliarLocalSearchRequest, container: ModelContainer) async {
        let id = UUID()
        generation = id
        self.request = request
        result = .init(); error = nil; nextOffset = 0
        guard !request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { loading = false; return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(200))
            try await fetch(request, container: container, id: id)
        } catch is CancellationError { }
        catch { if generation == id { self.error = error.localizedDescription } }
        if generation == id { loading = false }
    }

    func loadMore(container: ModelContainer) async {
        guard !loading, hasMore, let request else { return }
        loading = true; error = nil
        let id = generation
        do { try await fetch(request, container: container, id: id) }
        catch is CancellationError { }
        catch { if generation == id { self.error = error.localizedDescription } }
        if generation == id { loading = false }
    }

    private func fetch(_ request: FamiliarLocalSearchRequest, container: ModelContainer, id: UUID) async throws {
        let offset = nextOffset
        let job = Task.detached(priority: .userInitiated) {
            let store = FamiliarLocalSearchStore(modelContainer: container)
            return try await store.search(request, offset: offset)
        }
        let page = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        try Task.checkCancellation()
        guard generation == id else { return }
        let chatIDs = Set(result.conversations.map(\.id)), messageIDs = Set(result.messages.map(\.id))
        result.conversations += page.conversations.filter { !chatIDs.contains($0.id) }
        result.messages += page.messages.filter { !messageIDs.contains($0.id) }
        result.conversationCount = page.conversationCount; result.messageCount = page.messageCount
        nextOffset += FamiliarLocalSearchPage.size
    }
}
