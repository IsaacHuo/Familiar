import Foundation

nonisolated enum FamiliarProviderRequestError: LocalizedError, Sendable {
    case invalidResponse(provider: String)
    case server(provider: String, statusCode: Int, message: String)
    case emptyResponse(provider: String)
    case unsupportedImages(provider: String)
    case invalidConfiguration(provider: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let provider):
            String(format: String(localized: "error.provider.invalid_response"), provider)
        case .server(let provider, let statusCode, let message):
            String(format: String(localized: "error.provider.server"), provider, statusCode, message)
        case .emptyResponse(let provider):
            String(format: String(localized: "error.provider.empty_response"), provider)
        case .unsupportedImages(let provider):
            String(format: String(localized: "error.provider.images_unsupported"), provider)
        case .invalidConfiguration(let provider):
            String(format: String(localized: "error.provider.invalid_configuration"), provider)
        }
    }
}

nonisolated struct OpenAICompatibleClient: FamiliarModelProvider, Sendable {
    let descriptor: FamiliarProviderDescriptor

    var providerID: String { descriptor.id }

    func stream(
        request modelRequest: FamiliarModelRequest,
        apiKey: String
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !modelRequest.messages.contains(where: \.containsImagePlaceholder) else {
                        throw FamiliarProviderRequestError.unsupportedImages(provider: descriptor.displayName)
                    }
                    let endpoint = try FamiliarProviderHTTP.authorizedURL(
                        descriptor: descriptor,
                        path: descriptor.chatPath,
                        model: modelRequest.model,
                        apiKey: apiKey
                    )
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    FamiliarProviderHTTP.applyHeaders(
                        to: &request,
                        descriptor: descriptor,
                        apiKey: apiKey
                    )
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(
                        RequestBody(
                            modelRequest,
                            sendsStreamOptions: descriptor.openAIChat?.sendsStreamOptions == true
                        )
                    )

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

                    let dataPrefix = descriptor.openAIChat?.dataPrefix ?? "data:"
                    let doneToken = descriptor.openAIChat?.doneToken ?? "[DONE]"
                    var emittedContent = false
                    var emittedCompletion = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix(dataPrefix) else { continue }
                        let payload = line.dropFirst(dataPrefix.count).trimmingCharacters(in: .whitespaces)
                        if payload == doneToken { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamPayload.self, from: data)
                        else { continue }

                        for choice in event.choices {
                            if let content = choice.delta.content, !content.isEmpty {
                                emittedContent = true
                                continuation.yield(.textDelta(content))
                            }
                            for call in choice.delta.toolCalls ?? [] {
                                emittedContent = true
                                continuation.yield(.toolCallDelta(
                                    index: call.index,
                                    id: call.id,
                                    name: call.function?.name,
                                    arguments: call.function?.arguments
                                ))
                            }
                            if let reason = choice.finishReason {
                                emittedCompletion = true
                                continuation.yield(.completed(Self.finishReason(reason)))
                            }
                        }
                    }

                    guard emittedContent else {
                        throw FamiliarProviderRequestError.emptyResponse(provider: descriptor.displayName)
                    }
                    if !emittedCompletion { continuation.yield(.completed(.stop)) }
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
        case "stop": .stop
        case "tool_calls", "function_call": .toolCalls
        case "length", "max_tokens": .length
        default: .unknown
        }
    }
}

private nonisolated extension OpenAICompatibleClient {
    struct RequestBody: Encodable {
        let model: String
        let messages: [RequestMessage]
        let stream = true
        let streamOptions: StreamOptions?
        let tools: [RequestTool]?

        init(_ request: FamiliarModelRequest, sendsStreamOptions: Bool) {
            model = request.model
            messages = request.messages.map(RequestMessage.init)
            streamOptions = sendsStreamOptions ? StreamOptions(includeUsage: true) : nil
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
            content = message.networkText
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
            function = Function(name: call.name, arguments: call.arguments)
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
            function = Function(
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
}

nonisolated enum FamiliarProviderHTTP {
    static func authorizedURL(
        descriptor: FamiliarProviderDescriptor,
        path: String,
        model: String? = nil,
        apiKey: String
    ) throws -> URL {
        let resolvedPath = path.replacingOccurrences(of: "{model}", with: model ?? "")
        let base = descriptor.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let relative = resolvedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let combinedURL = URL(string: base + "/" + relative),
              var components = URLComponents(url: combinedURL, resolvingAgainstBaseURL: false)
        else {
            throw FamiliarProviderRequestError.invalidConfiguration(provider: descriptor.displayName)
        }
        if case .apiKeyQuery(let name) = descriptor.authStyle {
            var queryItems = components.queryItems ?? []
            queryItems.removeAll { $0.name == name }
            queryItems.append(URLQueryItem(name: name, value: apiKey))
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw FamiliarProviderRequestError.invalidConfiguration(provider: descriptor.displayName)
        }
        return url
    }

    static func applyHeaders(
        to request: inout URLRequest,
        descriptor: FamiliarProviderDescriptor,
        apiKey: String
    ) {
        switch descriptor.authStyle {
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .apiKeyHeader(let name):
            request.setValue(apiKey, forHTTPHeaderField: name)
        case .apiKeyQuery:
            break
        }
        descriptor.additionalHeaders.forEach {
            request.setValue($1, forHTTPHeaderField: $0)
        }
    }

    static func readError(_ bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            guard data.count < 64_000 else { break }
            data.append(byte)
        }
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           !envelope.error.message.isEmpty {
            return String(envelope.error.message.prefix(500))
        }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false
            ? String(value!.prefix(500))
            : String(localized: "error.provider.unknown_server")
    }

    private struct ErrorEnvelope: Decodable {
        let error: APIError
        struct APIError: Decodable { let message: String }
    }
}

nonisolated enum FamiliarProviderFactory {
    static func makeProvider(for descriptor: FamiliarProviderDescriptor) -> any FamiliarModelProvider {
        switch descriptor.protocolKind {
        case .openAIChat:
            OpenAICompatibleClient(descriptor: descriptor)
        case .anthropicMessages:
            AnthropicMessagesClient(descriptor: descriptor)
        case .geminiGenerateContent:
            GeminiGenerateContentClient(descriptor: descriptor)
        }
    }
}
