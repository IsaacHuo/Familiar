import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

nonisolated struct FamiliarSpotlightConversation: Equatable, Sendable {
    let id: UUID
    let title: String
    let updatedAt: Date

    var searchableIdentifier: String {
        "conversation:\(id.uuidString)"
    }
}

actor FamiliarSpotlightIndexer {
    static let shared = FamiliarSpotlightIndexer()
    static let domainIdentifier = "com.isaachuo.familiar.conversations"
    static let maximumTitleCharacters = 80

    private let index = CSSearchableIndex(
        name: "FamiliarConversations",
        protectionClass: .complete
    )
    private var pendingConversations: [FamiliarSpotlightConversation]?
    private var isUpdating = false

    func replaceConversations(_ conversations: [FamiliarSpotlightConversation]) async {
        pendingConversations = conversations
        guard !isUpdating else { return }

        isUpdating = true
        defer { isUpdating = false }

        while let latest = pendingConversations {
            pendingConversations = nil
            do {
                try await replaceIndex(with: latest)
            } catch {
                // Spotlight is an optional system surface. The local conversation remains authoritative.
            }
        }
    }

    nonisolated static func deepLink(forSearchableIdentifier identifier: String) -> FamiliarDeepLink? {
        let prefix = "conversation:"
        guard identifier.hasPrefix(prefix),
              let id = UUID(uuidString: String(identifier.dropFirst(prefix.count)))
        else { return nil }
        return .conversation(id)
    }

    nonisolated static func deepLink(from userActivity: NSUserActivity) -> FamiliarDeepLink? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return nil }
        return deepLink(forSearchableIdentifier: identifier)
    }

    nonisolated static func searchableItem(for conversation: FamiliarSpotlightConversation) -> CSSearchableItem {
        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedTitle = String(title.prefix(maximumTitleCharacters))
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = boundedTitle.isEmpty ? String(localized: "conversation.new") : boundedTitle
        attributes.displayName = attributes.title
        attributes.contentDescription = String(localized: "spotlight.conversation.description")
        attributes.metadataModificationDate = conversation.updatedAt
        attributes.keywords = ["Familiar", String(localized: "spotlight.conversation.keyword")]

        let item = CSSearchableItem(
            uniqueIdentifier: conversation.searchableIdentifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
        item.expirationDate = Date.distantFuture
        return item
    }

    private func replaceIndex(with conversations: [FamiliarSpotlightConversation]) async throws {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        try await deleteConversationDomain()
        guard !conversations.isEmpty else { return }
        try await indexItems(conversations.map(Self.searchableItem))
    }

    private func deleteConversationDomain() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func indexItems(_ items: [CSSearchableItem]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            index.indexSearchableItems(items) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
