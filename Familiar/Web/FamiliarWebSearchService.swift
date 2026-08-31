import Foundation

nonisolated struct FamiliarWebSearchService: Sendable {
    let settingsStore: FamiliarSearchSettingsStore
    let keyStore: any FamiliarSearchAPIKeyStoring
    private let providers: [String: any FamiliarSearchProvider]

    init() {
        let transport = FamiliarSearchURLSessionTransport()
        self.init(
            settingsStore: FamiliarSearchSettingsStore(),
            keyStore: FamiliarSearchKeychainAPIKeyStore(),
            providers: [
                FamiliarDuckDuckGoSearchProvider(transport: transport),
                FamiliarBingSearchProvider(transport: transport),
                FamiliarBraveSearchProvider(transport: transport),
                FamiliarTavilySearchProvider(transport: transport),
                FamiliarExaSearchProvider(transport: transport)
            ]
        )
    }

    init(
        settingsStore: FamiliarSearchSettingsStore,
        keyStore: any FamiliarSearchAPIKeyStoring,
        providers: [any FamiliarSearchProvider]
    ) {
        self.settingsStore = settingsStore
        self.keyStore = keyStore
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    func search(query: String, maximumResults: Int) async throws -> (FamiliarWebSearchOutput, [FamiliarSource]) {
        let providerID = settingsStore.selectedProviderID
        let response = try await search(
            request: normalizedRequest(query: query, maximumResults: maximumResults),
            providerID: providerID,
            apiKey: keyStore.load(for: providerID)
        )
        let sources = response.results.compactMap { result -> FamiliarSource? in
            guard let url = URL(string: result.url) else { return nil }
            return FamiliarSource(
                id: result.sourceID,
                kind: .searchResult,
                title: result.title,
                url: url,
                siteName: url.host,
                snippet: result.snippet,
                retrievedAt: Date()
            )
        }
        return (
            FamiliarWebSearchOutput(
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                engine: response.providerID,
                contentTrust: "untrusted_external_content",
                results: response.results,
                truncated: response.truncated
            ),
            sources
        )
    }

    func validateConnection(providerID: String, apiKey: String?) async throws {
        _ = try await search(
            request: .init(query: "Familiar iOS", maximumResults: 1),
            providerID: providerID,
            apiKey: apiKey
        )
    }

    private func search(
        request: FamiliarSearchRequest,
        providerID: String,
        apiKey: String?
    ) async throws -> FamiliarSearchResponse {
        guard let descriptor = FamiliarSearchProviderCatalog.descriptor(for: providerID),
              let provider = providers[providerID]
        else { throw FamiliarWebError.searchUnavailable }
        if descriptor.requiresAPIKey {
            guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FamiliarWebError.missingSearchAPIKey(descriptor.displayName)
            }
        }
        return try await provider.search(request: request, apiKey: apiKey)
    }

    private func normalizedRequest(query: String, maximumResults: Int) throws -> FamiliarSearchRequest {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 512 else { throw FamiliarWebError.invalidQuery }
        return .init(query: query, maximumResults: min(max(maximumResults, 1), 10))
    }
}
