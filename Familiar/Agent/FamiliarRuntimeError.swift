import Foundation

nonisolated enum FamiliarRuntimeFailureKind: String, Codable, Equatable, Sendable {
    case authentication
    case rateLimited
    case transientServer
    case network
    case clientRequest
    case invalidResponse
    case emptyResponse
    case incompleteResponse
    case contextTooLarge
    case toolArgument
    case toolResult
    case toolUnavailable
    case maxIterations
    case maxToolCalls
    case durationExceeded
    case cancelled
    case unknown

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .transientServer, .network: true
        default: false
        }
    }

    var code: String {
        switch self {
        case .authentication: "authentication_failed"
        case .rateLimited: "rate_limited"
        case .transientServer: "transient_server_error"
        case .network: "network_error"
        case .clientRequest: "client_request_failed"
        case .invalidResponse: "invalid_response"
        case .emptyResponse: "empty_response"
        case .incompleteResponse: "incomplete_response"
        case .contextTooLarge: "context_too_large"
        case .toolArgument: "invalid_tool_arguments"
        case .toolResult: "invalid_tool_result"
        case .toolUnavailable: "tool_unavailable"
        case .maxIterations: "max_iterations_exceeded"
        case .maxToolCalls: "max_tool_calls_exceeded"
        case .durationExceeded: "duration_exceeded"
        case .cancelled: "cancelled"
        case .unknown: "tool_failed"
        }
    }
}

nonisolated enum FamiliarRuntimeFailure {
    static func kind(for error: any Error) -> FamiliarRuntimeFailureKind {
        if error is CancellationError { return .cancelled }
        if let agent = error as? FamiliarAgentError { return kind(for: agent) }
        if error is FamiliarToolExecutionTimeout { return .network }
        if let environment = error as? FamiliarEnvironmentError {
            if case .dnsFailed = environment { return .network }
            return .toolResult
        }
        if let tool = error as? FamiliarToolRegistryError { return kind(for: tool) }
        if let provider = error as? FamiliarProviderRequestError { return kind(for: provider) }
        if let web = error as? FamiliarWebError {
            if case .rateLimited = web { return .rateLimited }
            if case .httpError(let status) = web, (500...599).contains(status) { return .transientServer }
            return web.isRetryable ? .network : .clientRequest
        }
        if error is URLError { return .network }
        return .unknown
    }

    private static func kind(for error: FamiliarAgentError) -> FamiliarRuntimeFailureKind {
        switch error {
        case .emptyResponse: .emptyResponse
        case .invalidToolCall: .toolArgument
        case .incompleteResponse: .incompleteResponse
        case .maxIterationsExceeded: .maxIterations
        case .contextTooLarge, .contextCompactionFailed: .contextTooLarge
        case .toolArgumentsTooLarge: .toolArgument
        case .toolResultTooLarge: .toolResult
        case .durationExceeded: .durationExceeded
        case .missingDeliverables: .toolResult
        }
    }

    private static func kind(for error: FamiliarToolRegistryError) -> FamiliarRuntimeFailureKind {
        switch error {
        case .duplicateTool, .toolNotFound: .unknown
        case .invalidArguments, .argumentDecodingFailed: .toolArgument
        case .capabilityUnavailable: .toolUnavailable
        }
    }

    private static func kind(for error: FamiliarProviderRequestError) -> FamiliarRuntimeFailureKind {
        switch error {
        case .invalidResponse, .invalidConfiguration: .invalidResponse
        case .emptyResponse: .emptyResponse
        case .server(_, let statusCode, _):
            switch statusCode {
            case 401, 403: .authentication
            case 429: .rateLimited
            case 500...599: .transientServer
            default: .clientRequest
            }
        }
    }
}
