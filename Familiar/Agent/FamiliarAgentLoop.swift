import Foundation

nonisolated enum FamiliarRunPhase: Equatable, Sendable {
    case starting
    case reasoning
    case responding
    case executingActivities([String])
    case awaitingApproval
    case awaitingClarification
}

nonisolated enum FamiliarRunOutcomeStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case cancelled
    case failed
}

nonisolated struct FamiliarRunOutcome: Codable, Equatable, Sendable {
    let status: FamiliarRunOutcomeStatus
    let failureKind: FamiliarRuntimeFailureKind?
    let message: String?

    static let succeeded = FamiliarRunOutcome(status: .succeeded, failureKind: nil, message: nil)

    static func cancelled(message: String? = nil) -> FamiliarRunOutcome {
        .init(status: .cancelled, failureKind: .cancelled, message: message)
    }

    static func failed(_ error: any Error) -> FamiliarRunOutcome {
        .init(status: .failed, failureKind: FamiliarRuntimeFailure.kind(for: error), message: error.localizedDescription)
    }
}

nonisolated struct FamiliarRuntimeActivity: Identifiable, Equatable, Sendable {
    let id: String
    let toolName: String
    let effect: FamiliarToolEffect
    let startedAt: Date
}

nonisolated struct FamiliarRuntimeActivityProgress: Identifiable, Equatable, Sendable {
    let id: String
    let fractionCompleted: Double?
    let detail: String?
}

nonisolated struct FamiliarRuntimeActivityCompletion: Sendable {
    let runID: String
    let toolCallID: String
    let toolName: String
    let effect: FamiliarToolEffect
    let assistantTurnID: String
    let detail: String
    let confirmation: FamiliarPersistedConfirmationResult
    let status: FamiliarToolRunTerminalStatus
    let startedAt: Date
    let finishedAt: Date
    let artifactIdentifier: String?
    let undoAvailable: Bool
    let automaticApprovalRequest: FamiliarToolConfirmationRequest?

    init(runID: String, toolCallID: String, toolName: String, effect: FamiliarToolEffect, assistantTurnID: String, detail: String, confirmation: FamiliarPersistedConfirmationResult, status: FamiliarToolRunTerminalStatus, startedAt: Date, finishedAt: Date, artifactIdentifier: String?, undoAvailable: Bool, automaticApprovalRequest: FamiliarToolConfirmationRequest?) {
        self.runID = runID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.effect = effect
        self.assistantTurnID = assistantTurnID
        self.detail = detail
        self.confirmation = confirmation
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.artifactIdentifier = artifactIdentifier
        self.undoAvailable = undoAvailable
        self.automaticApprovalRequest = automaticApprovalRequest
    }
}

nonisolated struct FamiliarToolResultProduced: Sendable {
    let runID: String
    let toolCallID: String
    let toolName: String
    let effect: FamiliarToolEffect
    let assistantTurnID: String
    let envelope: FamiliarToolResultEnvelope
    let sources: [FamiliarSource]
    let webCaptures: [FamiliarWebCapture]
    let artifact: FamiliarArtifactDescriptor?
    let producedAt: Date
}

nonisolated enum FamiliarRuntimeNoticeKind: String, Codable, Equatable, Sendable {
    case retrying
}

nonisolated struct FamiliarRuntimeNotice: Equatable, Sendable {
    let kind: FamiliarRuntimeNoticeKind
    let attempt: Int
    let delay: TimeInterval
    let failureKind: FamiliarRuntimeFailureKind
}

nonisolated enum FamiliarRuntimeEventPayload: Sendable {
    case runPhaseChanged(FamiliarRunPhase)
    case assistantTurnStarted(id: String, index: Int)
    case responseTextDelta(String)
    case reasoningSummaryDelta(String)
    case reasoningSummaryCompleted(String)
    case activityStarted(FamiliarRuntimeActivity)
    case activityProgress(FamiliarRuntimeActivityProgress)
    case activityCompleted(FamiliarRuntimeActivityCompletion)
    case toolInvocationRequested(id: String, name: String, arguments: String, effect: FamiliarToolEffect)
    case toolResultProduced(FamiliarToolResultProduced)
    case approvalRequested(FamiliarToolConfirmationRequest)
    case approvalResolved(requestID: UUID, decision: FamiliarToolConfirmationDecision)
    case clarificationRequested(FamiliarClarificationRequest)
    case clarificationResolved(requestID: UUID, resolution: FamiliarClarificationResolution)
    case runtimeNotice(FamiliarRuntimeNotice)
    case responseCompleted(FamiliarCompletedResponse)
    case runFinished(FamiliarRunOutcome)
}

nonisolated struct FamiliarRuntimeEvent: Sendable {
    let runID: String
    let sequence: Int
    let timestamp: Date
    let assistantTurnID: String?
    let payload: FamiliarRuntimeEventPayload
}

private actor FamiliarRuntimeEventEmitter {
    private let runID: String
    private var sequence = 0
    private var assistantTurnID: String?
    private let continuation: AsyncThrowingStream<FamiliarRuntimeEvent, Error>.Continuation

    init(runID: String, continuation: AsyncThrowingStream<FamiliarRuntimeEvent, Error>.Continuation) {
        self.runID = runID
        self.continuation = continuation
    }

    func emit(_ payload: FamiliarRuntimeEventPayload) {
        continuation.yield(.init(runID: runID, sequence: sequence, timestamp: Date(), assistantTurnID: assistantTurnID, payload: payload))
        sequence += 1
    }

    func beginAssistantTurn(_ id: String) {
        assistantTurnID = id
    }
}

actor FamiliarUndoStore {
    private var actions: [String: @Sendable () async throws -> FamiliarToolExecutionResult] = [:]
    func register(key: String, action: @escaping @Sendable () async throws -> FamiliarToolExecutionResult) { actions[key] = action }
    func execute(key: String) async throws -> FamiliarToolExecutionResult {
        guard let action = actions.removeValue(forKey: key) else { throw FamiliarEventKitError.undoUnavailable }
        return try await action()
    }
    func clear() { actions.removeAll() }
}

nonisolated enum FamiliarAgentError: LocalizedError, Sendable {
    case emptyResponse, invalidToolCall, incompleteResponse, maxIterationsExceeded
    case contextTooLarge, toolArgumentsTooLarge, toolResultTooLarge
    case maxToolCallsExceeded, durationExceeded

    var errorDescription: String? {
        switch self {
        case .emptyResponse: String(localized: "error.agent.empty_response")
        case .invalidToolCall: String(localized: "error.agent.invalid_tool_call")
        case .incompleteResponse: String(localized: "error.agent.incomplete_response")
        case .maxIterationsExceeded: String(localized: "error.agent.max_iterations")
        case .contextTooLarge: String(localized: "error.message.context_too_large")
        case .toolArgumentsTooLarge: String(localized: "error.agent.tool_arguments_too_large")
        case .toolResultTooLarge: String(localized: "error.agent.tool_result_too_large")
        case .maxToolCallsExceeded: String(localized: "error.agent.max_tool_calls")
        case .durationExceeded: String(localized: "error.agent.duration_exceeded")
        }
    }
}

nonisolated struct FamiliarAgentLoop: Sendable {
    private let provider: any FamiliarModelProvider
    private let registry: FamiliarToolRegistry
    private let policy: FamiliarExecutionPolicy
    private let confirmationCoordinator: FamiliarToolConfirmationCoordinator
    private let clarificationCoordinator: FamiliarClarificationCoordinator
    private let undoStore: FamiliarUndoStore
    private let authorizationRuntime: (any FamiliarAuthorizationServicing)?
    private let maximumIterations: Int
    private let maximumAttemptsPerRound: Int
    private let maximumToolCalls: Int
    private let maximumDuration: TimeInterval

    init(
        provider: any FamiliarModelProvider,
        registry: FamiliarToolRegistry,
        policy: FamiliarExecutionPolicy,
        confirmationCoordinator: FamiliarToolConfirmationCoordinator,
        clarificationCoordinator: FamiliarClarificationCoordinator = FamiliarClarificationCoordinator(),
        undoStore: FamiliarUndoStore,
        authorizationRuntime: (any FamiliarAuthorizationServicing)? = nil,
        maximumIterations: Int = 6,
        maximumAttemptsPerRound: Int = 2,
        maximumToolCalls: Int = 12,
        maximumDuration: TimeInterval = 180
    ) {
        self.provider = provider
        self.registry = registry
        self.policy = policy
        self.confirmationCoordinator = confirmationCoordinator
        self.clarificationCoordinator = clarificationCoordinator
        self.undoStore = undoStore
        self.authorizationRuntime = authorizationRuntime
        self.maximumIterations = maximumIterations
        self.maximumAttemptsPerRound = maximumAttemptsPerRound
        self.maximumToolCalls = maximumToolCalls
        self.maximumDuration = maximumDuration
    }

    func stream(
        contextSnapshot: FamiliarContextSnapshot
    ) -> AsyncThrowingStream<FamiliarRuntimeEvent, Error> {
        let runID = UUID().uuidString
        return AsyncThrowingStream { continuation in
            let emitter = FamiliarRuntimeEventEmitter(runID: runID, continuation: continuation)
            let task = Task {
                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(maximumDuration))
                await emitter.emit(.runPhaseChanged(.starting))
                do {
                    try await run(
                        runID: runID,
                        contextSnapshot: contextSnapshot,
                        emitter: emitter,
                        deadline: deadline
                    )
                    await emitter.emit(.runFinished(.succeeded))
                } catch is CancellationError {
                    await confirmationCoordinator.cancel(runID: runID)
                    await clarificationCoordinator.cancel(runID: runID)
                    await emitter.emit(.runFinished(.cancelled()))
                } catch {
                    await confirmationCoordinator.cancel(runID: runID)
                    await clarificationCoordinator.cancel(runID: runID)
                    await emitter.emit(.runFinished(.failed(error)))
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func run(
        runID: String,
        contextSnapshot: FamiliarContextSnapshot,
        emitter: FamiliarRuntimeEventEmitter,
        deadline: ContinuousClock.Instant
    ) async throws {
        let manifests = contextSnapshot.toolManifests
        let manifestsByName = Dictionary(uniqueKeysWithValues: manifests.map { ($0.name, $0) })
        var messages = contextSnapshot.providerMessages

        var visibleResponse = ""
        var collectedSources: [FamiliarSource] = []
        var seenFingerprints: Set<String> = []
        var executedToolCalls = 0
        await emitter.emit(.runPhaseChanged(.reasoning))

        for iteration in 0..<maximumIterations {
            try Task.checkCancellation()
            try Self.checkDeadline(deadline)
            if iteration > 0 { await emitter.emit(.runPhaseChanged(.reasoning)) }
            let characterCount = FamiliarProjectContextAssembler.inputCharacterCount(messages: messages, manifests: manifests)
            guard characterCount <= contextSnapshot.maximumInputCharacters else { throw FamiliarAgentError.contextTooLarge }

            let assistantTurnID = "\(runID):turn:\(iteration)"
            await emitter.beginAssistantTurn(assistantTurnID)
            await emitter.emit(.assistantTurnStarted(id: assistantTurnID, index: iteration))
            let request = FamiliarModelRequest(model: contextSnapshot.modelID, messages: messages, tools: manifests)
            let round = try await streamRound(request: request, emitter: emitter, deadline: deadline)
            visibleResponse += round.text
            if round.finishReason == .length || round.finishReason == .unknown { throw FamiliarAgentError.incompleteResponse }
            let calls = try round.pendingCalls.sorted { $0.key < $1.key }.map { try $0.value.completed() }
            guard !calls.isEmpty else {
                let answer = visibleResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !answer.isEmpty else { throw FamiliarAgentError.emptyResponse }
                await emitter.emit(.responseCompleted(.init(text: answer, sources: collectedSources)))
                return
            }

            messages.append(.assistant(round.text.isEmpty ? nil : round.text, toolCalls: calls))
            await emitter.emit(.runPhaseChanged(.executingActivities(calls.map(\.name))))
            var prepared: [PreparedToolCall] = []
            var toolMessages: [Int: FamiliarProviderMessage] = [:]
            for (index, call) in calls.enumerated() {
                try Task.checkCancellation()
                try Self.checkDeadline(deadline)
                let startedAt = Date()
                guard let manifest = manifestsByName[call.name] else {
                    throw FamiliarToolRegistryError.toolNotFound(call.name)
                }
                let fingerprint = call.name + "|" + FamiliarAuthorizationGrant.argumentsHash(call.arguments)
                await emitter.emit(.toolInvocationRequested(id: call.id, name: call.name, arguments: call.arguments, effect: manifest.effect))
                await emitter.emit(.activityStarted(.init(id: call.id, toolName: call.name, effect: manifest.effect, startedAt: startedAt)))
                guard seenFingerprints.insert(fingerprint).inserted else {
                    let detail = String(localized: "error.tool.duplicate_call")
                    let completion = activityCompletion(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID, detail: detail, confirmation: .notRequired, status: .failed, startedAt: startedAt)
                    await emitter.emit(.activityCompleted(completion))
                    toolMessages[index] = .tool(Self.errorResult(code: "duplicate_tool_call", retryable: false, message: detail), toolCallID: call.id, name: call.name)
                    continue
                }
                guard executedToolCalls < maximumToolCalls else { throw FamiliarAgentError.maxToolCallsExceeded }
                executedToolCalls += 1
                prepared.append(.init(index: index, call: call, manifest: manifest, startedAt: startedAt))
            }

            var cursor = 0
            while cursor < prepared.count {
                let current = prepared[cursor]
                if try await canRunInParallel(current, projectID: contextSnapshot.projectID, deadline: deadline) {
                    var batch = [current]
                    if cursor + 1 < prepared.count,
                       try await canRunInParallel(prepared[cursor + 1], projectID: contextSnapshot.projectID, deadline: deadline) {
                        batch.append(prepared[cursor + 1])
                    }
                    let outputs = try await withThrowingTaskGroup(of: ToolCallOutput.self) { group in
                        for item in batch {
                            group.addTask {
                                try await executeToolCall(item, runID: runID, assistantTurnID: assistantTurnID, contextSnapshot: contextSnapshot, emitter: emitter, deadline: deadline)
                            }
                        }
                        var values: [ToolCallOutput] = []
                        for try await value in group { values.append(value) }
                        return values.sorted { $0.index < $1.index }
                    }
                    for output in outputs {
                        toolMessages[output.index] = output.message
                        collectedSources = Self.mergingSources(collectedSources, with: output.sources)
                    }
                    cursor += batch.count
                } else {
                    let output = try await executeToolCall(current, runID: runID, assistantTurnID: assistantTurnID, contextSnapshot: contextSnapshot, emitter: emitter, deadline: deadline)
                    toolMessages[output.index] = output.message
                    collectedSources = Self.mergingSources(collectedSources, with: output.sources)
                    cursor += 1
                }
            }
            for index in calls.indices {
                guard let message = toolMessages[index] else { throw FamiliarAgentError.incompleteResponse }
                messages.append(message)
            }
        }
        throw FamiliarAgentError.maxIterationsExceeded
    }

    private func streamRound(
        request: FamiliarModelRequest,
        emitter: FamiliarRuntimeEventEmitter,
        deadline: ContinuousClock.Instant
    ) async throws -> RoundResult {
        var attempt = 0
        while true {
            attempt += 1
            do {
                let result = try await Self.withDeadline(deadline) {
                    var emittedContent = false
                    var pendingCalls: [Int: PendingToolCall] = [:]
                    var roundText = ""
                    var reasoningSummary = ""
                    var roundIsResponding = false
                    var finishReason: FamiliarModelFinishReason?
                    do {
                        for try await event in provider.stream(request: request) {
                            try Task.checkCancellation()
                            switch event {
                            case .textDelta(let value):
                                emittedContent = true
                                if !roundIsResponding {
                                    roundIsResponding = true
                                    await emitter.emit(.runPhaseChanged(.responding))
                                }
                                roundText += value
                                await emitter.emit(.responseTextDelta(value))
                            case .reasoningSummaryDelta(let value):
                                emittedContent = true
                                reasoningSummary += value
                                await emitter.emit(.reasoningSummaryDelta(value))
                            case .toolCallDelta(let index, let id, let name, let arguments):
                                emittedContent = true
                                var call = pendingCalls[index] ?? PendingToolCall()
                                if let id, !id.isEmpty { call.id = id }
                                if let name { call.name += name }
                                if let arguments { call.arguments += arguments }
                                pendingCalls[index] = call
                            case .completed(let reason):
                                finishReason = reason
                            }
                        }
                        return RoundResult(text: roundText, reasoningSummary: reasoningSummary, pendingCalls: pendingCalls, finishReason: finishReason)
                    } catch {
                        throw RoundAttemptError(underlying: error, emittedContent: emittedContent)
                    }
                }
                if !result.reasoningSummary.isEmpty {
                    await emitter.emit(.reasoningSummaryCompleted(result.reasoningSummary))
                }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as RoundAttemptError {
                let error = failure.underlying
                guard attempt < maximumAttemptsPerRound, !failure.emittedContent else { throw error }
                let kind = FamiliarRuntimeFailure.kind(for: error)
                guard kind.isRetryable else { throw error }
                let delay = Self.retryDelay(attempt: attempt)
                await emitter.emit(.runtimeNotice(.init(kind: .retrying, attempt: attempt + 1, delay: delay, failureKind: kind)))
                try await Self.sleep(for: delay, deadline: deadline)
            } catch {
                throw error
            }
        }
    }

    private func canRunInParallel(_ item: PreparedToolCall, projectID: UUID?, deadline: ContinuousClock.Instant) async throws -> Bool {
        guard item.manifest.effect == .read, item.manifest.supportsParallelism else { return false }
        let availability = try await Self.withDeadline(deadline) {
            await registry.availability(for: item.manifest)
        }
        return policy.decide(manifest: item.manifest, availability: availability, grant: nil, arguments: item.call.arguments, projectID: projectID) == .execute
    }

    private func executeToolCall(
        _ item: PreparedToolCall,
        runID: String,
        assistantTurnID: String,
        contextSnapshot: FamiliarContextSnapshot,
        emitter: FamiliarRuntimeEventEmitter,
        deadline: ContinuousClock.Instant
    ) async throws -> ToolCallOutput {
        let call = item.call
        let manifest = item.manifest
        var automaticApprovalRequest: FamiliarToolConfirmationRequest?
        do {
            await emitter.emit(.activityProgress(.init(id: call.id, fractionCompleted: nil, detail: nil)))
            let availability = try await Self.withDeadline(deadline) {
                await registry.availability(for: manifest)
            }
            let decision = policy.decide(manifest: manifest, availability: availability, grant: nil, arguments: call.arguments, projectID: contextSnapshot.projectID)
            if case .deny(let reason) = decision { throw FamiliarToolRegistryError.capabilityUnavailable(reason) }
            if manifest.effect == .read, decision == .requestApproval {
                let fields = [FamiliarApprovalField(id: "access_scope", label: "access_scope", type: .text, value: manifest.description)]
                guard try await approve(runID: runID, call: call, effect: manifest.effect, risk: manifest.risk, title: call.name, fields: fields, target: nil, consequence: manifest.description, undoPolicy: .unavailable, emitter: emitter, deadline: deadline).isConfirmed else {
                    let completion = activityCompletion(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID, detail: String(localized: "tool.cancelled_by_user"), confirmation: .cancelled, status: .cancelled, startedAt: item.startedAt)
                    await emitter.emit(.activityCompleted(completion))
                    return .init(index: item.index, message: .tool(Self.cancelledResult(), toolCallID: call.id, name: call.name), sources: [])
                }
            }
            if manifest.effect == .read {
                try await Self.withDeadline(deadline) {
                    try await registry.prepareCapabilities(for: manifest)
                }
            }
            let resources = contextSnapshot.resources.map {
                FamiliarToolContext.Resource(id: $0.resourceID, versionID: $0.resourceVersionID, version: $0.version, displayName: $0.displayName, filename: $0.filename, mimeType: $0.mimeType, contentHash: $0.contentHash, extractedText: $0.extractedText)
            }
            let attachments = contextSnapshot.attachments.map {
                FamiliarToolContext.Attachment(id: $0.id, kind: $0.kind, filename: $0.filename, mimeType: $0.mimeType, relativePath: $0.relativePath, extractedText: $0.extractedText, byteSize: $0.byteSize)
            }
            let workspaceID: FamiliarWorkspaceID = contextSnapshot.projectID.map(FamiliarWorkspaceID.project)
                ?? .conversation(contextSnapshot.conversationID)
            let toolContext = FamiliarToolContext(
                runID: runID,
                toolCallID: call.id,
                projectID: contextSnapshot.projectID,
                conversationID: contextSnapshot.conversationID,
                workspaceID: workspaceID,
                resources: resources,
                attachments: attachments
            )
            let outcome = try await executeOutcome(
                name: call.name,
                arguments: call.arguments,
                context: toolContext,
                allowsRetry: manifest.effect == .read,
                emitter: emitter,
                deadline: deadline
            )
            var undoAvailable = false
            let resolved: (FamiliarToolExecutionResult, FamiliarPersistedConfirmationResult)
            switch outcome {
            case .result(let result):
                resolved = (result, manifest.effect == .read && decision == .requestApproval ? .confirmed : .notRequired)
            case .action(let proposal):
                let authorizationScope: FamiliarAuthorizationDuration? = if manifest.effect == .reversibleWrite, manifest.risk != .high, let authorizationRuntime {
                    await authorizationRuntime.matchingAuthorizationScope(manifest: manifest, arguments: call.arguments, projectID: contextSnapshot.projectID, targetKey: proposal.targetKey)
                } else {
                    nil
                }
                let hasGrant = authorizationScope != nil
                let approvalDecision: FamiliarToolConfirmationDecision
                if hasGrant {
                    approvalDecision = .confirmed
                    automaticApprovalRequest = FamiliarToolConfirmationRequest(runID: runID, toolCallID: call.id, toolName: call.name, effect: manifest.effect, risk: manifest.risk, title: proposal.title, fields: proposal.fields, target: proposal.target, consequence: proposal.consequence, undoPolicy: proposal.undoPolicy, automaticAuthorization: true, automaticAuthorizationScope: authorizationScope)
                } else {
                    approvalDecision = try await approve(runID: runID, call: call, effect: manifest.effect, risk: manifest.risk, title: proposal.title, fields: proposal.fields, target: proposal.target, consequence: proposal.consequence, undoPolicy: proposal.undoPolicy, emitter: emitter, deadline: deadline)
                }
                guard approvalDecision.isConfirmed else {
                    let completion = activityCompletion(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID, detail: String(localized: "tool.cancelled_by_user"), confirmation: .cancelled, status: .cancelled, startedAt: item.startedAt)
                    await emitter.emit(.activityCompleted(completion))
                    return .init(index: item.index, message: .tool(Self.cancelledResult(), toolCallID: call.id, name: call.name), sources: [])
                }
                if !hasGrant, let duration = approvalDecision.authorizationDuration, let authorizationRuntime {
                    try await authorizationRuntime.issueAuthorization(duration: duration, manifest: manifest, arguments: call.arguments, projectID: contextSnapshot.projectID, targetKey: proposal.targetKey, evidence: proposal.title)
                }
                if manifest.effect != .read {
                    try await Self.withDeadline(deadline) {
                        try await registry.prepareCapabilities(for: manifest)
                    }
                }
                let committed = try await Self.withDeadline(deadline) { try await proposal.commit() }
                if let undo = committed.undo {
                    undoAvailable = true
                    await undoStore.register(key: proposal.idempotencyKey, action: undo)
                }
                resolved = (committed.result, hasGrant ? .notRequired : .confirmed)
            case .clarification(let proposal):
                let request = FamiliarClarificationRequest(
                    runID: runID,
                    toolCallID: call.id,
                    question: proposal.question,
                    options: proposal.options,
                    allowCustom: proposal.allowCustom
                )
                await emitter.emit(.runPhaseChanged(.awaitingClarification))
                await emitter.emit(.clarificationRequested(request))
                let resolution = try await Self.withDeadline(deadline) {
                    try await clarificationCoordinator.requestClarification(request)
                }
                await emitter.emit(.clarificationResolved(requestID: request.id, resolution: resolution))
                guard let answer = resolution.answer else { throw CancellationError() }
                await emitter.emit(.runPhaseChanged(.executingActivities([call.name])))
                let model = FamiliarClarificationModelResult(
                    answer: answer,
                    optionID: resolution.optionID,
                    custom: resolution.isCustom
                )
                let envelope = try FamiliarToolResultEnvelope(
                    model: model,
                    presentation: .scalar(.init(summary: String(localized: "clarification.answered", defaultValue: "Clarification answered"), label: proposal.question, value: answer))
                )
                resolved = (.init(envelope: envelope), .notRequired)
            }
            guard resolved.0.modelContent.count <= 48_000 else { throw FamiliarAgentError.toolResultTooLarge }
            let finishedAt = Date()
            let completion = activityCompletion(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID, detail: "", confirmation: resolved.1, status: .succeeded, startedAt: item.startedAt, finishedAt: finishedAt, artifactIdentifier: resolved.0.artifactIdentifier, undoAvailable: undoAvailable, automaticApprovalRequest: automaticApprovalRequest)
            await emitter.emit(.activityCompleted(completion))
            await emitter.emit(.toolResultProduced(.init(runID: runID, toolCallID: call.id, toolName: call.name, effect: manifest.effect, assistantTurnID: assistantTurnID, envelope: resolved.0.envelope, sources: resolved.0.sources, webCaptures: resolved.0.webCaptures, artifact: resolved.0.artifact, producedAt: finishedAt)))
            return .init(index: item.index, message: .tool(resolved.0.modelContent, toolCallID: call.id, name: call.name), sources: resolved.0.sources)
        } catch is CancellationError {
            throw CancellationError()
        } catch FamiliarAgentError.durationExceeded {
            throw FamiliarAgentError.durationExceeded
        } catch {
            let completion = activityCompletion(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID, detail: error.localizedDescription, confirmation: .notRequired, status: .failed, startedAt: item.startedAt, automaticApprovalRequest: automaticApprovalRequest)
            await emitter.emit(.activityCompleted(completion))
            return .init(index: item.index, message: .tool(Self.errorResult(error), toolCallID: call.id, name: call.name), sources: [])
        }
    }

    private func executeOutcome(
        name: String,
        arguments: String,
        context: FamiliarToolContext,
        allowsRetry: Bool,
        emitter: FamiliarRuntimeEventEmitter,
        deadline: ContinuousClock.Instant
    ) async throws -> FamiliarToolOutcome {
        let clock = ContinuousClock()
        let toolDeadline = min(deadline, clock.now.advanced(by: .seconds(30)))
        do {
            return try await Self.withDeadline(toolDeadline) {
                try await registry.execute(name: name, arguments: arguments, context: context)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch FamiliarAgentError.durationExceeded {
            throw FamiliarAgentError.durationExceeded
        } catch {
            let failureKind = FamiliarRuntimeFailure.kind(for: error)
            guard allowsRetry, failureKind.isRetryable else { throw error }
            let delay = Self.retryDelay(attempt: 1)
            await emitter.emit(.runtimeNotice(.init(
                kind: .retrying,
                attempt: 2,
                delay: delay,
                failureKind: failureKind
            )))
            try await Self.sleep(for: delay, deadline: toolDeadline)
            return try await Self.withDeadline(toolDeadline) {
                try await registry.execute(name: name, arguments: arguments, context: context)
            }
        }
    }

    private func approve(runID: String, call: FamiliarToolCall, effect: FamiliarToolEffect, risk: FamiliarToolRisk, title: String, fields: [FamiliarApprovalField], target: String?, consequence: String, undoPolicy: FamiliarApprovalUndoPolicy, emitter: FamiliarRuntimeEventEmitter, deadline: ContinuousClock.Instant) async throws -> FamiliarToolConfirmationDecision {
        let request = FamiliarToolConfirmationRequest(runID: runID, toolCallID: call.id, toolName: call.name, effect: effect, risk: risk, title: title, fields: fields, target: target, consequence: consequence, undoPolicy: undoPolicy)
        await emitter.emit(.runPhaseChanged(.awaitingApproval))
        await emitter.emit(.approvalRequested(request))
        let decision = try await Self.withDeadline(deadline) {
            try await confirmationCoordinator.requestConfirmation(request)
        }
        await emitter.emit(.approvalResolved(requestID: request.id, decision: decision))
        await emitter.emit(.runPhaseChanged(.executingActivities([call.name])))
        return decision
    }

    private func activityCompletion(runID: String, call: FamiliarToolCall, manifest: FamiliarToolManifest, assistantTurnID: String, detail: String, confirmation: FamiliarPersistedConfirmationResult, status: FamiliarToolRunTerminalStatus, startedAt: Date, finishedAt: Date = Date(), artifactIdentifier: String? = nil, undoAvailable: Bool = false, automaticApprovalRequest: FamiliarToolConfirmationRequest? = nil) -> FamiliarRuntimeActivityCompletion {
        .init(runID: runID, toolCallID: call.id, toolName: call.name, effect: manifest.effect, assistantTurnID: assistantTurnID, detail: detail, confirmation: confirmation, status: status, startedAt: startedAt, finishedAt: finishedAt, artifactIdentifier: artifactIdentifier, undoAvailable: undoAvailable, automaticApprovalRequest: automaticApprovalRequest)
    }

    private static func retryDelay(attempt: Int) -> TimeInterval {
        attempt <= 1 ? 0.3 : (attempt == 2 ? 0.8 : 1.5)
    }

    private static func sleep(for delay: TimeInterval, deadline: ContinuousClock.Instant) async throws {
        let clock = ContinuousClock()
        let requested = clock.now.advanced(by: .seconds(delay))
        let wake = min(requested, deadline)
        try await clock.sleep(until: wake)
        try checkDeadline(deadline)
    }

    private static func checkDeadline(_ deadline: ContinuousClock.Instant) throws {
        guard ContinuousClock().now < deadline else { throw FamiliarAgentError.durationExceeded }
    }

    private static func withDeadline<T: Sendable>(_ deadline: ContinuousClock.Instant, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try checkDeadline(deadline)
        let clock = ContinuousClock()
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await clock.sleep(until: deadline)
                throw FamiliarAgentError.durationExceeded
            }
            guard let result = try await group.next() else { throw FamiliarAgentError.durationExceeded }
            group.cancelAll()
            return result
        }
    }

    private static func errorResult(_ error: any Error) -> String {
        if let webError = error as? FamiliarWebError {
            return errorResult(code: webError.code, retryable: webError.isRetryable, message: webError.localizedDescription)
        }
        let kind = FamiliarRuntimeFailure.kind(for: error)
        return errorResult(code: kind.code, retryable: kind.isRetryable, message: error.localizedDescription)
    }

    private static func errorResult(code: String, retryable: Bool, message: String) -> String {
        guard let data = try? JSONEncoder().encode(FamiliarToolFailure(code: code, retryable: retryable, message: message)) else {
            return #"{"code":"tool_failed","message":"Tool failed.","retryable":false}"#
        }
        return FamiliarCanonicalJSON.string(for: String(decoding: data, as: UTF8.self))
    }
    private static func cancelledResult() -> String { #"{"cancelled":true,"reason":"user_cancelled"}"# }

    private static func mergingSources(_ current: [FamiliarSource], with additions: [FamiliarSource]) -> [FamiliarSource] {
        var result = current
        for source in additions {
            if let index = result.firstIndex(where: { $0.url == source.url }) {
                if source.kind == .fetchedPage && result[index].kind == .searchResult {
                    result[index] = source
                }
            } else {
                result.append(source)
            }
        }
        return result
    }

    private struct PreparedToolCall: Sendable {
        let index: Int
        let call: FamiliarToolCall
        let manifest: FamiliarToolManifest
        let startedAt: Date
    }

    private struct ToolCallOutput: Sendable {
        let index: Int
        let message: FamiliarProviderMessage
        let sources: [FamiliarSource]
    }

    private struct RoundResult: Sendable {
        let text: String
        let reasoningSummary: String
        let pendingCalls: [Int: PendingToolCall]
        let finishReason: FamiliarModelFinishReason?
    }

    private struct RoundAttemptError: Error, @unchecked Sendable {
        let underlying: any Error
        let emittedContent: Bool
    }

    private struct PendingToolCall: Sendable {
        var id = "", name = "", arguments = ""
        func completed() throws -> FamiliarToolCall {
            guard !id.isEmpty, !name.isEmpty else { throw FamiliarAgentError.invalidToolCall }
            guard arguments.count <= 16_000 else { throw FamiliarAgentError.toolArgumentsTooLarge }
            return .init(id: id, name: name, arguments: arguments)
        }
    }

    private struct FamiliarClarificationModelResult: Codable, Sendable {
        let answer: String
        let optionID: String?
        let custom: Bool
    }
}

private extension FamiliarClarificationResolution {
    nonisolated var optionID: String? {
        if case .selectedOption(let id, _) = self { return id }
        return nil
    }

    nonisolated var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}
