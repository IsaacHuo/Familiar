import Foundation

nonisolated struct AnthropicMessagesClient: FamiliarModelProvider, Sendable {
    let descriptor: FamiliarProviderDescriptor

    var providerID: String { descriptor.id }

    func stream(
        request modelRequest: FamiliarModelRequest,
        apiKey: String
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let endpoint = try FamiliarProviderHTTP.authorizedURL(
                        descriptor: descriptor,
                        path: descriptor.chatPath,
                        apiKey: apiKey
                    )
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    FamiliarProviderHTTP.applyHeaders(to: &request, descriptor: descriptor, apiKey: apiKey)
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(RequestBody(modelRequest))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw FamiliarProviderRequestError.invalidResponse(provider: descriptor.displayName)
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw FamiliarProviderRequestError.server(
                            provider: descriptor.displayName,
                            statusCode: http.statusCode,
                            message: try await FamiliarProviderHTTP.readError(bytes)
                        )
                    }

                    var eventName = ""
                    var emittedContent = false
                    var emittedCompletion = false
                    var observedToolCall = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line.hasPrefix("event:") {
                            eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        guard line.hasPrefix("data:"),
                              let data = line.dropFirst(5)
                                .trimmingCharacters(in: .whitespaces)
                                .data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: data)
                        else { continue }

                        switch eventName {
                        case "content_block_start":
                            if event.contentBlock?.type == "tool_use",
                               let index = event.index,
                               let id = event.contentBlock?.id,
                               let name = event.contentBlock?.name {
                                observedToolCall = true
                                emittedContent = true
                                continuation.yield(.toolCallDelta(
                                    index: index,
                                    id: id,
                                    name: name,
                                    arguments: nil
                                ))
                            }
                        case "content_block_delta":
                            if let text = event.delta?.text, !text.isEmpty {
                                emittedContent = true
                                continuation.yield(.textDelta(text))
                            }
                            if let partialJSON = event.delta?.partialJSON, !partialJSON.isEmpty {
                                emittedContent = true
                                continuation.yield(.toolCallDelta(
                                    index: event.index ?? 0,
                                    id: nil,
                                    name: nil,
                                    arguments: partialJSON
                                ))
                            }
                        case "message_delta":
                            if let reason = event.delta?.stopReason {
                                emittedCompletion = true
                                continuation.yield(.completed(Self.finishReason(reason)))
                            }
                        case "message_stop":
                            if !emittedCompletion {
                                emittedCompletion = true
                                continuation.yield(.completed(observedToolCall ? .toolCalls : .stop))
                            }
                        default:
                            break
                        }
                    }

                    guard emittedContent else {
                        throw FamiliarProviderRequestError.emptyResponse(provider: descriptor.displayName)
                    }
                    if !emittedCompletion {
                        continuation.yield(.completed(observedToolCall ? .toolCalls : .stop))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func finishReason(_ value: String) -> FamiliarModelFinishReason {
        switch value {
        case "end_turn", "stop_sequence": .stop
        case "tool_use": .toolCalls
        case "max_tokens": .length
        default: .unknown
        }
    }
}

private nonisolated extension AnthropicMessagesClient {
    struct RequestBody: Encodable {
        let model: String
        let maxTokens = 4_096
        let system: String?
        let messages: [RequestMessage]
        let stream = true
        let tools: [RequestTool]?

        init(_ request: FamiliarModelRequest) {
            model = request.model
            system = request.messages.first(where: { $0.role == .system })?.networkText
            messages = Self.coalescedMessages(request.messages.filter { $0.role != .system })
            tools = request.tools.isEmpty ? nil : request.tools.map(RequestTool.init)
        }

        private static func coalescedMessages(_ messages: [FamiliarProviderMessage]) -> [RequestMessage] {
            var result: [RequestMessage] = []
            for source in messages {
                let role = source.role == .assistant ? "assistant" : "user"
                var blocks: [ContentBlock] = []
                for part in source.contentParts {
                    switch part {
                    case .text(let text):
                        guard !text.isEmpty else { continue }
                        if source.role == .tool, let toolCallID = source.toolCallID {
                            blocks.append(.toolResult(toolUseID: toolCallID, content: text))
                        } else {
                            blocks.append(.text(text))
                        }
                    case .document(let text, let filename):
                        blocks.append(.text("[Document: \(filename)]\n\(text)"))
                    case .image(let data, let mimeType):
                        blocks.append(.image(mediaType: mimeType, data: data.base64EncodedString()))
                    }
                }
                if source.role == .assistant {
                    blocks += source.toolCalls.map { call in
                        .toolUse(
                            id: call.id,
                            name: call.name,
                            input: FamiliarJSONValue.parse(call.arguments)
                        )
                    }
                }
                guard !blocks.isEmpty else { continue }
                if result.last?.role == role {
                    result[result.count - 1].content += blocks
                } else {
                    result.append(RequestMessage(role: role, content: blocks))
                }
            }
            return result
        }

        enum CodingKeys: String, CodingKey {
            case model, system, messages, stream, tools
            case maxTokens = "max_tokens"
        }
    }

    struct RequestMessage: Encodable {
        let role: String
        var content: [ContentBlock]
    }

    enum ContentBlock: Encodable {
        case text(String)
        case toolUse(id: String, name: String, input: FamiliarJSONValue)
        case toolResult(toolUseID: String, content: String)
        case image(mediaType: String, data: String)

        enum CodingKeys: String, CodingKey {
            case type, text, id, name, input, content, source
            case toolUseID = "tool_use_id"
        }
        enum SourceKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .toolUse(let id, let name, let input):
                try container.encode("tool_use", forKey: .type)
                try container.encode(id, forKey: .id)
                try container.encode(name, forKey: .name)
                try container.encode(input, forKey: .input)
            case .toolResult(let toolUseID, let content):
                try container.encode("tool_result", forKey: .type)
                try container.encode(toolUseID, forKey: .toolUseID)
                try container.encode(content, forKey: .content)
            case .image(let mediaType, let data):
                try container.encode("image", forKey: .type)
                var source = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
                try source.encode("base64", forKey: .type)
                try source.encode(mediaType, forKey: .mediaType)
                try source.encode(data, forKey: .data)
            }
        }
    }

    struct RequestTool: Encodable {
        let name: String
        let description: String
        let inputSchema: FamiliarJSONSchema

        init(_ tool: FamiliarToolManifest) {
            name = tool.name
            description = tool.description
            inputSchema = tool.parameters
        }

        enum CodingKeys: String, CodingKey {
            case name, description
            case inputSchema = "input_schema"
        }
    }

    struct StreamEvent: Decodable {
        let index: Int?
        let contentBlock: ContentBlockStart?
        let delta: Delta?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case contentBlock = "content_block"
        }

        struct ContentBlockStart: Decodable {
            let type: String
            let id: String?
            let name: String?
        }

        struct Delta: Decodable {
            let text: String?
            let partialJSON: String?
            let stopReason: String?

            enum CodingKeys: String, CodingKey {
                case text
                case partialJSON = "partial_json"
                case stopReason = "stop_reason"
            }
        }
    }
}

nonisolated struct GeminiGenerateContentClient: FamiliarModelProvider, Sendable {
    let descriptor: FamiliarProviderDescriptor

    var providerID: String { descriptor.id }

    func stream(
        request modelRequest: FamiliarModelRequest,
        apiKey: String
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let endpoint = try FamiliarProviderHTTP.authorizedURL(
                        descriptor: descriptor,
                        path: descriptor.chatPath,
                        model: modelRequest.model,
                        apiKey: apiKey
                    )
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    FamiliarProviderHTTP.applyHeaders(to: &request, descriptor: descriptor, apiKey: apiKey)
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(RequestBody(modelRequest))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw FamiliarProviderRequestError.invalidResponse(provider: descriptor.displayName)
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw FamiliarProviderRequestError.server(
                            provider: descriptor.displayName,
                            statusCode: http.statusCode,
                            message: try await FamiliarProviderHTTP.readError(bytes)
                        )
                    }

                    var emittedContent = false
                    var emittedCompletion = false
                    var toolIndex = 0
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamResponse.self, from: data)
                        else { continue }

                        for candidate in event.candidates ?? [] {
                            for part in candidate.content?.parts ?? [] {
                                if let text = part.text, !text.isEmpty {
                                    emittedContent = true
                                    continuation.yield(.textDelta(text))
                                }
                                if let call = part.functionCall {
                                    emittedContent = true
                                    let arguments = FamiliarJSONValue.encodedString(call.args ?? .object([:]))
                                    continuation.yield(.toolCallDelta(
                                        index: toolIndex,
                                        id: "gemini-\(toolIndex)",
                                        name: call.name,
                                        arguments: arguments
                                    ))
                                    toolIndex += 1
                                }
                            }
                            if let reason = candidate.finishReason {
                                emittedCompletion = true
                                continuation.yield(.completed(Self.finishReason(reason)))
                            }
                        }
                    }

                    guard emittedContent else {
                        throw FamiliarProviderRequestError.emptyResponse(provider: descriptor.displayName)
                    }
                    if !emittedCompletion {
                        continuation.yield(.completed(toolIndex > 0 ? .toolCalls : .stop))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func finishReason(_ value: String) -> FamiliarModelFinishReason {
        switch value.uppercased() {
        case "STOP": .stop
        case "MAX_TOKENS": .length
        case "MALFORMED_FUNCTION_CALL": .unknown
        default: .unknown
        }
    }
}

private nonisolated extension GeminiGenerateContentClient {
    struct RequestBody: Encodable {
        let systemInstruction: Content?
        let contents: [Content]
        let tools: [ToolContainer]?

        init(_ request: FamiliarModelRequest) {
            if let systemText = request.messages.first(where: { $0.role == .system })?.networkText {
                systemInstruction = Content(role: nil, parts: [.text(systemText)])
            } else {
                systemInstruction = nil
            }
            contents = Self.coalescedContents(request.messages.filter { $0.role != .system })
            tools = request.tools.isEmpty
                ? nil
                : [ToolContainer(functionDeclarations: request.tools.map(FunctionDeclaration.init))]
        }

        private static func coalescedContents(_ messages: [FamiliarProviderMessage]) -> [Content] {
            var result: [Content] = []
            for source in messages {
                let role = source.role == .assistant ? "model" : "user"
                var parts: [RequestPart] = []
                for part in source.contentParts {
                    switch part {
                    case .text(let text):
                        guard !text.isEmpty else { continue }
                        if source.role == .tool {
                            parts.append(.functionResponse(
                                name: source.name ?? "tool",
                                response: FamiliarJSONValue.responseObject(from: text)
                            ))
                        } else {
                            parts.append(.text(text))
                        }
                    case .document(let text, let filename):
                        parts.append(.text("[Document: \(filename)]\n\(text)"))
                    case .image(let data, let mimeType):
                        parts.append(.inlineData(mimeType: mimeType, data: data.base64EncodedString()))
                    }
                }
                if source.role == .assistant {
                    parts += source.toolCalls.map {
                        .functionCall(name: $0.name, args: FamiliarJSONValue.parse($0.arguments))
                    }
                }
                guard !parts.isEmpty else { continue }
                if result.last?.role == role {
                    result[result.count - 1].parts += parts
                } else {
                    result.append(Content(role: role, parts: parts))
                }
            }
            return result
        }

        enum CodingKeys: String, CodingKey {
            case systemInstruction, contents, tools
        }
    }

    struct Content: Encodable {
        let role: String?
        var parts: [RequestPart]
    }

    enum RequestPart: Encodable {
        case text(String)
        case functionCall(name: String, args: FamiliarJSONValue)
        case functionResponse(name: String, response: FamiliarJSONValue)
        case inlineData(mimeType: String, data: String)

        enum CodingKeys: String, CodingKey {
            case text, functionCall, functionResponse, inlineData
        }
        enum FunctionKeys: String, CodingKey { case name, args, response }
        enum InlineDataKeys: String, CodingKey { case mimeType, data }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode(text, forKey: .text)
            case .functionCall(let name, let args):
                var nested = container.nestedContainer(keyedBy: FunctionKeys.self, forKey: .functionCall)
                try nested.encode(name, forKey: .name)
                try nested.encode(args, forKey: .args)
            case .functionResponse(let name, let response):
                var nested = container.nestedContainer(keyedBy: FunctionKeys.self, forKey: .functionResponse)
                try nested.encode(name, forKey: .name)
                try nested.encode(response, forKey: .response)
            case .inlineData(let mimeType, let data):
                var nested = container.nestedContainer(keyedBy: InlineDataKeys.self, forKey: .inlineData)
                try nested.encode(mimeType, forKey: .mimeType)
                try nested.encode(data, forKey: .data)
            }
        }
    }

    struct ToolContainer: Encodable {
        let functionDeclarations: [FunctionDeclaration]
    }

    struct FunctionDeclaration: Encodable {
        let name: String
        let description: String
        let parameters: FamiliarJSONSchema

        init(_ tool: FamiliarToolManifest) {
            name = tool.name
            description = tool.description
            parameters = tool.parameters
        }
    }

    struct StreamResponse: Decodable {
        let candidates: [Candidate]?

        struct Candidate: Decodable {
            let content: ResponseContent?
            let finishReason: String?
        }

        struct ResponseContent: Decodable {
            let parts: [ResponsePart]?
        }

        struct ResponsePart: Decodable {
            let text: String?
            let functionCall: FunctionCall?
        }

        struct FunctionCall: Decodable {
            let name: String
            let args: FamiliarJSONValue?
        }
    }
}

private nonisolated enum FamiliarJSONValue: Codable, Equatable, Sendable {
    case object([String: FamiliarJSONValue])
    case array([FamiliarJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: FamiliarJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([FamiliarJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    static func parse(_ string: String) -> FamiliarJSONValue {
        guard let data = string.data(using: .utf8),
              let value = try? JSONDecoder().decode(FamiliarJSONValue.self, from: data)
        else { return .object([:]) }
        return value
    }

    static func encodedString(_ value: FamiliarJSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func responseObject(from string: String) -> FamiliarJSONValue {
        let value = parse(string)
        if case .object = value { return value }
        return .object(["result": value])
    }
}
