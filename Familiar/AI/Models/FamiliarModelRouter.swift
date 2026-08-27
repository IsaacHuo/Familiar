import Foundation

nonisolated enum FamiliarModelRouteTarget: String, Codable, Sendable {
    case local
    case cloud
}

nonisolated enum FamiliarModelEscalationReason: String, Codable, Sendable {
    case localUnavailable
    case localGenerationFailed
    case unsupportedCapability
    case contextTooLarge
    case modelRequested
}

nonisolated enum FamiliarModelRoutingError: LocalizedError, Sendable {
    case localUnavailable
    case cloudUnavailable
    case cloudEscalationDenied

    var errorDescription: String? {
        switch self {
        case .localUnavailable:
            "本地模型尚未准备好。"
        case .cloudUnavailable:
            "DeepSeek 尚未配置。"
        case .cloudEscalationDenied:
            "已取消将当前任务交给 DeepSeek。"
        }
    }
}

nonisolated struct FamiliarModelEscalationRequest: Sendable {
    let reason: FamiliarModelEscalationReason
    let localProviderID: String?
    let cloudProviderID: String
    let modelID: String
    let messageCount: Int
    let includesDocuments: Bool
    let includesImages: Bool
}

nonisolated struct FamiliarModelRouter: FamiliarModelProvider, Sendable {
    typealias CloudAuthorizer = @Sendable (FamiliarModelEscalationRequest) async -> Bool

    let policy: FamiliarModelRoutePolicy
    let localProvider: (any FamiliarModelProvider)?
    let cloudProvider: (any FamiliarModelProvider)?
    let authorizeCloudEscalation: CloudAuthorizer

    var providerID: String { "model-router" }

    init(
        policy: FamiliarModelRoutePolicy,
        localProvider: (any FamiliarModelProvider)? = nil,
        cloudProvider: (any FamiliarModelProvider)? = nil,
        authorizeCloudEscalation: @escaping CloudAuthorizer = { _ in false }
    ) {
        self.policy = policy
        self.localProvider = localProvider
        self.cloudProvider = cloudProvider
        self.authorizeCloudEscalation = authorizeCloudEscalation
    }

    func stream(
        request: FamiliarModelRequest
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch policy {
                    case .localOnly:
                        guard let localProvider else {
                            throw FamiliarModelRoutingError.localUnavailable
                        }
                        try await Self.forward(
                            localProvider.stream(request: request),
                            to: continuation
                        )

                    case .cloud:
                        guard let cloudProvider else {
                            throw FamiliarModelRoutingError.cloudUnavailable
                        }
                        try await Self.forward(
                            cloudProvider.stream(request: request),
                            to: continuation
                        )

                    case .preferLocal:
                        try await streamPreferLocal(request: request, continuation: continuation)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func streamPreferLocal(
        request: FamiliarModelRequest,
        continuation: AsyncThrowingStream<FamiliarModelStreamEvent, Error>.Continuation
    ) async throws {
        guard let localProvider else {
            try await escalate(
                request: request,
                reason: .localUnavailable,
                continuation: continuation
            )
            return
        }

        var emittedContent = false
        do {
            for try await event in localProvider.stream(request: request) {
                try Task.checkCancellation()
                switch event {
                case .textDelta, .reasoningSummaryDelta, .toolCallDelta:
                    emittedContent = true
                case .completed:
                    break
                }
                continuation.yield(event)
            }
        } catch {
            guard !emittedContent else { throw error }
            try await escalate(
                request: request,
                reason: .localGenerationFailed,
                continuation: continuation
            )
        }
    }

    private func escalate(
        request: FamiliarModelRequest,
        reason: FamiliarModelEscalationReason,
        continuation: AsyncThrowingStream<FamiliarModelStreamEvent, Error>.Continuation
    ) async throws {
        guard let cloudProvider else {
            throw FamiliarModelRoutingError.cloudUnavailable
        }
        let content = request.messages.flatMap(\.contentParts)
        let escalation = FamiliarModelEscalationRequest(
            reason: reason,
            localProviderID: localProvider?.providerID,
            cloudProviderID: cloudProvider.providerID,
            modelID: request.model,
            messageCount: request.messages.count,
            includesDocuments: content.contains { part in
                if case .document = part { true } else { false }
            },
            includesImages: content.contains { part in
                if case .image = part { true } else { false }
            }
        )
        guard await authorizeCloudEscalation(escalation) else {
            throw FamiliarModelRoutingError.cloudEscalationDenied
        }
        try await Self.forward(
            cloudProvider.stream(request: request),
            to: continuation
        )
    }

    private static func forward(
        _ stream: AsyncThrowingStream<FamiliarModelStreamEvent, Error>,
        to continuation: AsyncThrowingStream<FamiliarModelStreamEvent, Error>.Continuation
    ) async throws {
        for try await event in stream {
            try Task.checkCancellation()
            continuation.yield(event)
        }
    }
}
