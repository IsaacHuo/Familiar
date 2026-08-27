import Foundation

nonisolated enum FamiliarProviderProtocol: String, Codable, Sendable {
    case openAIChat
}

nonisolated enum FamiliarProviderAuthStyle: Codable, Equatable, Sendable {
    case bearer
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
        "sk-…"
    }

    func model(for modelID: String) -> FamiliarModelDescriptor {
        curatedModels.first(where: { $0.id == modelID })
            ?? FamiliarModelDescriptor(id: modelID, capabilities: .textOnly)
    }
}

nonisolated enum FamiliarProviderCatalog {
    static let builtIn: [FamiliarProviderDescriptor] = [deepSeek]

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
        guard providerID == deepSeek.id,
              deepSeek.curatedModels.contains(where: { $0.id == id })
        else { return deepSeek.defaultModel.id }
        return id
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
