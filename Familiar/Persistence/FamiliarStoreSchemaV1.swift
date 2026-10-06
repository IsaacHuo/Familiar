import Foundation
import SwiftData

/// Frozen storage definitions of the pre-convergence 1.0.0 store.
/// Never edit these models. Future changes belong in a new VersionedSchema.
/// V3...V11 were source organization, not historical store versions.
enum FamiliarStoreSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            FamiliarConversation.self,
            FamiliarAgentRun.self,
            FamiliarMessage.self,
            FamiliarSourceRecord.self,
            FamiliarAttachment.self,
            FamiliarModelSwitchRecord.self,
            FamiliarProject.self,
            FamiliarProjectInstruction.self,
            FamiliarResource.self,
            FamiliarResourceVersion.self,
            FamiliarContextSnapshotRecord.self,
            FamiliarContextResourceReference.self,
            FamiliarArtifact.self,
            FamiliarCapabilitySnapshotRecord.self,
            FamiliarAuthorizationGrantRecord.self,
            FamiliarRunResumeCursorRecord.self,
            FamiliarToolInvocationRecord.self,
            FamiliarAuthorizationRuleRecord.self,
            FamiliarEventKitUndoRecord.self,
            FamiliarVisualEvidenceRecord.self,
            FamiliarSkill.self,
            FamiliarMemoryItem.self,
            FamiliarMCPServerRecord.self,
            FamiliarMCPBindingRecord.self,
            FamiliarRunSkillSnapshotRecord.self,
            FamiliarActivityRecord.self,
            FamiliarToolResultRecord.self,
            FamiliarApprovalRecord.self,
            FamiliarResponseBlockRecord.self,
            FamiliarClarificationRecord.self,
            FamiliarContextAttachmentReference.self,
            FamiliarEventKitUndoMutationRecord.self,
            FamiliarPinnedItemRecord.self,
            FamiliarProjectEnvironmentRecord.self,
            FamiliarProjectSkillBindingRecord.self,
            FamiliarProjectCapabilityBindingRecord.self,
            FamiliarAlarmUndoRecord.self,
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
        var parentConversationID: UUID?
        var contextSummary: String?
        var summaryThroughSequence: Int?
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
        var firstTokenAt: Date?
        var inputTokenCount: Int?
        var outputTokenCount: Int?
        var cachedInputTokenCount: Int?
        var modelRequestsJSON: String?
        var finishReason: String?
        var responseMessageID: UUID?
        var responseBlockID: UUID?
        var assistantTurnID: String?
        var conversation: FamiliarConversation?
        var project: FamiliarProject?
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
        }

        var status: FamiliarAgentRunStatus {
            get { FamiliarAgentRunStatus(rawValue: statusRawValue) ?? .failed }
            set { statusRawValue = newValue.rawValue }
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
        var runtimeID: String?
        var assistantTurnID: String?
        var responseBlockID: UUID?
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
            runtimeID: String? = nil,
            assistantTurnID: String? = nil,
            responseBlockID: UUID? = nil,
            conversation: FamiliarConversation? = nil
        ) {
            self.id = id
            roleRawValue = role.rawValue
            self.content = content
            self.createdAt = createdAt
            self.sequence = sequence
            self.providerID = providerID
            self.modelID = modelID
            self.runtimeID = runtimeID
            self.assistantTurnID = assistantTurnID
            self.responseBlockID = responseBlockID
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
        var responseBlockID: UUID?
        var retrievalActivityID: String?
        var citationOrdinal: Int?
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
            responseBlockID: UUID? = nil,
            retrievalActivityID: String? = nil,
            citationOrdinal: Int? = nil,
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
            self.responseBlockID = responseBlockID
            self.retrievalActivityID = retrievalActivityID
            self.citationOrdinal = citationOrdinal
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
        /// Stable identity, independent of the localized name and install language.
        static let dailyProjectID = UUID(uuidString: "FA0111A0-0000-4000-8000-000000000001")!
        var isDefaultProject: Bool { id == Self.dailyProjectID }
        var displayName: String {
            isDefaultProject ? String(localized: "conversation.ordinary") : name
        }
        var providerIDOverride: String?
        @Attribute(.unique) var id: UUID
        var name: String
        var summary: String
        var statusRawValue: String
        /// Optional per-Project model. `nil` means follow the global selection, which is
        /// why this is not defaulted to a concrete ID: a stored ID would silently pin the
        /// Project to a model the user never chose for it.
        var modelIDOverride: String?
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

    @Model
    final class FamiliarArtifact {
        @Attribute(.unique) var id: UUID
        var projectID: UUID
        var identifier: String
        /// Groups the successive versions of one logical deliverable. Each version is its
        /// own row and its own directory, because the store keys files by artifact ID and
        /// overwriting in place would destroy the previous version's bytes.
        var lineageID: UUID
        var version: Int
        var title: String
        var formatRawValue: String
        var relativePath: String
        var byteSize: Int64
        var contentHash: String
        var sourceKindRawValue: String
        var sourceURLString: String?
        var sourceResourceID: UUID?
        var sourceResourceVersionID: UUID?
        var sourceCaptureID: String?
        var createdByRunID: String?
        var utiIdentifier: String?
        var mimeType: String?
        var validationReceiptJSON: String?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(), projectID: UUID, identifier: String, title: String,
            lineageID: UUID? = nil, version: Int = 1,
            format: FamiliarArtifactFormat = .markdown, relativePath: String,
            byteSize: Int64, contentHash: String, source: FamiliarArtifactSource = .generated,
            sourceURLString: String? = nil, sourceResourceID: UUID? = nil,
            sourceResourceVersionID: UUID? = nil, sourceCaptureID: String? = nil,
            createdByRunID: String? = nil, utiIdentifier: String? = nil, mimeType: String? = nil,
            validationReceiptJSON: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()
        ) {
            self.id = id; self.projectID = projectID; self.identifier = identifier; self.title = title
            // Defaults to this row's own id: a first version is the origin of its lineage,
            // so an artifact created without an explicit lineage is still well-formed.
            self.lineageID = lineageID ?? id; self.version = version
            formatRawValue = format.rawValue; self.relativePath = relativePath; self.byteSize = byteSize
            self.contentHash = contentHash; sourceKindRawValue = source.rawValue
            self.sourceURLString = sourceURLString; self.sourceResourceID = sourceResourceID
            self.sourceResourceVersionID = sourceResourceVersionID; self.sourceCaptureID = sourceCaptureID
            self.createdByRunID = createdByRunID; self.createdAt = createdAt; self.updatedAt = updatedAt
            self.utiIdentifier = utiIdentifier; self.mimeType = mimeType; self.validationReceiptJSON = validationReceiptJSON
        }

        var format: FamiliarArtifactFormat { FamiliarArtifactFormat(rawValue: formatRawValue) ?? .markdown }
        var source: FamiliarArtifactSource { FamiliarArtifactSource(rawValue: sourceKindRawValue) ?? .generated }
    }

    @Model
    final class FamiliarCapabilitySnapshotRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var projectID: UUID?
        var conversationID: UUID
        var contextSnapshotID: UUID
        var manifestsJSON: String

        init(id: UUID = UUID(), createdAt: Date, projectID: UUID?, conversationID: UUID, contextSnapshotID: UUID, manifestsJSON: String) {
            self.id = id
            self.createdAt = createdAt
            self.projectID = projectID
            self.conversationID = conversationID
            self.contextSnapshotID = contextSnapshotID
            self.manifestsJSON = manifestsJSON
        }
    }

    @Model
    // Stored historical audit columns only. No runtime signs or consumes these rows;
    // current authorization uses FamiliarAuthorizationRuleRecord.
    final class FamiliarAuthorizationGrantRecord {
        @Attribute(.unique) var id: UUID
        var userAction: String
        var sourceRawValue: String
        var capabilityID: String
        var capabilityVersion: String
        var argumentsHash: String
        var projectID: UUID?
        var expiresAt: Date
        var singleUse: Bool
        var evidence: String
        var consumedAt: Date?
        var stateRawValue: String

        init(id: UUID, userAction: String, sourceRawValue: String, capabilityID: String,
             capabilityVersion: String, argumentsHash: String, projectID: UUID?, expiresAt: Date,
             singleUse: Bool, evidence: String, consumedAt: Date?, stateRawValue: String) {
            self.id = id
            self.userAction = userAction
            self.sourceRawValue = sourceRawValue
            self.capabilityID = capabilityID
            self.capabilityVersion = capabilityVersion
            self.argumentsHash = argumentsHash
            self.projectID = projectID
            self.expiresAt = expiresAt
            self.singleUse = singleUse
            self.evidence = evidence
            self.consumedAt = consumedAt
            self.stateRawValue = stateRawValue
        }
    }

    @Model
    final class FamiliarRunResumeCursorRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var runtimeID: String
        var runID: UUID?
        var contextSnapshotID: UUID
        var nextIteration: Int
        var phaseRawValue: String
        var lastEventSequence: Int
        var pendingToolCallID: String?
        var pendingToolName: String?
        var updatedAt: Date

        init(runtimeID: String, contextSnapshotID: UUID, runID: UUID? = nil, nextIteration: Int = 0, phase: FamiliarRunRecoveryPhase = .model, lastEventSequence: Int = -1, updatedAt: Date = Date()) {
            id = UUID()
            self.runtimeID = runtimeID
            self.runID = runID
            self.contextSnapshotID = contextSnapshotID
            self.nextIteration = nextIteration
            phaseRawValue = phase.rawValue
            self.lastEventSequence = lastEventSequence
            self.updatedAt = updatedAt
        }

        var phase: FamiliarRunRecoveryPhase {
            get { FamiliarRunRecoveryPhase(rawValue: phaseRawValue) ?? .terminal }
            set { phaseRawValue = newValue.rawValue }
        }
    }

    @Model
    final class FamiliarToolInvocationRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var idempotencyKey: String
        var runtimeID: String
        var toolCallID: String
        var toolName: String
        var argumentsHash: String
        var assistantTurnID: String?
        var activityID: String?
        var approvalRecordID: UUID?
        var toolResultRecordID: UUID?
        var stateRawValue: String
        var startedAt: Date
        var committedAt: Date?
        var resultReference: String?

        init(idempotencyKey: String, runtimeID: String, toolCallID: String, toolName: String, argumentsHash: String, assistantTurnID: String? = nil, activityID: String? = nil, state: FamiliarToolInvocationState = .requested, startedAt: Date = Date()) {
            id = UUID()
            self.idempotencyKey = idempotencyKey
            self.runtimeID = runtimeID
            self.toolCallID = toolCallID
            self.toolName = toolName
            self.argumentsHash = argumentsHash
            self.assistantTurnID = assistantTurnID
            self.activityID = activityID
            stateRawValue = state.rawValue
            self.startedAt = startedAt
        }

        var state: FamiliarToolInvocationState {
            get { FamiliarToolInvocationState(rawValue: stateRawValue) ?? .failed }
            set { stateRawValue = newValue.rawValue }
        }
    }

    @Model
    final class FamiliarAuthorizationRuleRecord {
        @Attribute(.unique) var id: UUID
        var projectID: UUID?
        var capabilityID: String
        var capabilityVersion: String
        var targetKey: String
        var argumentsHash: String
        var durationRawValue: String
        var sessionID: String?
        var createdAt: Date
        var expiresAt: Date
        var lastUsedAt: Date?
        var revokedAt: Date?
        var evidence: String

        init(id: UUID = UUID(), projectID: UUID?, capabilityID: String, capabilityVersion: String, targetKey: String, argumentsHash: String, duration: FamiliarAuthorizationDuration, sessionID: String?, createdAt: Date = Date(), expiresAt: Date, evidence: String) {
            self.id = id
            self.projectID = projectID
            self.capabilityID = capabilityID
            self.capabilityVersion = capabilityVersion
            self.targetKey = targetKey
            self.argumentsHash = argumentsHash
            durationRawValue = duration.rawValue
            self.sessionID = sessionID
            self.createdAt = createdAt
            self.expiresAt = expiresAt
            self.evidence = evidence
        }

        var duration: FamiliarAuthorizationDuration {
            FamiliarAuthorizationDuration(rawValue: durationRawValue) ?? .once
        }
    }

    @Model
    final class FamiliarEventKitUndoRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var idempotencyKey: String
        var runtimeID: String
        var toolCallID: String
        var toolName: String
        var kindRawValue: String
        var calendarItemIdentifier: String
        var stateRawValue: String
        var createdAt: Date
        var undoneAt: Date?
        var lastError: String?

        init(idempotencyKey: String, runtimeID: String, toolCallID: String, toolName: String, kind: FamiliarEventKitAccessKind, calendarItemIdentifier: String, state: FamiliarDurableUndoState = .available, createdAt: Date = Date()) {
            id = UUID()
            self.idempotencyKey = idempotencyKey
            self.runtimeID = runtimeID
            self.toolCallID = toolCallID
            self.toolName = toolName
            kindRawValue = kind.rawValue
            self.calendarItemIdentifier = calendarItemIdentifier
            stateRawValue = state.rawValue
            self.createdAt = createdAt
        }

        var kind: FamiliarEventKitAccessKind { FamiliarEventKitAccessKind(rawValue: kindRawValue) ?? .events }
        var state: FamiliarDurableUndoState {
            get { FamiliarDurableUndoState(rawValue: stateRawValue) ?? .unavailable }
            set { stateRawValue = newValue.rawValue }
        }
    }

    @Model
    final class FamiliarVisualEvidenceRecord {
        @Attribute(.unique) var id: UUID
        var attachmentID: UUID
        var messageID: UUID?
        var contextSnapshotID: UUID
        var filename: String
        var sourceRelativePath: String
        var renderedText: String
        var processingMethod: String
        var engineVersion: String
        var createdAt: Date

        init(id: UUID, attachmentID: UUID, messageID: UUID?, contextSnapshotID: UUID, filename: String, sourceRelativePath: String, renderedText: String, processingMethod: String, engineVersion: String, createdAt: Date) {
            self.id = id
            self.attachmentID = attachmentID
            self.messageID = messageID
            self.contextSnapshotID = contextSnapshotID
            self.filename = filename
            self.sourceRelativePath = sourceRelativePath
            self.renderedText = renderedText
            self.processingMethod = processingMethod
            self.engineVersion = engineVersion
            self.createdAt = createdAt
        }
    }

    @Model final class FamiliarSkill {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var stableID: String
        var version: String
        var name: String
        var descriptionText: String
        var instructions: String
        var examplesJSON: String
        var allowedToolsJSON: String
        var contentHash: String
        var installedAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), stableID: String, version: String, name: String, descriptionText: String, instructions: String, examplesJSON: String, allowedToolsJSON: String, contentHash: String, installedAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.stableID = stableID; self.version = version; self.name = name
            self.descriptionText = descriptionText; self.instructions = instructions; self.examplesJSON = examplesJSON
            self.allowedToolsJSON = allowedToolsJSON; self.contentHash = contentHash; self.installedAt = installedAt; self.updatedAt = updatedAt
        }
    }

    @Model final class FamiliarMemoryItem {
        @Attribute(.unique) var id: UUID
        var scopeRawValue: String
        var projectID: UUID?
        var conversationID: UUID?
        var content: String
        var normalizedKey: String
        var provenance: String
        var confidence: Double
        var createdByRawValue: String
        var createdAt: Date
        var updatedAt: Date
        var lastUsedAt: Date?
        var isVisible: Bool
        init(scopeRawValue: String, projectID: UUID?, conversationID: UUID?, content: String, normalizedKey: String, provenance: String, confidence: Double, createdByRawValue: String, id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date = Date(), isVisible: Bool = true) {
            self.id = id; self.scopeRawValue = scopeRawValue; self.projectID = projectID; self.conversationID = conversationID; self.content = content
            self.normalizedKey = normalizedKey; self.provenance = provenance; self.confidence = confidence; self.createdByRawValue = createdByRawValue
            self.createdAt = createdAt; self.updatedAt = updatedAt; self.isVisible = isVisible
        }
    }

    @Model final class FamiliarMCPServerRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var serverIdentity: String
        var displayName: String; var endpointString: String; var protocolVersion: String?; var serverName: String?; var serverVersion: String?
        var capabilitiesJSON: String; var toolsHash: String?; var enabled: Bool; var createdAt: Date; var updatedAt: Date; var lastConnectedAt: Date?; var lastError: String?
        init(displayName: String, endpointString: String, serverIdentity: String, id: UUID = UUID(), enabled: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.displayName = displayName; self.endpointString = endpointString; self.serverIdentity = serverIdentity; self.enabled = enabled
            self.capabilitiesJSON = "{}"; self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    @Model final class FamiliarMCPBindingRecord {
        @Attribute(.unique) var id: UUID
        var serverID: UUID; var projectID: UUID?; var conversationID: UUID?; var enabled: Bool; var enabledToolNamesJSON: String; var createdAt: Date; var updatedAt: Date
        init(serverID: UUID, projectID: UUID? = nil, conversationID: UUID? = nil, enabled: Bool = false, enabledToolNamesJSON: String = "[]", id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.serverID = serverID; self.projectID = projectID; self.conversationID = conversationID; self.enabled = enabled; self.enabledToolNamesJSON = enabledToolNamesJSON; self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    @Model
    final class FamiliarRunSkillSnapshotRecord {
        @Attribute(.unique) var id: UUID
        var runID: UUID
        var runtimeID: String
        var contextSnapshotID: UUID
        var projectID: UUID?
        var sequence: Int
        var stableID: String
        var version: String
        var name: String
        var contentHash: String
        var allowedToolsJSON: String
        var createdAt: Date

        init(
            id: UUID = UUID(),
            runID: UUID,
            runtimeID: String,
            contextSnapshotID: UUID,
            projectID: UUID?,
            sequence: Int,
            stableID: String,
            version: String,
            name: String,
            contentHash: String,
            allowedToolsJSON: String,
            createdAt: Date
        ) {
            self.id = id
            self.runID = runID
            self.runtimeID = runtimeID
            self.contextSnapshotID = contextSnapshotID
            self.projectID = projectID
            self.sequence = sequence
            self.stableID = stableID
            self.version = version
            self.name = name
            self.contentHash = contentHash
            self.allowedToolsJSON = allowedToolsJSON
            self.createdAt = createdAt
        }

        var allowedTools: [String] {
            guard let data = allowedToolsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
    }

    @Model
    final class FamiliarActivityRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var activityID: String
        var runtimeID: String
        var parentID: String?
        var assistantTurnID: String
        var kindRawValue: String
        var effectRawValue: String?
        var phaseRawValue: String
        var toolName: String?
        var toolCallID: String?
        var summary: String
        var detail: String?
        var failureCode: String?
        var failureRetryable: Bool?
        var progress: Double?
        var resultRecordID: UUID?
        var approvalRecordID: UUID?
        var sequence: Int
        var startedAt: Date
        var endedAt: Date?

        init(
            id: UUID = UUID(),
            activityID: String,
            runtimeID: String,
            parentID: String? = nil,
            assistantTurnID: String,
            kind: FamiliarActivityKind,
            effect: FamiliarToolEffect? = nil,
            phase: FamiliarActivityPhase,
            toolName: String? = nil,
            toolCallID: String? = nil,
            summary: String,
            detail: String? = nil,
            failureCode: String? = nil,
            failureRetryable: Bool? = nil,
            progress: Double? = nil,
            resultRecordID: UUID? = nil,
            approvalRecordID: UUID? = nil,
            sequence: Int,
            startedAt: Date,
            endedAt: Date? = nil
        ) {
            self.id = id
            self.activityID = activityID
            self.runtimeID = runtimeID
            self.parentID = parentID
            self.assistantTurnID = assistantTurnID
            kindRawValue = kind.rawValue
            effectRawValue = effect?.rawValue
            phaseRawValue = phase.rawValue
            self.toolName = toolName
            self.toolCallID = toolCallID
            self.summary = summary
            self.detail = detail
            self.failureCode = failureCode
            self.failureRetryable = failureRetryable
            self.progress = progress
            self.resultRecordID = resultRecordID
            self.approvalRecordID = approvalRecordID
            self.sequence = sequence
            self.startedAt = startedAt
            self.endedAt = endedAt
        }

        var kind: FamiliarActivityKind {
            FamiliarActivityKind(rawValue: kindRawValue) ?? .runtimeNotice
        }

        var effect: FamiliarToolEffect? {
            effectRawValue.flatMap(FamiliarToolEffect.init(rawValue:))
        }

        var phase: FamiliarActivityPhase {
            get { FamiliarActivityPhase(rawValue: phaseRawValue) ?? .failed }
            set { phaseRawValue = newValue.rawValue }
        }
    }

    @Model
    final class FamiliarToolResultRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var activityID: String
        var runtimeID: String
        var assistantTurnID: String
        var toolCallID: String
        var envelopeJSON: String
        var schemaVersion: Int
        var payloadName: String
        var payloadHash: String
        var semanticID: String?
        var revision: Int
        var trustRawValue: String
        var truncated: Bool
        var createdAt: Date

        init(
            id: UUID = UUID(),
            activityID: String,
            runtimeID: String,
            assistantTurnID: String,
            toolCallID: String,
            envelopeJSON: String,
            schemaVersion: Int,
            payloadName: String,
            payloadHash: String,
            semanticID: String? = nil,
            revision: Int = 1,
            trust: FamiliarContentTrust,
            truncated: Bool,
            createdAt: Date
        ) {
            self.id = id
            self.activityID = activityID
            self.runtimeID = runtimeID
            self.assistantTurnID = assistantTurnID
            self.toolCallID = toolCallID
            self.envelopeJSON = envelopeJSON
            self.schemaVersion = schemaVersion
            self.payloadName = payloadName
            self.payloadHash = payloadHash
            self.semanticID = semanticID
            self.revision = revision
            trustRawValue = trust.rawValue
            self.truncated = truncated
            self.createdAt = createdAt
        }

        var trust: FamiliarContentTrust {
            FamiliarContentTrust(rawValue: trustRawValue) ?? .untrusted
        }
    }

    @Model
    final class FamiliarApprovalRecord {
        @Attribute(.unique) var id: UUID
        var runtimeID: String
        var assistantTurnID: String
        var activityID: String
        var toolCallID: String
        var toolName: String
        var title: String
        var orderedFieldsJSON: String
        var target: String?
        var effectRawValue: String
        var riskRawValue: String
        var consequence: String
        var undoPolicyRawValue: String
        var allowedAuthorizationDurationsJSON: String
        var decisionRawValue: String?
        var scopeRawValue: String?
        var requestedAt: Date
        var resolvedAt: Date?
        var automaticAuthorization: Bool

        init(
            id: UUID,
            runtimeID: String,
            assistantTurnID: String,
            activityID: String,
            toolCallID: String,
            toolName: String,
            title: String,
            orderedFieldsJSON: String,
            target: String?,
            effect: FamiliarToolEffect,
            risk: FamiliarToolRisk,
            consequence: String,
            undoPolicy: FamiliarApprovalUndoPolicy,
            allowedAuthorizationDurationsJSON: String = "[]",
            decision: FamiliarApprovalDecision? = nil,
            scope: FamiliarApprovalScope? = nil,
            requestedAt: Date,
            resolvedAt: Date? = nil,
            automaticAuthorization: Bool
        ) {
            self.id = id
            self.runtimeID = runtimeID
            self.assistantTurnID = assistantTurnID
            self.activityID = activityID
            self.toolCallID = toolCallID
            self.toolName = toolName
            self.title = title
            self.orderedFieldsJSON = orderedFieldsJSON
            self.target = target
            effectRawValue = effect.rawValue
            riskRawValue = risk.rawValue
            self.consequence = consequence
            undoPolicyRawValue = undoPolicy.rawValue
            self.allowedAuthorizationDurationsJSON = allowedAuthorizationDurationsJSON
            decisionRawValue = decision?.rawValue
            scopeRawValue = scope?.rawValue
            self.requestedAt = requestedAt
            self.resolvedAt = resolvedAt
            self.automaticAuthorization = automaticAuthorization
        }

        var effect: FamiliarToolEffect { FamiliarToolEffect(rawValue: effectRawValue) ?? .read }
        var risk: FamiliarToolRisk { FamiliarToolRisk(rawValue: riskRawValue) ?? .low }
        var undoPolicy: FamiliarApprovalUndoPolicy { FamiliarApprovalUndoPolicy(rawValue: undoPolicyRawValue) ?? .unavailable }
        var decision: FamiliarApprovalDecision? { decisionRawValue.flatMap(FamiliarApprovalDecision.init(rawValue:)) }
        var scope: FamiliarApprovalScope? { scopeRawValue.flatMap(FamiliarApprovalScope.init(rawValue:)) }
    }

    @Model
    final class FamiliarResponseBlockRecord {
        @Attribute(.unique) var id: UUID
        var runtimeID: String
        var assistantTurnID: String
        var messageID: UUID?
        var kindRawValue: String
        var order: Int
        var stateRawValue: String
        var content: String
        var payloadJSON: String
        var schemaVersion: Int
        var startedAt: Date
        var endedAt: Date?
        var contentHash: String

        init(
            id: UUID = UUID(),
            runtimeID: String,
            assistantTurnID: String,
            messageID: UUID?,
            kind: FamiliarResponseBlockKind,
            order: Int,
            state: FamiliarResponseBlockState,
            content: String,
            payloadJSON: String = "{}",
            schemaVersion: Int = 1,
            startedAt: Date,
            endedAt: Date?,
            contentHash: String
        ) {
            self.id = id
            self.runtimeID = runtimeID
            self.assistantTurnID = assistantTurnID
            self.messageID = messageID
            kindRawValue = kind.rawValue
            self.order = order
            stateRawValue = state.rawValue
            self.content = content
            self.payloadJSON = payloadJSON
            self.schemaVersion = schemaVersion
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.contentHash = contentHash
        }

        var kind: FamiliarResponseBlockKind {
            FamiliarResponseBlockKind(rawValue: kindRawValue) ?? .runtimeNotice
        }

        var state: FamiliarResponseBlockState {
            get { FamiliarResponseBlockState(rawValue: stateRawValue) ?? .failed }
            set { stateRawValue = newValue.rawValue }
        }
    }

    @Model
    final class FamiliarClarificationRecord {
        @Attribute(.unique) var id: UUID
        var runtimeID: String
        var assistantTurnID: String
        var activityID: String
        var toolCallID: String
        var question: String
        var optionsJSON: String
        var allowCustom: Bool
        var stateRawValue: String
        var resolutionJSON: String?
        var requestedAt: Date
        var resolvedAt: Date?

        init(id: UUID, runtimeID: String, assistantTurnID: String, activityID: String, toolCallID: String, question: String, optionsJSON: String, allowCustom: Bool, state: FamiliarClarificationState = .requested, resolutionJSON: String? = nil, requestedAt: Date, resolvedAt: Date? = nil) {
            self.id = id
            self.runtimeID = runtimeID
            self.assistantTurnID = assistantTurnID
            self.activityID = activityID
            self.toolCallID = toolCallID
            self.question = question
            self.optionsJSON = optionsJSON
            self.allowCustom = allowCustom
            stateRawValue = state.rawValue
            self.resolutionJSON = resolutionJSON
            self.requestedAt = requestedAt
            self.resolvedAt = resolvedAt
        }

        var state: FamiliarClarificationState {
            get { FamiliarClarificationState(rawValue: stateRawValue) ?? .interrupted }
            set { stateRawValue = newValue.rawValue }
        }
    }

    @Model
    final class FamiliarContextAttachmentReference {
        @Attribute(.unique) var id: UUID
        var contextSnapshotID: UUID
        var attachmentID: UUID
        var filename: String
        var mimeType: String
        var sourceRelativePath: String
        var byteSize: Int64
        var contentHash: String
        var extractedTextHash: String
        var createdAt: Date

        init(
            id: UUID = UUID(),
            contextSnapshotID: UUID,
            attachmentID: UUID,
            filename: String,
            mimeType: String,
            sourceRelativePath: String,
            byteSize: Int64,
            contentHash: String,
            extractedTextHash: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.contextSnapshotID = contextSnapshotID
            self.attachmentID = attachmentID
            self.filename = filename
            self.mimeType = mimeType
            self.sourceRelativePath = sourceRelativePath
            self.byteSize = byteSize
            self.contentHash = contentHash
            self.extractedTextHash = extractedTextHash
            self.createdAt = createdAt
        }
    }

    @Model
    final class FamiliarEventKitUndoMutationRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var idempotencyKey: String
        var operationRawValue: String
        var descriptorJSON: String
        var originalCalendarItemIdentifier: String
        var restoredCalendarItemIdentifier: String?
        var createdAt: Date

        init(
            id: UUID = UUID(),
            idempotencyKey: String,
            descriptor: FamiliarEventKitUndoDescriptor,
            createdAt: Date = Date()
        ) throws {
            self.id = id
            self.idempotencyKey = idempotencyKey
            operationRawValue = descriptor.operation.rawValue
            descriptorJSON = String(decoding: try JSONEncoder().encode(descriptor), as: UTF8.self)
            originalCalendarItemIdentifier = descriptor.calendarItemIdentifier
            self.createdAt = createdAt
        }

        var operation: FamiliarEventKitMutationOperation {
            FamiliarEventKitMutationOperation(rawValue: operationRawValue) ?? .create
        }

        func descriptor() throws -> FamiliarEventKitUndoDescriptor {
            try JSONDecoder().decode(FamiliarEventKitUndoDescriptor.self, from: Data(descriptorJSON.utf8))
        }
    }

    @Model
    final class FamiliarPinnedItemRecord {
        @Attribute(.unique) var targetKey: String
        var targetTypeRawValue: String
        var targetID: UUID
        var pinnedAt: Date

        init(targetType: FamiliarPinnedTargetType, targetID: UUID, pinnedAt: Date = Date()) {
            targetKey = targetType.targetKey(for: targetID)
            targetTypeRawValue = targetType.rawValue
            self.targetID = targetID
            self.pinnedAt = pinnedAt
        }

        var targetType: FamiliarPinnedTargetType? {
            FamiliarPinnedTargetType(rawValue: targetTypeRawValue)
        }
    }

    @Model
    final class FamiliarProjectEnvironmentRecord {
        @Attribute(.unique) var projectID: UUID
        var revision: UUID
        var stateRawValue: String
        var requestedPackagesJSON: String
        var pythonVersion: String
        var resolvedPackagesJSON: String
        var lockHash: String
        var byteSize: Int64
        var preparedAt: Date

        init(receipt: FamiliarEnvironmentReceipt) throws {
            projectID = receipt.projectID
            revision = receipt.revision
            stateRawValue = receipt.state.rawValue
            requestedPackagesJSON = String(decoding: try JSONEncoder().encode(receipt.requestedPackages), as: UTF8.self)
            pythonVersion = receipt.lock.pythonVersion
            resolvedPackagesJSON = String(decoding: try JSONEncoder().encode(receipt.lock.resolvedPackages), as: UTF8.self)
            lockHash = receipt.lock.contentHash
            byteSize = receipt.byteSize
            preparedAt = receipt.preparedAt
        }

        var state: FamiliarRuntimeEnvironmentState {
            FamiliarRuntimeEnvironmentState(rawValue: stateRawValue) ?? .failed
        }
    }

    @Model
    final class FamiliarProjectSkillBindingRecord {
        @Attribute(.unique) var bindingKey: String
        var projectID: UUID
        var skillID: UUID
        var enabled: Bool
        var createdAt: Date
        var updatedAt: Date

        init(projectID: UUID, skillID: UUID, enabled: Bool = true, now: Date = Date()) {
            bindingKey = "\(projectID.uuidString):\(skillID.uuidString)"
            self.projectID = projectID
            self.skillID = skillID
            self.enabled = enabled
            createdAt = now
            updatedAt = now
        }
    }

    @Model
    final class FamiliarProjectCapabilityBindingRecord {
        @Attribute(.unique) var bindingKey: String
        var projectID: UUID
        var capabilityID: String
        var enabled: Bool
        var createdAt: Date
        var updatedAt: Date

        init(projectID: UUID, capabilityID: String, enabled: Bool = true, now: Date = Date()) {
            bindingKey = "\(projectID.uuidString):\(capabilityID)"
            self.projectID = projectID
            self.capabilityID = capabilityID
            self.enabled = enabled
            createdAt = now
            updatedAt = now
        }
    }

    @Model
    final class FamiliarAlarmUndoRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var idempotencyKey: String
        var runtimeID: String
        var toolCallID: String
        var toolName: String
        var alarmIdentifier: String
        var stateRawValue: String
        var createdAt: Date
        var undoneAt: Date?
        var lastError: String?

        init(
            idempotencyKey: String,
            runtimeID: String,
            toolCallID: String,
            toolName: String,
            alarmIdentifier: String,
            state: FamiliarDurableUndoState = .available,
            createdAt: Date = Date()
        ) {
            id = UUID()
            self.idempotencyKey = idempotencyKey
            self.runtimeID = runtimeID
            self.toolCallID = toolCallID
            self.toolName = toolName
            self.alarmIdentifier = alarmIdentifier
            stateRawValue = state.rawValue
            self.createdAt = createdAt
        }

        var state: FamiliarDurableUndoState {
            get { FamiliarDurableUndoState(rawValue: stateRawValue) ?? .unavailable }
            set { stateRawValue = newValue.rawValue }
        }
    }

    nonisolated enum FamiliarArtifactFormat: String, Codable, CaseIterable, Sendable {
        case markdown
        case plainText
        case docx
        case pdf
        case xlsx
        case html
    
        var filenameExtension: String {
            switch self {
            case .markdown: "md"
            case .plainText: "txt"
            case .docx: "docx"
            case .pdf: "pdf"
            case .xlsx: "xlsx"
            case .html: "html"
            }
        }
    
        var mimeType: String {
            switch self {
            case .markdown: "text/markdown"
            case .plainText: "text/plain"
            case .docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            case .pdf: "application/pdf"
            case .xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            case .html: "text/html"
            }
        }
    
        var utiIdentifier: String {
            switch self {
            case .markdown: "net.daringfireball.markdown"
            case .plainText: "public.plain-text"
            case .docx: "org.openxmlformats.wordprocessingml.document"
            case .pdf: "com.adobe.pdf"
            case .xlsx: "org.openxmlformats.spreadsheetml.sheet"
            case .html: "public.html"
            }
        }
    }
    nonisolated enum FamiliarArtifactSource: String, Codable, Sendable { case generated, webCapture, projectResource }
}
