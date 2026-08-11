import Foundation

nonisolated enum FamiliarProviderProtocol: String, Codable, Sendable {
    case openAIChat
    case anthropicMessages
    case geminiGenerateContent
}

nonisolated enum FamiliarProviderAuthStyle: Codable, Equatable, Sendable {
    case bearer
    case apiKeyHeader(name: String)
    case apiKeyQuery(name: String)
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

    var defaultModel: FamiliarModelDescriptor {
        curatedModels.first ?? FamiliarModelDescriptor(id: "manual-model")
    }

    var apiKeyPlaceholder: String {
        switch id {
        case "anthropic": "sk-ant-…"
        case "groq": "gsk_…"
        case "gemini": "AIza…"
        default: "sk-…"
        }
    }

    func model(for modelID: String) -> FamiliarModelDescriptor {
        curatedModels.first(where: { $0.id == modelID })
            ?? FamiliarModelDescriptor(id: modelID, capabilities: .textOnly)
    }
}

nonisolated enum FamiliarProviderCatalog {
    static let customProviderID = "custom-openai"

    static let builtIn: [FamiliarProviderDescriptor] = [
        openAI, anthropic, gemini, deepSeek, groq, xAI,
        openRouter, qwen, kimi, glm, miniMax, siliconFlow
    ]

    static func descriptor(
        for providerID: String,
        configuration: FamiliarProviderConfiguration = .empty
    ) -> FamiliarProviderDescriptor? {
        if providerID == customProviderID {
            guard let baseURL = normalizedBaseURL(configuration.baseURL) else { return nil }
            return FamiliarProviderDescriptor(
                id: customProviderID,
                displayName: configuration.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "OpenAI-compatible"
                    : configuration.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                protocolKind: .openAIChat,
                baseURL: baseURL,
                chatPath: "/chat/completions",
                modelsPath: normalizedPath(configuration.modelsPath),
                authStyle: .bearer,
                additionalHeaders: [:],
                curatedModels: [],
                openAIChat: .init(),
                isCustom: true
            )
        }

        guard let descriptor = builtIn.first(where: { $0.id == providerID }) else { return nil }
        if providerID == "openai" {
            var headers = descriptor.additionalHeaders
            let organization = configuration.organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
            let project = configuration.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !organization.isEmpty { headers["OpenAI-Organization"] = organization }
            if !project.isEmpty { headers["OpenAI-Project"] = project }
            return descriptor.replacing(additionalHeaders: headers)
        }
        if providerID == "qwen" {
            let url = configuration.region == .international
                ? URL(string: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")!
                : URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!
            return descriptor.replacing(baseURL: url)
        }
        return descriptor
    }

    static func configuration(for providerID: String, in configurations: [String: FamiliarProviderConfiguration]) -> FamiliarProviderConfiguration {
        configurations[providerID] ?? .empty
    }

    private static let toolText = FamiliarModelCapabilities(supportsTools: true)
    private static let toolVision = FamiliarModelCapabilities(supportsTools: true, supportsImages: true)
    private static let longToolText = FamiliarModelCapabilities(supportsTools: true, maximumInputCharacters: 300_000)

    static let openAI = provider(
        id: "openai",
        name: "OpenAI",
        baseURL: "https://api.openai.com",
        chatPath: "/v1/chat/completions",
        modelsPath: "/v1/models",
        models: [
            .init(id: "gpt-4.1-mini", displayName: "GPT-4.1 mini", capabilities: toolVision),
            .init(id: "gpt-4.1", displayName: "GPT-4.1", capabilities: toolVision)
        ]
    )

    static let anthropic = provider(
        id: "anthropic",
        name: "Anthropic",
        protocolKind: .anthropicMessages,
        baseURL: "https://api.anthropic.com",
        chatPath: "/v1/messages",
        modelsPath: "/v1/models",
        authStyle: .apiKeyHeader(name: "x-api-key"),
        headers: ["anthropic-version": "2023-06-01"],
        models: [
            .init(id: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4", capabilities: toolVision),
            .init(id: "claude-3-5-haiku-latest", displayName: "Claude 3.5 Haiku", capabilities: toolVision)
        ],
        openAIChat: nil
    )

    static let gemini = provider(
        id: "gemini",
        name: "Gemini",
        protocolKind: .geminiGenerateContent,
        baseURL: "https://generativelanguage.googleapis.com/v1beta",
        chatPath: "/models/{model}:streamGenerateContent?alt=sse",
        modelsPath: "/models",
        authStyle: .apiKeyQuery(name: "key"),
        models: [
            .init(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", capabilities: toolVision),
            .init(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", capabilities: toolVision)
        ],
        openAIChat: nil
    )

    static let deepSeek = provider(
        id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com",
        chatPath: "/chat/completions", modelsPath: "/models",
        models: [
            .init(id: "deepseek-chat", displayName: "DeepSeek Chat", capabilities: toolText),
            .init(id: "deepseek-reasoner", displayName: "DeepSeek Reasoner", capabilities: toolText)
        ],
        sendsStreamOptions: false
    )

    static let groq = provider(
        id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1",
        chatPath: "/chat/completions", modelsPath: "/models",
        models: [
            .init(id: "llama-3.3-70b-versatile", displayName: "Llama 3.3 70B", capabilities: toolText),
            .init(id: "openai/gpt-oss-120b", displayName: "GPT-OSS 120B", capabilities: toolText)
        ],
        sendsStreamOptions: false
    )

    static let xAI = provider(
        id: "xai", name: "xAI", baseURL: "https://api.x.ai/v1",
        chatPath: "/chat/completions", modelsPath: "/models",
        models: [
            .init(id: "grok-3-mini", displayName: "Grok 3 mini", capabilities: toolText),
            .init(id: "grok-3", displayName: "Grok 3", capabilities: toolText)
        ]
    )

    static let openRouter = provider(
        id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",
        chatPath: "/chat/completions", modelsPath: "/models",
        headers: ["HTTP-Referer": "https://familiar.app", "X-Title": "Familiar"],
        models: [
            .init(id: "openai/gpt-4.1-mini", displayName: "GPT-4.1 mini", capabilities: toolVision),
            .init(id: "anthropic/claude-sonnet-4", displayName: "Claude Sonnet 4", capabilities: toolVision)
        ]
    )

    static let qwen = provider(
        id: "qwen", name: "Qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        chatPath: "/chat/completions", modelsPath: nil,
        models: [
            .init(id: "qwen-plus", displayName: "Qwen Plus", capabilities: longToolText),
            .init(id: "qwen-max", displayName: "Qwen Max", capabilities: longToolText)
        ],
        sendsStreamOptions: false
    )

    static let kimi = provider(
        id: "kimi", name: "Kimi", baseURL: "https://api.moonshot.cn/v1",
        chatPath: "/chat/completions", modelsPath: nil,
        models: [
            .init(id: "moonshot-v1-32k", displayName: "Moonshot 32K", capabilities: toolText),
            .init(id: "kimi-k2-0711-preview", displayName: "Kimi K2", capabilities: toolText)
        ],
        sendsStreamOptions: false
    )

    static let glm = provider(
        id: "glm", name: "GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4",
        chatPath: "/chat/completions", modelsPath: nil,
        models: [
            .init(id: "glm-4.5", displayName: "GLM-4.5", capabilities: toolText),
            .init(id: "glm-4-plus", displayName: "GLM-4 Plus", capabilities: toolText)
        ],
        sendsStreamOptions: false
    )

    static let miniMax = provider(
        id: "minimax", name: "MiniMax", baseURL: "https://api.minimax.io/v1",
        chatPath: "/chat/completions", modelsPath: nil,
        models: [
            .init(id: "MiniMax-M1", displayName: "MiniMax M1", capabilities: toolText),
            .init(id: "MiniMax-Text-01", displayName: "MiniMax Text 01", capabilities: toolText)
        ],
        sendsStreamOptions: false
    )

    static let siliconFlow = provider(
        id: "siliconflow", name: "SiliconFlow", baseURL: "https://api.siliconflow.cn/v1",
        chatPath: "/chat/completions", modelsPath: nil,
        models: [
            .init(id: "deepseek-ai/DeepSeek-V3.1", displayName: "DeepSeek V3.1", capabilities: toolText),
            .init(id: "Qwen/Qwen3-32B", displayName: "Qwen3 32B", capabilities: toolText)
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

    private static func normalizedBaseURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["https", "http"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }

    private static func normalizedPath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }
}

private nonisolated extension FamiliarProviderDescriptor {
    func replacing(
        baseURL: URL? = nil,
        additionalHeaders: [String: String]? = nil
    ) -> FamiliarProviderDescriptor {
        FamiliarProviderDescriptor(
            id: id,
            displayName: displayName,
            protocolKind: protocolKind,
            baseURL: baseURL ?? self.baseURL,
            chatPath: chatPath,
            modelsPath: modelsPath,
            authStyle: authStyle,
            additionalHeaders: additionalHeaders ?? self.additionalHeaders,
            curatedModels: curatedModels,
            openAIChat: openAIChat,
            isCustom: isCustom
        )
    }
}
