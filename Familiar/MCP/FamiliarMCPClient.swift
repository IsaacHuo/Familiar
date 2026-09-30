import Foundation

/// HTTP configuration follows OpenMinis MCPStore (4ef2900). Secrets are kept out
/// of SwiftData, snapshots and exported configuration.
nonisolated struct FamiliarMCPConfiguration: Sendable, Identifiable {
    let id: UUID
    let name: String
    let endpoint: URL
    let token: String?
}

nonisolated enum FamiliarMCPError: LocalizedError, Sendable {
    case invalidResponse
    case server(String)
    case unsupportedSchema(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: String(localized: "mcp.error.response")
        case .server(let message): message
        case .unsupportedSchema(let name): String(format: String(localized: "mcp.error.schema"), name)
        }
    }
}

actor FamiliarMCPClient {
    let configuration: FamiliarMCPConfiguration
    private var sessionID: String?
    private var protocolVersion = "2025-03-26"
    private var initialized = false
    init(configuration: FamiliarMCPConfiguration) { self.configuration = configuration }

    func tools() async throws -> [FamiliarMCPToolDefinition] {
        if !initialized {
            let params = try JSONSerialization.data(withJSONObject: [
                "protocolVersion": protocolVersion, "capabilities": [:],
                "clientInfo": ["name": "Familiar", "version": "1.0"]
            ])
            let data = try await rpc("initialize", params: params)
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let version = object["protocolVersion"] as? String { protocolVersion = version }
            _ = try await rpc("notifications/initialized", notification: true)
            initialized = true
        }
        var result: [FamiliarMCPToolDefinition] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            let params = try cursor.map { try JSONSerialization.data(withJSONObject: ["cursor": $0]) }
            let data = try await rpc("tools/list", params: params)
            let page = try JSONDecoder().decode(ToolPage.self, from: data)
            result += page.tools
            cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw FamiliarMCPError.invalidResponse }
            guard result.count <= 512 else { throw FamiliarMCPError.invalidResponse }
        } while cursor != nil
        return result
    }

    func call(name: String, arguments: Data) async throws -> Data {
        let args = try JSONSerialization.jsonObject(with: arguments)
        let params = try JSONSerialization.data(withJSONObject: ["name": name, "arguments": args])
        return try await rpc("tools/call", params: params)
    }

    private func rpc(_ method: String, params: Data? = nil, notification: Bool = false) async throws -> Data {
        let id = UUID().uuidString
        var envelope: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if !notification { envelope["id"] = id }
        if let params { envelope["params"] = try JSONSerialization.jsonObject(with: params) }
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: envelope)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if let token = configuration.token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await FamiliarProviderHTTP.session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw FamiliarMCPError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw FamiliarMCPError.server(try await FamiliarProviderHTTP.readError(bytes))
        }
        if let value = http.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = value }
        if notification { return Data("{}".utf8) }
        if http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true {
            var count = 0
            var payload: [String] = []
            for try await line in bytes.lines {
                try Task.checkCancellation()
                count += line.utf8.count
                guard count <= 8_000_000 else { throw FamiliarMCPError.invalidResponse }
                if line.hasPrefix("data:") { payload.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
                if line.isEmpty, !payload.isEmpty {
                    let data = Data(payload.joined(separator: "\n").utf8)
                    payload = []
                    if let result = try responseResult(data, id: id) { return result }
                }
            }
            if !payload.isEmpty, let result = try responseResult(Data(payload.joined(separator: "\n").utf8), id: id) { return result }
        } else {
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 8_000_000 else { throw FamiliarMCPError.invalidResponse }
                data.append(byte)
            }
            if let result = try responseResult(data, id: id) { return result }
        }
        throw FamiliarMCPError.invalidResponse
    }

    private func responseResult(_ data: Data, id: String) throws -> Data? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FamiliarMCPError.invalidResponse }
        guard object["id"] as? String == id else { return nil }
        if let error = object["error"] as? [String: Any] { throw FamiliarMCPError.server(FamiliarProviderHTTP.sanitizedMessage(error["message"] as? String ?? "MCP error")) }
        guard let result = object["result"] else { throw FamiliarMCPError.invalidResponse }
        return try JSONSerialization.data(withJSONObject: result)
    }
    private struct ToolPage: Decodable { let tools: [FamiliarMCPToolDefinition]; let nextCursor: String? }
}

nonisolated struct FamiliarMCPToolDefinition: Decodable, Sendable {
    let name: String
    let description: String?
    let inputSchema: FamiliarJSONSchema
}

nonisolated enum FamiliarMCPValue: Codable, Sendable {
    case object([String: FamiliarMCPValue]), array([FamiliarMCPValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: Self].self) { self = .object(v) }
        else { self = .array(try c.decode([Self].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

/// Remote annotations cannot grant authorization. Every call is an explicit,
/// one-time proposal bound to the selected server, arguments and active run.
nonisolated struct FamiliarMCPTool: FamiliarTool {
    typealias Input = FamiliarMCPValue
    let manifest: FamiliarToolManifest
    let definition: FamiliarMCPToolDefinition
    let configuration: FamiliarMCPConfiguration
    let client: FamiliarMCPClient

    init(definition: FamiliarMCPToolDefinition, configuration: FamiliarMCPConfiguration, client: FamiliarMCPClient) {
        self.definition = definition; self.configuration = configuration; self.client = client
        let suffix = String(FamiliarHash.sha256(Data(definition.name.utf8)).prefix(12))
        manifest = FamiliarToolManifest(
            name: "mcp_" + configuration.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased() + "_" + suffix,
            title: configuration.name + " · " + definition.name,
            description: definition.description ?? definition.name,
            parameters: definition.inputSchema,
            effect: .destructiveWrite, risk: .high, source: .mcp,
            networkDomains: [configuration.endpoint.host ?? ""], supportsIdempotency: false
        )
    }
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let arguments = try JSONEncoder().encode(input)
        return .action(.init(
            title: manifest.title,
            fields: [.init(id: "server", label: String(localized: "mcp.server"), type: .text, value: configuration.endpoint.absoluteString), .init(id: "arguments", label: String(localized: "mcp.arguments"), type: .text, value: String(decoding: arguments, as: UTF8.self))],
            target: configuration.endpoint.absoluteString, targetKey: configuration.id.uuidString + ":" + definition.name,
            effect: .destructiveWrite, risk: .high,
            consequence: String(localized: "mcp.consequence"), undoPolicy: .unavailable,
            idempotencyKey: context.idempotencyKey, allowedAuthorizationDurations: [.once],
            commit: {
                let data = try await client.call(name: definition.name, arguments: arguments)
                let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                if raw["isError"] as? Bool == true { throw FamiliarMCPError.server(String(localized: "mcp.error.tool")) }
                let output = try JSONDecoder().decode(FamiliarMCPValue.self, from: data)
                let content = raw["content"] as? [[String: Any]] ?? []
                let summary = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
                let presentation = FamiliarToolPresentationPayload.scalar(.init(summary: String(summary.prefix(240)), value: String(summary.prefix(16_000))))
                let envelope = try FamiliarToolResultEnvelope(model: output, presentation: presentation)
                return FamiliarCommittedAction(result: FamiliarToolExecutionResult(envelope: envelope))
            }
        ))
    }
}
