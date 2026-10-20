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
    var editStateData: Data?
    var updatedAt: Date = Date()

    init(id: UUID, conversationID: UUID?, projectID: UUID?) {
        self.id = id
        self.conversationID = conversationID
        self.projectID = projectID
    }

    func attachments() throws -> [FamiliarAttachmentDraft] {
        attachmentsData.isEmpty ? [] : try JSONDecoder().decode([FamiliarAttachmentDraft].self, from: attachmentsData)
    }

    func editState() throws -> FamiliarMessageEditState? {
        try editStateData.map { try JSONDecoder().decode(FamiliarMessageEditState.self, from: $0) }
    }

    func retainedAttachments() throws -> [FamiliarAttachmentDraft] {
        try attachments() + (editState()?.previousDraft.attachments ?? [])
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
            result.formUnion(try record.retainedAttachments().map(\.relativePath))
        }
    }

    static func stageRemoval(conversationIDs: Set<UUID>, in context: ModelContext) throws -> [String] {
        let drafts = try context.fetch(FetchDescriptor<FamiliarComposerDraftRecord>())
            .filter { conversationIDs.contains($0.conversationID ?? $0.id) }
        let paths = try drafts.flatMap { try $0.retainedAttachments().map(\.relativePath) }
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

    static func draftSummary(_ draft: FamiliarComposerDraftRecord) -> String {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = (try? draft.attachments()) ?? []
        let files = attachmentSummary(attachments.map { ($0.kind, $0.filename) })
        return [files, String(text.prefix(180))].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func attachmentSummary(_ files: [(FamiliarAttachmentKind, String)]) -> String {
        let photos = files.filter { $0.0 == .image }.count
        let documents = files.filter { $0.0 != .image }
        var parts: [String] = []
        if photos > 0 { parts.append(String(format: String(localized: "local_search.photos_count"), photos)) }
        parts += documents.prefix(2).map { $0.1 }
        if documents.count > 2 { parts.append(String(format: String(localized: "local_search.files_more"), documents.count - 2)) }
        return parts.joined(separator: " · ")
    }

    static func summary(_ message: FamiliarMessage?) -> String {
        guard let message else { return "" }
        let excerpt = String(message.content.prefix(2_000)).replacingOccurrences(of: #"\[\[[^\]\n]+\]\]"#, with: "", options: .regularExpression)
        let plain = (try? AttributedString(markdown: excerpt)).map { String($0.characters) } ?? excerpt
        let text = plain.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let files = attachmentSummary(message.attachments.map { ($0.kind, $0.filename) })
        return [files, String(text.prefix(200))].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
