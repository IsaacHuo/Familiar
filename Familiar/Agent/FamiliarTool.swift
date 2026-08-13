import Foundation

nonisolated public enum FamiliarToolEffect: String, Codable, Sendable {
    case read
    case reversibleWrite
    case destructiveWrite
}

nonisolated enum FamiliarToolRisk: String, Codable, Sendable {
    case low
    case sensitive
    case high
}

nonisolated enum FamiliarCapabilityRequirement: String, Codable, Hashable, Sendable {
    case calendarFullAccess
    case remindersFullAccess
}

nonisolated enum FamiliarCapabilityAvailability: Equatable, Sendable {
    case available
    case requestable
    case unavailable(reason: String)
}

nonisolated struct FamiliarToolContext: Sendable {
    let runID: String
    let toolCallID: String

    init(runID: String = "standalone", toolCallID: String = UUID().uuidString) {
        self.runID = runID
        self.toolCallID = toolCallID
    }

    var idempotencyKey: String { runID + ":" + toolCallID }
}

nonisolated struct FamiliarToolExecutionResult: Sendable {
    let modelContent: String
    let displayContent: String
    let artifactIdentifier: String?

    init(modelContent: String, displayContent: String, artifactIdentifier: String? = nil) {
        self.modelContent = modelContent
        self.displayContent = displayContent
        self.artifactIdentifier = artifactIdentifier
    }
}

nonisolated struct FamiliarActionProposal: Sendable {
    let title: String
    let fields: [String: String]
    let target: String?
    let idempotencyKey: String
    let execute: @Sendable () async throws -> FamiliarToolExecutionResult
    let undo: (@Sendable () async throws -> FamiliarToolExecutionResult)?
}

nonisolated enum FamiliarToolOutcome: Sendable {
    case result(FamiliarToolExecutionResult)
    case action(FamiliarActionProposal)
}

nonisolated protocol FamiliarCapabilityProviding: Sendable {
    func availability(for requirement: FamiliarCapabilityRequirement) async -> FamiliarCapabilityAvailability
    func request(_ requirement: FamiliarCapabilityRequirement) async throws
}

nonisolated protocol FamiliarTool: Sendable {
    associatedtype Input: Decodable & Sendable

    var manifest: FamiliarToolManifest { get }

    func execute(
        _ input: Input,
        context: FamiliarToolContext
    ) async throws -> FamiliarToolOutcome
}

nonisolated struct AnyFamiliarTool: Sendable {
    let manifest: FamiliarToolManifest
    private let executeClosure: @Sendable (Data, FamiliarToolContext) async throws -> FamiliarToolOutcome

    init<T: FamiliarTool>(_ tool: T) {
        manifest = tool.manifest
        executeClosure = { data, context in
            let input = try JSONDecoder().decode(T.Input.self, from: data)
            return try await tool.execute(input, context: context)
        }
    }

    func execute(arguments: String, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let normalized = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = (normalized.isEmpty ? "{}" : normalized).data(using: .utf8) else {
            throw FamiliarToolRegistryError.invalidArguments(manifest.name)
        }
        do {
            return try await executeClosure(data, context)
        } catch let error as DecodingError {
            throw FamiliarToolRegistryError.argumentDecodingFailed(
                tool: manifest.name,
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
    case capabilityUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .duplicateTool(let name): String(format: String(localized: "error.tool.duplicate"), name)
        case .toolNotFound(let name): String(format: String(localized: "error.tool.not_found"), name)
        case .invalidArguments(let name): String(format: String(localized: "error.tool.invalid_arguments"), name)
        case .argumentDecodingFailed(let tool, let reason):
            String(format: String(localized: "error.tool.decoding"), tool, reason)
        case .capabilityUnavailable(let reason): reason
        }
    }
}

actor FamiliarToolRegistry {
    private let toolsByName: [String: AnyFamiliarTool]
    private let capabilities: (any FamiliarCapabilityProviding)?

    init(tools: [AnyFamiliarTool], capabilities: (any FamiliarCapabilityProviding)? = nil) throws {
        var values: [String: AnyFamiliarTool] = [:]
        for tool in tools {
            guard values[tool.manifest.name] == nil else {
                throw FamiliarToolRegistryError.duplicateTool(tool.manifest.name)
            }
            values[tool.manifest.name] = tool
        }
        toolsByName = values
        self.capabilities = capabilities
    }

    func manifests() async -> [FamiliarToolManifest] {
        var result: [FamiliarToolManifest] = []
        for tool in toolsByName.values {
            guard case .unavailable = await availability(for: tool.manifest) else {
                result.append(tool.manifest)
                continue
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    func manifest(named name: String) throws -> FamiliarToolManifest {
        guard let tool = toolsByName[name] else { throw FamiliarToolRegistryError.toolNotFound(name) }
        return tool.manifest
    }

    func availability(for manifest: FamiliarToolManifest) async -> FamiliarCapabilityAvailability {
        guard let capabilities else {
            return manifest.requirements.isEmpty ? .available : .unavailable(reason: "设备能力服务不可用。")
        }
        var needsRequest = false
        for requirement in manifest.requirements {
            switch await capabilities.availability(for: requirement) {
            case .available: continue
            case .requestable: needsRequest = true
            case .unavailable(let reason): return .unavailable(reason: reason)
            }
        }
        return needsRequest ? .requestable : .available
    }

    func prepareCapabilities(for manifest: FamiliarToolManifest) async throws {
        guard let capabilities else {
            guard manifest.requirements.isEmpty else {
                throw FamiliarToolRegistryError.capabilityUnavailable("设备能力服务不可用。")
            }
            return
        }
        for requirement in manifest.requirements {
            switch await capabilities.availability(for: requirement) {
            case .available: continue
            case .requestable: try await capabilities.request(requirement)
            case .unavailable(let reason): throw FamiliarToolRegistryError.capabilityUnavailable(reason)
            }
        }
    }

    func execute(
        name: String,
        arguments: String,
        context: FamiliarToolContext
    ) async throws -> FamiliarToolOutcome {
        guard let tool = toolsByName[name] else { throw FamiliarToolRegistryError.toolNotFound(name) }
        return try await tool.execute(arguments: arguments, context: context)
    }
}
