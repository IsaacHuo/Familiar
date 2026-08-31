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

    func get(
        _ url: URL,
        bodyLimit: Int = 2_000_000,
        redirectLimit: Int = 5,
        timeout: Duration = .seconds(30)
    ) async throws -> FamiliarRestrictedHTTPResponse {
        try await request(
            url: url,
            method: "GET",
            body: nil,
            bodyLimit: bodyLimit,
            redirectLimit: redirectLimit,
            timeout: timeout
        )
    }

    func postForm(
        _ url: URL,
        fields: [String: String],
        bodyLimit: Int = 512_000,
        redirectLimit: Int = 3,
        timeout: Duration = .seconds(25)
    ) async throws -> FamiliarRestrictedHTTPResponse {
        let body = fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return try await request(
            url: url,
            method: "POST",
            body: Data(body.utf8),
            bodyLimit: bodyLimit,
            redirectLimit: redirectLimit,
            timeout: timeout
        )
    }

    private func request(
        url: URL,
        method: String,
        body: Data?,
        bodyLimit: Int,
        redirectLimit: Int,
        timeout: Duration
    ) async throws -> FamiliarRestrictedHTTPResponse {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var currentURL = try FamiliarWebURLPolicy.normalize(url.absoluteString)
        var currentMethod = method
        var currentBody = body
        var visited: Set<URL> = []

        for redirectCount in 0...redirectLimit {
            try Task.checkCancellation()
            try Self.checkDeadline(deadline, clock: clock)
            guard visited.insert(currentURL).inserted else { throw FamiliarWebError.redirectLoop }
            guard let host = currentURL.host else { throw FamiliarWebError.invalidURL }
            let resolver = resolver
            let addresses = try await runUntilDeadline(deadline, clock: clock) {
                try await resolver.resolve(host: host)
            }
            let response = try await performPinnedRequest(
                url: currentURL,
                host: host,
                addresses: addresses,
                method: currentMethod,
                body: currentBody,
                bodyLimit: bodyLimit,
                deadline: deadline,
                clock: clock
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
        bodyLimit: Int,
        deadline: ContinuousClock.Instant,
        clock: ContinuousClock
    ) async throws -> FamiliarHTTPParsedResponse {
        try Self.checkDeadline(deadline, clock: clock)
        guard !addresses.isEmpty else { throw FamiliarWebError.dnsFailed }
        let request = Self.makeRequest(url: url, host: host, method: method, body: body)
        let raceStart = clock.now

        return try await withThrowingTaskGroup(of: FamiliarHTTPAttempt.self) { group in
            for (index, address) in addresses.enumerated() {
                group.addTask {
                    if index > 0 {
                        let launch = raceStart.advanced(by: .milliseconds(250 * index))
                        try await clock.sleep(until: launch)
                    }
                    try Task.checkCancellation()
                    guard clock.now < deadline else { return .deadline }

                    let operation = FamiliarPinnedConnection(
                        address: address,
                        serverName: host,
                        request: request,
                        maximumBytes: bodyLimit + 65_536
                    )
                    do {
                        let response = try await withTaskCancellationHandler {
                            try await operation.execute(bodyLimit: bodyLimit)
                        } onCancel: {
                            operation.cancel()
                        }
                        return .response(response)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        return .failure(Self.normalizedTransportError(error))
                    }
                }
            }
            group.addTask {
                try await clock.sleep(until: deadline)
                return .deadline
            }

            var failures = 0
            var lastError: Error = FamiliarWebError.dnsFailed
            while let attempt = try await group.next() {
                switch attempt {
                case .response(let response):
                    group.cancelAll()
                    return response
                case .failure(let error):
                    failures += 1
                    lastError = error
                    if failures == addresses.count {
                        group.cancelAll()
                        throw lastError
                    }
                case .deadline:
                    group.cancelAll()
                    throw FamiliarWebError.timeout
                }
            }
            throw lastError
        }
    }

    private static func checkDeadline(_ deadline: ContinuousClock.Instant, clock: ContinuousClock) throws {
        guard clock.now < deadline else { throw FamiliarWebError.timeout }
    }

    private static func normalizedTransportError(_ error: Error) -> Error {
        if let webError = error as? FamiliarWebError { return webError }
        if let networkError = error as? NWError,
           case .posix(let code) = networkError,
           code == .ETIMEDOUT {
            return FamiliarWebError.timeout
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ETIMEDOUT) {
            return FamiliarWebError.timeout
        }
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
            return FamiliarWebError.timeout
        }
        return error
    }

    private static func makeRequest(url: URL, host: String, method: String, body: Data?) -> Data {
        var target = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty { target += "?" + query }
        var lines = [
            "\(method) \(target) HTTP/1.1",
            "Host: \(host)",
            "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1 Familiar/1",
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

private nonisolated enum FamiliarHTTPAttempt: Sendable {
    case response(FamiliarHTTPParsedResponse)
    case failure(any Error)
    case deadline
}

fileprivate nonisolated struct FamiliarHTTPParsedResponse: Sendable {
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
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !finished else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
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
                    do {
                        if try FamiliarHTTPParser.isComplete(self.received, bodyLimit: self.maximumBytes - 65_536) {
                            self.finish(.success(self.received))
                            return
                        }
                    } catch {
                        self.finish(.failure(error))
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

nonisolated enum FamiliarHTTPParser {
    private struct Head {
        let statusCode: Int
        let headers: [String: String]
        let bodyStart: Data.Index
    }

    static func isComplete(_ data: Data, bodyLimit: Int) throws -> Bool {
        guard let head = try parseHead(data) else { return false }
        try validateContentEncoding(head.headers)
        let rawBody = data[head.bodyStart...]

        if head.statusCode == 204 || head.statusCode == 304 {
            return true
        }
        if head.headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            return try isCompleteChunked(rawBody, limit: bodyLimit)
        }
        if let length = try contentLength(head.headers) {
            guard length <= bodyLimit else { throw FamiliarWebError.responseTooLarge }
            return rawBody.count >= length
        }
        return false
    }

    fileprivate static func parse(_ data: Data, bodyLimit: Int) throws -> FamiliarHTTPParsedResponse {
        guard let head = try parseHead(data) else { throw FamiliarWebError.malformedResponse }
        try validateContentEncoding(head.headers)
        let rawBody = Data(data[head.bodyStart...])
        let body: Data
        if head.statusCode == 204 || head.statusCode == 304 {
            body = Data()
        } else if head.headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            guard try isCompleteChunked(rawBody, limit: bodyLimit) else { throw FamiliarWebError.malformedResponse }
            body = try decodeChunked(rawBody, limit: bodyLimit)
        } else if let length = try contentLength(head.headers) {
            guard length <= bodyLimit else { throw FamiliarWebError.responseTooLarge }
            guard rawBody.count >= length else { throw FamiliarWebError.malformedResponse }
            body = Data(rawBody.prefix(length))
        } else {
            guard rawBody.count <= bodyLimit else { throw FamiliarWebError.responseTooLarge }
            body = rawBody
        }
        return .init(statusCode: head.statusCode, headers: head.headers, body: body)
    }

    private static func parseHead(_ data: Data) throws -> Head? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter) else {
            if data.count > 65_540 { throw FamiliarWebError.malformedResponse }
            return nil
        }
        guard headerRange.lowerBound <= 65_536 else { throw FamiliarWebError.malformedResponse }
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
        return Head(statusCode: status, headers: headers, bodyStart: headerRange.upperBound)
    }

    private static func validateContentEncoding(_ headers: [String: String]) throws {
        if let encoding = headers["content-encoding"], encoding.lowercased() != "identity" {
            throw FamiliarWebError.unsupportedContentEncoding
        }
    }

    private static func contentLength(_ headers: [String: String]) throws -> Int? {
        guard let value = headers["content-length"] else { return nil }
        let values = value.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let first = values.first.flatMap(Int.init), first >= 0,
              values.allSatisfy({ Int($0) == first }) else {
            throw FamiliarWebError.malformedResponse
        }
        return first
    }

    private static func isCompleteChunked(_ data: some DataProtocol, limit: Int) throws -> Bool {
        let bytes = Data(data)
        var cursor = bytes.startIndex
        var decodedCount = 0
        while true {
            guard let lineEnd = bytes[cursor...].range(of: Data("\r\n".utf8)) else { return false }
            let sizeData = bytes[cursor..<lineEnd.lowerBound]
            guard let sizeText = String(data: sizeData, encoding: .ascii)?.split(separator: ";").first,
                  let size = Int(sizeText, radix: 16), size >= 0 else {
                throw FamiliarWebError.malformedResponse
            }
            cursor = lineEnd.upperBound
            guard size <= limit - decodedCount else { throw FamiliarWebError.responseTooLarge }
            if size == 0 {
                if bytes.distance(from: cursor, to: bytes.endIndex) < 2 { return false }
                if bytes[cursor..<bytes.index(cursor, offsetBy: 2)] == Data("\r\n".utf8) { return true }
                return bytes[cursor...].range(of: Data("\r\n\r\n".utf8)) != nil
            }
            guard bytes.distance(from: cursor, to: bytes.endIndex) >= size + 2 else { return false }
            let end = bytes.index(cursor, offsetBy: size)
            guard bytes[end..<bytes.index(end, offsetBy: 2)] == Data("\r\n".utf8) else {
                throw FamiliarWebError.malformedResponse
            }
            decodedCount += size
            cursor = bytes.index(end, offsetBy: 2)
        }
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

private nonisolated final class FamiliarDeadlineRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func add(_ task: Task<Void, Never>) {
        lock.lock()
        if result == nil {
            tasks.append(task)
            lock.unlock()
        } else {
            lock.unlock()
            task.cancel()
        }
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        let tasks = tasks
        self.tasks.removeAll()
        lock.unlock()

        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}

private nonisolated func runUntilDeadline<Value: Sendable>(
    _ deadline: ContinuousClock.Instant,
    clock: ContinuousClock,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let race = FamiliarDeadlineRace<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.install(continuation)

            let operationTask = Task {
                do {
                    race.resolve(.success(try await operation()))
                } catch {
                    race.resolve(.failure(error))
                }
            }
            race.add(operationTask)

            let deadlineTask = Task {
                do {
                    try await clock.sleep(until: deadline)
                    race.resolve(.failure(FamiliarWebError.timeout))
                } catch {
                    // The operation or parent cancellation won the race.
                }
            }
            race.add(deadlineTask)
        }
    } onCancel: {
        race.resolve(.failure(CancellationError()))
    }
}
