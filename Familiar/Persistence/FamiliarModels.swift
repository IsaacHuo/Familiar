import Foundation
import SwiftData

@Model
final class FamiliarConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var currentProviderID: String
    var currentModelID: String

    @Relationship(deleteRule: .cascade, inverse: \FamiliarMessage.conversation)
    var messages: [FamiliarMessage]

    @Relationship(deleteRule: .cascade, inverse: \FamiliarModelSwitchRecord.conversation)
    var modelSwitchRecords: [FamiliarModelSwitchRecord]

    @Relationship(deleteRule: .cascade, inverse: \FamiliarToolRunRecord.conversation)
    var toolRunRecords: [FamiliarToolRunRecord]

    init(
        id: UUID = UUID(),
        title: String = String(localized: "conversation.new"),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        currentProviderID: String = FamiliarProviderCatalog.deepSeek.id,
        currentModelID: String = FamiliarProviderCatalog.deepSeek.defaultModel.id
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.currentProviderID = currentProviderID
        self.currentModelID = currentModelID
        messages = []
        modelSwitchRecords = []
        toolRunRecords = []
    }
}

@Model
final class FamiliarToolRunRecord {
    @Attribute(.unique) var id: UUID
    var runID: String
    var toolCallID: String
    var toolName: String
    var summary: String
    var detail: String
    var confirmationRawValue: String
    var statusRawValue: String
    var sequence: Int
    var startedAt: Date
    var finishedAt: Date
    var conversation: FamiliarConversation?

    init(
        id: UUID = UUID(),
        runID: String,
        toolCallID: String,
        toolName: String,
        summary: String,
        detail: String,
        confirmation: FamiliarPersistedConfirmationResult,
        status: FamiliarToolRunTerminalStatus,
        sequence: Int,
        startedAt: Date,
        finishedAt: Date,
        conversation: FamiliarConversation? = nil
    ) {
        self.id = id
        self.runID = runID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.summary = summary
        self.detail = detail
        confirmationRawValue = confirmation.rawValue
        statusRawValue = status.rawValue
        self.sequence = sequence
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.conversation = conversation
    }

    var confirmation: FamiliarPersistedConfirmationResult {
        FamiliarPersistedConfirmationResult(rawValue: confirmationRawValue) ?? .notRequired
    }

    var status: FamiliarToolRunTerminalStatus {
        FamiliarToolRunTerminalStatus(rawValue: statusRawValue) ?? .failed
    }
}

@Model
final class FamiliarMessage {
    @Attribute(.unique) var id: UUID
    var roleRawValue: String
    var content: String
    var createdAt: Date
    var sequence: Int
    var providerID: String?
    var modelID: String?
    var conversation: FamiliarConversation?

    @Relationship(deleteRule: .cascade, inverse: \FamiliarAttachment.message)
    var attachments: [FamiliarAttachment]

    init(
        id: UUID = UUID(),
        role: FamiliarMessageRole,
        content: String,
        createdAt: Date = Date(),
        sequence: Int,
        providerID: String? = nil,
        modelID: String? = nil,
        conversation: FamiliarConversation? = nil
    ) {
        self.id = id
        roleRawValue = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.sequence = sequence
        self.providerID = providerID
        self.modelID = modelID
        self.conversation = conversation
        attachments = []
    }

    var role: FamiliarMessageRole {
        FamiliarMessageRole(rawValue: roleRawValue) ?? .assistant
    }
}

@Model
final class FamiliarAttachment {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var filename: String
    var mimeType: String
    var relativePath: String
    var extractedText: String
    var byteSize: Int64
    var createdAt: Date
    var message: FamiliarMessage?

    init(
        id: UUID = UUID(),
        kind: FamiliarAttachmentKind,
        filename: String,
        mimeType: String,
        relativePath: String,
        extractedText: String,
        byteSize: Int64,
        createdAt: Date = Date(),
        message: FamiliarMessage? = nil
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        self.filename = filename
        self.mimeType = mimeType
        self.relativePath = relativePath
        self.extractedText = extractedText
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.message = message
    }

    var kind: FamiliarAttachmentKind {
        FamiliarAttachmentKind(rawValue: kindRawValue) ?? .document
    }
}
