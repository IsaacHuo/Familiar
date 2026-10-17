import Foundation
import NaturalLanguage

nonisolated enum FamiliarSearchRecency: String, Codable, CaseIterable, Sendable {
    case day, week, month, year
}

nonisolated struct FamiliarSearchRequest: Equatable, Sendable {
    let query: String
    let maximumResults: Int
    var recency: FamiliarSearchRecency? = nil
    /// One deadline for transport retries, HTML shape changes and provider fallback.
    var deadline: ContinuousClock.Instant? = nil
    var language: String {
        let detector = NLLanguageRecognizer()
        detector.processString(query)
        let language = detector.dominantLanguage?.rawValue
            ?? Locale.preferredLanguages.first?.split(separator: "-").first.map(String.init) ?? "en"
        return language.hasPrefix("zh") ? "zh" : language
    }
    var acceptLanguage: String { language == "zh" ? "zh-CN,zh;q=0.9" : language + ",en;q=0.7" }
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
            id: "bing",
            displayName: "Bing",
            requiresAPIKey: false,
            apiKeyPlaceholder: "",
            websiteURL: URL(string: "https://www.bing.com/")!
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

    /// Providers exposed by the iOS 1.0 settings UI. Tavily passed explicit Simulator live HTTP acceptance; other adapters stay
    /// available for deterministic contract tests until their real-key release
    /// smoke tests are complete.
    static var releaseVisible: [FamiliarSearchProviderDescriptor] {
        all.filter { ["duckduckgo", "bing", "tavily"].contains($0.id) }
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
    private let recoversProviderFromKeychain: Bool

    /// `recoversProviderFromKeychain`: UserDefaults is cleared on reinstall while the
    /// Keychain survives, so an unset selection falls back to a provider that still
    /// has a stored key instead of silently orphaning it.
    init(defaults: UserDefaults = .standard, recoversProviderFromKeychain: Bool = false) {
        self.defaults = defaults
        self.recoversProviderFromKeychain = recoversProviderFromKeychain
    }

    var selectedProviderID: String {
        if let stored = defaults.string(forKey: Self.providerDefaultsKey) {
            return FamiliarSearchProviderCatalog.resolvedProviderID(stored)
        }
        if recoversProviderFromKeychain,
           let keyed = FamiliarSearchProviderCatalog.releaseVisible.first(where: {
               $0.requiresAPIKey && FamiliarSearchKeychainStore.lookup(for: $0.id).key != nil
           }) {
            return keyed.id
        }
        return FamiliarSearchProviderCatalog.defaultProviderID
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
    func lookup(for providerID: String) -> FamiliarSearchKeyLookup
}

nonisolated protocol FamiliarSearchAPIKeyManaging: FamiliarSearchAPIKeyStoring {
    func save(_ value: String, for providerID: String) throws
    func delete(for providerID: String) throws
}

nonisolated extension FamiliarSearchAPIKeyStoring {
    func lookup(for providerID: String) -> FamiliarSearchKeyLookup {
        load(for: providerID).map { .found($0) } ?? .missing
    }
}

nonisolated struct FamiliarSearchKeychainAPIKeyStore: FamiliarSearchAPIKeyManaging {
    func save(_ value: String, for providerID: String) throws {
        try FamiliarSearchKeychainStore.save(value, for: providerID)
    }

    func delete(for providerID: String) throws {
        try FamiliarSearchKeychainStore.delete(for: providerID)
    }
    func load(for providerID: String) -> String? {
        FamiliarSearchKeychainStore.load(for: providerID)
    }

    func lookup(for providerID: String) -> FamiliarSearchKeyLookup {
        FamiliarSearchKeychainStore.lookup(for: providerID)
    }
}
