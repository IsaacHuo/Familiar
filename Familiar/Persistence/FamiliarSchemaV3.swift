import Foundation
import SwiftData

enum FamiliarSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            FamiliarConversation.self,
            FamiliarMessage.self,
            FamiliarSourceRecord.self,
            FamiliarAttachment.self,
            FamiliarModelSwitchRecord.self,
            FamiliarAgentRun.self,
            FamiliarAgentStep.self,
            FamiliarProject.self,
            FamiliarProjectInstruction.self,
            FamiliarResource.self,
            FamiliarResourceVersion.self,
            FamiliarContextSnapshotRecord.self,
            FamiliarContextResourceReference.self
        ]
    }

    @Model
    final class FamiliarConversation {
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var currentProviderID: String
        var currentModelID: String
        var project: FamiliarProject?

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
            currentModelID: String = FamiliarProviderCatalog.deepSeek.defaultModel.id,
            project: FamiliarProject? = nil
        ) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.currentProviderID = currentProviderID
            self.currentModelID = currentModelID
            self.project = project
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
        var project: FamiliarProject?
        @Relationship(deleteRule: .cascade, inverse: \FamiliarAgentStep.run)
        var steps: [FamiliarAgentStep]
        @Relationship(deleteRule: .cascade, inverse: \FamiliarContextSnapshotRecord.run)
        var contextSnapshot: FamiliarContextSnapshotRecord?

        init(
            id: UUID = UUID(),
            runtimeID: String,
            status: FamiliarAgentRunStatus = .running,
            startedAt: Date = Date(),
            conversation: FamiliarConversation? = nil,
            project: FamiliarProject? = nil
        ) {
            self.id = id
            self.runtimeID = runtimeID
            statusRawValue = status.rawValue
            self.startedAt = startedAt
            self.conversation = conversation
            self.project = project
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
        var resourceVersion: FamiliarResourceVersion?

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
            message: FamiliarMessage? = nil,
            resourceVersion: FamiliarResourceVersion? = nil
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
            self.resourceVersion = resourceVersion
        }

        var kind: FamiliarAttachmentKind {
            FamiliarAttachmentKind(rawValue: kindRawValue) ?? .document
        }
    }

    @Model
    final class FamiliarModelSwitchRecord {
        @Attribute(.unique) var id: UUID
        var previousProviderID: String
        var previousModelID: String
        var currentProviderID: String
        var currentModelID: String
        var sequence: Int
        var createdAt: Date
        var conversation: FamiliarConversation?

        init(
            id: UUID = UUID(),
            previousProviderID: String,
            previousModelID: String,
            currentProviderID: String = FamiliarProviderCatalog.deepSeek.id,
            currentModelID: String = FamiliarProviderCatalog.deepSeek.defaultModel.id,
            sequence: Int,
            createdAt: Date = Date(),
            conversation: FamiliarConversation? = nil
        ) {
            self.id = id
            self.previousProviderID = previousProviderID
            self.previousModelID = previousModelID
            self.currentProviderID = currentProviderID
            self.currentModelID = currentModelID
            self.sequence = sequence
            self.createdAt = createdAt
            self.conversation = conversation
        }
    }

    @Model
    final class FamiliarProject {
        @Attribute(.unique) var id: UUID
        var name: String
        var summary: String
        var statusRawValue: String
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .nullify, inverse: \FamiliarConversation.project)
        var conversations: [FamiliarConversation]
        @Relationship(deleteRule: .nullify, inverse: \FamiliarAgentRun.project)
        var agentRuns: [FamiliarAgentRun]
        @Relationship(deleteRule: .cascade, inverse: \FamiliarProjectInstruction.project)
        var instruction: FamiliarProjectInstruction?
        @Relationship(deleteRule: .cascade, inverse: \FamiliarResource.project)
        var resources: [FamiliarResource]

        init(
            id: UUID = UUID(),
            name: String,
            summary: String = "",
            statusRawValue: String = FamiliarProjectStatus.active.rawValue,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.name = name
            self.summary = summary
            self.statusRawValue = statusRawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            conversations = []
            agentRuns = []
            resources = []
        }

        var status: FamiliarProjectStatus {
            get { FamiliarProjectStatus(rawValue: statusRawValue) ?? .active }
            set { statusRawValue = newValue.rawValue }
        }
    }

    @Model
    final class FamiliarProjectInstruction {
        @Attribute(.unique) var id: UUID
        var text: String
        var createdAt: Date
        var updatedAt: Date
        var project: FamiliarProject?

        init(
            id: UUID = UUID(),
            text: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            project: FamiliarProject? = nil
        ) {
            self.id = id
            self.text = text
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.project = project
        }
    }

    @Model
    final class FamiliarResource {
        @Attribute(.unique) var id: UUID
        var documentKindRawValue: String
        var displayName: String
        var createdAt: Date
        var updatedAt: Date
        var project: FamiliarProject?
        @Relationship(deleteRule: .cascade, inverse: \FamiliarResourceVersion.resource)
        var versions: [FamiliarResourceVersion]

        init(
            id: UUID = UUID(),
            documentKind: FamiliarResourceDocumentKind = .document,
            displayName: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            project: FamiliarProject? = nil
        ) {
            self.id = id
            documentKindRawValue = documentKind.rawValue
            self.displayName = displayName
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.project = project
            versions = []
        }

        var documentKind: FamiliarResourceDocumentKind {
            FamiliarResourceDocumentKind(rawValue: documentKindRawValue) ?? .document
        }
    }

    @Model
    final class FamiliarResourceVersion {
        @Attribute(.unique) var id: UUID
        var version: Int
        var sourceRawValue: String
        var sourceURLString: String?
        var filename: String
        var mimeType: String
        var originalRelativePath: String
        var byteSize: Int64
        var contentHash: String
        var extractedText: String
        var extractedTextHash: String
        var extractionEngine: String
        var extractionVersion: String
        var detectedFormat: String
        var usedOCR: Bool
        var createdAt: Date
        var resource: FamiliarResource?
        @Relationship(deleteRule: .nullify, inverse: \FamiliarAttachment.resourceVersion)
        var attachments: [FamiliarAttachment]

        init(
            id: UUID = UUID(),
            version: Int,
            source: FamiliarResourceVersionSource,
            sourceURLString: String? = nil,
            filename: String,
            mimeType: String,
            originalRelativePath: String,
            byteSize: Int64,
            contentHash: String,
            extractedText: String,
            extractedTextHash: String,
            extractionEngine: String,
            extractionVersion: String,
            detectedFormat: String,
            usedOCR: Bool,
            createdAt: Date = Date(),
            resource: FamiliarResource? = nil
        ) {
            self.id = id
            self.version = version
            sourceRawValue = source.rawValue
            self.sourceURLString = sourceURLString
            self.filename = filename
            self.mimeType = mimeType
            self.originalRelativePath = originalRelativePath
            self.byteSize = byteSize
            self.contentHash = contentHash
            self.extractedText = extractedText
            self.extractedTextHash = extractedTextHash
            self.extractionEngine = extractionEngine
            self.extractionVersion = extractionVersion
            self.detectedFormat = detectedFormat
            self.usedOCR = usedOCR
            self.createdAt = createdAt
            self.resource = resource
            attachments = []
        }

        var source: FamiliarResourceVersionSource {
            FamiliarResourceVersionSource(rawValue: sourceRawValue) ?? .importedFile
        }
    }

    @Model
    final class FamiliarContextSnapshotRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var projectID: UUID?
        var projectName: String?
        var conversationID: UUID
        var projectInstruction: String?
        var providerID: String
        var modelID: String
        var exposedToolNamesJSON: String
        var maximumInputCharacters: Int
        var initialInputCharacters: Int
        var run: FamiliarAgentRun?
        @Relationship(deleteRule: .cascade, inverse: \FamiliarContextResourceReference.snapshot)
        var resourceReferences: [FamiliarContextResourceReference]

        init(
            id: UUID = UUID(),
            createdAt: Date,
            projectID: UUID?,
            projectName: String?,
            conversationID: UUID,
            projectInstruction: String?,
            providerID: String,
            modelID: String,
            exposedToolNamesJSON: String,
            maximumInputCharacters: Int,
            initialInputCharacters: Int,
            run: FamiliarAgentRun? = nil
        ) {
            self.id = id
            self.createdAt = createdAt
            self.projectID = projectID
            self.projectName = projectName
            self.conversationID = conversationID
            self.projectInstruction = projectInstruction
            self.providerID = providerID
            self.modelID = modelID
            self.exposedToolNamesJSON = exposedToolNamesJSON
            self.maximumInputCharacters = maximumInputCharacters
            self.initialInputCharacters = initialInputCharacters
            self.run = run
            resourceReferences = []
        }
    }

    @Model
    final class FamiliarContextResourceReference {
        @Attribute(.unique) var id: UUID
        var resourceID: UUID
        var resourceVersionID: UUID
        var version: Int
        var filename: String
        var mimeType: String
        var contentHash: String
        var extractedTextHash: String
        var snapshot: FamiliarContextSnapshotRecord?

        init(
            id: UUID = UUID(),
            resourceID: UUID,
            resourceVersionID: UUID,
            version: Int,
            filename: String,
            mimeType: String,
            contentHash: String,
            extractedTextHash: String,
            snapshot: FamiliarContextSnapshotRecord? = nil
        ) {
            self.id = id
            self.resourceID = resourceID
            self.resourceVersionID = resourceVersionID
            self.version = version
            self.filename = filename
            self.mimeType = mimeType
            self.contentHash = contentHash
            self.extractedTextHash = extractedTextHash
            self.snapshot = snapshot
        }
    }
}

nonisolated enum FamiliarResourceDocumentKind: String, Codable, Sendable {
    case document
}

nonisolated enum FamiliarResourceVersionSource: String, Codable, Sendable {
    case importedFile
    case messageAttachment
}
