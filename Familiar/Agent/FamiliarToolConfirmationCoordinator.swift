import Foundation

/// The decision delivered to an agent after a confirmation request finishes.
nonisolated public enum FamiliarToolConfirmationDecision: Sendable, Equatable {
    case confirmedOnce
    case confirmed
    case confirmedAlways
    case cancelled

    var authorizationDuration: FamiliarAuthorizationDuration? {
        switch self {
        case .confirmedOnce: .once
        case .confirmed: .session
        case .confirmedAlways: .always
        case .cancelled: nil
        }
    }

    var isConfirmed: Bool { authorizationDuration != nil }
}

/// The result of attempting to resolve a request from the UI.
nonisolated public enum FamiliarToolConfirmationResolution: Sendable, Equatable {
    case confirmed
    case cancelled
    case alreadyResolved(FamiliarToolConfirmationDecision)
    case unknownRequest
}

nonisolated public enum FamiliarToolConfirmationError: Error, Sendable, Equatable {
    /// The request's idempotency key was resolved before this request was made.
    case alreadyResolved(FamiliarToolConfirmationDecision)
    /// Another request with the same run/tool-call idempotency key is waiting.
    case alreadyPending
}

/// A value that can safely cross the AgentLoop/SwiftUI boundary.
nonisolated public struct FamiliarToolConfirmationRequest: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let runID: String
    public let toolCallID: String
    public let toolName: String
    public let effect: FamiliarToolEffect
    public let risk: FamiliarToolRisk
    public let title: String
    public let fields: [FamiliarApprovalField]
    public let target: String?
    public let consequence: String
    public let undoPolicy: FamiliarApprovalUndoPolicy
    public let automaticAuthorization: Bool
    public let automaticAuthorizationScope: FamiliarAuthorizationDuration?

    nonisolated public init(
        id: UUID = UUID(),
        runID: String,
        toolCallID: String,
        toolName: String,
        effect: FamiliarToolEffect = .read,
        risk: FamiliarToolRisk = .low,
        title: String,
        fields: [FamiliarApprovalField] = [],
        target: String? = nil,
        consequence: String = "",
        undoPolicy: FamiliarApprovalUndoPolicy = .unavailable,
        automaticAuthorization: Bool = false,
        automaticAuthorizationScope: FamiliarAuthorizationDuration? = nil
    ) {
        self.id = id
        self.runID = runID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.effect = effect
        self.risk = risk
        self.title = title
        self.fields = fields
        self.target = target
        self.consequence = consequence
        self.undoPolicy = undoPolicy
        self.automaticAuthorization = automaticAuthorization
        self.automaticAuthorizationScope = automaticAuthorizationScope
    }
}

/// Coordinates one-shot tool confirmations without depending on SwiftUI.
public actor FamiliarToolConfirmationCoordinator {
    private struct IdempotencyKey: Hashable, Sendable {
        let runID: String
        let toolCallID: String
    }

    private struct PendingRequest {
        let request: FamiliarToolConfirmationRequest
        let key: IdempotencyKey
        let continuation: CheckedContinuation<FamiliarToolConfirmationDecision, Error>
    }

    private var pendingByID: [UUID: PendingRequest] = [:]
    private var pendingIDByKey: [IdempotencyKey: UUID] = [:]
    private var completedByKey: [IdempotencyKey: FamiliarToolConfirmationDecision] = [:]
    private var completedByRequestID: [UUID: FamiliarToolConfirmationDecision] = [:]

    public init() {}

    /// Suspends until the UI calls `resolve`, or until the request is cancelled.
    /// A task cancelled while waiting is removed and cannot later be confirmed.
    public func requestConfirmation(
        _ request: FamiliarToolConfirmationRequest
    ) async throws -> FamiliarToolConfirmationDecision {
        let key = IdempotencyKey(runID: request.runID, toolCallID: request.toolCallID)

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<FamiliarToolConfirmationDecision, Error>) in
                if let completedDecision = completedByKey[key] {
                    continuation.resume(throwing: FamiliarToolConfirmationError.alreadyResolved(completedDecision))
                    return
                }

                if pendingIDByKey[key] != nil {
                    continuation.resume(throwing: FamiliarToolConfirmationError.alreadyPending)
                    return
                }

                if Task.isCancelled {
                    completedByKey[key] = .cancelled
                    completedByRequestID[request.id] = .cancelled
                    continuation.resume(throwing: CancellationError())
                    return
                }

                pendingByID[request.id] = PendingRequest(
                    request: request,
                    key: key,
                    continuation: continuation
                )
                pendingIDByKey[key] = request.id
            }
        }, onCancel: {
            Task {
                await self.cancelWaitingTask(requestID: request.id)
            }
        })
    }

    /// Resolves a pending request exactly once. Repeated attempts never confirm it again.
    @discardableResult
    public func resolve(
        requestID: UUID,
        decision: FamiliarToolConfirmationDecision
    ) -> FamiliarToolConfirmationResolution {
        guard let pending = pendingByID.removeValue(forKey: requestID) else {
            if let previousDecision = completedByRequestID[requestID] {
                return .alreadyResolved(previousDecision)
            }
            return .unknownRequest
        }

        pendingIDByKey.removeValue(forKey: pending.key)
        if let previousDecision = completedByKey[pending.key] {
            return .alreadyResolved(previousDecision)
        }

        completedByKey[pending.key] = decision
        completedByRequestID[requestID] = decision
        pending.continuation.resume(returning: decision)
        return decision.isConfirmed ? .confirmed : .cancelled
    }

    /// Cancels every pending request belonging to a run. Cancellation is never confirmation.
    @discardableResult
    public func cancel(runID: String) -> Int {
        let ids = pendingByID.values
            .filter { $0.request.runID == runID }
            .map { $0.request.id }

        for requestID in ids {
            cancelPending(requestID: requestID, error: nil)
        }
        return ids.count
    }

    /// Cancels all pending requests. Completed keys remain remembered for idempotency.
    @discardableResult
    public func cancelAll() -> Int {
        let ids = Array(pendingByID.keys)
        for requestID in ids {
            cancelPending(requestID: requestID, error: nil)
        }
        return ids.count
    }

    /// The current requests are snapshots and can be consumed directly by SwiftUI.
    public func pendingRequests() -> [FamiliarToolConfirmationRequest] {
        pendingByID.values.map(\.request)
    }

    private func cancelWaitingTask(requestID: UUID) {
        cancelPending(requestID: requestID, error: CancellationError())
    }

    private func cancelPending(requestID: UUID, error: (any Error)?) {
        guard let pending = pendingByID.removeValue(forKey: requestID) else { return }

        pendingIDByKey.removeValue(forKey: pending.key)
        completedByKey[pending.key] = .cancelled
        completedByRequestID[requestID] = .cancelled

        if let error {
            pending.continuation.resume(throwing: error)
        } else {
            pending.continuation.resume(returning: .cancelled)
        }
    }
}
