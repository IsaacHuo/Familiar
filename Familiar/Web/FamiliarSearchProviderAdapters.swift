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
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest, responseLimit: Int) async throws -> FamiliarSearchHTTPResponse {
        guard let url = request.url,
              url.scheme == "https",
              let host = url.host?.lowercased(),
              Self.allowedHosts.contains(host)
        else { throw FamiliarWebError.invalidURL }

        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 15
        let delegate = FamiliarSearchNoRedirectDelegate()
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        guard let response = response as? HTTPURLResponse else {
            throw FamiliarWebError.malformedResponse
        }

        var body = Data()
        body.reserveCapacity(min(max(Int(response.expectedContentLength), 0), responseLimit))
        for try await byte in bytes {
            guard body.count < responseLimit else { throw FamiliarWebError.responseTooLarge }
            body.append(byte)
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            guard let key = field.key as? String, let value = field.value as? String else { return }
            result[key.lowercased()] = value
        }
        return .init(statusCode: response.statusCode, headers: headers, body: body)
    }
}

private nonisolated final class FamiliarSearchNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

nonisolated struct FamiliarDuckDuckGoSearchProvider: FamiliarSearchProvider {
    let id = "duckduckgo"
    let transport: any FamiliarSearchHTTPTransport

    func search(request: FamiliarSearchRequest, apiKey: String?) async throws -> FamiliarSearchResponse {
        var htmlRequest = URLRequest(url: URL(string: "https://html.duckduckgo.com/html/")!)
        htmlRequest.httpMethod = "POST"
        htmlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        htmlRequest.setValue("text/html", forHTTPHeaderField: "Accept")
        htmlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        htmlRequest.httpBody = Data("q=\(Self.formEncode(request.query))".utf8)
        let htmlResponse = try await transport.send(htmlRequest, responseLimit: 512_000)
        try FamiliarSearchAdapterSupport.validate(htmlResponse)
        let html = try FamiliarSearchAdapterSupport.decodeText(htmlResponse)

        do {
            return .init(
                providerID: id,
                results: try FamiliarWebContentService.parseDuckDuckGoHTML(
                    html,
                    maximumResults: request.maximumResults
                ),
                truncated: false
            )
        } catch FamiliarWebError.searchUnavailable {
            var components = URLComponents(string: "https://lite.duckduckgo.com/lite/")!
            components.queryItems = [.init(name: "q", value: request.query)]
            var liteRequest = URLRequest(url: components.url!)
            liteRequest.setValue("text/html", forHTTPHeaderField: "Accept")
            liteRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
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
        }
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
