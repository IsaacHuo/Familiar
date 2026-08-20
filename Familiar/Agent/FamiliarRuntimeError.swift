import Foundation

nonisolated enum FamiliarRuntimeFailureKind: Equatable, Sendable {
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
}

nonisolated enum FamiliarRuntimeFailure {
    static func kind(for error: any Error) -> FamiliarRuntimeFailureKind {
        if error is CancellationError { return .cancelled }
        if let agent = error as? FamiliarAgentError { return kind(for: agent) }
        if let tool = error as? FamiliarToolRegistryError { return kind(for: tool) }
        if let provider = error as? FamiliarProviderRequestError { return kind(for: provider) }
        if error is URLError { return .network }
        return .unknown
    }

    private static func kind(for error: FamiliarAgentError) -> FamiliarRuntimeFailureKind {
        switch error {
        case .emptyResponse: .emptyResponse
        case .invalidToolCall: .toolArgument
        case .incompleteResponse: .incompleteResponse
        case .maxIterationsExceeded: .maxIterations
        case .contextTooLarge: .contextTooLarge
        case .toolArgumentsTooLarge: .toolArgument
        case .toolResultTooLarge: .toolResult
        case .maxToolCallsExceeded: .maxToolCalls
        case .durationExceeded: .durationExceeded
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
