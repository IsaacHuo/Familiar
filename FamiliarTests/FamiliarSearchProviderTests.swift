import Foundation
import Testing
@testable import Familiar

@Suite("BYOK search providers")
struct FamiliarSearchProviderTests {
    @Test("Catalog keeps DuckDuckGo default and exposes Bing as a no-key alternative")
    func catalogAndSettings() {
        let suiteName = "FamiliarSearchProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FamiliarSearchSettingsStore(defaults: defaults)

        #expect(FamiliarSearchProviderCatalog.all.map(\.id) == ["duckduckgo", "bing", "brave", "tavily", "exa"])
        #expect(FamiliarSearchProviderCatalog.releaseVisible.map(\.id) == ["duckduckgo", "bing"])
        #expect(store.selectedProviderID == "duckduckgo")
        #expect(store.settings == .default)
        store.save(.init(providerID: "tavily"))
        #expect(store.selectedProviderID == "tavily")
        defaults.set("unknown", forKey: FamiliarSearchSettingsStore.providerDefaultsKey)
        #expect(store.selectedProviderID == "duckduckgo")
        #expect(FamiliarSearchKeychainStore.service == "com.isaachuo.familiar.search-provider-api-keys.v1")
    }

    @Test("DuckDuckGo adapter uses Lite first on mobile networks")
    func duckDuckGoFixture() async throws {
        let transport = FamiliarFixtureSearchTransport(responses: [
            .init(statusCode: 200, headers: ["content-type": "text/html; charset=utf-8"], body: Data("""
            <html><body><table><tr><td><a class="result-link" href="https://example.com/result">Fixture result</a></td></tr></table></body></html>
            """.utf8))
        ])
        let provider = FamiliarDuckDuckGoSearchProvider(transport: transport)

        let response = try await provider.search(
            request: .init(query: "swift language", maximumResults: 3),
            apiKey: nil
        )
        let requests = await transport.recordedRequests()

        #expect(requests.count == 1)
        #expect(requests[0].url?.host == "lite.duckduckgo.com")
        #expect(requests[0].httpMethod == "GET")
        #expect(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "swift language")
        #expect(response.providerID == "duckduckgo")
        #expect(response.results.first?.title == "Fixture result")
    }

    @Test("DuckDuckGo falls back to its HTML shape without changing provider")
    func duckDuckGoShapeFallback() async throws {
        let transport = FamiliarFixtureSearchTransport(responses: [
            .init(statusCode: 503, headers: [:], body: Data()),
            .init(statusCode: 200, headers: ["content-type": "text/html"], body: Data("""
            <html><body><div class="results--main"><div class="result">
              <a class="result__a" href="https://example.com/html">HTML result</a>
            </div></div></body></html>
            """.utf8))
        ])
        let provider = FamiliarDuckDuckGoSearchProvider(transport: transport)
        let response = try await provider.search(request: .init(query: "fixture", maximumResults: 2), apiKey: nil)
        #expect(response.providerID == "duckduckgo")
        #expect(response.results.first?.title == "HTML result")
        #expect(await transport.recordedRequests().map { $0.url?.host } == ["lite.duckduckgo.com", "html.duckduckgo.com"])
    }

    @Test("Bing adapter maps direct public result links")
    func bingFixture() async throws {
        let transport = FamiliarFixtureSearchTransport(responses: [
            .init(statusCode: 200, headers: ["content-type": "text/html"], body: Data("""
            <html><body><ol><li class="b_algo"><div class="b_algoheader">
              <a href="https://example.com/beijing"><h2>Beijing guide</h2></a>
            </div><div class="b_caption"><p>Public information.</p></div></li></ol></body></html>
            """.utf8))
        ])
        let response = try await FamiliarBingSearchProvider(transport: transport).search(
            request: .init(query: "北京", maximumResults: 3),
            apiKey: nil
        )
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.host == "www.bing.com")
        #expect(response.providerID == "bing")
        #expect(response.results.first?.url == "https://example.com/beijing")
        #expect(response.results.first?.snippet == "Public information.")
    }

    @Test("Brave adapter authenticates by header and maps normal web results")
    func braveFixture() async throws {
        let transport = FamiliarFixtureSearchTransport(json: """
        {"web":{"results":[{"title":"Brave result","url":"https://example.com/brave","description":"Brave snippet"}]}}
        """)
        let provider = FamiliarBraveSearchProvider(transport: transport)
        let response = try await provider.search(
            request: .init(query: "fixture", maximumResults: 5),
            apiKey: "brave-secret"
        )
        let request = try #require(await transport.recordedRequests().first)
        let url = try #require(request.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(request.url?.host == "api.search.brave.com")
        #expect(request.value(forHTTPHeaderField: "X-Subscription-Token") == "brave-secret")
        #expect(query.queryItems?.first(where: { $0.name == "q" })?.value == "fixture")
        #expect(query.queryItems?.first(where: { $0.name == "count" })?.value == "5")
        #expect(response.results.first?.url == "https://example.com/brave")
        #expect(response.results.first?.snippet == "Brave snippet")
    }

    @Test("Tavily adapter uses bearer auth and disables answer, raw content, and images")
    func tavilyFixture() async throws {
        let transport = FamiliarFixtureSearchTransport(json: """
        {"results":[{"title":"Tavily result","url":"https://example.com/tavily","content":"Tavily snippet"}]}
        """)
        let provider = FamiliarTavilySearchProvider(transport: transport)
        let response = try await provider.search(
            request: .init(query: "fixture", maximumResults: 4),
            apiKey: "tvly-secret"
        )
        let request = try #require(await transport.recordedRequests().first)
        let requestBody = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: requestBody)
        let body = try #require(json as? [String: Any])

        #expect(request.url?.absoluteString == "https://api.tavily.com/search")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tvly-secret")
        #expect(body["include_answer"] as? Bool == false)
        #expect(body["include_raw_content"] as? Bool == false)
        #expect(body["include_images"] as? Bool == false)
        #expect(body["max_results"] as? Int == 4)
        #expect(response.results.first?.title == "Tavily result")
    }

    @Test("Exa adapter uses fast search and requests only highlights")
    func exaFixture() async throws {
        let transport = FamiliarFixtureSearchTransport(json: """
        {"results":[{"title":"Exa result","url":"https://example.com/exa","highlights":["First highlight","Second highlight"],"text":"must not map"}]}
        """)
        let provider = FamiliarExaSearchProvider(transport: transport)
        let response = try await provider.search(
            request: .init(query: "fixture", maximumResults: 2),
            apiKey: "exa-secret"
        )
        let request = try #require(await transport.recordedRequests().first)
        let requestBody = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: requestBody)
        let body = try #require(json as? [String: Any])
        let contents = try #require(body["contents"] as? [String: Any])

        #expect(request.url?.absoluteString == "https://api.exa.ai/search")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "exa-secret")
        #expect(body["type"] as? String == "fast")
        #expect(contents.keys.sorted() == ["highlights"])
        #expect(body["text"] == nil)
        #expect(body["summary"] == nil)
        #expect(response.results.first?.snippet == "First highlight … Second highlight")
    }

    @Test("A selected keyed provider fails before networking when no key exists")
    func noKey() async throws {
        let suiteName = "FamiliarSearchProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = FamiliarSearchSettingsStore(defaults: defaults)
        settings.save(selectedProviderID: "brave")
        let transport = FamiliarFixtureSearchTransport(json: "{}")
        let service = FamiliarWebSearchService(
            settingsStore: settings,
            keyStore: FamiliarFixtureSearchKeyStore(keys: [:]),
            providers: [FamiliarBraveSearchProvider(transport: transport)]
        )

        do {
            _ = try await service.search(query: "fixture", maximumResults: 1)
            Issue.record("Expected a missing API key error")
        } catch FamiliarWebError.missingSearchAPIKey(let provider) {
            #expect(provider == "Brave Search")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await transport.recordedRequests().isEmpty)
    }

    @Test("A selected provider failure does not fall back to DuckDuckGo")
    func noSilentFallback() async throws {
        let suiteName = "FamiliarSearchProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = FamiliarSearchSettingsStore(defaults: defaults)
        settings.save(selectedProviderID: "brave")
        let transport = FamiliarFixtureSearchTransport(responses: [
            .init(statusCode: 429, headers: [:], body: Data())
        ])
        let service = FamiliarWebSearchService(
            settingsStore: settings,
            keyStore: FamiliarFixtureSearchKeyStore(keys: ["brave": "key"]),
            providers: [
                FamiliarBraveSearchProvider(transport: transport),
                FamiliarDuckDuckGoSearchProvider(transport: transport)
            ]
        )

        do {
            _ = try await service.search(query: "fixture", maximumResults: 1)
            Issue.record("Expected rate limiting")
        } catch FamiliarWebError.rateLimited {
            // Expected: the router reports the selected provider's failure.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let requests = await transport.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests.first?.url?.host == "api.search.brave.com")
    }
}

private nonisolated struct FamiliarFixtureSearchKeyStore: FamiliarSearchAPIKeyStoring {
    let keys: [String: String]
    func load(for providerID: String) -> String? { keys[providerID] }
}

private actor FamiliarFixtureSearchTransport: FamiliarSearchHTTPTransport {
    private var responses: [FamiliarSearchHTTPResponse]
    private var requests: [URLRequest] = []

    init(responses: [FamiliarSearchHTTPResponse]) {
        self.responses = responses
    }

    init(json: String) {
        responses = [
            .init(
                statusCode: 200,
                headers: ["content-type": "application/json"],
                body: Data(json.utf8)
            )
        ]
    }

    func send(_ request: URLRequest, responseLimit: Int) async throws -> FamiliarSearchHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw FamiliarWebError.searchUnavailable }
        let response = responses.removeFirst()
        guard response.body.count <= responseLimit else { throw FamiliarWebError.responseTooLarge }
        return response
    }

    func recordedRequests() -> [URLRequest] { requests }
}
