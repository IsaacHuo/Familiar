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

    init(
        id: UUID,
        role: FamiliarMessageRole,
        content: String,
        createdAt: Date,
        sequence: Int,
        providerID: String?,
        modelID: String?,
        attachments: [FamiliarAttachmentSnapshot],
        sources: [FamiliarSource] = []
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

nonisolated enum FamiliarAgentStepType: String, Codable, Sendable {
    case model, tool, approval, result
}

nonisolated struct FamiliarToolRunSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let runID: String
    let toolCallID: String
    let toolName: String
    let summary: String
    let detail: String
    let confirmation: FamiliarPersistedConfirmationResult
    let status: FamiliarToolRunTerminalStatus
    let sequence: Int
    let startedAt: Date
    let finishedAt: Date
}

nonisolated struct FamiliarAgentRunSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let responseMessageID: UUID?
    let status: FamiliarAgentRunStatus
    let startedAt: Date
    let finishedAt: Date?
    let steps: [FamiliarAgentStepSnapshot]
    let context: FamiliarRunContextSummary?

    init(
        id: String,
        responseMessageID: UUID?,
        status: FamiliarAgentRunStatus,
        startedAt: Date,
        finishedAt: Date?,
        steps: [FamiliarAgentStepSnapshot],
        context: FamiliarRunContextSummary? = nil
    ) {
        self.id = id
        self.responseMessageID = responseMessageID
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.steps = steps
        self.context = context
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

nonisolated struct FamiliarAgentStepSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let type: FamiliarAgentStepType
    let toolName: String
    let summary: String
    let detail: String
    let status: FamiliarToolRunTerminalStatus
    let eventSequence: Int
    let startedAt: Date
    let finishedAt: Date
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
              let settings = try? JSONDecoder().decode(FamiliarSettings.self, from: data)
        else { return .defaultValue }
        return settings
    }

    static func save(_ settings: FamiliarSettings) throws {
        let data = try JSONEncoder().encode(settings)
        UserDefaults.standard.set(data, forKey: key)
    }
}
