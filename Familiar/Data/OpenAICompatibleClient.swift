import Foundation

nonisolated enum OpenAICompatibleClientError: LocalizedError, Sendable {
    case invalidResponse(provider: String)
    case server(provider: String, statusCode: Int, message: String)
    case emptyResponse(provider: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let provider):
            String(format: String(localized: "error.provider.invalid_response"), provider)
        case .server(let provider, let statusCode, let message):
            String(format: String(localized: "error.provider.server"), provider, statusCode, message)
        case .emptyResponse(let provider):
            String(format: String(localized: "error.provider.empty_response"), provider)
        }
    }
}

nonisolated struct OpenAICompatibleClient: FamiliarModelProvider, Sendable {
    let providerName: String
    let endpoint: URL

    func stream(
        request modelRequest: FamiliarModelRequest,
        apiKey: String
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(RequestBody(modelRequest))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw OpenAICompatibleClientError.invalidResponse(provider: providerName)
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var data = Data()
                        for try await byte in bytes {
                            guard data.count < 64_000 else { break }
                            data.append(byte)
                        }
                        let message = Self.serverMessage(from: data)
                        throw OpenAICompatibleClientError.server(
                            provider: providerName,
                            statusCode: http.statusCode,
                            message: message
                        )
                    }

                    var emittedEvent = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamPayload.self, from: data)
                        else { continue }

                        for choice in event.choices {
                            if let content = choice.delta.content, !content.isEmpty {
                                emittedEvent = true
                                continuation.yield(.textDelta(content))
                            }
                            for call in choice.delta.toolCalls ?? [] {
                                emittedEvent = true
                                continuation.yield(.toolCallDelta(
                                    index: call.index,
                                    id: call.id,
                                    name: call.function?.name,
                                    arguments: call.function?.arguments
                                ))
                            }
                            if let reason = choice.finishReason {
                                continuation.yield(.completed(FamiliarModelFinishReason(rawValue: reason) ?? .unknown))
                            }
                        }
                    }

                    guard emittedEvent else {
                        throw OpenAICompatibleClientError.emptyResponse(provider: providerName)
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

    private static func serverMessage(from data: Data) -> String {
        if let payload = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           !payload.error.message.isEmpty {
            return payload.error.message
        }
        let fallback = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback?.isEmpty == false
            ? String(fallback!.prefix(500))
            : String(localized: "error.provider.unknown_server")
    }
}

nonisolated enum FamiliarProviderFactory {
    static func makeProvider(for provider: FamiliarProvider) -> any FamiliarModelProvider {
        switch provider {
        case .deepSeek:
            OpenAICompatibleClient(
                providerName: provider.title,
                endpoint: URL(string: "https://api.deepseek.com/chat/completions")!
            )
        case .groq:
            OpenAICompatibleClient(
                providerName: provider.title,
                endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!
            )
        }
    }
}

private nonisolated extension OpenAICompatibleClient {
    struct RequestBody: Encodable {
        let model: String
        let messages: [RequestMessage]
        let stream: Bool
        let streamOptions: StreamOptions
        let tools: [RequestTool]?

        init(_ request: FamiliarModelRequest) {
            model = request.model
            messages = request.messages.map(RequestMessage.init)
            stream = true
            streamOptions = .init(includeUsage: true)
            tools = request.tools.isEmpty ? nil : request.tools.map(RequestTool.init)
        }

        enum CodingKeys: String, CodingKey {
            case model, messages, stream, tools
            case streamOptions = "stream_options"
        }
    }

    struct RequestMessage: Encodable {
        let role: String
        let content: String?
        let toolCalls: [RequestToolCall]?
        let toolCallID: String?
        let name: String?

        init(_ message: FamiliarProviderMessage) {
            role = message.role.rawValue
            content = message.content
            toolCalls = message.toolCalls.isEmpty ? nil : message.toolCalls.map(RequestToolCall.init)
            toolCallID = message.toolCallID
            name = message.name
        }

        enum CodingKeys: String, CodingKey {
            case role, content, name
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
        }
    }

    struct RequestToolCall: Encodable {
        let id: String
        let type = "function"
        let function: Function

        init(_ call: FamiliarProviderToolCall) {
            id = call.id
            function = .init(name: call.name, arguments: call.arguments)
        }

        struct Function: Encodable {
            let name: String
            let arguments: String
        }
    }

    struct RequestTool: Encodable {
        let type = "function"
        let function: Function

        init(_ definition: FamiliarToolDefinition) {
            function = .init(
                name: definition.name,
                description: definition.description,
                parameters: definition.parameters
            )
        }

        struct Function: Encodable {
            let name: String
            let description: String
            let parameters: FamiliarJSONSchema
        }
    }

    struct StreamOptions: Encodable {
        let includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    struct StreamPayload: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let delta: Delta
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        struct Delta: Decodable {
            let content: String?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }

        struct ToolCall: Decodable {
            let index: Int
            let id: String?
            let function: Function?

            struct Function: Decodable {
                let name: String?
                let arguments: String?
            }
        }
    }

    struct ErrorEnvelope: Decodable {
        let error: APIError

        struct APIError: Decodable {
            let message: String
        }
    }
}
