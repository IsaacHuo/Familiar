import Foundation

nonisolated enum FamiliarProviderRequestError: LocalizedError, Sendable {
    case invalidResponse(provider: String)
    case server(provider: String, statusCode: Int, message: String)
    case emptyResponse(provider: String)
    case invalidConfiguration(provider: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let provider):
            String(format: String(localized: "error.provider.invalid_response"), provider)
        case .server(let provider, let statusCode, let message):
            String(format: String(localized: "error.provider.server"), provider, statusCode, message)
        case .emptyResponse(let provider):
            String(format: String(localized: "error.provider.empty_response"), provider)
        case .invalidConfiguration(let provider):
            String(format: String(localized: "error.provider.invalid_configuration"), provider)
        }
    }
}

nonisolated struct FamiliarOpenAICompatibleModelProvider: FamiliarModelProvider, Sendable {
    let descriptor: FamiliarProviderDescriptor
    let apiKey: String

    var providerID: String { descriptor.id }

    func stream(
        request modelRequest: FamiliarModelRequest
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

                    let (bytes, response) = try await FamiliarProviderHTTP.session.bytes(for: request)
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
                        guard let data = payload.data(using: .utf8) else {
                            throw FamiliarProviderRequestError.invalidResponse(provider: descriptor.displayName)
                        }
                        let event: StreamPayload
                        do {
                            event = try JSONDecoder().decode(StreamPayload.self, from: data)
                        } catch {
                            throw FamiliarProviderRequestError.invalidResponse(provider: descriptor.displayName)
                        }

                        for choice in event.choices {
                            if let reasoning = choice.delta.reasoningContent, !reasoning.isEmpty {
                                emittedContent = true
                                continuation.yield(.reasoningSummaryDelta(reasoning))
                            }
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
                    if !emittedCompletion { continuation.yield(.completed(.unknown)) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as URLError where error.code == .cancelled {
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

private nonisolated extension FamiliarOpenAICompatibleModelProvider {
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
        let content: RequestContent?
        let toolCalls: [RequestToolCall]?
        let toolCallID: String?
        let name: String?

        init(_ message: FamiliarProviderMessage) {
            role = message.role.rawValue
            if message.hasImages {
                content = .parts(message.contentParts.map(RequestContentPart.init))
            } else {
                content = message.networkText.map(RequestContent.text)
            }
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

    enum RequestContent: Encodable {
        case text(String)
        case parts([RequestContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text): try container.encode(text)
            case .parts(let parts): try container.encode(parts)
            }
        }
    }

    struct RequestContentPart: Encodable {
        let type: String
        let text: String?
        let imageURL: ImageURL?

        init(_ part: FamiliarProviderContent) {
            switch part {
            case .text(let text):
                type = "text"
                self.text = text
                imageURL = nil
            case .document(let text, let filename):
                type = "text"
                self.text = "[Document: \(filename)]\n\(text)"
                imageURL = nil
            case .image(let data, let mimeType):
                type = "image_url"
                text = nil
                imageURL = ImageURL(url: "data:\(mimeType);base64,\(data.base64EncodedString())")
            }
        }

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }

        struct ImageURL: Encodable {
            let url: String
        }
    }

    struct RequestToolCall: Encodable {
        let id: String
        let type = "function"
        let function: Function

        init(_ call: FamiliarToolCall) {
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

        init(_ definition: FamiliarToolManifest) {
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
            let reasoningContent: String?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
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
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()

    static func authorizedURL(
        descriptor: FamiliarProviderDescriptor,
        path: String,
        model: String? = nil,
        apiKey: String
    ) throws -> URL {
        let resolvedPath = path.replacingOccurrences(of: "{model}", with: model ?? "")
        let base = descriptor.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let relative = resolvedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let combinedURL = URL(string: base + "/" + relative) else {
            throw FamiliarProviderRequestError.invalidConfiguration(provider: descriptor.displayName)
        }
        return combinedURL
    }

    static func applyHeaders(
        to request: inout URLRequest,
        descriptor: FamiliarProviderDescriptor,
        apiKey: String
    ) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
        return errorMessage(from: data)
    }

    static func errorMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           !envelope.error.message.isEmpty {
            return sanitizedMessage(envelope.error.message)
        }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false
            ? sanitizedMessage(value!)
            : String(localized: "error.provider.unknown_server")
    }

    private static func sanitizedMessage(_ value: String) -> String {
        let bounded = String(value.prefix(500))
        return bounded.replacingOccurrences(
            of: #"(?i)bearer\s+[a-z0-9._-]+|sk-[a-z0-9_-]+"#,
            with: "[REDACTED]",
            options: .regularExpression
        )
    }

    private struct ErrorEnvelope: Decodable {
        let error: APIError
        struct APIError: Decodable { let message: String }
    }
}

nonisolated enum FamiliarProviderFactory {
    static func makeProvider(
        for descriptor: FamiliarProviderDescriptor,
        apiKey: String
    ) -> any FamiliarModelProvider {
        FamiliarOpenAICompatibleModelProvider(descriptor: descriptor, apiKey: apiKey)
    }
}
