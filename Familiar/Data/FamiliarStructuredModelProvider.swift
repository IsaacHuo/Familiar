import Foundation

/// Protocol adapters share transport, cancellation and Familiar's typed event contract.
/// Vendor payloads never enter the tool authorization layer.
nonisolated struct FamiliarStructuredModelProvider: FamiliarModelProvider, Sendable {
    let descriptor: FamiliarProviderDescriptor
    let apiKey: String
    private let signatures = FamiliarGeminiSignatures()
    var providerID: String { descriptor.id }

    func stream(request input: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: try FamiliarProviderHTTP.authorizedURL(
                        descriptor: descriptor, path: descriptor.chatPath, model: input.model, apiKey: apiKey
                    ))
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    FamiliarProviderHTTP.applyHeaders(to: &request, descriptor: descriptor, apiKey: apiKey)
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let body = try await requestBody(input)
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    continuation.yield(.providerSelection(providerID: descriptor.id, modelID: input.model))
                    let (bytes, response) = try await FamiliarProviderHTTP.session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw invalidResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        throw FamiliarProviderRequestError.server(provider: descriptor.displayName, statusCode: http.statusCode, message: try await FamiliarProviderHTTP.readError(bytes))
                    }
                    var inputTokens: Int?
                    var outputTokens: Int?
                    var cachedTokens: Int?
                    var finished = false
                    var finishReason: FamiliarModelFinishReason = .stop
                    var toolCount = 0
                    var responseToolIndices: [String: Int] = [:]
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let event = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { throw invalidResponse }
                        if event["error"] != nil || event["type"] as? String == "error" { throw invalidResponse }
                        let nested = (event["message"] ?? event["response"]) as? [String: Any]
                        if let usage = (event["usage"] ?? event["usageMetadata"] ?? nested?["usage"]) as? [String: Any] {
                            inputTokens = usage["input_tokens"] as? Int ?? usage["promptTokenCount"] as? Int ?? inputTokens
                            outputTokens = usage["output_tokens"] as? Int ?? usage["candidatesTokenCount"] as? Int ?? outputTokens
                            cachedTokens = usage["cache_read_input_tokens"] as? Int ?? usage["cachedContentTokenCount"] as? Int ?? (usage["input_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int ?? cachedTokens
                        }
                        switch descriptor.protocolKind {
                        case .anthropic:
                            let type = event["type"] as? String
                            let index = event["index"] as? Int ?? 0
                            if type == "content_block_start", let block = event["content_block"] as? [String: Any], block["type"] as? String == "tool_use" {
                                toolCount += 1
                                continuation.yield(.toolCallDelta(index: index, id: block["id"] as? String, name: block["name"] as? String, arguments: nil))
                            }
                            if type == "content_block_delta", let delta = event["delta"] as? [String: Any] {
                                if let text = delta["text"] as? String { continuation.yield(.textDelta(text)) }
                                if let text = delta["thinking"] as? String { continuation.yield(.reasoningSummaryDelta(text)) }
                                if let json = delta["partial_json"] as? String { continuation.yield(.toolCallDelta(index: index, id: nil, name: nil, arguments: json)) }
                            }
                            if type == "message_delta", let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                                finishReason = reason == "tool_use" ? .toolCalls : reason == "max_tokens" ? .length : reason == "end_turn" || reason == "stop_sequence" ? .stop : .unknown
                            }
                            if type == "message_stop" { finished = true }
                        case .openAIResponses:
                            let type = event["type"] as? String ?? ""
                            if type == "response.output_text.delta", let delta = event["delta"] as? String { continuation.yield(.textDelta(delta)) }
                            if type == "response.reasoning_summary_text.delta", let delta = event["delta"] as? String { continuation.yield(.reasoningSummaryDelta(delta)) }
                            if type == "response.output_item.added", let item = event["item"] as? [String: Any], item["type"] as? String == "function_call", let id = item["id"] as? String {
                                let index = toolCount
                                toolCount += 1
                                responseToolIndices[id] = index
                                continuation.yield(.toolCallDelta(index: index, id: item["call_id"] as? String, name: item["name"] as? String, arguments: nil))
                            }
                            if type == "response.function_call_arguments.delta", let id = event["item_id"] as? String, let index = responseToolIndices[id] {
                                continuation.yield(.toolCallDelta(index: index, id: nil, name: nil, arguments: event["delta"] as? String))
                            }
                            if type == "response.completed" { finished = true; finishReason = toolCount > 0 ? .toolCalls : .stop }
                            if type == "response.incomplete" { finished = true; finishReason = .length }
                            if type == "response.failed" { throw invalidResponse }
                        case .gemini:
                            for candidate in event["candidates"] as? [[String: Any]] ?? [] {
                                let content = candidate["content"] as? [String: Any] ?? [:]
                                for part in content["parts"] as? [[String: Any]] ?? [] {
                                    if let text = part["text"] as? String {
                                        continuation.yield(part["thought"] as? Bool == true ? .reasoningSummaryDelta(text) : .textDelta(text))
                                    }
                                    if let call = part["functionCall"] as? [String: Any], let name = call["name"] as? String {
                                        let id = call["id"] as? String ?? UUID().uuidString
                                        if let signature = part["thoughtSignature"] as? String { await signatures.set(signature, for: id) }
                                        let arguments = try Self.json(call["args"] ?? [:])
                                        continuation.yield(.toolCallDelta(index: toolCount, id: id, name: name, arguments: arguments))
                                        toolCount += 1
                                    }
                                }
                                if let reason = candidate["finishReason"] as? String {
                                    finished = true
                                    finishReason = reason == "STOP" ? (toolCount > 0 ? .toolCalls : .stop) : reason == "MAX_TOKENS" ? .length : .unknown
                                }
                            }
                        case .openAIChat: throw invalidResponse
                        }
                    }
                    guard finished else { throw invalidResponse }
                    if inputTokens != nil || outputTokens != nil || cachedTokens != nil {
                        continuation.yield(.usage(.init(inputTokens: inputTokens, outputTokens: outputTokens, cachedInputTokens: cachedTokens)))
                    }
                    continuation.yield(.completed(finishReason))
                    continuation.finish()
                } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
                catch let error as URLError where error.code == .cancelled { continuation.finish(throwing: CancellationError()) }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func requestBody(_ input: FamiliarModelRequest) async throws -> [String: Any] {
        let system = input.messages.filter { $0.role == .system }.compactMap(\.networkText).joined(separator: "\n\n")
        let schemas = try input.tools.map { tool -> [String: Any] in
            ["name": tool.name, "description": tool.description,
             "parameters": try JSONSerialization.jsonObject(with: JSONEncoder().encode(tool.parameters))]
        }
        switch descriptor.protocolKind {
        case .anthropic:
            var messages: [[String: Any]] = []
            for message in input.messages where message.role != .system {
                var parts: [[String: Any]] = []
                if message.role == .tool {
                    parts = [["type": "tool_result", "tool_use_id": message.toolCallID ?? "", "content": message.networkText ?? ""]]
                } else {
                    for part in message.contentParts {
                        switch part {
                        case .image(let data, let mime): parts.append(["type": "image", "source": ["type": "base64", "media_type": mime, "data": data.base64EncodedString()]])
                        case .text(let text): if !text.isEmpty { parts.append(["type": "text", "text": text]) }
                        case .document(let text, let name): parts.append(["type": "text", "text": "[\(name)]\n\(text)"])
                        }
                    }
                    for call in message.toolCalls {
                        parts.append(["type": "tool_use", "id": call.id, "name": call.name, "input": try JSONSerialization.jsonObject(with: Data(call.arguments.utf8))])
                    }
                }
                guard !parts.isEmpty else { continue }
                let role = message.role == .assistant ? "assistant" : "user"
                if messages.last?["role"] as? String == role {
                    let existing = messages[messages.count - 1]["content"] as? [[String: Any]] ?? []
                    messages[messages.count - 1]["content"] = existing + parts
                } else { messages.append(["role": role, "content": parts]) }
            }
            var body: [String: Any] = ["model": input.model, "messages": messages, "system": system, "stream": true, "max_tokens": input.maximumOutputTokens ?? 8192]
            if !schemas.isEmpty { body["tools"] = schemas.map { ["name": $0["name"]!, "description": $0["description"]!, "input_schema": $0["parameters"]!] } }
            return body
        case .openAIResponses:
            var items: [[String: Any]] = []
            for message in input.messages where message.role != .system {
                if message.role == .tool {
                    items.append(["type": "function_call_output", "call_id": message.toolCallID ?? "", "output": message.networkText ?? ""])
                    continue
                }
                var content: [[String: Any]] = []
                for part in message.contentParts {
                    switch part {
                    case .image(let data, let mime): content.append(["type": "input_image", "image_url": "data:\(mime);base64,\(data.base64EncodedString())"])
                    case .text(let text): if !text.isEmpty { content.append(["type": message.role == .assistant ? "output_text" : "input_text", "text": text]) }
                    case .document(let text, let name): content.append(["type": "input_text", "text": "[\(name)]\n\(text)"])
                    }
                }
                if !content.isEmpty { items.append(["role": message.role.rawValue, "content": content]) }
                for call in message.toolCalls { items.append(["type": "function_call", "call_id": call.id, "name": call.name, "arguments": call.arguments]) }
            }
            var body: [String: Any] = ["model": input.model, "instructions": system, "input": items, "stream": true, "store": false]
            if let maximum = input.maximumOutputTokens { body["max_output_tokens"] = maximum }
            if !schemas.isEmpty { body["tools"] = schemas.map { $0.merging(["type": "function", "strict": false]) { _, new in new } } }
            return body
        case .gemini:
            var contents: [[String: Any]] = []
            for message in input.messages where message.role != .system {
                var parts: [[String: Any]] = []
                if message.role == .tool {
                    let result = (try? JSONSerialization.jsonObject(with: Data((message.networkText ?? "").utf8))) as? [String: Any] ?? ["result": message.networkText ?? ""]
                    parts.append(["functionResponse": ["name": message.name ?? "", "response": result]])
                } else {
                    for part in message.contentParts {
                        switch part {
                        case .image(let data, let mime): parts.append(["inlineData": ["mimeType": mime, "data": data.base64EncodedString()]])
                        case .text(let text): if !text.isEmpty { parts.append(["text": text]) }
                        case .document(let text, let name): parts.append(["text": "[\(name)]\n\(text)"])
                        }
                    }
                    for call in message.toolCalls {
                        var part: [String: Any] = ["functionCall": ["name": call.name, "args": try JSONSerialization.jsonObject(with: Data(call.arguments.utf8))]]
                        if let signature = await signatures.get(call.id) { part["thoughtSignature"] = signature }
                        parts.append(part)
                    }
                }
                guard !parts.isEmpty else { continue }
                let role = message.role == .assistant ? "model" : "user"
                if contents.last?["role"] as? String == role {
                    let existing = contents[contents.count - 1]["parts"] as? [[String: Any]] ?? []
                    contents[contents.count - 1]["parts"] = existing + parts
                } else { contents.append(["role": role, "parts": parts]) }
            }
            var body: [String: Any] = ["contents": contents, "systemInstruction": ["parts": [["text": system]]]]
            if let maximum = input.maximumOutputTokens { body["generationConfig"] = ["maxOutputTokens": maximum] }
            if !schemas.isEmpty {
                body["tools"] = [["functionDeclarations": schemas.map { ["name": $0["name"]!, "description": $0["description"]!, "parametersJsonSchema": $0["parameters"]!] }]]
            }
            return body
        case .openAIChat: throw invalidResponse
        }
    }

    private var invalidResponse: FamiliarProviderRequestError { .invalidResponse(provider: descriptor.displayName) }
    private static func json(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) }
}

private actor FamiliarGeminiSignatures {
    var values: [String: String] = [:]
    func set(_ signature: String, for id: String) { values[id] = signature }
    func get(_ id: String) -> String? { values[id] }
}
