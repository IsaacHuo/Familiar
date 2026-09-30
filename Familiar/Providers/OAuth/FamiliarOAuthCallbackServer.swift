// Adapted from OpenMinis OAuthCallbackServer, 4ef2900 (GPL-3.0).
// Use nonblocking Network callbacks and bind only to loopback.
import Foundation
import Network

nonisolated struct FamiliarOAuthCallback: Sendable { let code: String; let state: String? }
nonisolated final class FamiliarOAuthCallbackServer: @unchecked Sendable {
    private let port: UInt16
    private let path: String
    private let queue = DispatchQueue(label: "familiar.oauth.callback")
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var result: Result<FamiliarOAuthCallback, Error>?
    private var waiter: CheckedContinuation<FamiliarOAuthCallback, Error>?
    private var startup: CheckedContinuation<Void, Error>?
    init(port: UInt16, path: String) { self.port = port; self.path = path }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: self.port)!)
                    parameters.allowLocalEndpointReuse = true
                    let listener = try NWListener(using: parameters)
                    self.startup = continuation; self.listener = listener
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready: self.startup?.resume(); self.startup = nil
                        case .failed(let error): self.startup?.resume(throwing: error); self.startup = nil; self.complete(.failure(error))
                        default: break
                        }
                    }
                    listener.newConnectionHandler = { connection in
                        guard self.connections.count < 8 else { connection.cancel(); return }
                        self.connections.append(connection)
                        connection.start(queue: self.queue)
                        self.read(connection, data: Data())
                    }
                    listener.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + 300) { [weak self] in
                        guard let self else { return }
                        self.startup?.resume(throwing: FamiliarOAuthError.expired); self.startup = nil
                        self.complete(.failure(FamiliarOAuthError.expired))
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func wait() async throws -> FamiliarOAuthCallback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if let result = self.result { continuation.resume(with: result) }
                    else { self.waiter = continuation }
                }
            }
        } onCancel: { self.stop() }
    }
    func stop() {
        queue.async {
            self.startup?.resume(throwing: CancellationError()); self.startup = nil
            self.complete(.failure(CancellationError()))
        }
    }
    private func complete(_ value: Result<FamiliarOAuthCallback, Error>) {
        guard result == nil else { return }
        result = value; waiter?.resume(with: value); waiter = nil
        listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }; connections = []
    }
    private func read(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { chunk, _, complete, error in
            var bytes = data
            if let chunk { bytes.append(chunk) }
            guard bytes.count <= 16_384, error == nil else { connection.cancel(); return }
            guard let text = String(data: bytes, encoding: .utf8), text.contains("\r\n\r\n") else {
                if complete { connection.cancel() } else { self.read(connection, data: bytes) }
                return
            }
            let firstLine = text.components(separatedBy: "\r\n").first ?? ""
            let pieces = firstLine.split(separator: " ")
            guard pieces.count >= 2, pieces[0] == "GET",
                  let url = URLComponents(string: "http://localhost" + String(pieces[1])), url.path == self.path else {
                self.reply(connection, status: "404 Not Found", body: "", completion: nil); return
            }
            let items = url.queryItems ?? []
            guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                self.reply(connection, status: "400 Bad Request", body: "Authorization failed.") { self.complete(.failure(FamiliarOAuthError.expired)) }
                return
            }
            let callback = FamiliarOAuthCallback(code: code, state: items.first { $0.name == "state" }?.value)
            self.reply(connection, status: "200 OK", body: String(localized: "oauth.return")) { self.complete(.success(callback)) }
        }
    }
    private func reply(_ connection: NWConnection, status: String, body: String, completion: (() -> Void)?) {
        let message = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(message.utf8), completion: .contentProcessed { _ in
            connection.cancel(); self.connections.removeAll { $0 === connection }; completion?()
        })
    }
}
