import Foundation
import Testing
@testable import Familiar

private actor WebProbe {
    var calls = 0
    var active = 0
    var peak = 0
    func begin() { calls += 1; active += 1; peak = max(peak, active) }
    func end() { active -= 1 }
    func counts() -> (Int, Int) { (calls, peak) }
}

@Suite("Run-local web evidence")
struct FamiliarWebEvidenceTests {
    private func search(_ url: String = "https://example.com/article") -> FamiliarWebEvidenceState.Search {
        (.init(query: "evidence", engine: "fixture", contentTrust: "untrusted_external_content",
            results: [.init(sourceID: "source", position: 1, title: "Evidence", url: url, displayURL: "example.com", snippet: "Captured evidence")], truncated: false), [])
    }
    private func page(_ url: String) -> FamiliarWebEvidenceState.Page {
        let date = Date(timeIntervalSince1970: 100)
        let source = FamiliarSource(id: "source", kind: .fetchedPage, title: "Evidence", url: URL(string: url)!,
            siteName: "example.com", snippet: "Evidence", retrievedAt: date)
        return (.init(sourceID: source.id, finalURL: url, title: source.title, mimeType: "text/plain",
            contentTrust: "untrusted_external_content", text: "Evidence", truncated: false,
            accessedAt: date, contentHash: FamiliarHash.sha256("Evidence")), source)
    }

    @Test("Normalized repeat searches and in-flight calls execute once")
    func repeatedSearch() async throws {
        let state = FamiliarWebEvidenceState(), probe = WebProbe(), result = search()
        let operation: @Sendable () async throws -> FamiliarWebEvidenceState.Search = {
            await probe.begin(); try await Task.sleep(for: .milliseconds(40)); await probe.end(); return result
        }
        async let first = state.search(query: "  Swift  iOS ", providerID: "fixture", language: "en", operation: operation)
        async let second = state.search(query: "swift ios", providerID: "fixture", language: "en", operation: operation)
        _ = try await (first, second)
        _ = try await state.search(query: "SWIFT IOS", providerID: "fixture", language: "en", operation: operation)
        #expect(await probe.counts().0 == 1)
        _ = try await FamiliarWebEvidenceState().search(query: "swift ios", providerID: "fixture", language: "en", operation: operation)
        #expect(await probe.counts().0 == 2)
    }

    @Test("Canonical URL aliases share one fetch and retain original capture time")
    func repeatedFetch() async throws {
        let state = FamiliarWebEvidenceState(), probe = WebProbe(), result = page("https://example.com/final")
        let operation: @Sendable (String) async throws -> FamiliarWebEvidenceState.Page = { _ in
            await probe.begin(); try await Task.sleep(for: .milliseconds(30)); await probe.end(); return result
        }
        async let first = state.fetch(url: "https://EXAMPLE.com/start?utm_source=test#one", operation: operation)
        async let second = state.fetch(url: "https://example.com/start#two", operation: operation)
        let values = try await (first, second)
        let final = try await state.fetch(url: "https://example.com/final", operation: operation)
        #expect(await probe.counts().0 == 1)
        #expect(values.0.0.accessedAt == final.0.accessedAt)
        #expect(values.1.0.contentHash == final.0.contentHash)
    }

    @Test("Different URLs run concurrently; failed pages are not fetched again")
    func parallelAndFailure() async throws {
        let state = FamiliarWebEvidenceState(), probe = WebProbe()
        let operation: @Sendable (String) async throws -> FamiliarWebEvidenceState.Page = { url in
            await probe.begin(); try await Task.sleep(for: .milliseconds(40)); await probe.end()
            if url.hasSuffix("bad") { throw FamiliarWebError.noReadableContent }
            return page(url)
        }
        async let first = state.fetch(url: "https://example.com/first", operation: operation)
        async let second = state.fetch(url: "https://example.com/second", operation: operation)
        _ = try await (first, second)
        #expect(await probe.counts().1 == 2)
        for _ in 0..<2 {
            await #expect(throws: FamiliarWebError.self) { try await state.fetch(url: "https://example.com/bad", operation: operation) }
        }
        #expect(await probe.counts().0 == 3)
        _ = try await state.fetch(url: "https://example.com/first", operation: operation)
        #expect(await probe.counts().0 == 3)
    }

    @Test("Two searches without new sources stop the loop but known evidence remains usable")
    func noProgress() async throws {
        let state = FamiliarWebEvidenceState(), result = search()
        for query in ["first", "second", "third"] {
            _ = try await state.search(query: query, providerID: "fixture", language: "en") { result }
        }
        await #expect(throws: FamiliarWebError.self) {
            try await state.search(query: "fourth", providerID: "fixture", language: "en") { result }
        }
        let reused = try await state.search(query: "first", providerID: "fixture", language: "en") { throw FamiliarWebError.timeout }
        #expect(reused.0.results.count == 1)
    }

    @Test("Canonicalization preserves business parameters and diverse search selection")
    func canonicalDiversity() throws {
        #expect(try FamiliarWebURLPolicy.normalize("https://example.com/a?id=2&utm_campaign=x#section").absoluteString == "https://example.com/a?id=2")
        #expect(try FamiliarWebURLPolicy.normalize("https://example.com/a?id=3").absoluteString != FamiliarWebURLPolicy.normalize("https://example.com/a?id=2").absoluteString)
        let urls = ["https://example.com/a?utm_source=x", "https://example.com/a#part", "https://example.com/b", "https://swift.org/documentation", "https://developer.apple.com/documentation"]
        let input = urls.enumerated().map { index, url in
            FamiliarWebSearchResult(sourceID: "old-\(index)", position: index + 1, title: "Result", url: url, displayURL: "", snippet: nil)
        }
        let selected = FamiliarWebSearchService.diverseResults(input, maximum: 4)
        #expect(selected.count == 4)
        #expect(selected.map(\.displayURL).prefix(3) == ["example.com", "swift.org", "developer.apple.com"])
        #expect(selected.map(\.position) == [1, 2, 3, 4])
    }

    @Test("Article outranks larger surrounding noise; code and block boundaries survive")
    func readableArticle() throws {
        let html = "<body><div>" + String(repeating: "Surrounding navigation text. ", count: 100)
            + "</div><article><h1>Technical article</h1><p>A specific and sufficiently long explanation of the actual technical content.</p>"
            + "<pre>let value = 1\n    print(value)</pre><div class='comments'><p>Comment noise</p></div></article></body>"
        let extracted = try FamiliarWebContentService.extractReadableHTML(html)
        #expect(extracted.text.contains("actual technical content"))
        #expect(extracted.text.contains("\n    print(value)"))
        #expect(!extracted.text.contains("Surrounding"))
        #expect(!extracted.text.contains("Comment noise"))
        #expect(FamiliarWebContentService.truncate("First paragraph.\n\nSecond long paragraph.", maximum: 25) == "First paragraph.")
        #expect(FamiliarSearchRequest(query: "How does Swift actor isolation work?", maximumResults: 5).language == "en")
        #expect(FamiliarSearchRequest(query: "北京今天的天气预报", maximumResults: 5).language == "zh")
    }
}

private nonisolated struct EvidenceKeyStore: FamiliarSearchAPIKeyStoring {
    func load(for providerID: String) -> String? { nil }
}
private actor EvidenceSearchProvider: FamiliarSearchProvider {
    nonisolated let id = "duckduckgo"
    private var requests = 0
    func search(request: FamiliarSearchRequest, apiKey: String?) async throws -> FamiliarSearchResponse {
        requests += 1
        return .init(providerID: id, results: [.init(sourceID: "fixture", position: 1, title: "Captured fact",
            url: "https://example.com/article", displayURL: "example.com", snippet: "A fact to use in the final answer")], truncated: false)
    }
    func count() -> Int { requests }
}
private actor EvidenceFailedPage: FamiliarWebHTTPTransport {
    private var requests = 0
    func get(_ url: URL, bodyLimit: Int, redirectLimit: Int, timeout: Duration) async throws -> FamiliarRestrictedHTTPResponse {
        requests += 1
        throw FamiliarWebError.noReadableContent
    }
    func count() -> Int { requests }
}
private nonisolated struct EvidenceLoopProvider: FamiliarModelProvider {
    let providerID = "evidence-fixture"
    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let count = request.messages.filter { $0.role == .tool }.count
            if count < 5 {
                let fetch = count == 2 || count == 3
                continuation.yield(.toolCallDelta(index: 0, id: "evidence-\(count)",
                    name: fetch ? "web_fetch" : "web_search",
                    arguments: fetch ? #"{"url":"https://example.com/bad"}"# : #"{"query":"same evidence","maxResults":5}"#))
                continuation.yield(.completed(.toolCalls))
            } else {
                continuation.yield(.textDelta("An answer using the evidence already obtained; one unavailable page does not discard it."))
                continuation.yield(.completed(.stop))
            }
            continuation.finish()
        }
    }
}

extension FamiliarWebEvidenceTests {
    @Test("Production Loop reuses searches and failed pages and still finishes an answer")
    func loopUsesExistingEvidence() async throws {
        let defaults = try #require(UserDefaults(suiteName: "EvidenceLoop-" + UUID().uuidString))
        let searchProvider = EvidenceSearchProvider(), pageProvider = EvidenceFailedPage()
        let service = FamiliarWebSearchService(settingsStore: .init(defaults: defaults), keyStore: EvidenceKeyStore(), providers: [searchProvider])
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarWebSearchTool(service: service)),
            AnyFamiliarTool(FamiliarWebFetchTool(service: .init(client: pageProvider)))])
        let loop = FamiliarAgentLoop(provider: EvidenceLoopProvider(), registry: registry, policy: .init(),
            confirmationCoordinator: .init(), undoStore: .init())
        let snapshot = try familiarTestContextSnapshot(manifests: await registry.snapshot(), projectID: UUID())
        var finish: [FamiliarRunOutcome] = [], answer: FamiliarCompletedResponse?
        for try await event in loop.stream(contextSnapshot: snapshot) {
            if case .runFinished(let value) = event.payload { finish.append(value) }
            if case .responseCompleted(let value) = event.payload { answer = value }
        }
        #expect(await searchProvider.count() == 1)
        #expect(await pageProvider.count() == 1)
        #expect(finish.count == 1)
        #expect(finish.first?.status == .succeeded)
        #expect(answer?.sources.count == 1)
        #expect(answer?.text.contains("already obtained") == true)
    }
}
