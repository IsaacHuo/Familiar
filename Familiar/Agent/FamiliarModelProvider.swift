import Foundation

nonisolated enum FamiliarProviderMessageRole: String, Sendable {
    case system
    case user
    case assistant
    case tool
}

nonisolated struct FamiliarProviderToolCall: Equatable, Sendable {
    let id: String
    let name: String
    let arguments: String
}

nonisolated struct FamiliarProviderMessage: Sendable {
    let role: FamiliarProviderMessageRole
    let content: String?
    let toolCalls: [FamiliarProviderToolCall]
    let toolCallID: String?
    let name: String?

    static func system(_ content: String) -> Self {
        .init(role: .system, content: content, toolCalls: [], toolCallID: nil, name: nil)
    }

    static func user(_ content: String) -> Self {
        .init(role: .user, content: content, toolCalls: [], toolCallID: nil, name: nil)
    }

    static func assistant(_ content: String?, toolCalls: [FamiliarProviderToolCall] = []) -> Self {
        .init(role: .assistant, content: content, toolCalls: toolCalls, toolCallID: nil, name: nil)
    }

    static func tool(_ content: String, toolCallID: String, name: String) -> Self {
        .init(role: .tool, content: content, toolCalls: [], toolCallID: toolCallID, name: name)
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
    func stream(
        request: FamiliarModelRequest,
        apiKey: String
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error>
}
