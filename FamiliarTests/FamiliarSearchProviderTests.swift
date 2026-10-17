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
        #expect(FamiliarSearchProviderCatalog.releaseVisible.map(\.id) == ["duckduckgo", "bing", "tavily"])
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

@Suite("Search reliability")
struct FamiliarSearchReliabilityTests {
    @Test("Tavily tolerates null titles and missing URLs instead of failing the response")
    func tavilyLenientDecoding() async throws {
        let transport = FamiliarFixtureSearchTransport(json: """
        {"results":[{"title":null,"url":"https://example.com/a","content":"A"},{"title":"No URL","url":null},{"title":"B","url":"https://example.com/b"}]}
        """)
        let response = try await FamiliarTavilySearchProvider(transport: transport)
            .search(request: .init(query: "q", maximumResults: 5, recency: .week), apiKey: "k")
        #expect(response.results.map(\.url) == ["https://example.com/a", "https://example.com/b"])
        #expect(response.results.first?.title == "example.com")
        let httpBody = try #require(await transport.recordedRequests().first?.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(body["time_range"] as? String == "week")
    }

    @Test("Tavily key and quota errors map to real causes", arguments: [(401, "search_api_key_rejected"), (432, "search_quota_exceeded")])
    func tavilyErrors(status: Int, code: String) async throws {
        let transport = FamiliarFixtureSearchTransport(responses: [.init(statusCode: status, headers: [:], body: Data())])
        do {
            _ = try await FamiliarTavilySearchProvider(transport: transport).search(request: .init(query: "q", maximumResults: 1), apiKey: "k")
            Issue.record("Expected failure")
        } catch let error as FamiliarWebError {
            #expect(error.code == code)
        }
    }

    @Test("An unreachable keyed provider falls back to keyless search and says so")
    func keylessFallback() async throws {
        let suiteName = "FamiliarSearchReliabilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = FamiliarSearchSettingsStore(defaults: defaults)
        settings.save(selectedProviderID: "tavily")
        let transport = FamiliarFixtureSearchTransport(responses: [.init(statusCode: 503, headers: [:], body: Data())])
        let service = FamiliarWebSearchService(settingsStore: settings,
            keyStore: FamiliarFixtureSearchKeyStore(keys: ["tavily": "k"]),
            providers: [FamiliarTavilySearchProvider(transport: transport), FamiliarFixedSearchProvider(id: "duckduckgo")])
        let (output, sources) = try await service.search(query: "q", maximumResults: 5)
        #expect(output.engine == "duckduckgo")
        #expect(output.fallbackFrom == "Tavily")
        #expect(sources.count == 1)
    }

    @Test("Rate limiting on a keyed provider is reported, not masked by fallback")
    func noFallbackOnAccountErrors() {
        #expect(!FamiliarWebSearchService.allowsKeylessFallback(after: .rateLimited, providerID: "tavily"))
        #expect(!FamiliarWebSearchService.allowsKeylessFallback(after: .searchKeyRejected("Tavily"), providerID: "tavily"))
        #expect(FamiliarWebSearchService.allowsKeylessFallback(after: .timeout, providerID: "tavily"))
        #expect(!FamiliarWebSearchService.allowsKeylessFallback(after: .timeout, providerID: "duckduckgo"))
    }

    @Test("Query language never adds a geographic restriction", arguments: [
        "Swift 并发 官方文档", "Python 最新稳定版本", "中国人口统计 官方数据"
    ])
    func languageDoesNotSetCountry(query: String) async throws {
        let tavily = FamiliarFixtureSearchTransport(json: #"{"results":[{"title":"Official","url":"https://example.com/official"}]}"#)
        _ = try await FamiliarTavilySearchProvider(transport: tavily).search(request: .init(query: query, maximumResults: 2), apiKey: "fixture")
        let tavilyRequest = try #require(await tavily.recordedRequests().first)
        let data = try #require(tavilyRequest.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["query"] as? String == query)
        #expect(body["country"] == nil)
        #expect(body["language"] == nil)
        let ddg = FamiliarFixtureSearchTransport(responses: [.init(statusCode: 200, headers: [:],
            body: Data(#"<table><tr><td><a class="result-link" href="https://example.com/official">Official</a></td></tr></table>"#.utf8))])
        _ = try await FamiliarDuckDuckGoSearchProvider(transport: ddg).search(request: .init(query: query, maximumResults: 2), apiKey: nil)
        let ddgURL = try #require(await ddg.recordedRequests().first?.url)
        let ddgItems = try #require(URLComponents(url: ddgURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(ddgItems.first { $0.name == "q" }?.value == query)
        #expect(ddgItems.first { $0.name == "kl" }?.value == "wt-wt")
        let bing = FamiliarFixtureSearchTransport(responses: [.init(statusCode: 200, headers: [:],
            body: Data(#"<li class="b_algo"><h2><a href="https://example.com/official">Official</a></h2></li>"#.utf8))])
        _ = try await FamiliarBingSearchProvider(transport: bing).search(request: .init(query: query, maximumResults: 2), apiKey: nil)
        let bingURL = try #require(await bing.recordedRequests().first?.url)
        let bingItems = try #require(URLComponents(url: bingURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(bingItems.first { $0.name == "q" }?.value == query)
        #expect(!bingItems.contains { $0.name == "mkt" })
    }

    @Test("Web tool requests the actual count and only reuses identical requests")
    func toolRequestsActualCount() async throws {
        let name = "SearchToolCount-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = FamiliarSearchSettingsStore(defaults: defaults)
        settings.save(selectedProviderID: "tavily")
        let response = FamiliarSearchHTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"results":[{"title":"A","url":"https://example.com/a"}]}"#.utf8))
        let transport = FamiliarFixtureSearchTransport(responses: [response, response])
        let tool = FamiliarWebSearchTool(service: .init(settingsStore: settings,
            keyStore: FamiliarFixtureSearchKeyStore(keys: ["tavily": "fixture"]), providers: [FamiliarTavilySearchProvider(transport: transport)]))
        let context = FamiliarToolContext(webEvidence: FamiliarWebEvidenceState())
        for count in [2, 2, 1] {
            _ = try await tool.execute(.init(query: "same query", maxResults: count, recency: .none), context: context)
        }
        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        let counts = try requests.map { request in
            let data = try #require(request.httpBody)
            let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return body["max_results"] as? Int
        }
        #expect(counts == [2, 1])
    }

    @Test("Search deadlines cancel the provider and never reset for fallback")
    func sharedDeadline() async throws {
        let name = "SearchDeadline-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = FamiliarSearchSettingsStore(defaults: defaults)
        settings.save(selectedProviderID: "tavily")
        let probe = SearchDeadlineProbe()
        let service = FamiliarWebSearchService(settingsStore: settings,
            keyStore: FamiliarFixtureSearchKeyStore(keys: ["tavily": "fixture"]),
            providers: [SlowSearchProvider(id: "tavily", probe: probe),
                        SlowSearchProvider(id: "duckduckgo", probe: probe)], timeout: .milliseconds(80))
        let start = ContinuousClock.now
        await #expect(throws: FamiliarWebError.self) { _ = try await service.search(query: "q", maximumResults: 2) }
        #expect(start.duration(to: .now) < .seconds(1))
        #expect(await probe.cancellations == 1)
        #expect(await probe.calls == 1)
    }

    @Test("Caller cancellation stops the provider without starting fallback")
    func cancelledSearch() async throws {
        let name = "SearchCancellation-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = FamiliarSearchSettingsStore(defaults: defaults)
        settings.save(selectedProviderID: "tavily")
        let probe = SearchDeadlineProbe()
        let service = FamiliarWebSearchService(settingsStore: settings,
            keyStore: FamiliarFixtureSearchKeyStore(keys: ["tavily": "fixture"]),
            providers: [SlowSearchProvider(id: "tavily", probe: probe), SlowSearchProvider(id: "duckduckgo", probe: probe)])
        let task = Task { try await service.search(query: "q", maximumResults: 2) }
        await probe.waitForStart()
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(await probe.calls == 1)
        #expect(await probe.cancellations == 1)
    }

    @Test("Provider fallback uses the original deadline and actual result count")
    func fallbackBudgetAndResultCount() async throws {
        let name = "SearchFallback-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = FamiliarSearchSettingsStore(defaults: defaults)
        settings.save(selectedProviderID: "tavily")
        let transport = FamiliarFixtureSearchTransport(responses: [.init(statusCode: 503, headers: [:], body: Data())])
        let probe = SearchDeadlineProbe()
        let service = FamiliarWebSearchService(settingsStore: settings,
            keyStore: FamiliarFixtureSearchKeyStore(keys: ["tavily": "fixture"]),
            providers: [FamiliarTavilySearchProvider(transport: transport), SlowSearchProvider(id: "duckduckgo", probe: probe)],
            timeout: .milliseconds(80))
        let start = ContinuousClock.now
        await #expect(throws: FamiliarWebError.self) { _ = try await service.search(query: "q", maximumResults: 2) }
        #expect(start.duration(to: .now) < .seconds(1))
        let request = try #require(await transport.recordedRequests().first)
        let httpBody = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(body["max_results"] as? Int == 2)
        #expect(await probe.calls == 1)
        #expect(await probe.cancellations == 1)
    }

    @MainActor @Test("Provider switching commits to the old service; save failure keeps its draft")
    func editorSwitchAndSaveFailure() throws {
        let name = "SearchEditor-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = FamiliarSearchSettingsStore(defaults: defaults)
        settings.save(selectedProviderID: "tavily")
        let keys = SearchEditingKeys()
        let state = FamiliarSearchSettingsState(settings: settings, keys: keys) { _, _ in }
        state.apiKey = "Bearer fixture-one"
        state.selectProvider("bing")
        #expect(keys.load(for: "tavily") == "fixture-one")
        #expect(keys.load(for: "bing") == nil)
        #expect(state.providerID == "bing")
        state.selectProvider("tavily")
        state.apiKey = "fixture-two"
        keys.failSaving = true
        state.selectProvider("bing")
        #expect(state.providerID == "tavily")
        #expect(state.apiKey == "fixture-two")
        #expect(state.errorMessage != nil)
        #expect(state.startValidation() == nil)
        #expect(!state.validationSucceeded)
        keys.failSaving = false
        state.leave()
        let restored = FamiliarSearchSettingsState(settings: settings, keys: keys) { _, _ in }
        #expect(restored.keyState.key == "fixture-two")
        restored.deleteKey()
        #expect(restored.keyState == .missing)
    }

    @MainActor @Test("Only the current saved key may become verified")
    func editorValidationRevision() async throws {
        let name = "SearchVerification-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = FamiliarSearchSettingsStore(defaults: defaults)
        settings.save(selectedProviderID: "tavily")
        let keys = SearchEditingKeys(), gate = SearchValidationGate()
        let state = FamiliarSearchSettingsState(settings: settings, keys: keys) { _, _ in await gate.validate() }
        state.apiKey = "fixture-one"
        let old = try #require(state.startValidation())
        await gate.waitForStart()
        state.apiKey = "fixture-two"
        await gate.finish()
        await old.value
        #expect(!state.validationSucceeded)
        #expect(state.apiKey == "fixture-two")
        let current = try #require(state.startValidation())
        await gate.waitForStart()
        await gate.finish()
        await current.value
        #expect(state.validationSucceeded)
        #expect(state.keyState.key == "fixture-two")
        let switched = try #require(state.startValidation())
        await gate.waitForStart()
        state.selectProvider("bing")
        await gate.finish()
        await switched.value
        #expect(state.providerID == "bing")
        #expect(!state.validationSucceeded)
        keys.forcedLookup = .locked
        state.selectProvider("tavily")
        #expect(state.keyState == .locked)
        #expect(state.startValidation() == nil)
        #expect(!state.validationSucceeded)
    }

    @Test("Pasted keys are normalized")
    func keyNormalization() {
        #expect(FamiliarSearchKeychainStore.normalized("  \"Bearer tvly-abc\u{200B}\"\n") == "tvly-abc")
        #expect(FamiliarSearchKeychainStore.normalized("tvly-abc") == "tvly-abc")
    }
}

private nonisolated struct FamiliarFixedSearchProvider: FamiliarSearchProvider {
    let id: String
    func search(request: FamiliarSearchRequest, apiKey: String?) async throws -> FamiliarSearchResponse {
        .init(providerID: id, results: [.init(sourceID: "s", position: 1, title: "Fallback", url: "https://example.com/f",
            displayURL: "example.com", snippet: nil)], truncated: false)
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

    func send(_ request: URLRequest, responseLimit: Int, deadline: ContinuousClock.Instant?) async throws -> FamiliarSearchHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw FamiliarWebError.searchUnavailable }
        let response = responses.removeFirst()
        guard response.body.count <= responseLimit else { throw FamiliarWebError.responseTooLarge }
        return response
    }

    func recordedRequests() -> [URLRequest] { requests }
}

private actor SearchDeadlineProbe {
    private(set) var calls = 0
    private(set) var cancellations = 0
    private var waiter: CheckedContinuation<Void, Never>?
    func begin() { calls += 1; waiter?.resume(); waiter = nil }
    func cancelled() { cancellations += 1 }
    func waitForStart() async {
        if calls > 0 { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private nonisolated struct SlowSearchProvider: FamiliarSearchProvider {
    let id: String
    let probe: SearchDeadlineProbe
    func search(request: FamiliarSearchRequest, apiKey: String?) async throws -> FamiliarSearchResponse {
        await probe.begin()
        do { try await Task.sleep(for: .seconds(10)) }
        catch { await probe.cancelled(); throw error }
        return .init(providerID: id, results: [], truncated: false)
    }
}

private nonisolated final class SearchEditingKeys: FamiliarSearchAPIKeyManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var fail = false
    private var forced: FamiliarSearchKeyLookup?
    var failSaving: Bool {
        get { lock.withLock { fail } }
        set { lock.withLock { fail = newValue } }
    }
    var forcedLookup: FamiliarSearchKeyLookup? {
        get { lock.withLock { forced } }
        set { lock.withLock { forced = newValue } }
    }
    func load(for providerID: String) -> String? { lookup(for: providerID).key }
    func lookup(for providerID: String) -> FamiliarSearchKeyLookup {
        lock.withLock { forced ?? values[providerID].map { .found($0) } ?? .missing }
    }
    func save(_ value: String, for providerID: String) throws {
        try lock.withLock {
            if fail { throw FamiliarWebError.searchKeyLocked }
            values[providerID] = value
        }
    }
    func delete(for providerID: String) throws { _ = lock.withLock { values.removeValue(forKey: providerID) } }
}

private actor SearchValidationGate {
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func validate() async {
        await withCheckedContinuation { continuation in
            pending = continuation
            waiter?.resume(); waiter = nil
        }
    }
    func waitForStart() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish() { pending?.resume(); pending = nil }
}
