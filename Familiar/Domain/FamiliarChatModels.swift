import Foundation

nonisolated enum FamiliarMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

nonisolated struct FamiliarMessageSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: FamiliarMessageRole
    let content: String
    let createdAt: Date
    let sequence: Int
    let providerID: String?
    let modelID: String?
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
