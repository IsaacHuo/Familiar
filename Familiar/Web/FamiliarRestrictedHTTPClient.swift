import Foundation
import Network
import Security

nonisolated struct FamiliarRestrictedHTTPResponse: Sendable {
    let finalURL: URL
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

nonisolated struct FamiliarRestrictedHTTPClient: Sendable {
    private let resolver = FamiliarWebDNSResolver()

    func get(_ url: URL, bodyLimit: Int = 2_000_000, redirectLimit: Int = 5) async throws -> FamiliarRestrictedHTTPResponse {
        try await request(url: url, method: "GET", body: nil, bodyLimit: bodyLimit, redirectLimit: redirectLimit)
    }

    func postForm(_ url: URL, fields: [String: String], bodyLimit: Int = 512_000, redirectLimit: Int = 3) async throws -> FamiliarRestrictedHTTPResponse {
        let body = fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return try await request(url: url, method: "POST", body: Data(body.utf8), bodyLimit: bodyLimit, redirectLimit: redirectLimit)
    }

    private func request(
        url: URL,
        method: String,
        body: Data?,
        bodyLimit: Int,
        redirectLimit: Int
    ) async throws -> FamiliarRestrictedHTTPResponse {
        var currentURL = try FamiliarWebURLPolicy.normalize(url.absoluteString)
        var currentMethod = method
        var currentBody = body
        var visited: Set<URL> = []

        for redirectCount in 0...redirectLimit {
            try Task.checkCancellation()
            guard visited.insert(currentURL).inserted else { throw FamiliarWebError.redirectLoop }
            guard let host = currentURL.host else { throw FamiliarWebError.invalidURL }
            let addresses = try await resolver.resolve(host: host)
            let response = try await performPinnedRequest(
                url: currentURL,
                host: host,
                addresses: addresses,
                method: currentMethod,
                body: currentBody,
                bodyLimit: bodyLimit
            )
            guard [301, 302, 303, 307, 308].contains(response.statusCode) else {
                return .init(finalURL: currentURL, statusCode: response.statusCode, headers: response.headers, body: response.body)
            }
            guard redirectCount < redirectLimit else { throw FamiliarWebError.tooManyRedirects }
            guard let location = response.headers["location"] else { throw FamiliarWebError.redirectBlocked }
            currentURL = try FamiliarWebURLPolicy.normalize(location, relativeTo: currentURL)
            if response.statusCode == 303 || ([301, 302].contains(response.statusCode) && currentMethod == "POST") {
                currentMethod = "GET"
                currentBody = nil
            }
        }
        throw FamiliarWebError.tooManyRedirects
    }

    private func performPinnedRequest(
        url: URL,
        host: String,
        addresses: [String],
        method: String,
        body: Data?,
        bodyLimit: Int
    ) async throws -> FamiliarHTTPParsedResponse {
        var lastError: Error = FamiliarWebError.dnsFailed
        for address in addresses {
            do {
                return try await withThrowingTaskGroup(of: FamiliarHTTPParsedResponse.self) { group in
                    group.addTask {
                        let operation = FamiliarPinnedConnection(
                            address: address,
                            serverName: host,
                            request: Self.makeRequest(url: url, host: host, method: method, body: body),
                            maximumBytes: bodyLimit + 65_536
                        )
                        return try await withTaskCancellationHandler {
                            try await operation.execute(bodyLimit: bodyLimit)
                        } onCancel: {
                            operation.cancel()
                        }
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(30))
                        throw FamiliarWebError.timeout
                    }
                    guard let result = try await group.next() else { throw FamiliarWebError.timeout }
                    group.cancelAll()
                    return result
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func makeRequest(url: URL, host: String, method: String, body: Data?) -> Data {
        var target = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty { target += "?" + query }
        var lines = [
            "\(method) \(target) HTTP/1.1",
            "Host: \(host)",
            "User-Agent: Familiar/1 iOS",
            "Accept: text/html,application/xhtml+xml,text/plain;q=0.9",
            "Accept-Encoding: identity",
            "Connection: close"
        ]
        if let body {
            lines.append("Content-Type: application/x-www-form-urlencoded; charset=utf-8")
            lines.append("Content-Length: \(body.count)")
        }
        var request = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        if let body { request.append(body) }
        return request
    }
}

private nonisolated struct FamiliarHTTPParsedResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

private nonisolated final class FamiliarPinnedConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let request: Data
    private let maximumBytes: Int
    private let queue = DispatchQueue(label: "com.isaachuo.familiar.web-connection")
    private var continuation: CheckedContinuation<Data, Error>?
    private var received = Data()
    private var finished = false

    init(address: String, serverName: String, request: Data, maximumBytes: Int) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, serverName)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        connection = NWConnection(host: NWEndpoint.Host(address), port: .https, using: parameters)
        self.request = request
        self.maximumBytes = maximumBytes
    }

    func execute(bodyLimit: Int) async throws -> FamiliarHTTPParsedResponse {
        let data = try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                self.continuation = continuation
                connection.stateUpdateHandler = { [weak self] state in
                    self?.handle(state)
                }
                connection.start(queue: queue)
            }
        }
        return try FamiliarHTTPParser.parse(data, bodyLimit: bodyLimit)
    }

    func cancel() {
        queue.async { [self] in
            finish(.failure(CancellationError()))
        }
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connection.send(content: request, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                self.queue.async {
                    if let error { self.finish(.failure(error)) } else { self.receive() }
                }
            })
        case .failed(let error): finish(.failure(error))
        case .cancelled:
            if !finished { finish(.failure(CancellationError())) }
        default: break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                if let content {
                    self.received.append(content)
                    if self.received.count > self.maximumBytes {
                        self.finish(.failure(FamiliarWebError.responseTooLarge))
                        return
                    }
                }
                if let error {
                    self.finish(.failure(error))
                } else if isComplete || content == nil {
                    self.finish(.success(self.received))
                } else {
                    self.receive()
                }
            }
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard !finished else { return }
        finished = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}

private nonisolated enum FamiliarHTTPParser {
    static func parse(_ data: Data, bodyLimit: Int) throws -> FamiliarHTTPParsedResponse {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter), headerRange.lowerBound <= 65_536 else {
            throw FamiliarWebError.malformedResponse
        }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .isoLatin1) else {
            throw FamiliarWebError.malformedResponse
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { throw FamiliarWebError.malformedResponse }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, statusParts[0].hasPrefix("HTTP/1."), let status = Int(statusParts[1]) else {
            throw FamiliarWebError.malformedResponse
        }
        var headers: [String: String] = [:]
        guard lines.count <= 101 else { throw FamiliarWebError.malformedResponse }
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { throw FamiliarWebError.malformedResponse }
            let key = line[..<separator].lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if headers[key] != nil { headers[key] = headers[key]! + "," + value } else { headers[key] = value }
        }
        if let encoding = headers["content-encoding"], encoding.lowercased() != "identity" {
            throw FamiliarWebError.unsupportedContentEncoding
        }
        let rawBody = Data(data[headerRange.upperBound...])
        let body: Data
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            body = try decodeChunked(rawBody, limit: bodyLimit)
        } else if let value = headers["content-length"], let length = Int(value) {
            guard length <= bodyLimit, rawBody.count >= length else { throw FamiliarWebError.responseTooLarge }
            body = Data(rawBody.prefix(length))
        } else {
            guard rawBody.count <= bodyLimit else { throw FamiliarWebError.responseTooLarge }
            body = rawBody
        }
        return .init(statusCode: status, headers: headers, body: body)
    }

    private static func decodeChunked(_ data: Data, limit: Int) throws -> Data {
        var cursor = data.startIndex
        var result = Data()
        while cursor < data.endIndex {
            guard let lineEnd = data[cursor...].range(of: Data("\r\n".utf8)) else { throw FamiliarWebError.malformedResponse }
            let sizeData = data[cursor..<lineEnd.lowerBound]
            guard let sizeText = String(data: sizeData, encoding: .ascii)?.split(separator: ";").first,
                  let size = Int(sizeText, radix: 16) else { throw FamiliarWebError.malformedResponse }
            cursor = lineEnd.upperBound
            if size == 0 { return result }
            guard size >= 0, result.count + size <= limit, data.distance(from: cursor, to: data.endIndex) >= size + 2 else {
                throw FamiliarWebError.responseTooLarge
            }
            let end = data.index(cursor, offsetBy: size)
            result.append(data[cursor..<end])
            guard data[end..<data.index(end, offsetBy: 2)] == Data("\r\n".utf8) else {
                throw FamiliarWebError.malformedResponse
            }
            cursor = data.index(end, offsetBy: 2)
        }
        throw FamiliarWebError.malformedResponse
    }
}
