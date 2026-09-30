import Foundation

nonisolated enum FamiliarProviderProtocol: String, Codable, Sendable {
    case openAIChat
    case openAIResponses
    case anthropic
    case gemini
}

nonisolated enum FamiliarProviderAuthStyle: Codable, Equatable, Sendable {
    case bearer
    case anthropicKey
    case googleKey
}

nonisolated enum FamiliarProviderRegion: String, CaseIterable, Codable, Identifiable, Sendable {
    case china
    case international

    var id: String { rawValue }
}

nonisolated struct FamiliarProviderConfiguration: Codable, Equatable, Sendable {
    var displayName: String
    var baseURL: String
    var organizationID: String
    var projectID: String
    var region: FamiliarProviderRegion
    var modelsPath: String

    static let empty = FamiliarProviderConfiguration(
        displayName: "",
        baseURL: "",
        organizationID: "",
        projectID: "",
        region: .china,
        modelsPath: ""
    )
}

nonisolated struct FamiliarModelCapabilities: Codable, Equatable, Sendable {
    let supportsText: Bool
    let supportsTools: Bool
    let supportsImages: Bool
    let supportsDocuments: Bool
    let maximumInputCharacters: Int

    init(
        supportsText: Bool = true,
        supportsTools: Bool = false,
        supportsImages: Bool = false,
        supportsDocuments: Bool = true,
        maximumInputCharacters: Int = 120_000
    ) {
        self.supportsText = supportsText
        self.supportsTools = supportsTools
        self.supportsImages = supportsImages
        self.supportsDocuments = supportsDocuments
        self.maximumInputCharacters = maximumInputCharacters
    }

    static let textOnly = FamiliarModelCapabilities(
        supportsText: true,
        supportsTools: false,
        supportsImages: false,
        supportsDocuments: false,
        maximumInputCharacters: 60_000
    )
}

nonisolated struct FamiliarModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let capabilities: FamiliarModelCapabilities

    init(
        id: String,
        displayName: String? = nil,
        capabilities: FamiliarModelCapabilities = .textOnly
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.capabilities = capabilities
    }
}

nonisolated struct FamiliarOpenAIChatConfiguration: Codable, Equatable, Sendable {
    let sendsStreamOptions: Bool
    let dataPrefix: String
    let doneToken: String

    init(
        sendsStreamOptions: Bool = true,
        dataPrefix: String = "data:",
        doneToken: String = "[DONE]"
    ) {
        self.sendsStreamOptions = sendsStreamOptions
        self.dataPrefix = dataPrefix
        self.doneToken = doneToken
    }
}

nonisolated struct FamiliarProviderDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let protocolKind: FamiliarProviderProtocol
    let baseURL: URL
    let chatPath: String
    let modelsPath: String?
    let authStyle: FamiliarProviderAuthStyle
    let additionalHeaders: [String: String]
    let curatedModels: [FamiliarModelDescriptor]
    let openAIChat: FamiliarOpenAIChatConfiguration?
    let isCustom: Bool
    var oauthKind: String?
    var routes: [FamiliarProviderRoute]?
    var routeStrategy: String?
    var fallbackOnAnyError: Bool?

    var defaultModel: FamiliarModelDescriptor {
        curatedModels.first ?? FamiliarModelDescriptor(id: "manual-model")
    }

    var apiKeyPlaceholder: String {
        "sk-…"
    }

    func model(for modelID: String) -> FamiliarModelDescriptor {
        curatedModels.first(where: { $0.id == modelID })
            ?? FamiliarModelDescriptor(id: modelID, capabilities: .textOnly)
    }
}

nonisolated enum FamiliarProviderCatalog {
    static var instances: [FamiliarProviderDescriptor] {
        let saved = FamiliarProviderInstanceStore.load()
        return saved.contains(where: { $0.id == deepSeek.id }) ? saved : [deepSeek] + saved
    }

    static var builtIn: [FamiliarProviderDescriptor] {
        let values = instances
        return values + FamiliarModelGroupStore.descriptors(instances: values)
    }

    static let templates: [FamiliarProviderDescriptor] = [
        {
            var value = provider(id: "codex", name: "Codex", protocolKind: .openAIResponses, baseURL: "https://chatgpt.com/backend-api/codex", chatPath: "/responses", modelsPath: nil, models: ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini"].map { .init(id: $0, capabilities: .init(supportsTools: true, supportsImages: true)) })
            value.oauthKind = "codex"
            return value
        }(),
        provider(id: "openai", name: "OpenAI / Compatible API", baseURL: "https://api.openai.com/v1", chatPath: "/chat/completions", modelsPath: "/models", models: []),
        provider(id: "responses", name: "OpenAI Responses", protocolKind: .openAIResponses, baseURL: "https://api.openai.com/v1", chatPath: "/responses", modelsPath: "/models", models: []),
        provider(id: "anthropic", name: "Anthropic / Compatible API", protocolKind: .anthropic, baseURL: "https://api.anthropic.com/v1", chatPath: "/messages", modelsPath: "/models", authStyle: .anthropicKey, headers: ["anthropic-version": "2023-06-01"], models: []),
        provider(id: "gemini", name: "Google Gemini", protocolKind: .gemini, baseURL: "https://generativelanguage.googleapis.com/v1beta", chatPath: "/models/{model}:streamGenerateContent?alt=sse", modelsPath: "/models", authStyle: .googleKey, models: []),
        provider(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", chatPath: "/chat/completions", modelsPath: "/models", models: []),
        provider(id: "xai", name: "xAI (Grok)", baseURL: "https://api.x.ai/v1", chatPath: "/chat/completions", modelsPath: "/models", models: []),
        provider(id: "kimi", name: "Kimi", baseURL: "https://api.moonshot.cn/v1", chatPath: "/chat/completions", modelsPath: "/models", models: []),
        {
            var value = provider(id: "kimi-code", name: "Kimi Code", baseURL: "https://api.kimi.com/coding/v1", chatPath: "/chat/completions", modelsPath: "/models", models: [.init(id: "kimi-k3", displayName: "Kimi K3", capabilities: toolText), .init(id: "kimi-k2", displayName: "Kimi K2", capabilities: toolText)])
            value.oauthKind = "kimi"
            return value
        }(),
        deepSeek
    ]

    static var allProviderIDs: [String] {
        builtIn.map(\.id)
    }

    static func descriptor(
        for providerID: String,
        configuration: FamiliarProviderConfiguration = .empty
    ) -> FamiliarProviderDescriptor? {
        builtIn.first(where: { $0.id == providerID })
    }

    static func configuration(for providerID: String, in configurations: [String: FamiliarProviderConfiguration]) -> FamiliarProviderConfiguration {
        configurations[providerID] ?? .empty
    }

    static func normalizedModelID(_ id: String, providerID: String) -> String {
        let value = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? (descriptor(for: providerID)?.defaultModel.id ?? id) : value
    }

    private static let toolText = FamiliarModelCapabilities(supportsTools: true)
    static let deepSeek = provider(
        id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com",
        chatPath: "/chat/completions", modelsPath: "/models",
        models: [
            .init(id: "deepseek-v4-flash", displayName: "Flash", capabilities: toolText),
            .init(id: "deepseek-v4-pro", displayName: "Pro", capabilities: toolText)
        ],
        sendsStreamOptions: false
    )


    private static func provider(
        id: String,
        name: String,
        protocolKind: FamiliarProviderProtocol = .openAIChat,
        baseURL: String,
        chatPath: String,
        modelsPath: String?,
        authStyle: FamiliarProviderAuthStyle = .bearer,
        headers: [String: String] = [:],
        models: [FamiliarModelDescriptor],
        sendsStreamOptions: Bool = true,
        openAIChat: FamiliarOpenAIChatConfiguration? = .init()
    ) -> FamiliarProviderDescriptor {
        FamiliarProviderDescriptor(
            id: id,
            displayName: name,
            protocolKind: protocolKind,
            baseURL: URL(string: baseURL)!,
            chatPath: chatPath,
            modelsPath: modelsPath,
            authStyle: authStyle,
            additionalHeaders: headers,
            curatedModels: models,
            openAIChat: openAIChat.map {
                FamiliarOpenAIChatConfiguration(
                    sendsStreamOptions: sendsStreamOptions,
                    dataPrefix: $0.dataPrefix,
                    doneToken: $0.doneToken
                )
            },
            isCustom: false
        )
    }

}
