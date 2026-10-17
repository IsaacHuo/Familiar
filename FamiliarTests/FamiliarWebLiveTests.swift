import Foundation
import XCTest
@testable import Familiar

/// Explicitly selected network acceptance, never part of deterministic regressions.
final class FamiliarWebLiveTests: XCTestCase {
    private func search(providerID: String, query: String, key: String? = nil) async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FamiliarWebLive-" + UUID().uuidString))
        let settings = FamiliarSearchSettingsStore(defaults: defaults)
        settings.save(selectedProviderID: providerID)
        let transport = FamiliarSearchURLSessionTransport()
        let service = FamiliarWebSearchService(settingsStore: settings, keyStore: LiveSearchCredential(key: key),
            providers: [FamiliarDuckDuckGoSearchProvider(transport: transport), FamiliarBingSearchProvider(transport: transport),
                FamiliarTavilySearchProvider(transport: transport)])
        let (output, sources) = try await service.search(query: query, maximumResults: 5)
        XCTAssertEqual(output.engine, providerID)
        XCTAssertFalse(output.results.isEmpty)
        XCTAssertEqual(output.results.count, sources.count)
        XCTAssertEqual(Set(output.results.map(\.url)).count, output.results.count)
        let receipt = "provider=\(providerID) query=\(query) results=\(sources.count)\n"
            + sources.map { $0.url.absoluteString }.joined(separator: "\n")
        let attachment = XCTAttachment(string: receipt)
        attachment.name = "live-search-\(providerID)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    /// Uses only keys already configured in the Simulator App; no credentials
    /// are copied into arguments, attachments, source files or test results.
    func testS1DeepSeekTavilyTwentyQueries() async throws {
        guard let modelKey = FamiliarKeychainStore.load(for: "deepseek"),
              let searchKey = Self.suppliedSearchKey() ?? FamiliarSearchKeychainStore.lookup(for: "tavily").key else {
            throw XCTSkip("S1 requires configured DeepSeek and Tavily keys in this Simulator; no real-service acceptance performed.")
        }
        let descriptor = try XCTUnwrap(FamiliarProviderCatalog.descriptor(for: "deepseek"))
        let provider = FamiliarProviderFactory.makeProvider(for: descriptor, apiKey: modelKey)
        let name = "S1LiveSearch-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = FamiliarSearchSettingsStore(defaults: defaults)
        settings.save(selectedProviderID: "tavily")
        let transport = FamiliarSearchURLSessionTransport()
        let search = FamiliarWebSearchService(settingsStore: settings, keyStore: LiveSearchCredential(key: searchKey),
            providers: [FamiliarTavilySearchProvider(transport: transport), FamiliarDuckDuckGoSearchProvider(transport: transport)])
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarWebSearchTool(service: search)),
            AnyFamiliarTool(FamiliarWebFetchTool(service: .init()))])
        for (index, query) in Self.s1Queries.enumerated() {
            print("S1 live query \(index + 1)/20 started")
            let start = ContinuousClock.now
            let loop = FamiliarAgentLoop(provider: provider, registry: registry, policy: .init(),
                confirmationCoordinator: .init(), undoStore: .init(), maximumIterations: 12, maximumDuration: 120)
            let message = FamiliarMessageSnapshot(id: UUID(), role: .user, content: query,
                createdAt: Date(), sequence: 0, providerID: nil, modelID: nil, attachments: [])
            let snapshot = try FamiliarContextCompiler.assemble(seed: .init(projectID: UUID(), projectName: "S1 verification",
                conversationID: UUID(), projectInstruction: nil, resources: []),
                settings: .defaultValue, messages: [message], toolManifests: await registry.snapshot())
            var answer: FamiliarCompletedResponse?, outcome: FamiliarRunOutcome?
            var calls: [String] = [], errors: [String] = [], fetched = Set<String>(), engines: [String] = [], searchQueries: [String] = []
            for try await event in loop.stream(contextSnapshot: snapshot) {
                switch event.payload {
                case .activityCompleted(let record):
                    calls.append(record.toolName)
                    if let code = record.failureCode { errors.append(code) }
                case .toolResultProduced(let result):
                    if result.toolName == "web_fetch" { fetched.formUnion(result.sources.map(\.id)) }
                    if result.toolName == "web_search",
                       let data = result.envelope.modelContent.data(using: .utf8),
                       let output = try? JSONDecoder().decode(FamiliarWebSearchOutput.self, from: data) { engines.append(output.engine); searchQueries.append(output.query) }
                case .responseCompleted(let response): answer = response
                case .runFinished(let result): outcome = result
                default: break
                }
            }
            let resolved = FamiliarCitation.canonicalized(answer?.text ?? "", sources: answer?.sources ?? [])
            let cited = FamiliarCitation.cited(in: resolved.text, sources: resolved.sources)
            let unknown = Set(FamiliarCitation.identifiers(in: resolved.text)).subtracting(resolved.sources.map(\.id))
            let receipt: [String: Any] = ["query": query, "model": snapshot.modelID,
                "elapsed": String(describing: start.duration(to: .now)), "tools": calls, "errors": errors,
                "searchEngines": engines, "searchQueries": searchQueries, "answer": resolved.text, "unknownCitations": Array(unknown),
                "sources": cited.map { ["id": $0.id, "url": $0.url.absoluteString, "kind": $0.kind.rawValue] },
                "relevanceReview": "pending", "citationContentReview": "pending"]
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = String(format: "S1-live-%02d", index + 1)
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(outcome?.status, .succeeded, "Query \(index + 1) did not finish")
            XCTAssertTrue(calls.contains("web_search"), "Query \(index + 1) did not search")
            XCTAssertFalse(fetched.isEmpty, "Query \(index + 1) did not read a page")
            XCTAssertFalse(cited.isEmpty, "Query \(index + 1) has no citations")
            XCTAssertTrue(unknown.isEmpty, "Query \(index + 1) contains unresolved citations")
            if [0, 1, 6, 7, 8, 10, 11, 12, 16, 17, 18].contains(index) {
                XCTAssertFalse(searchQueries.contains { $0.contains("中国") || $0.localizedCaseInsensitiveContains("china") },
                    "A global technical query acquired an unrequested country restriction")
            }
        }
    }

    private static func suppliedSearchKey() -> String? {
        guard let path = ProcessInfo.processInfo.environment["FAMILIAR_LIVE_SECRET_FILE"],
              let value = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let key = FamiliarSearchKeychainStore.normalized(value)
        return key.isEmpty ? nil : key
    }

    private static let s1Queries = [
        "请查官方来源，说明 Swift 当前稳定版本及发布日期。",
        "请查苹果官方来源，说明当前 iOS 稳定版本及发布日期。",
        "请查中国气象局近期公开公告，概括最近一条公告并引用正文。",
        "请查北京地铁官方网站，找到最新线路图页面并说明获取方式。",
        "请查国家统计局最近发布的居民消费价格数据，说明统计月份和变化。",
        "请查中国人民银行最新公开货币政策公告，说明发布日期和要点。",
        "请查 Swift 官方文档，解释 actor isolation，引用具体页面。",
        "请查 Apple 官方文档，说明 SwiftUI 的 Observation 数据流。",
        "请查 Python 官方网站，说明当前稳定版及发布日期。",
        "请对照两个官方来源，说明目前 WebAssembly 标准与浏览器支持情况。",
        "Find the latest stable Swift release and its publication date from official sources.",
        "Find the current stable iOS release from Apple's official release notes.",
        "Read the latest Python release announcement and summarize its main changes.",
        "Find the latest NASA press release and summarize it with citations to the article.",
        "Find the latest ECB monetary policy decision and state its date and key points.",
        "Find the latest US CPI release from BLS and identify its reference month.",
        "Explain Swift actor isolation using current official documentation.",
        "Explain SwiftUI Observation using current Apple documentation.",
        "Compare the current stable Python and Swift versions using their official release pages.",
        "Read two official sources about the current WebAssembly standard and browser support."
    ]

    func testBingEnglishProductionLinks() async throws {
        try await search(providerID: "bing", query: "Swift programming language official documentation")
    }
    func testBingChinese() async throws {
        try await search(providerID: "bing", query: "北京 地铁 官方 线路图")
    }
    func testDuckDuckGoEnglishAndChinese() async throws {
        try await search(providerID: "duckduckgo", query: "Swift programming language official documentation")
        try await search(providerID: "duckduckgo", query: "北京 地铁 官方 线路图")
    }
    func testPublicPageThroughRestrictedClient() async throws {
        let (output, source) = try await FamiliarWebContentService().fetch(url: "https://www.swift.org/about/")
        XCTAssertFalse(output.text.isEmpty)
        XCTAssertEqual(output.contentHash, FamiliarHash.sha256(output.text))
        XCTAssertEqual(source.id, output.sourceID)
        XCTAssertTrue(output.text.localizedCaseInsensitiveContains("Swift"))
        let attachment = XCTAttachment(string: "url=\(output.finalURL) chars=\(output.text.count) truncated=\(output.truncated) hash=\(output.contentHash)")
        attachment.name = "live-restricted-fetch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testTavilyEnglishAndChinese() async throws {
        // The secret is supplied through an owned 0600 temporary file. Neither the
        // .xctestrun environment nor CLI/logs contains its value. No shipping key.
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["FAMILIAR_LIVE_SECRET_FILE"])
        let key = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(key.isEmpty)
        try await search(providerID: "tavily", query: "Swift programming language official documentation", key: key)
        try await search(providerID: "tavily", query: "北京 地铁 官方 线路图", key: key)
    }
}
private nonisolated struct LiveSearchCredential: FamiliarSearchAPIKeyStoring {
    let key: String?
    func load(for providerID: String) -> String? { key }
}
