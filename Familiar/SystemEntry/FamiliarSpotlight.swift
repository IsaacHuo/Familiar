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

    func searchConversations(
        matching searchText: String,
        limit: Int = 20
    ) async throws -> [FamiliarSpotlightConversation] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, CSSearchableIndex.isIndexingAvailable() else { return [] }
        let escaped = term
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let context = CSSearchQueryContext()
        context.fetchAttributes = ["title", "metadataModificationDate"]
        let query = CSSearchQuery(
            queryString: "domainIdentifier == \"\(Self.domainIdentifier)\" && title == \"*\(escaped)*\"cd",
            queryContext: context
        )
        query.protectionClasses = [.complete]
        var conversations: [FamiliarSpotlightConversation] = []
        for try await result in query.results {
            guard let deepLink = Self.deepLink(forSearchableIdentifier: result.item.uniqueIdentifier),
                  case .conversation(let id) = deepLink
            else { continue }
            conversations.append(.init(
                id: id,
                title: result.item.attributeSet.title ?? String(localized: "conversation.new"),
                updatedAt: result.item.attributeSet.metadataModificationDate ?? .distantPast
            ))
            if conversations.count == max(1, min(limit, 50)) {
                query.cancel()
                break
            }
        }
        return conversations
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

nonisolated struct FamiliarSpotlightSearchTool: FamiliarTool {
    struct Input: Decodable, Sendable { let query: String; let limit: Int? }
    private struct Item: Encodable { let conversationID: UUID; let title: String; let updatedAt: Date }

    let indexer: FamiliarSpotlightIndexer
    let manifest = FamiliarToolManifest(
        name: "familiar_search",
        title: "搜索 Familiar",
        description: "只搜索 Familiar 自己写入私有 Core Spotlight 索引的会话标题，不读取其他 App 或系统全局 Spotlight 内容。",
        parameters: .init(
            type: .object,
            properties: [
                "query": .init(type: .string, description: "会话标题搜索词"),
                "limit": .init(type: .integer, description: "最多返回 20 条")
            ],
            required: ["query"]
        ),
        effect: .read,
        risk: .low,
        requirements: [],
        dataDomains: ["familiar.spotlight.conversation-metadata"],
        supportsParallelism: true,
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let results = try await indexer.searchConversations(
            matching: input.query,
            limit: min(max(input.limit ?? 20, 1), 20)
        )
        let items = results.map { Item(conversationID: $0.id, title: $0.title, updatedAt: $0.updatedAt) }
        let records = items.map { item in
            FamiliarToolPresentationPayload.Record(id: item.conversationID.uuidString, fields: [
                .init(name: "title", value: item.title),
                .init(name: "conversationID", value: item.conversationID.uuidString),
                .init(name: "updatedAt", value: item.updatedAt.ISO8601Format())
            ])
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: items,
            presentation: .recordCollection(.init(
                summary: "找到 \(items.count) 条 Familiar 会话。",
                recordType: "familiarConversation",
                records: records
            ))
        )))
    }
}
