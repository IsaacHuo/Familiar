import Foundation
import SwiftSoup

nonisolated struct FamiliarWebContentService: Sendable {
    private let client = FamiliarRestrictedHTTPClient()

    func search(query: String, maximumResults: Int) async throws -> (FamiliarWebSearchOutput, [FamiliarSource]) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty, normalizedQuery.count <= 512 else { throw FamiliarWebError.invalidQuery }
        let limit = min(max(maximumResults, 1), 10)
        let endpoint = try FamiliarWebURLPolicy.normalize("https://html.duckduckgo.com/html/")
        let response = try await client.postForm(endpoint, fields: ["q": normalizedQuery])
        try validate(response)
        guard let html = decode(response.body, contentType: response.headers["content-type"]) else {
            throw FamiliarWebError.malformedResponse
        }
        let engine: String
        let results: [FamiliarWebSearchResult]
        do {
            results = try Self.parseDuckDuckGoHTML(html, maximumResults: limit)
            engine = "duckduckgo_html"
        } catch FamiliarWebError.searchUnavailable {
            let liteURL = try FamiliarWebURLPolicy.normalize("https://lite.duckduckgo.com/lite/?q=\(normalizedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
            let liteResponse = try await client.get(liteURL, bodyLimit: 512_000, redirectLimit: 3)
            try validate(liteResponse)
            guard let liteHTML = decode(liteResponse.body, contentType: liteResponse.headers["content-type"]) else {
                throw FamiliarWebError.malformedResponse
            }
            results = try Self.parseDuckDuckGoLiteHTML(liteHTML, maximumResults: limit)
            engine = "duckduckgo_lite"
        }
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
                query: normalizedQuery,
                engine: engine,
                contentTrust: "untrusted_external_content",
                results: results,
                truncated: false
            ),
            sources
        )
    }

    func fetch(url value: String) async throws -> (FamiliarWebFetchOutput, FamiliarSource) {
        let url = try FamiliarWebURLPolicy.normalize(value)
        let response = try await client.get(url)
        try validate(response)
        let mimeType = response.headers["content-type"]?.split(separator: ";").first.map(String.init)?.lowercased() ?? "text/html"
        guard ["text/html", "application/xhtml+xml", "text/plain"].contains(mimeType) else {
            throw FamiliarWebError.unsupportedContentType
        }
        guard let content = decode(response.body, contentType: response.headers["content-type"]) else {
            throw FamiliarWebError.malformedResponse
        }
        let extracted: (title: String?, text: String)
        if mimeType == "text/plain" {
            extracted = (nil, Self.normalizedText(content))
        } else {
            extracted = try Self.extractReadableHTML(content)
        }
        guard !extracted.text.isEmpty else { throw FamiliarWebError.noReadableContent }
        let truncated = extracted.text.count > 24_000
        let text = String(extracted.text.prefix(24_000))
        let sourceID = FamiliarSourceIdentifier.make(for: response.finalURL)
        let source = FamiliarSource(
            id: sourceID,
            kind: .fetchedPage,
            title: extracted.title ?? response.finalURL.host ?? response.finalURL.absoluteString,
            url: response.finalURL,
            siteName: response.finalURL.host,
            snippet: String(text.prefix(360)),
            retrievedAt: Date()
        )
        return (
            FamiliarWebFetchOutput(
                sourceID: sourceID,
                finalURL: response.finalURL.absoluteString,
                title: extracted.title,
                mimeType: mimeType,
                contentTrust: "untrusted_external_content",
                text: text,
                truncated: truncated
            ),
            source
        )
    }

    static func parseDuckDuckGoHTML(_ html: String, maximumResults: Int) throws -> [FamiliarWebSearchResult] {
        let lowercased = html.lowercased()
        if lowercased.contains("anomaly-modal") || lowercased.contains("captcha") || lowercased.contains("challenge-form") {
            throw FamiliarWebError.searchUnavailable
        }
        let document = try SwiftSoup.parse(html)
        let nodes = try document.select(".result")
        if nodes.isEmpty() {
            if try !document.select(".no-results, .results--main").isEmpty() { return [] }
            throw FamiliarWebError.searchUnavailable
        }
        var seen: Set<String> = []
        var output: [FamiliarWebSearchResult] = []
        for node in nodes.array() {
            guard output.count < maximumResults,
                  let link = try node.select("a.result__a").first(),
                  let destination = unwrapDuckDuckGoURL(try link.attr("href")),
                  let normalized = try? FamiliarWebURLPolicy.normalize(destination.absoluteString),
                  seen.insert(normalized.absoluteString).inserted
            else { continue }
            let title = String(try link.text().trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
            guard !title.isEmpty else { continue }
            let snippet = try node.select(".result__snippet").first().map {
                String(try $0.text().trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
            }
            output.append(.init(
                sourceID: FamiliarSourceIdentifier.make(for: normalized),
                position: output.count + 1,
                title: title,
                url: normalized.absoluteString,
                displayURL: normalized.host ?? normalized.absoluteString,
                snippet: snippet
            ))
        }
        guard !output.isEmpty else { throw FamiliarWebError.searchUnavailable }
        return output
    }

    static func extractReadableHTML(_ html: String) throws -> (title: String?, text: String) {
        let document = try SwiftSoup.parse(html)
        try document.select("script,style,noscript,template,svg,canvas,iframe,form,nav,footer,aside,dialog").remove()
        let openGraphTitle = try nonempty(document.select("meta[property=og:title]").first()?.attr("content"))
        let documentTitle = try nonempty(document.title())
        let headingTitle = try nonempty(document.select("h1").first()?.text())
        let title = openGraphTitle ?? documentTitle ?? headingTitle
        let candidates = try [
            document.select("article").first(),
            document.select("main").first(),
            document.select("[role=main]").first(),
            document.body()
        ].compactMap { $0 }
        guard let selected = try candidates.max(by: { try $0.text().count < $1.text().count }) else {
            throw FamiliarWebError.noReadableContent
        }
        let blocks = try selected.select("h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,th,td")
            .array()
            .compactMap { element -> String? in
                let value = Self.normalizedText(try element.text())
                return value.isEmpty ? nil : value
            }
        let rawText = try blocks.isEmpty ? selected.text() : blocks.joined(separator: "\n\n")
        let text = Self.normalizedText(rawText)
        guard text.count >= 40 else { throw FamiliarWebError.noReadableContent }
        return (title, text)
    }

    static func parseDuckDuckGoLiteHTML(_ html: String, maximumResults: Int) throws -> [FamiliarWebSearchResult] {
        let lowercased = html.lowercased()
        if lowercased.contains("captcha") || lowercased.contains("challenge-form") { throw FamiliarWebError.searchUnavailable }
        let document = try SwiftSoup.parse(html)
        let links = try document.select("a.result-link")
        guard !links.isEmpty() else {
            if lowercased.contains("no results") { return [] }
            throw FamiliarWebError.searchUnavailable
        }
        var output: [FamiliarWebSearchResult] = []
        var seen: Set<String> = []
        for link in links.array() {
            guard output.count < maximumResults,
                  let destination = unwrapDuckDuckGoURL(try link.attr("href")),
                  let normalized = try? FamiliarWebURLPolicy.normalize(destination.absoluteString),
                  seen.insert(normalized.absoluteString).inserted
            else { continue }
            let title = String(try link.text().trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
            guard !title.isEmpty else { continue }
            let row = link.parent()?.parent()
            let snippet = try row?.nextElementSibling()?.select(".result-snippet").first()?.text()
            output.append(.init(
                sourceID: FamiliarSourceIdentifier.make(for: normalized),
                position: output.count + 1,
                title: title,
                url: normalized.absoluteString,
                displayURL: normalized.host ?? normalized.absoluteString,
                snippet: snippet.map { String($0.prefix(600)) }
            ))
        }
        guard !output.isEmpty else { throw FamiliarWebError.searchUnavailable }
        return output
    }

    private func validate(_ response: FamiliarRestrictedHTTPResponse) throws {
        if response.statusCode == 429 { throw FamiliarWebError.rateLimited }
        guard (200..<300).contains(response.statusCode) else { throw FamiliarWebError.httpError(response.statusCode) }
    }

    private func decode(_ data: Data, contentType: String?) -> String? {
        let lowercased = contentType?.lowercased() ?? ""
        if lowercased.contains("charset=iso-8859-1") || lowercased.contains("charset=windows-1252") {
            return String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    }

    private static func unwrapDuckDuckGoURL(_ value: String) -> URL? {
        let absolute = value.hasPrefix("//") ? "https:" + value : value
        guard let url = URL(string: absolute) else { return nil }
        if url.host?.hasSuffix("duckduckgo.com") == true,
           let destination = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "uddg" })?.value {
            return URL(string: destination)
        }
        return url
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func nonempty(_ input: String?) -> String? {
        guard let input else { return nil }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
