import Foundation

nonisolated enum DeepSeekClientError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidResponse
    case server(statusCode: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "请先在设置中配置 DeepSeek API Key。"
        case .invalidResponse:
            "DeepSeek 返回了无法识别的响应。"
        case .server(let statusCode, let message):
            "DeepSeek 请求失败（\(statusCode)）：\(message)"
        case .emptyResponse:
            "DeepSeek 没有返回回答内容。"
        }
    }
}

nonisolated struct DeepSeekClient: Sendable {
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    func stream(
        messages: [FamiliarMessageSnapshot],
        settings: FamiliarSettings,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(
                        RequestBody(
                            model: settings.model.rawValue,
                            messages: [
                                RequestMessage(role: "system", content: settings.normalizedSystemPrompt)
                            ] + messages.suffix(40).map {
                                RequestMessage(role: $0.role.rawValue, content: $0.content)
                            },
                            stream: true,
                            streamOptions: .init(includeUsage: true)
                        )
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw DeepSeekClientError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var data = Data()
                        for try await byte in bytes {
                            guard data.count < 64_000 else { break }
                            data.append(byte)
                        }
                        let message = Self.serverMessage(from: data)
                        throw DeepSeekClientError.server(statusCode: http.statusCode, message: message)
                    }

                    var emittedContent = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamPayload.self, from: data)
                        else { continue }
                        for value in event.choices.compactMap(\.delta.content) where !value.isEmpty {
                            emittedContent = true
                            continuation.yield(value)
                        }
                    }

                    guard emittedContent else { throw DeepSeekClientError.emptyResponse }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
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
        return fallback?.isEmpty == false ? String(fallback!.prefix(500)) : "未知服务错误"
    }
}

private nonisolated extension DeepSeekClient {
    struct RequestBody: Encodable {
        let model: String
        let messages: [RequestMessage]
        let stream: Bool
        let streamOptions: StreamOptions

        enum CodingKeys: String, CodingKey {
            case model, messages, stream
            case streamOptions = "stream_options"
        }
    }

    struct RequestMessage: Encodable {
        let role: String
        let content: String
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
        }

        struct Delta: Decodable {
            let content: String?
        }
    }

    struct ErrorEnvelope: Decodable {
        let error: APIError

        struct APIError: Decodable {
            let message: String
        }
    }
}
