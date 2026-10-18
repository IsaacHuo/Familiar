import Foundation
import SwiftData

/// Local composition state. A draft may exist before its Conversation does.
@Model
final class FamiliarComposerDraftRecord {
    @Attribute(.unique) var id: UUID
    var conversationID: UUID?
    var projectID: UUID?
    var text: String = ""
    var selectionStart: Int = 0
    var selectionEnd: Int = 0
    var skillID: UUID?
    var attachmentsData: Data = Data()
    var updatedAt: Date = Date()

    init(id: UUID, conversationID: UUID?, projectID: UUID?) {
        self.id = id
        self.conversationID = conversationID
        self.projectID = projectID
    }

    func attachments() throws -> [FamiliarAttachmentDraft] {
        attachmentsData.isEmpty ? [] : try JSONDecoder().decode([FamiliarAttachmentDraft].self, from: attachmentsData)
    }
}

/// Presentation metadata is never compiled into model context or authorization.
@Model
final class FamiliarConversationListStateRecord {
    @Attribute(.unique) var conversationID: UUID
    var isArchived: Bool = false
    var unreadReplyID: UUID?
    var manuallyUnread: Bool = false
    var hasFailure: Bool = false
    var preview: String = ""
    var latestActivityAt: Date = Date()

    init(conversationID: UUID, preview: String = "", latestActivityAt: Date = Date()) {
        self.conversationID = conversationID
        self.preview = preview
        self.latestActivityAt = latestActivityAt
    }

    var isUnread: Bool { manuallyUnread || unreadReplyID != nil }
}

@MainActor
enum FamiliarChatListStore {
    static func state(for conversation: FamiliarConversation, in context: ModelContext) throws -> FamiliarConversationListStateRecord {
        let id = conversation.id
        var descriptor = FetchDescriptor<FamiliarConversationListStateRecord>(predicate: #Predicate { $0.conversationID == id })
        descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first { return record }
        let record = FamiliarConversationListStateRecord(conversationID: id,
            preview: summary(try latestMessage(conversationID: id, in: context)), latestActivityAt: conversation.updatedAt)
        context.insert(record)
        return record
    }

    nonisolated static func draft(_ id: UUID, in context: ModelContext) throws -> FamiliarComposerDraftRecord? {
        var descriptor = FetchDescriptor<FamiliarComposerDraftRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func stageMessage(_ message: FamiliarMessage, in context: ModelContext) throws {
        guard let conversation = message.conversation else { return }
        let record = try state(for: conversation, in: context)
        record.hasFailure = false
        record.preview = summary(message)
        record.latestActivityAt = conversation.updatedAt
        if message.role == .assistant { record.unreadReplyID = message.id }
    }

    static func markRead(_ record: FamiliarConversationListStateRecord, replyID: UUID? = nil) {
        // A late visibility callback for an older reply cannot clear a newer one.
        if let replyID, let unread = record.unreadReplyID, unread != replyID { return }
        record.unreadReplyID = nil
        record.manuallyUnread = false
    }

    static func retainedDraftPaths(in context: ModelContext) throws -> Set<String> {
        try context.fetch(FetchDescriptor<FamiliarComposerDraftRecord>()).reduce(into: Set<String>()) { result, record in
            result.formUnion(try record.attachments().map(\.relativePath))
        }
    }

    static func stageRemoval(conversationIDs: Set<UUID>, in context: ModelContext) throws -> [String] {
        let drafts = try context.fetch(FetchDescriptor<FamiliarComposerDraftRecord>())
            .filter { conversationIDs.contains($0.conversationID ?? $0.id) }
        let paths = try drafts.flatMap { try $0.attachments().map(\.relativePath) }
        drafts.forEach(context.delete)
        try context.fetch(FetchDescriptor<FamiliarConversationListStateRecord>())
            .filter { conversationIDs.contains($0.conversationID) }.forEach(context.delete)
        return paths
    }

    static func latestMessage(conversationID: UUID, in context: ModelContext) throws -> FamiliarMessage? {
        var descriptor = FetchDescriptor<FamiliarMessage>(predicate: #Predicate { $0.conversation?.id == conversationID },
            sortBy: [SortDescriptor(\.sequence, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func summary(_ message: FamiliarMessage?) -> String {
        guard let message else { return "" }
        let excerpt = String(message.content.prefix(2_000)).replacingOccurrences(of: #"\[\[[^\]\n]+\]\]"#, with: "", options: .regularExpression)
        let plain = (try? AttributedString(markdown: excerpt)).map { String($0.characters) } ?? excerpt
        let text = plain.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        if !text.isEmpty { return String(text.prefix(200)) }
        let files = message.attachments
        if files.contains(where: { $0.kind == .image }) { return String(localized: "attachment.photos") }
        return files.first?.filename ?? ""
    }
}
