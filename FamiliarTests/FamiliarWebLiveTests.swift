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
