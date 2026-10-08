import Foundation
import SwiftSoup

nonisolated struct FamiliarWebContentService: Sendable {
    private let client: any FamiliarWebHTTPTransport
    init(client: any FamiliarWebHTTPTransport = FamiliarRestrictedHTTPClient()) { self.client = client }

    func fetch(url value: String) async throws -> (FamiliarWebFetchOutput, FamiliarSource) {
        let url = try FamiliarWebURLPolicy.normalize(value)
        let response = try await client.get(url, bodyLimit: 2_000_000, redirectLimit: 5, timeout: .seconds(30))
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
        let text = Self.truncate(extracted.text, maximum: 24_000)
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
                truncated: truncated,
                accessedAt: source.retrievedAt,
                contentHash: FamiliarHash.sha256(text)
            ),
            source
        )
    }

    static func parseDuckDuckGoHTML(_ html: String, maximumResults: Int) throws -> [FamiliarWebSearchResult] {
        let lowercased = html.lowercased()
        if lowercased.contains("anomaly-modal") || lowercased.contains("captcha") || lowercased.contains("challenge-form") {
            throw FamiliarWebError.searchChallenge
        }
        let document = try SwiftSoup.parse(html)
        let nodes = try document.select(".result")
        if nodes.isEmpty() {
            if try !document.select(".no-results, .result--no-result").isEmpty() { return [] }
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
        let noise: Set<String> = ["comment", "comments", "related", "recommended", "recommendations", "cookie", "cookies", "consent", "advertisement", "ads", "social", "copyright"]
        for element in try document.select("[class], [id]").array() {
            let labels = try (element.className() + " " + element.id()).lowercased()
                .split { !$0.isLetter }.map(String.init)
            if !noise.isDisjoint(with: labels) { try element.remove() }
        }
        func score(_ element: Element) throws -> Double {
            let count = try element.text().count
            guard count >= 40 else { return 0 }
            let links = try element.select("a").array().reduce(0) { try $0 + $1.text().count }
            let density = min(1, Double(links) / Double(count))
            guard density < 0.5 else { return 0 }
            let nodes = try element.select("*").size()
            return Double(count) * (1 - density) / sqrt(Double(max(1, nodes)))
        }
        var selected: Element?
        for selector in ["article", "main, [role=main]", "section, div"] {
            var best = 0.0
            for element in try document.select(selector).array() {
                let candidate = try score(element)
                if candidate > best { best = candidate; selected = element }
            }
            if selected != nil { break }
        }
        guard let selected = selected ?? document.body() else { throw FamiliarWebError.noReadableContent }
        let tags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "li", "blockquote", "pre", "tr"]
        var blocks: [String] = []
        for element in try selected.select(tags.sorted().joined(separator: ",")).array() {
            var ancestor = element.parent()
            var nested = false
            while let node = ancestor, node !== selected {
                if tags.contains(node.tagName()) { nested = true; break }
                ancestor = node.parent()
            }
            guard !nested else { continue }
            let value = element.tagName() == "pre"
                ? try element.text(trimAndNormaliseWhitespace: false).trimmingCharacters(in: .whitespacesAndNewlines)
                : try Self.normalizedText(element.text())
            if !value.isEmpty { blocks.append(value) }
        }
        let text = try blocks.isEmpty ? Self.normalizedText(selected.text()) : blocks.joined(separator: "\n\n")
        guard text.count >= 40 else { throw FamiliarWebError.noReadableContent }
        return (title, text)
    }

    static func truncate(_ text: String, maximum: Int) -> String {
        guard text.count > maximum else { return text }
        let prefix = String(text.prefix(maximum))
        if let boundary = prefix.range(of: "\n\n", options: .backwards),
           prefix.distance(from: prefix.startIndex, to: boundary.lowerBound) >= maximum / 2 {
            return String(prefix[..<boundary.lowerBound])
        }
        if let boundary = prefix.lastIndex(where: { ".!?\u{3002}\u{ff01}\u{ff1f}\n".contains($0) }),
           prefix.distance(from: prefix.startIndex, to: boundary) >= maximum / 2 {
            return String(prefix[...boundary])
        }
        return prefix
    }

    static func parseDuckDuckGoLiteHTML(_ html: String, maximumResults: Int) throws -> [FamiliarWebSearchResult] {
        let lowercased = html.lowercased()
        if lowercased.contains("captcha") || lowercased.contains("challenge-form") { throw FamiliarWebError.searchChallenge }
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

    static func parseBingHTML(_ html: String, maximumResults: Int) throws -> [FamiliarWebSearchResult] {
        let lowercased = html.lowercased()
        if lowercased.contains("b_captcha") || lowercased.contains("verify you are human") {
            throw FamiliarWebError.searchChallenge
        }
        let document = try SwiftSoup.parse(html)
        let nodes = try document.select("li.b_algo")
        guard !nodes.isEmpty() else {
            if lowercased.contains("no results") || lowercased.contains("没有与此相关的结果") { return [] }
            throw FamiliarWebError.searchUnavailable
        }
        var seen = Set<String>()
        var output: [FamiliarWebSearchResult] = []
        for node in nodes.array() {
            guard output.count < maximumResults,
                  let link = try node.select(".b_algoheader > a, h2 a").first(),
                  let destination = unwrapBingURL(try link.attr("href")),
                  let normalized = try? FamiliarWebURLPolicy.normalize(destination.absoluteString),
                  !(normalized.host == "bing.com" || normalized.host?.hasSuffix(".bing.com") == true),
                  seen.insert(normalized.absoluteString).inserted
            else { continue }
            let title = String(try link.text().trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
            guard !title.isEmpty else { continue }
            let snippet = try node.select(".b_caption p").first().map {
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

    /// Bing's production result links use /ck/a with a URL-safe base64 `u=a1...`.
    /// Decode the supplied destination only; never guess a URL or follow tracking.
    private static func unwrapBingURL(_ value: String) -> URL? {
        guard let url = URL(string: value) else { return nil }
        guard url.host == "bing.com" || url.host?.hasSuffix(".bing.com") == true else { return url }
        guard url.path == "/ck/a",
              let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "u" })?.value,
              encoded.hasPrefix("a1") else { return nil }
        var base64 = String(encoded.dropFirst(2)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let bytes = Data(base64Encoded: base64), let destination = String(data: bytes, encoding: .utf8) else { return nil }
        return URL(string: destination)
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
