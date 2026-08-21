import Foundation

nonisolated public struct FamiliarClarificationRequest: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let runID: String
    public let toolCallID: String
    public let question: String
    public let options: [FamiliarClarificationOption]
    public let allowCustom: Bool

    public init(id: UUID = UUID(), runID: String, toolCallID: String, question: String, options: [FamiliarClarificationOption], allowCustom: Bool) {
        self.id = id
        self.runID = runID
        self.toolCallID = toolCallID
        self.question = question
        self.options = options
        self.allowCustom = allowCustom
    }
}

nonisolated public enum FamiliarClarificationResolution: Codable, Equatable, Sendable {
    case selectedOption(id: String, label: String)
    case custom(String)
    case cancelled
    case interrupted

    var answer: String? {
        switch self {
        case .selectedOption(_, let label), .custom(let label): label
        case .cancelled, .interrupted: nil
        }
    }
}

nonisolated public enum FamiliarClarificationCoordinatorResult: Equatable, Sendable {
    case resolved
    case alreadyResolved(FamiliarClarificationResolution)
    case invalidResolution
    case unknownRequest
}

public actor FamiliarClarificationCoordinator {
    private struct Pending {
        let request: FamiliarClarificationRequest
        let continuation: CheckedContinuation<FamiliarClarificationResolution, Error>
    }

    private var pending: [UUID: Pending] = [:]
    private var completed: [UUID: FamiliarClarificationResolution] = [:]

    public init() {}

    public func requestClarification(_ request: FamiliarClarificationRequest) async throws -> FamiliarClarificationResolution {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if let resolution = completed[request.id] {
                    continuation.resume(returning: resolution)
                } else if Task.isCancelled {
                    completed[request.id] = .cancelled
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending[request.id] = Pending(request: request, continuation: continuation)
                }
            }
        }, onCancel: {
            Task { await self.cancel(requestID: request.id, throwing: true) }
        })
    }

    @discardableResult
    public func resolve(requestID: UUID, resolution: FamiliarClarificationResolution) -> FamiliarClarificationCoordinatorResult {
        guard let value = pending.removeValue(forKey: requestID) else {
            if let completed = completed[requestID] { return .alreadyResolved(completed) }
            return .unknownRequest
        }
        guard Self.isValid(resolution, for: value.request) else {
            pending[requestID] = value
            return .invalidResolution
        }
        completed[requestID] = resolution
        value.continuation.resume(returning: resolution)
        return .resolved
    }

    @discardableResult
    public func cancel(runID: String) -> Int {
        let ids = pending.values.filter { $0.request.runID == runID }.map { $0.request.id }
        for id in ids { cancel(requestID: id, throwing: false) }
        return ids.count
    }

    @discardableResult
    public func cancelAll() -> Int {
        let ids = Array(pending.keys)
        for id in ids { cancel(requestID: id, throwing: false) }
        return ids.count
    }

    public func pendingRequests() -> [FamiliarClarificationRequest] {
        pending.values.map(\.request)
    }

    private func cancel(requestID: UUID, throwing: Bool) {
        guard let value = pending.removeValue(forKey: requestID) else { return }
        completed[requestID] = .cancelled
        if throwing {
            value.continuation.resume(throwing: CancellationError())
        } else {
            value.continuation.resume(returning: .cancelled)
        }
    }

    private static func isValid(_ resolution: FamiliarClarificationResolution, for request: FamiliarClarificationRequest) -> Bool {
        switch resolution {
        case .selectedOption(let id, let label):
            return request.options.contains { $0.id == id && $0.label == label }
        case .custom(let text):
            return request.allowCustom && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .cancelled, .interrupted:
            return true
        }
    }
}
