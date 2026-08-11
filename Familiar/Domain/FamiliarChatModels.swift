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
}

nonisolated struct FamiliarModelOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
}

nonisolated enum FamiliarProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case deepSeek = "deepseek"
    case groq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .groq: "Groq"
        }
    }

    var detail: String {
        switch self {
        case .deepSeek: String(localized: "provider.deepseek.detail")
        case .groq: String(localized: "provider.groq.detail")
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .deepSeek: "sk-…"
        case .groq: "gsk_…"
        }
    }

    var models: [FamiliarModelOption] {
        switch self {
        case .deepSeek:
            [
                .init(id: "deepseek-v4-flash", title: "Flash", detail: String(localized: "model.detail.fast")),
                .init(id: "deepseek-v4-pro", title: "Pro", detail: String(localized: "model.detail.reasoning"))
            ]
        case .groq:
            [
                .init(id: "llama-3.3-70b-versatile", title: "Llama 3.3 70B", detail: String(localized: "model.detail.quality_tools")),
                .init(id: "llama-3.1-8b-instant", title: "Llama 3.1 8B Instant", detail: String(localized: "model.detail.speed_tools")),
                .init(id: "openai/gpt-oss-20b", title: "GPT-OSS 20B", detail: String(localized: "model.detail.light_tools")),
                .init(id: "openai/gpt-oss-120b", title: "GPT-OSS 120B", detail: String(localized: "model.detail.strong_tools"))
            ]
        }
    }

    var modelsEndpoint: URL {
        switch self {
        case .deepSeek:
            URL(string: "https://api.deepseek.com/models")!
        case .groq:
            URL(string: "https://api.groq.com/openai/v1/models")!
        }
    }

    var defaultModelID: String {
        models[0].id
    }

    func model(for id: String) -> FamiliarModelOption {
        models.first(where: { $0.id == id }) ?? models[0]
    }
}

nonisolated struct FamiliarSettings: Codable, Equatable, Sendable {
    var provider: FamiliarProvider
    var modelID: String
    var systemPrompt: String

    static let defaultValue = FamiliarSettings(
        provider: .deepSeek,
        modelID: FamiliarProvider.deepSeek.defaultModelID,
        systemPrompt: String(localized: "settings.system_prompt.default")
    )

    var selectedModel: FamiliarModelOption {
        provider.model(for: modelID)
    }

    var normalizedSystemPrompt: String {
        let value = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? Self.defaultValue.systemPrompt : String(value.prefix(3_000))
    }

    init(provider: FamiliarProvider, modelID: String, systemPrompt: String) {
        self.provider = provider
        self.modelID = modelID
        self.systemPrompt = systemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(FamiliarProvider.self, forKey: .provider) ?? .deepSeek
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
            ?? container.decodeIfPresent(String.self, forKey: .legacyModel)
            ?? provider.defaultModelID
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
            ?? Self.defaultValue.systemPrompt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(systemPrompt, forKey: .systemPrompt)
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case modelID
        case systemPrompt
        case legacyModel = "model"
    }
}

@MainActor
enum FamiliarSettingsStore {
    private static let key = "familiar.chat.settings.v1"

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
