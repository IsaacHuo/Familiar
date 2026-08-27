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
    case image(data: Data, mimeType: String)
}

nonisolated struct FamiliarToolCall: Equatable, Sendable {
    let id: String
    let name: String
    let arguments: String
}

nonisolated struct FamiliarProviderMessage: Sendable {
    let role: FamiliarProviderMessageRole
    let contentParts: [FamiliarProviderContent]
    let toolCalls: [FamiliarToolCall]
    let toolCallID: String?
    let name: String?

    init(
        role: FamiliarProviderMessageRole,
        contentParts: [FamiliarProviderContent] = [],
        toolCalls: [FamiliarToolCall] = [],
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

    static func assistant(_ content: String?, toolCalls: [FamiliarToolCall] = []) -> Self {
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
            case .image:
                nil
            }
        }
        return values.isEmpty ? nil : values.joined(separator: "\n\n")
    }

    var hasImages: Bool {
        contentParts.contains { part in
            if case .image = part { return true }
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

nonisolated struct FamiliarToolManifest: Codable, Equatable, Sendable {
    let id: String
    let version: String
    let name: String
    let title: String
    let description: String
    let parameters: FamiliarJSONSchema
    let effect: FamiliarToolEffect
    let risk: FamiliarToolRisk
    let requirements: [FamiliarCapabilityRequirement]
    let source: FamiliarCapabilitySource
    let payloadLimit: Int
    let dataDomains: [String]
    let networkDomains: [String]
    let privacyLabels: [String]
    let supportsIdempotency: Bool
    let supportsCancellation: Bool
    let supportsRecovery: Bool
    let supportsParallelism: Bool
    let requiredScopes: [String]
    let executionClass: FamiliarToolExecutionClass

    init(
        id: String? = nil,
        version: String = "1",
        name: String,
        title: String,
        description: String,
        parameters: FamiliarJSONSchema,
        effect: FamiliarToolEffect,
        risk: FamiliarToolRisk,
        requirements: [FamiliarCapabilityRequirement] = [],
        source: FamiliarCapabilitySource = .builtIn,
        payloadLimit: Int = 16_000,
        dataDomains: [String] = [],
        networkDomains: [String] = [],
        privacyLabels: [String] = [],
        supportsIdempotency: Bool = true,
        supportsCancellation: Bool = true,
        supportsRecovery: Bool = false,
        supportsParallelism: Bool = false,
        requiredScopes: [String] = [],
        executionClass: FamiliarToolExecutionClass = .specializedLocal
    ) {
        self.id = id ?? name
        self.version = version
        self.name = name
        self.title = title
        self.description = description
        self.parameters = parameters
        self.effect = effect
        self.risk = risk
        self.requirements = requirements
        self.source = source
        self.payloadLimit = payloadLimit
        self.dataDomains = dataDomains.sorted()
        self.networkDomains = networkDomains.sorted()
        self.privacyLabels = privacyLabels.sorted()
        self.supportsIdempotency = supportsIdempotency
        self.supportsCancellation = supportsCancellation
        self.supportsRecovery = supportsRecovery
        self.supportsParallelism = supportsParallelism
        self.requiredScopes = requiredScopes.sorted()
        self.executionClass = executionClass
    }
}

nonisolated enum FamiliarToolExecutionClass: String, Codable, Sendable {
    case native
    case specializedLocal
    case shell

    var preferenceRank: Int {
        switch self {
        case .native: 0
        case .specializedLocal: 1
        case .shell: 2
        }
    }
}

nonisolated struct FamiliarModelRequest: Sendable {
    let model: String
    let messages: [FamiliarProviderMessage]
    let tools: [FamiliarToolManifest]
}

nonisolated enum FamiliarModelFinishReason: String, Sendable {
    case stop
    case toolCalls = "tool_calls"
    case length
    case unknown
}

nonisolated enum FamiliarModelStreamEvent: Sendable {
    case textDelta(String)
    case reasoningSummaryDelta(String)
    case toolCallDelta(index: Int, id: String?, name: String?, arguments: String?)
    case completed(FamiliarModelFinishReason)
}

nonisolated struct FamiliarModelResponse: Sendable {
    let text: String
    let reasoningSummary: String
    let toolCalls: [FamiliarToolCall]
    let finishReason: FamiliarModelFinishReason
}

nonisolated enum FamiliarModelRoutePolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case localOnly
    case preferLocal
    case cloud

    var id: String { rawValue }
}

nonisolated protocol FamiliarModelProvider: Sendable {
    var providerID: String { get }

    func stream(
        request: FamiliarModelRequest
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error>
}

nonisolated extension FamiliarModelProvider {
    func generate(request: FamiliarModelRequest) async throws -> FamiliarModelResponse {
        var text = ""
        var reasoning = ""
        var pendingCalls: [Int: FamiliarPendingModelToolCall] = [:]
        var finishReason: FamiliarModelFinishReason = .unknown

        for try await event in stream(request: request) {
            switch event {
            case .textDelta(let delta):
                text += delta
            case .reasoningSummaryDelta(let delta):
                reasoning += delta
            case .toolCallDelta(let index, let id, let name, let arguments):
                var call = pendingCalls[index] ?? FamiliarPendingModelToolCall()
                if let id { call.id += id }
                if let name { call.name += name }
                if let arguments { call.arguments += arguments }
                pendingCalls[index] = call
            case .completed(let reason):
                finishReason = reason
            }
        }

        let calls = pendingCalls.keys.sorted().compactMap { index -> FamiliarToolCall? in
            guard let call = pendingCalls[index], !call.name.isEmpty else { return nil }
            return FamiliarToolCall(
                id: call.id.isEmpty ? UUID().uuidString : call.id,
                name: call.name,
                arguments: call.arguments.isEmpty ? "{}" : call.arguments
            )
        }
        return FamiliarModelResponse(
            text: text,
            reasoningSummary: reasoning,
            toolCalls: calls,
            finishReason: finishReason
        )
    }
}

private nonisolated struct FamiliarPendingModelToolCall {
    var id = ""
    var name = ""
    var arguments = ""
}
