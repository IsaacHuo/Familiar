import Foundation

nonisolated enum FamiliarProviderMessageRole: String, Sendable {
    case system
    case user
    case assistant
    case tool
}

nonisolated enum FamiliarProviderContent: Equatable, Sendable {
    case text(String)
    case document(text: String, filename: String)
    case imagePlaceholder(localIdentifier: String?)
}

nonisolated struct FamiliarProviderToolCall: Equatable, Sendable {
    let id: String
    let name: String
    let arguments: String
}

nonisolated struct FamiliarProviderMessage: Sendable {
    let role: FamiliarProviderMessageRole
    let contentParts: [FamiliarProviderContent]
    let toolCalls: [FamiliarProviderToolCall]
    let toolCallID: String?
    let name: String?

    init(
        role: FamiliarProviderMessageRole,
        contentParts: [FamiliarProviderContent] = [],
        toolCalls: [FamiliarProviderToolCall] = [],
        toolCallID: String? = nil,
        name: String? = nil
    ) {
        self.role = role
        self.contentParts = contentParts
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
    }

    static func system(_ content: String) -> Self {
        .init(role: .system, contentParts: [.text(content)])
    }

    static func user(_ content: String) -> Self {
        .init(role: .user, contentParts: [.text(content)])
    }

    static func user(parts: [FamiliarProviderContent]) -> Self {
        .init(role: .user, contentParts: parts)
    }

    static func assistant(_ content: String?, toolCalls: [FamiliarProviderToolCall] = []) -> Self {
        .init(
            role: .assistant,
            contentParts: content.map { [.text($0)] } ?? [],
            toolCalls: toolCalls
        )
    }

    static func tool(_ content: String, toolCallID: String, name: String) -> Self {
        .init(
            role: .tool,
            contentParts: [.text(content)],
            toolCallID: toolCallID,
            name: name
        )
    }

    var networkText: String? {
        let values = contentParts.compactMap { part -> String? in
            switch part {
            case .text(let text):
                text
            case .document(let text, let filename):
                "[Document: \(filename)]\n\(text)"
            case .imagePlaceholder:
                nil
            }
        }
        return values.isEmpty ? nil : values.joined(separator: "\n\n")
    }

    var containsImagePlaceholder: Bool {
        contentParts.contains { part in
            if case .imagePlaceholder = part { return true }
            return false
        }
    }
}

nonisolated enum FamiliarJSONSchemaType: String, Codable, Sendable {
    case object
    case string
    case integer
    case number
    case boolean
    case array
}

nonisolated struct FamiliarJSONSchema: Codable, Equatable, Sendable {
    let type: FamiliarJSONSchemaType
    let description: String?
    let properties: [String: FamiliarJSONSchema]?
    let required: [String]?
    let enumValues: [String]?

    init(
        type: FamiliarJSONSchemaType,
        description: String? = nil,
        properties: [String: FamiliarJSONSchema]? = nil,
        required: [String]? = nil,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.enumValues = enumValues
    }

    enum CodingKeys: String, CodingKey {
        case type, description, properties, required
        case enumValues = "enum"
    }
}

nonisolated struct FamiliarToolDefinition: Equatable, Sendable {
    let name: String
    let description: String
    let parameters: FamiliarJSONSchema
}

nonisolated struct FamiliarModelRequest: Sendable {
    let model: String
    let messages: [FamiliarProviderMessage]
    let tools: [FamiliarToolDefinition]
}

nonisolated enum FamiliarModelFinishReason: String, Sendable {
    case stop
    case toolCalls = "tool_calls"
    case length
    case unknown
}

nonisolated enum FamiliarModelStreamEvent: Sendable {
    case textDelta(String)
    case toolCallDelta(index: Int, id: String?, name: String?, arguments: String?)
    case completed(FamiliarModelFinishReason)
}

nonisolated protocol FamiliarModelProvider: Sendable {
    var providerID: String { get }

    func stream(
        request: FamiliarModelRequest,
        apiKey: String
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error>
}
