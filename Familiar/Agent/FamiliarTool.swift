import Foundation

nonisolated struct FamiliarToolContext: Sendable {
    init() {}
}

nonisolated struct FamiliarToolExecutionResult: Sendable {
    let modelContent: String
    let displayContent: String
}

nonisolated protocol FamiliarTool: Sendable {
    associatedtype Input: Decodable & Sendable

    var definition: FamiliarToolDefinition { get }

    func execute(
        _ input: Input,
        context: FamiliarToolContext
    ) async throws -> FamiliarToolExecutionResult
}

nonisolated struct AnyFamiliarTool: Sendable {
    let definition: FamiliarToolDefinition
    private let executeClosure: @Sendable (Data, FamiliarToolContext) async throws -> FamiliarToolExecutionResult

    init<T: FamiliarTool>(_ tool: T) {
        definition = tool.definition
        executeClosure = { data, context in
            let input = try JSONDecoder().decode(T.Input.self, from: data)
            return try await tool.execute(input, context: context)
        }
    }

    func execute(
        arguments: String,
        context: FamiliarToolContext
    ) async throws -> FamiliarToolExecutionResult {
        let normalized = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = (normalized.isEmpty ? "{}" : normalized).data(using: .utf8) else {
            throw FamiliarToolRegistryError.invalidArguments(definition.name)
        }
        do {
            return try await executeClosure(data, context)
        } catch let error as DecodingError {
            throw FamiliarToolRegistryError.argumentDecodingFailed(
                tool: definition.name,
                reason: error.localizedDescription
            )
        }
    }
}

nonisolated enum FamiliarToolRegistryError: LocalizedError, Sendable {
    case duplicateTool(String)
    case toolNotFound(String)
    case invalidArguments(String)
    case argumentDecodingFailed(tool: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .duplicateTool(let name):
            String(format: String(localized: "error.tool.duplicate"), name)
        case .toolNotFound(let name):
            String(format: String(localized: "error.tool.not_found"), name)
        case .invalidArguments(let name):
            String(format: String(localized: "error.tool.invalid_arguments"), name)
        case .argumentDecodingFailed(let tool, let reason):
            String(format: String(localized: "error.tool.decoding"), tool, reason)
        }
    }
}

actor FamiliarToolRegistry {
    private let toolsByName: [String: AnyFamiliarTool]

    init(tools: [AnyFamiliarTool]) throws {
        var values: [String: AnyFamiliarTool] = [:]
        for tool in tools {
            guard values[tool.definition.name] == nil else {
                throw FamiliarToolRegistryError.duplicateTool(tool.definition.name)
            }
            values[tool.definition.name] = tool
        }
        toolsByName = values
    }

    func definitions() -> [FamiliarToolDefinition] {
        toolsByName.values.map(\.definition).sorted { $0.name < $1.name }
    }

    func execute(
        name: String,
        arguments: String,
        context: FamiliarToolContext = .init()
    ) async throws -> FamiliarToolExecutionResult {
        guard let tool = toolsByName[name] else {
            throw FamiliarToolRegistryError.toolNotFound(name)
        }
        return try await tool.execute(arguments: arguments, context: context)
    }
}
