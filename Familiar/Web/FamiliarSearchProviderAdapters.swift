import Foundation

nonisolated struct FamiliarSearchHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

nonisolated protocol FamiliarSearchHTTPTransport: Sendable {
    func send(_ request: URLRequest, responseLimit: Int) async throws -> FamiliarSearchHTTPResponse
}

nonisolated final class FamiliarSearchURLSessionTransport: FamiliarSearchHTTPTransport, @unchecked Sendable {
    private static let allowedHosts: Set<String> = [
        "html.duckduckgo.com",
        "lite.duckduckgo.com",
        "www.bing.com",
        "cn.bing.com",
        "api.search.brave.com",
        "api.tavily.com",
        "api.exa.ai"
    ]

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest, responseLimit: Int) async throws -> FamiliarSearchHTTPResponse {
        guard let url = request.url,
              url.scheme == "https",
              let host = url.host?.lowercased(),
              Self.allowedHosts.contains(host)
        else { throw FamiliarWebError.invalidURL }

        var lastError: (any Error)?
        for attempt in 0..<2 {
            do {
                return try await sendOnce(request, responseLimit: responseLimit)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt == 0, Self.isRetryableTransportError(error) else { throw Self.mapped(error) }
                try await Task.sleep(for: .milliseconds(350))
            }
        }
        throw Self.mapped(lastError ?? FamiliarWebError.searchUnavailable)
    }

    private func sendOnce(_ original: URLRequest, responseLimit: Int) async throws -> FamiliarSearchHTTPResponse {
        var request = original
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 12
        let delegate = FamiliarSearchRedirectDelegate()
        let (body, response) = try await session.data(for: request, delegate: delegate)
        guard let response = response as? HTTPURLResponse else { throw FamiliarWebError.malformedResponse }
        guard response.expectedContentLength < 0 || response.expectedContentLength <= Int64(responseLimit),
              body.count <= responseLimit
        else { throw FamiliarWebError.responseTooLarge }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            guard let key = field.key as? String, let value = field.value as? String else { return }
            result[key.lowercased()] = value
        }
        return .init(statusCode: response.statusCode, headers: headers, body: body)
    }

    private static func isRetryableTransportError(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [
            .timedOut, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost,
            .cannotConnectToHost, .notConnectedToInternet
        ].contains(error.code)
    }

    private static func mapped(_ error: any Error) -> any Error {
        guard let error = error as? URLError else { return error }
        return switch error.code {
        case .timedOut: FamiliarWebError.timeout
        case .cannotFindHost, .dnsLookupFailed: FamiliarWebError.dnsFailed
        default: FamiliarWebError.searchUnavailable
        }
    }
}

private nonisolated final class FamiliarSearchRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var redirectCount = 0

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let from = task.currentRequest?.url,
              let to = request.url,
              to.scheme?.lowercased() == "https",
              Self.isAllowed(from: from, to: to),
              lock.withLock({
                  guard redirectCount < 3 else { return false }
                  redirectCount += 1
                  return true
              })
        else {
            completionHandler(nil)
            return
        }
        var sanitized = request
        sanitized.httpShouldHandleCookies = false
        sanitized.setValue(nil, forHTTPHeaderField: "Cookie")
        if from.host?.lowercased() != to.host?.lowercased() {
            for header in ["Authorization", "X-Subscription-Token", "x-api-key"] {
                sanitized.setValue(nil, forHTTPHeaderField: header)
            }
        }
        completionHandler(sanitized)
    }

    private static func isAllowed(from: URL, to: URL) -> Bool {
        guard let fromHost = from.host?.lowercased(),
              let toHost = to.host?.lowercased()
        else { return false }
        if fromHost == toHost { return true }
        let bingHosts: Set<String> = ["www.bing.com", "cn.bing.com"]
        return bingHosts.contains(fromHost) && bingHosts.contains(toHost)
    }
}

nonisolated struct FamiliarDuckDuckGoSearchProvider: FamiliarSearchProvider {
    let id = "duckduckgo"
    let transport: any FamiliarSearchHTTPTransport

    func search(request: FamiliarSearchRequest, apiKey: String?) async throws -> FamiliarSearchResponse {
        do {
            var components = URLComponents(string: "https://lite.duckduckgo.com/lite/")!
            components.queryItems = [.init(name: "q", value: request.query)]
            var liteRequest = URLRequest(url: components.url!)
            liteRequest.setValue("text/html", forHTTPHeaderField: "Accept")
            liteRequest.setValue("zh-CN,zh;q=0.9,en;q=0.6", forHTTPHeaderField: "Accept-Language")
            let liteResponse = try await transport.send(liteRequest, responseLimit: 512_000)
            try FamiliarSearchAdapterSupport.validate(liteResponse)
            return .init(
                providerID: id,
                results: try FamiliarWebContentService.parseDuckDuckGoLiteHTML(
                    FamiliarSearchAdapterSupport.decodeText(liteResponse),
                    maximumResults: request.maximumResults
                ),
                truncated: false
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // DuckDuckGo exposes two public HTML shapes. A mobile carrier may
            // block or throttle either host independently, so retry the same
            // selected provider through its other shape before surfacing the
            // failure. This is not a provider fallback.
        }
        var htmlRequest = URLRequest(url: URL(string: "https://html.duckduckgo.com/html/")!)
        htmlRequest.httpMethod = "POST"
        htmlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        htmlRequest.setValue("text/html", forHTTPHeaderField: "Accept")
        htmlRequest.httpBody = Data("q=\(Self.formEncode(request.query))".utf8)
        let htmlResponse = try await transport.send(htmlRequest, responseLimit: 512_000)
        try FamiliarSearchAdapterSupport.validate(htmlResponse)
        let html = try FamiliarSearchAdapterSupport.decodeText(htmlResponse)

        return .init(
            providerID: id,
            results: try FamiliarWebContentService.parseDuckDuckGoHTML(
                html,
                maximumResults: request.maximumResults
            ),
            truncated: false
        )
    }

    private static func formEncode(_ value: String) -> String {
        value.utf8.map { byte in
            switch byte {
            case 45, 46, 48...57, 65...90, 95, 97...122, 126:
                String(UnicodeScalar(byte))
            default:
                String(format: "%%%02X", byte)
            }
        }.joined()
    }
}

nonisolated struct FamiliarBingSearchProvider: FamiliarSearchProvider {
    let id = "bing"
    let transport: any FamiliarSearchHTTPTransport

    func search(request: FamiliarSearchRequest, apiKey: String?) async throws -> FamiliarSearchResponse {
        var components = URLComponents(string: "https://www.bing.com/search")!
        components.queryItems = [
            .init(name: "q", value: request.query),
            .init(name: "count", value: String(request.maximumResults)),
            .init(name: "mkt", value: "zh-CN"),
            .init(name: "setlang", value: "zh-hans"),
            .init(name: "safesearch", value: "moderate")
        ]
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("text/html", forHTTPHeaderField: "Accept")
        urlRequest.setValue("zh-CN,zh;q=0.9,en;q=0.6", forHTTPHeaderField: "Accept-Language")
        urlRequest.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let response = try await transport.send(urlRequest, responseLimit: 750_000)
        try FamiliarSearchAdapterSupport.validate(response)
        return .init(
            providerID: id,
            results: try FamiliarWebContentService.parseBingHTML(
                FamiliarSearchAdapterSupport.decodeText(response),
                maximumResults: request.maximumResults
            ),
            truncated: false
        )
    }
}

nonisolated struct FamiliarBraveSearchProvider: FamiliarSearchProvider {
    let id = "brave"
    let transport: any FamiliarSearchHTTPTransport

    func search(request: FamiliarSearchRequest, apiKey: String?) async throws -> FamiliarSearchResponse {
        guard let apiKey, !apiKey.isEmpty else { throw FamiliarWebError.missingSearchAPIKey(id) }
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [
            .init(name: "q", value: request.query),
            .init(name: "count", value: String(request.maximumResults)),
            .init(name: "safesearch", value: "moderate"),
            .init(name: "text_decorations", value: "false")
        ]
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        let response = try await transport.send(urlRequest, responseLimit: 1_000_000)
        try FamiliarSearchAdapterSupport.validate(response)
        let fixture = try FamiliarSearchAdapterSupport.decode(BraveResponse.self, from: response.body)
        let results = (fixture.web?.results ?? []).prefix(request.maximumResults).enumerated().compactMap {
            FamiliarSearchAdapterSupport.result(
                position: $0.offset + 1,
                title: $0.element.title,
                url: $0.element.url,
                snippet: $0.element.description
            )
        }
        return .init(providerID: id, results: results, truncated: false)
    }

    private struct BraveResponse: Decodable {
        let web: Web?
        struct Web: Decodable { let results: [Result] }
        struct Result: Decodable { let title: String; let url: String; let description: String? }
    }
}

nonisolated struct FamiliarTavilySearchProvider: FamiliarSearchProvider {
    let id = "tavily"
    let transport: any FamiliarSearchHTTPTransport

    func search(request: FamiliarSearchRequest, apiKey: String?) async throws -> FamiliarSearchResponse {
        guard let apiKey, !apiKey.isEmpty else { throw FamiliarWebError.missingSearchAPIKey(id) }
        var urlRequest = URLRequest(url: URL(string: "https://api.tavily.com/search")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": request.query,
            "max_results": request.maximumResults,
            "search_depth": "basic",
            "include_answer": false,
            "include_raw_content": false,
            "include_images": false
        ], options: [.sortedKeys])
        let response = try await transport.send(urlRequest, responseLimit: 1_000_000)
        try FamiliarSearchAdapterSupport.validate(response)
        let fixture = try FamiliarSearchAdapterSupport.decode(TavilyResponse.self, from: response.body)
        let results = fixture.results.prefix(request.maximumResults).enumerated().compactMap {
            FamiliarSearchAdapterSupport.result(
                position: $0.offset + 1,
                title: $0.element.title,
                url: $0.element.url,
                snippet: $0.element.content
            )
        }
        return .init(providerID: id, results: results, truncated: false)
    }

    private struct TavilyResponse: Decodable {
        let results: [Result]
        struct Result: Decodable { let title: String; let url: String; let content: String? }
    }
}

nonisolated struct FamiliarExaSearchProvider: FamiliarSearchProvider {
    let id = "exa"
    let transport: any FamiliarSearchHTTPTransport

    func search(request: FamiliarSearchRequest, apiKey: String?) async throws -> FamiliarSearchResponse {
        guard let apiKey, !apiKey.isEmpty else { throw FamiliarWebError.missingSearchAPIKey(id) }
        var urlRequest = URLRequest(url: URL(string: "https://api.exa.ai/search")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": request.query,
            "numResults": request.maximumResults,
            "type": "fast",
            "contents": [
                "highlights": ["maxCharacters": 600]
            ]
        ], options: [.sortedKeys])
        let response = try await transport.send(urlRequest, responseLimit: 1_000_000)
        try FamiliarSearchAdapterSupport.validate(response)
        let fixture = try FamiliarSearchAdapterSupport.decode(ExaResponse.self, from: response.body)
        let results = fixture.results.prefix(request.maximumResults).enumerated().compactMap {
            FamiliarSearchAdapterSupport.result(
                position: $0.offset + 1,
                title: $0.element.title ?? $0.element.url,
                url: $0.element.url,
                snippet: $0.element.highlights?.joined(separator: " … ")
            )
        }
        return .init(providerID: id, results: results, truncated: false)
    }

    private struct ExaResponse: Decodable {
        let results: [Result]
        struct Result: Decodable { let title: String?; let url: String; let highlights: [String]? }
    }
}

private nonisolated enum FamiliarSearchAdapterSupport {
    static func validate(_ response: FamiliarSearchHTTPResponse) throws {
        if response.statusCode == 429 { throw FamiliarWebError.rateLimited }
        guard (200..<300).contains(response.statusCode) else {
            throw FamiliarWebError.httpError(response.statusCode)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw FamiliarWebError.malformedResponse
        }
    }

    static func decodeText(_ response: FamiliarSearchHTTPResponse) throws -> String {
        let contentType = response.headers["content-type"]?.lowercased() ?? ""
        let text: String?
        if contentType.contains("charset=iso-8859-1") || contentType.contains("charset=windows-1252") {
            text = String(data: response.body, encoding: .windowsCP1252)
                ?? String(data: response.body, encoding: .isoLatin1)
        } else {
            text = String(data: response.body, encoding: .utf8)
                ?? String(data: response.body, encoding: .windowsCP1252)
        }
        guard let text else { throw FamiliarWebError.malformedResponse }
        return text
    }

    static func result(position: Int, title: String, url: String, snippet: String?) -> FamiliarWebSearchResult? {
        guard let normalizedURL = try? FamiliarWebURLPolicy.normalize(url) else { return nil }
        let normalizedTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !normalizedTitle.isEmpty else { return nil }
        let normalizedSnippet = snippet.map {
            String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        }.flatMap { $0.isEmpty ? nil : $0 }
        return .init(
            sourceID: FamiliarSourceIdentifier.make(for: normalizedURL),
            position: position,
            title: normalizedTitle,
            url: normalizedURL.absoluteString,
            displayURL: normalizedURL.host ?? normalizedURL.absoluteString,
            snippet: normalizedSnippet
        )
    }
}
