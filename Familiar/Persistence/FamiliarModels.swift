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

    @Relationship(deleteRule: .cascade, inverse: \FamiliarAgentRun.conversation)
    var agentRuns: [FamiliarAgentRun]

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
        agentRuns = []
    }
}

@Model
final class FamiliarAgentRun {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var runtimeID: String
    var statusRawValue: String
    var startedAt: Date
    var finishedAt: Date?
    var finishReason: String?
    var responseMessageID: UUID?
    var conversation: FamiliarConversation?

    @Relationship(deleteRule: .cascade, inverse: \FamiliarAgentStep.run)
    var steps: [FamiliarAgentStep]

    init(id: UUID = UUID(), runtimeID: String, status: FamiliarAgentRunStatus = .running, startedAt: Date = Date(), conversation: FamiliarConversation? = nil) {
        self.id = id
        self.runtimeID = runtimeID
        statusRawValue = status.rawValue
        self.startedAt = startedAt
        self.conversation = conversation
        steps = []
    }

    var status: FamiliarAgentRunStatus {
        get { FamiliarAgentRunStatus(rawValue: statusRawValue) ?? .failed }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class FamiliarAgentStep {
    @Attribute(.unique) var id: UUID
    var typeRawValue: String
    var eventSequence: Int
    var timelineSequence: Int
    var toolCallID: String
    var toolName: String
    var summary: String
    var detail: String
    var confirmationRawValue: String
    var statusRawValue: String
    var startedAt: Date
    var finishedAt: Date
    var artifactIdentifier: String?
    var run: FamiliarAgentRun?

    init(
        id: UUID = UUID(),
        type: FamiliarAgentStepType,
        eventSequence: Int,
        timelineSequence: Int,
        toolCallID: String,
        toolName: String,
        summary: String,
        detail: String,
        confirmation: FamiliarPersistedConfirmationResult,
        status: FamiliarToolRunTerminalStatus,
        startedAt: Date,
        finishedAt: Date,
        artifactIdentifier: String? = nil,
        run: FamiliarAgentRun? = nil
    ) {
        self.id = id
        typeRawValue = type.rawValue
        self.eventSequence = eventSequence
        self.timelineSequence = timelineSequence
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.summary = summary
        self.detail = detail
        confirmationRawValue = confirmation.rawValue
        statusRawValue = status.rawValue
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.artifactIdentifier = artifactIdentifier
        self.run = run
    }

    var confirmation: FamiliarPersistedConfirmationResult {
        FamiliarPersistedConfirmationResult(rawValue: confirmationRawValue) ?? .notRequired
    }

    var status: FamiliarToolRunTerminalStatus {
        FamiliarToolRunTerminalStatus(rawValue: statusRawValue) ?? .failed
    }

    var type: FamiliarAgentStepType {
        FamiliarAgentStepType(rawValue: typeRawValue) ?? .result
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

    @Relationship(deleteRule: .cascade, inverse: \FamiliarSourceRecord.message)
    var sources: [FamiliarSourceRecord]

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
        sources = []
    }

    var role: FamiliarMessageRole {
        FamiliarMessageRole(rawValue: roleRawValue) ?? .assistant
    }
}

@Model
final class FamiliarSourceRecord {
    @Attribute(.unique) var id: UUID
    var sourceID: String
    var kindRawValue: String
    var title: String
    var urlString: String
    var siteName: String?
    var snippet: String?
    var sequence: Int
    var retrievedAt: Date
    var message: FamiliarMessage?

    init(
        id: UUID = UUID(),
        sourceID: String,
        kind: FamiliarSourceKind,
        title: String,
        urlString: String,
        siteName: String?,
        snippet: String? = nil,
        sequence: Int,
        retrievedAt: Date,
        message: FamiliarMessage? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        kindRawValue = kind.rawValue
        self.title = title
        self.urlString = urlString
        self.siteName = siteName
        self.snippet = snippet
        self.sequence = sequence
        self.retrievedAt = retrievedAt
        self.message = message
    }

    var kind: FamiliarSourceKind {
        FamiliarSourceKind(rawValue: kindRawValue) ?? .searchResult
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
    var extractionEngine: String
    var extractionVersion: String
    var detectedFormat: String
    var usedOCR: Bool
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
        extractionEngine: String,
        extractionVersion: String,
        detectedFormat: String,
        usedOCR: Bool,
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
        self.extractionEngine = extractionEngine
        self.extractionVersion = extractionVersion
        self.detectedFormat = detectedFormat
        self.usedOCR = usedOCR
        self.createdAt = createdAt
        self.message = message
    }

    var kind: FamiliarAttachmentKind {
        FamiliarAttachmentKind(rawValue: kindRawValue) ?? .document
    }
}
