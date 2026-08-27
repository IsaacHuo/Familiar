import Foundation

nonisolated struct FamiliarSearchRequest: Equatable, Sendable {
    let query: String
    let maximumResults: Int
}

nonisolated struct FamiliarSearchResponse: Equatable, Sendable {
    let providerID: String
    let results: [FamiliarWebSearchResult]
    let truncated: Bool
}

nonisolated protocol FamiliarSearchProvider: Sendable {
    var id: String { get }
    func search(request: FamiliarSearchRequest, apiKey: String?) async throws -> FamiliarSearchResponse
}

nonisolated struct FamiliarSearchProviderDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let requiresAPIKey: Bool
    let apiKeyPlaceholder: String
    let websiteURL: URL
}

nonisolated enum FamiliarSearchProviderCatalog {
    static let defaultProviderID = "duckduckgo"

    static let all: [FamiliarSearchProviderDescriptor] = [
        .init(
            id: "duckduckgo",
            displayName: "DuckDuckGo",
            requiresAPIKey: false,
            apiKeyPlaceholder: "",
            websiteURL: URL(string: "https://duckduckgo.com/")!
        ),
        .init(
            id: "brave",
            displayName: "Brave Search",
            requiresAPIKey: true,
            apiKeyPlaceholder: "BSA...",
            websiteURL: URL(string: "https://brave.com/search/api/")!
        ),
        .init(
            id: "tavily",
            displayName: "Tavily",
            requiresAPIKey: true,
            apiKeyPlaceholder: "tvly-...",
            websiteURL: URL(string: "https://tavily.com/")!
        ),
        .init(
            id: "exa",
            displayName: "Exa",
            requiresAPIKey: true,
            apiKeyPlaceholder: "exa-...",
            websiteURL: URL(string: "https://exa.ai/")!
        )
    ]

    /// Providers exposed by the iOS 1.0 settings UI. Additional adapters stay
    /// available for deterministic contract tests until their real-key release
    /// smoke tests are complete.
    static var releaseVisible: [FamiliarSearchProviderDescriptor] {
        all.filter { $0.id == defaultProviderID }
    }

    static func descriptor(for id: String) -> FamiliarSearchProviderDescriptor? {
        all.first { $0.id == id }
    }

    static func resolvedProviderID(_ id: String?) -> String {
        guard let id, descriptor(for: id) != nil else { return defaultProviderID }
        return id
    }
}

nonisolated struct FamiliarSearchSettings: Equatable, Sendable {
    var providerID: String

    static let `default` = FamiliarSearchSettings(
        providerID: FamiliarSearchProviderCatalog.defaultProviderID
    )
}

nonisolated final class FamiliarSearchSettingsStore: @unchecked Sendable {
    static let providerDefaultsKey = "familiar.search.provider.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedProviderID: String {
        FamiliarSearchProviderCatalog.resolvedProviderID(
            defaults.string(forKey: Self.providerDefaultsKey)
        )
    }

    var settings: FamiliarSearchSettings {
        FamiliarSearchSettings(providerID: selectedProviderID)
    }

    func save(_ settings: FamiliarSearchSettings) {
        save(selectedProviderID: settings.providerID)
    }

    func save(selectedProviderID: String) {
        defaults.set(
            FamiliarSearchProviderCatalog.resolvedProviderID(selectedProviderID),
            forKey: Self.providerDefaultsKey
        )
    }
}

nonisolated protocol FamiliarSearchAPIKeyStoring: Sendable {
    func load(for providerID: String) -> String?
}

nonisolated struct FamiliarSearchKeychainAPIKeyStore: FamiliarSearchAPIKeyStoring {
    func load(for providerID: String) -> String? {
        FamiliarSearchKeychainStore.load(for: providerID)
    }
}
