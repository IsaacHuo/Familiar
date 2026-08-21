import Foundation

nonisolated enum FamiliarMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

nonisolated enum FamiliarAttachmentKind: String, Codable, Sendable {
    case document
    case image
}

nonisolated struct FamiliarAttachmentDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: FamiliarAttachmentKind
    let filename: String
    let mimeType: String
    let relativePath: String
    let extractedText: String
    let byteSize: Int64
    let extractionEngine: String
    let extractionVersion: String
    let detectedFormat: String
    let usedOCR: Bool
}

nonisolated struct FamiliarAttachmentSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: FamiliarAttachmentKind
    let filename: String
    let mimeType: String
    let relativePath: String
    let extractedText: String
    let byteSize: Int64
    let extractionEngine: String
    let extractionVersion: String
    let detectedFormat: String
    let usedOCR: Bool
}

nonisolated struct FamiliarMessageSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: FamiliarMessageRole
    let content: String
    let createdAt: Date
    let sequence: Int
    let providerID: String?
    let modelID: String?
    let attachments: [FamiliarAttachmentSnapshot]
    let sources: [FamiliarSource]
    let responseBlocks: [FamiliarResponseBlockSnapshot]

    init(
        id: UUID,
        role: FamiliarMessageRole,
        content: String,
        createdAt: Date,
        sequence: Int,
        providerID: String?,
        modelID: String?,
        attachments: [FamiliarAttachmentSnapshot],
        sources: [FamiliarSource] = [],
        responseBlocks: [FamiliarResponseBlockSnapshot] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.sequence = sequence
        self.providerID = providerID
        self.modelID = modelID
        self.attachments = attachments
        self.sources = sources
        self.responseBlocks = responseBlocks
    }
}

nonisolated enum FamiliarSourceKind: String, Codable, Sendable {
    case searchResult
    case fetchedPage
    case providerNative
}

nonisolated struct FamiliarSource: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let kind: FamiliarSourceKind
    let title: String
    let url: URL
    let siteName: String?
    let snippet: String?
    let retrievedAt: Date
    let responseBlockID: UUID?
    let retrievalActivityID: String?
    let citationOrdinal: Int?

    init(
        id: String,
        kind: FamiliarSourceKind,
        title: String,
        url: URL,
        siteName: String?,
        snippet: String?,
        retrievedAt: Date,
        responseBlockID: UUID? = nil,
        retrievalActivityID: String? = nil,
        citationOrdinal: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.url = url
        self.siteName = siteName
        self.snippet = snippet
        self.retrievedAt = retrievedAt
        self.responseBlockID = responseBlockID
        self.retrievalActivityID = retrievalActivityID
        self.citationOrdinal = citationOrdinal
    }
}

nonisolated struct FamiliarCompletedResponse: Equatable, Sendable {
    let text: String
    let sources: [FamiliarSource]
}

nonisolated enum FamiliarPersistedConfirmationResult: String, Codable, Sendable {
    case notRequired
    case confirmed
    case cancelled
}

nonisolated enum FamiliarToolRunTerminalStatus: String, Codable, Sendable {
    case succeeded
    case cancelled
    case failed
}

nonisolated enum FamiliarAgentRunStatus: String, Codable, Sendable {
    case running, completed, cancelled, failed
}

nonisolated struct FamiliarAgentRunSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let responseMessageID: UUID?
    let status: FamiliarAgentRunStatus
    let startedAt: Date
    let finishedAt: Date?
    let context: FamiliarRunContextSummary?
    let activities: [FamiliarActivitySnapshot]
    let approvals: [FamiliarApprovalSnapshot]
    let clarifications: [FamiliarClarificationSnapshot]
    let toolResults: [FamiliarToolResultSnapshot]
    let responseBlocks: [FamiliarResponseBlockSnapshot]

    init(
        id: String,
        responseMessageID: UUID?,
        status: FamiliarAgentRunStatus,
        startedAt: Date,
        finishedAt: Date?,
        context: FamiliarRunContextSummary? = nil,
        activities: [FamiliarActivitySnapshot] = [],
        approvals: [FamiliarApprovalSnapshot] = [],
        clarifications: [FamiliarClarificationSnapshot] = [],
        toolResults: [FamiliarToolResultSnapshot] = [],
        responseBlocks: [FamiliarResponseBlockSnapshot] = []
    ) {
        self.id = id
        self.responseMessageID = responseMessageID
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.context = context
        self.activities = activities
        self.approvals = approvals
        self.clarifications = clarifications
        self.toolResults = toolResults
        self.responseBlocks = responseBlocks
    }
}

nonisolated struct FamiliarRunContextSummary: Equatable, Sendable {
    let projectName: String?
    let providerID: String
    let modelID: String
    let resources: [FamiliarRunResourceSummary]
    let skills: [FamiliarRunSkillSummary]
    let toolNames: [String]
}

nonisolated struct FamiliarRunResourceSummary: Identifiable, Equatable, Sendable {
    var id: UUID { versionID }
    let versionID: UUID
    let filename: String
    let version: Int
}

nonisolated struct FamiliarRunSkillSummary: Identifiable, Equatable, Sendable {
    var id: String { stableID + "@" + version }
    let stableID: String
    let name: String
    let version: String
}

nonisolated struct FamiliarToolResultSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let activityID: String
    let toolCallID: String
    let envelope: FamiliarToolResultEnvelope?
    let envelopeJSON: String
    let schemaVersion: Int
    let payloadName: String
    let payloadHash: String
    let semanticID: String?
    let revision: Int
    let trust: FamiliarContentTrust
    let truncated: Bool

    init(id: UUID, activityID: String, toolCallID: String, envelope: FamiliarToolResultEnvelope?, envelopeJSON: String, schemaVersion: Int, payloadName: String, payloadHash: String, semanticID: String? = nil, revision: Int = 1, trust: FamiliarContentTrust, truncated: Bool) {
        self.id = id
        self.activityID = activityID
        self.toolCallID = toolCallID
        self.envelope = envelope
        self.envelopeJSON = envelopeJSON
        self.schemaVersion = schemaVersion
        self.payloadName = payloadName
        self.payloadHash = payloadHash
        self.semanticID = semanticID
        self.revision = revision
        self.trust = trust
        self.truncated = truncated
    }
}

nonisolated struct FamiliarClarificationSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let activityID: String
    let assistantTurnID: String
    let toolCallID: String
    let question: String
    let options: [FamiliarClarificationOption]
    let allowCustom: Bool
    let state: FamiliarClarificationState
    let resolution: FamiliarClarificationResolution?
    let requestedAt: Date
    let resolvedAt: Date?
}

nonisolated struct FamiliarApprovalSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let activityID: String
    let assistantTurnID: String
    let toolCallID: String
    let toolName: String
    let title: String
    let fields: [FamiliarApprovalField]
    let target: String?
    let effect: FamiliarToolEffect
    let risk: FamiliarToolRisk
    let consequence: String
    let undoPolicy: FamiliarApprovalUndoPolicy
    let decision: FamiliarApprovalDecision?
    let scope: FamiliarApprovalScope?
    let requestedAt: Date
    let resolvedAt: Date?
    let automaticAuthorization: Bool
}

nonisolated struct FamiliarActivitySnapshot: Identifiable, Equatable, Sendable {
    var id: String { activityID }
    let activityID: String
    let parentID: String?
    let assistantTurnID: String
    let kind: FamiliarActivityKind
    let effect: FamiliarToolEffect?
    let phase: FamiliarActivityPhase
    let toolName: String?
    let toolCallID: String?
    let summary: String
    let detail: String?
    let progress: Double?
    let resultRecordID: UUID?
    let approvalRecordID: UUID?
    let sequence: Int
    let startedAt: Date
    let endedAt: Date?
}

nonisolated struct FamiliarResponseBlockSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let assistantTurnID: String
    let messageID: UUID?
    let kind: FamiliarResponseBlockKind
    let order: Int
    let state: FamiliarResponseBlockState
    let content: String
    let payloadJSON: String
    let schemaVersion: Int
    let startedAt: Date
    let endedAt: Date?
    let contentHash: String
}

nonisolated struct FamiliarModelSwitchSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let previousProviderID: String
    let previousModelID: String
    let currentProviderID: String
    let currentModelID: String
    let sequence: Int
    let createdAt: Date
}

nonisolated struct FamiliarSettings: Codable, Equatable, Sendable {
    var providerID: String
    var modelID: String
    var systemPrompt: String
    var providerConfigurations: [String: FamiliarProviderConfiguration]

    static let defaultValue = FamiliarSettings(
        providerID: FamiliarProviderCatalog.deepSeek.id,
        modelID: FamiliarProviderCatalog.deepSeek.defaultModel.id,
        systemPrompt: String(localized: "settings.system_prompt.default"),
        providerConfigurations: [:]
    )

    var providerConfiguration: FamiliarProviderConfiguration {
        FamiliarProviderCatalog.configuration(
            for: providerID,
            in: providerConfigurations
        )
    }

    var resolvedProvider: FamiliarProviderDescriptor? {
        FamiliarProviderCatalog.descriptor(
            for: providerID,
            configuration: providerConfiguration
        )
    }

    var selectedProvider: FamiliarProviderDescriptor {
        resolvedProvider ?? FamiliarProviderCatalog.deepSeek
    }

    var selectedModel: FamiliarModelDescriptor {
        selectedProvider.model(for: modelID)
    }

    var normalizedSystemPrompt: String {
        let value = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? Self.defaultValue.systemPrompt : String(value.prefix(3_000))
    }

    mutating func updateConfiguration(_ configuration: FamiliarProviderConfiguration) {
        providerConfigurations[providerID] = configuration
    }
}

@MainActor
enum FamiliarSettingsStore {
    private static let key = "familiar.chat.settings.v2"

    static func load() -> FamiliarSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              var settings = try? JSONDecoder().decode(FamiliarSettings.self, from: data)
        else { return .defaultValue }
        settings.modelID = FamiliarProviderCatalog.normalizedModelID(settings.modelID, providerID: settings.providerID)
        return settings
    }

    static func save(_ settings: FamiliarSettings) throws {
        let data = try JSONEncoder().encode(settings)
        UserDefaults.standard.set(data, forKey: key)
    }
}
