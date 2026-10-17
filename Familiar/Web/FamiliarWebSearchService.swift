import Foundation

nonisolated struct FamiliarWebSearchService: Sendable {
    /// Answers when a keyed provider is unreachable. Key, quota and rate-limit
    /// failures are account problems and are reported instead of masked.
    static let keylessFallbackProviderID = "duckduckgo"

    let settingsStore: FamiliarSearchSettingsStore
    let keyStore: any FamiliarSearchAPIKeyStoring
    private let providers: [String: any FamiliarSearchProvider]
    private let timeout: Duration

    init() {
        let transport = FamiliarSearchURLSessionTransport()
        self.init(
            settingsStore: FamiliarSearchSettingsStore(recoversProviderFromKeychain: true),
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
        providers: [any FamiliarSearchProvider],
        timeout: Duration = .seconds(24)
    ) {
        self.settingsStore = settingsStore
        self.keyStore = keyStore
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.timeout = min(timeout, .seconds(24))
    }

    func search(
        query: String,
        maximumResults: Int,
        recency: FamiliarSearchRecency? = nil
    ) async throws -> (FamiliarWebSearchOutput, [FamiliarSource]) {
        let providerID = settingsStore.selectedProviderID
        var request = try normalizedRequest(query: query, maximumResults: maximumResults, recency: recency)
        let deadline = ContinuousClock.now.advanced(by: timeout)
        request.deadline = deadline
        let response: FamiliarSearchResponse
        var fallbackFrom: String?
        do {
            var primary = request
            // Leave room for a keyless answer instead of letting transport retries
            // consume the entire tool budget. Validation never uses this fallback.
            if FamiliarSearchProviderCatalog.descriptor(for: providerID)?.requiresAPIKey == true {
                primary.deadline = min(deadline, ContinuousClock.now.advanced(by: .seconds(12)))
            }
            response = try await search(request: primary, providerID: providerID, apiKey: try apiKey(for: providerID))
        } catch let error as FamiliarWebError where Self.allowsKeylessFallback(after: error, providerID: providerID) {
            fallbackFrom = FamiliarSearchProviderCatalog.descriptor(for: providerID)?.displayName ?? providerID
            response = try await search(request: request, providerID: Self.keylessFallbackProviderID, apiKey: nil)
        }
        let results = Self.rankedResults(response.results, maximum: request.maximumResults)
        let sources = results.compactMap { result -> FamiliarSource? in
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
                query: request.query,
                engine: response.providerID,
                contentTrust: "untrusted_external_content",
                results: results,
                truncated: response.truncated,
                fallbackFrom: fallbackFrom
            ),
            sources
        )
    }

    /// Validates exactly the given provider and key; never falls back.
    func validateConnection(providerID: String, apiKey: String?) async throws {
        _ = try await search(
            request: .init(query: "Familiar iOS", maximumResults: 1,
                           deadline: ContinuousClock.now.advanced(by: timeout)),
            providerID: providerID,
            apiKey: apiKey
        )
    }

    static func allowsKeylessFallback(after error: FamiliarWebError, providerID: String) -> Bool {
        guard providerID != keylessFallbackProviderID,
              FamiliarSearchProviderCatalog.descriptor(for: providerID)?.requiresAPIKey == true
        else { return false }
        switch error {
        case .timeout, .dnsFailed, .searchUnavailable: return true
        case .httpError(let status): return (500...599).contains(status)
        default: return false
        }
    }

    private func apiKey(for providerID: String) throws -> String? {
        guard FamiliarSearchProviderCatalog.descriptor(for: providerID)?.requiresAPIKey == true else { return nil }
        switch keyStore.lookup(for: providerID) {
        case .found(let key): return key
        case .missing: return nil
        case .locked: throw FamiliarWebError.searchKeyLocked
        case .failed(let status): throw FamiliarKeychainError.unexpectedStatus(status)
        }
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
        let deadline = request.deadline ?? ContinuousClock.now.advanced(by: timeout)
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw FamiliarWebError.timeout }
        return try await withThrowingTaskGroup(of: FamiliarSearchResponse.self) { group in
            defer { group.cancelAll() }
            group.addTask { try await provider.search(request: request, apiKey: apiKey) }
            group.addTask {
                try await ContinuousClock().sleep(until: deadline)
                throw FamiliarWebError.timeout
            }
            guard let result = try await group.next() else { throw FamiliarWebError.timeout }
            try Task.checkCancellation()
            return result
        }
    }

    private func normalizedRequest(
        query: String,
        maximumResults: Int,
        recency: FamiliarSearchRecency?
    ) throws -> FamiliarSearchRequest {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 512 else { throw FamiliarWebError.invalidQuery }
        return .init(query: query, maximumResults: min(max(maximumResults, 1), 20), recency: recency)
    }

    /// Keeps the engine's ranking; only removes duplicate URLs and assigns
    /// canonical source IDs. Same-host results (e.g. several official docs
    /// pages) are legitimate and must not be demoted.
    static func rankedResults(_ input: [FamiliarWebSearchResult], maximum: Int) -> [FamiliarWebSearchResult] {
        var seen = Set<String>()
        var ranked: [FamiliarWebSearchResult] = []
        for result in input {
            guard let url = try? FamiliarWebURLPolicy.normalize(result.url),
                  seen.insert(url.absoluteString).inserted else { continue }
            let host = (url.host ?? "").replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            ranked.append(.init(sourceID: FamiliarSourceIdentifier.make(for: url), position: ranked.count + 1,
                title: result.title, url: url.absoluteString, displayURL: host, snippet: result.snippet))
            if ranked.count == min(max(maximum, 1), 20) { break }
        }
        return ranked
    }
}
