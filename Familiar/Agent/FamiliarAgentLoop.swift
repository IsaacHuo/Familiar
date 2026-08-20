import Foundation

nonisolated enum FamiliarRuntimeState: Equatable, Sendable {
    case thinking
    case usingTool(String)
    case awaitingApproval
    case responding

    var title: String {
        switch self {
        case .thinking: String(localized: "agent.status.thinking")
        case .usingTool(let title): String(format: String(localized: "agent.status.using_tool"), title)
        case .awaitingApproval: String(localized: "agent.status.awaiting_confirmation")
        case .responding: String(localized: "agent.status.responding")
        }
    }
}

nonisolated enum FamiliarToolProgressState: Equatable, Sendable { case running, succeeded, cancelled, failed }

nonisolated struct FamiliarToolProgress: Identifiable, Equatable, Sendable {
    let id: String
    let toolName: String
    let title: String
    let detail: String?
    let state: FamiliarToolProgressState
    let effect: FamiliarToolEffect
}

nonisolated struct FamiliarToolRunTerminalEvent: Sendable {
    let runID: String
    let toolCallID: String
    let toolName: String
    let effect: FamiliarToolEffect
    let assistantTurnID: String
    let summary: String
    let detail: String
    let confirmation: FamiliarPersistedConfirmationResult
    let status: FamiliarToolRunTerminalStatus
    let startedAt: Date
    let finishedAt: Date
    let artifactIdentifier: String?
    let undoAvailable: Bool
    let sources: [FamiliarSource]
    let webCaptures: [FamiliarWebCapture]
    let artifact: FamiliarArtifactDescriptor?

    init(runID: String, toolCallID: String, toolName: String, effect: FamiliarToolEffect = .read, assistantTurnID: String = "legacy", summary: String, detail: String, confirmation: FamiliarPersistedConfirmationResult, status: FamiliarToolRunTerminalStatus, startedAt: Date, finishedAt: Date, artifactIdentifier: String? = nil, undoAvailable: Bool = false, sources: [FamiliarSource] = [], webCaptures: [FamiliarWebCapture] = [], artifact: FamiliarArtifactDescriptor? = nil) {
        self.runID = runID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.effect = effect
        self.assistantTurnID = assistantTurnID
        self.summary = summary
        self.detail = detail
        self.confirmation = confirmation
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.artifactIdentifier = artifactIdentifier
        self.undoAvailable = undoAvailable
        self.sources = sources
        self.webCaptures = webCaptures
        self.artifact = artifact
    }
}

nonisolated enum FamiliarRuntimeEventPayload: Sendable {
    case runStarted
    case state(FamiliarRuntimeState)
    case textDelta(String)
    case toolRequested(id: String, name: String, effect: FamiliarToolEffect)
    case toolInvocationRequested(id: String, name: String, arguments: String, effect: FamiliarToolEffect)
    case toolProgress(FamiliarToolProgress)
    case approvalRequested(FamiliarToolConfirmationRequest)
    case approvalResolved(requestID: UUID, decision: FamiliarToolConfirmationDecision)
    case toolFinished(FamiliarToolRunTerminalEvent)
    case responseCompleted(FamiliarCompletedResponse)
    case runCompleted
    case runCancelled
    case runFailed(String)
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
        self.undoStore = undoStore
        self.authorizationRuntime = authorizationRuntime
        self.maximumIterations = maximumIterations
        self.maximumAttemptsPerRound = maximumAttemptsPerRound
        self.maximumToolCalls = maximumToolCalls
        self.maximumDuration = maximumDuration
    }

    func stream(
        contextSnapshot: FamiliarContextSnapshot,
        apiKey: String
    ) -> AsyncThrowingStream<FamiliarRuntimeEvent, Error> {
        let runID = UUID().uuidString
        return AsyncThrowingStream { continuation in
            let emitter = FamiliarRuntimeEventEmitter(runID: runID, continuation: continuation)
            let task = Task {
                await emitter.emit(.runStarted)
                do {
                    try await run(
                        runID: runID,
                        contextSnapshot: contextSnapshot,
                        apiKey: apiKey,
                        emitter: emitter
                    )
                    await emitter.emit(.runCompleted)
                    continuation.finish()
                } catch is CancellationError {
                    await confirmationCoordinator.cancel(runID: runID)
                    await emitter.emit(.runCancelled)
                    continuation.finish()
                } catch {
                    await confirmationCoordinator.cancel(runID: runID)
                    await emitter.emit(.runFailed(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func run(
        runID: String,
        contextSnapshot: FamiliarContextSnapshot,
        apiKey: String,
        emitter: FamiliarRuntimeEventEmitter
    ) async throws {
        let manifests = contextSnapshot.toolManifests
        let manifestsByName = Dictionary(uniqueKeysWithValues: manifests.map { ($0.name, $0) })
        var messages = contextSnapshot.providerMessages

        var visibleResponse = ""
        var collectedSources: [FamiliarSource] = []
        var executedFingerprints: Set<String> = []
        var executedToolCalls = 0
        let runStartedAt = Date()
        await emitter.emit(.state(.thinking))

        for iteration in 0..<maximumIterations {
            try Task.checkCancellation()
            guard Date().timeIntervalSince(runStartedAt) < maximumDuration else { throw FamiliarAgentError.durationExceeded }
            if iteration > 0 { await emitter.emit(.state(.responding)) }
            let characterCount = FamiliarProjectContextAssembler.inputCharacterCount(messages: messages, manifests: manifests)
            guard characterCount <= contextSnapshot.maximumInputCharacters else { throw FamiliarAgentError.contextTooLarge }

            let assistantTurnID = "\(runID):turn:\(iteration)"
            await emitter.beginAssistantTurn(assistantTurnID)
            let request = FamiliarModelRequest(model: contextSnapshot.modelID, messages: messages, tools: manifests)
            let (roundText, pendingCalls, finishReason) = try await streamRound(request: request, apiKey: apiKey, emitter: emitter)
            visibleResponse += roundText
            if finishReason == .length || finishReason == .unknown { throw FamiliarAgentError.incompleteResponse }
            let calls = try pendingCalls.sorted { $0.key < $1.key }.map { try $0.value.completed() }
            guard !calls.isEmpty else {
                let answer = visibleResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !answer.isEmpty else { throw FamiliarAgentError.emptyResponse }
                await emitter.emit(.responseCompleted(.init(text: answer, sources: collectedSources)))
                return
            }

            messages.append(.assistant(roundText.isEmpty ? nil : roundText, toolCalls: calls))
            for call in calls {
                try Task.checkCancellation()
                let startedAt = Date()
                guard let manifest = manifestsByName[call.name] else {
                    throw FamiliarToolRegistryError.toolNotFound(call.name)
                }
                let fingerprint = call.name + "|" + FamiliarAuthorizationGrant.argumentsHash(call.arguments)
                await emitter.emit(.toolRequested(id: call.id, name: call.name, effect: manifest.effect))
                guard executedFingerprints.insert(fingerprint).inserted else {
                    let result = terminal(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID, detail: String(localized: "error.tool.duplicate_call"), confirmation: .notRequired, status: .failed, startedAt: startedAt)
                    await emitTerminal(result, emitter: emitter)
                    messages.append(.tool(Self.errorResult(message: result.detail), toolCallID: call.id, name: call.name))
                    continue
                }
                guard executedToolCalls < maximumToolCalls else { throw FamiliarAgentError.maxToolCallsExceeded }
                guard Date().timeIntervalSince(runStartedAt) < maximumDuration else { throw FamiliarAgentError.durationExceeded }
                executedToolCalls += 1
                await emitter.emit(.state(.usingTool(manifest.title)))
                await emitter.emit(.toolInvocationRequested(id: call.id, name: call.name, arguments: call.arguments, effect: manifest.effect))
                await emitter.emit(.toolProgress(.init(id: call.id, toolName: call.name, title: manifest.title, detail: nil, state: .running, effect: manifest.effect)))

                do {
                    let availability = await registry.availability(for: manifest)
                    let decision = policy.decide(
                        manifest: manifest,
                        availability: availability,
                        grant: nil,
                        arguments: call.arguments,
                        projectID: contextSnapshot.projectID
                    )
                    if case .deny(let reason) = decision { throw FamiliarToolRegistryError.capabilityUnavailable(reason) }
                    if manifest.effect == .read, decision == .requestApproval {
                        guard try await approve(runID: runID, call: call, effect: manifest.effect, title: manifest.title, fields: ["访问范围": manifest.description], target: nil, emitter: emitter).isConfirmed else {
                            let result = terminal(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID, detail: String(localized: "tool.cancelled_by_user"), confirmation: .cancelled, status: .cancelled, startedAt: startedAt)
                            await emitTerminal(result, emitter: emitter)
                            messages.append(.tool(Self.cancelledResult(), toolCallID: call.id, name: call.name))
                            continue
                        }
                    }
                    if manifest.effect == .read {
                        try await registry.prepareCapabilities(for: manifest)
                    }
                    let resourceContext = contextSnapshot.resources.map {
                        FamiliarToolContext.Resource(
                            id: $0.resourceID,
                            versionID: $0.resourceVersionID,
                            version: $0.version,
                            displayName: $0.displayName,
                            filename: $0.filename,
                            mimeType: $0.mimeType,
                            extractedText: $0.extractedText
                        )
                    }
                    let outcome = try await registry.execute(
                        name: call.name,
                        arguments: call.arguments,
                        context: .init(runID: runID, toolCallID: call.id, projectID: contextSnapshot.projectID, resources: resourceContext)
                    )
                    var undoAvailable = false
                    let resolved: (FamiliarToolExecutionResult, FamiliarPersistedConfirmationResult)
                    switch outcome {
                    case .result(let result): resolved = (result, manifest.effect == .read && decision == .requestApproval ? .confirmed : .notRequired)
                    case .action(let proposal):
                        let hasGrant = if manifest.effect == .reversibleWrite, manifest.risk != .high, let authorizationRuntime {
                            await authorizationRuntime.matchingAuthorization(manifest: manifest, arguments: call.arguments, projectID: contextSnapshot.projectID, targetKey: proposal.targetKey)
                        } else {
                            false
                        }
                        let approvalDecision: FamiliarToolConfirmationDecision
                        if hasGrant {
                            approvalDecision = .confirmed
                        } else {
                            approvalDecision = try await approve(runID: runID, call: call, effect: manifest.effect, title: proposal.title, fields: proposal.fields, target: proposal.target, emitter: emitter)
                        }
                        guard approvalDecision.isConfirmed else {
                            let result = terminal(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID, detail: String(localized: "tool.cancelled_by_user"), confirmation: .cancelled, status: .cancelled, startedAt: startedAt)
                            await emitTerminal(result, emitter: emitter)
                            messages.append(.tool(Self.cancelledResult(), toolCallID: call.id, name: call.name))
                            continue
                        }
                        if !hasGrant, let duration = approvalDecision.authorizationDuration, let authorizationRuntime {
                            try await authorizationRuntime.issueAuthorization(duration: duration, manifest: manifest, arguments: call.arguments, projectID: contextSnapshot.projectID, targetKey: proposal.targetKey, evidence: proposal.title)
                        }
                        let result = try await proposal.execute()
                        if let undo = proposal.undo {
                            undoAvailable = true
                            await undoStore.register(key: proposal.idempotencyKey, action: undo)
                        }
                        resolved = (result, hasGrant ? .notRequired : .confirmed)
                    }
                    guard resolved.0.modelContent.count <= 48_000 else { throw FamiliarAgentError.toolResultTooLarge }
                    collectedSources = Self.mergingSources(collectedSources, with: resolved.0.sources)
                    let record = terminal(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID, detail: String(resolved.0.displayContent.prefix(2_000)), confirmation: resolved.1, status: .succeeded, startedAt: startedAt, artifactIdentifier: resolved.0.artifactIdentifier, undoAvailable: undoAvailable, sources: resolved.0.sources, webCaptures: resolved.0.webCaptures, artifact: resolved.0.artifact)
                    await emitTerminal(record, emitter: emitter)
                    messages.append(.tool(resolved.0.modelContent, toolCallID: call.id, name: call.name))
                } catch is CancellationError { throw CancellationError() }
                catch {
                    let record = terminal(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID, detail: error.localizedDescription, confirmation: .notRequired, status: .failed, startedAt: startedAt)
                    await emitTerminal(record, emitter: emitter)
                    messages.append(.tool(Self.errorResult(message: error.localizedDescription), toolCallID: call.id, name: call.name))
                }
            }
        }
        throw FamiliarAgentError.maxIterationsExceeded
    }

    private func streamRound(
        request: FamiliarModelRequest,
        apiKey: String,
        emitter: FamiliarRuntimeEventEmitter
    ) async throws -> (roundText: String, pendingCalls: [Int: PendingToolCall], finishReason: FamiliarModelFinishReason?) {
        var attempt = 0
        while true {
            attempt += 1
            var emittedContent = false
            var pendingCalls: [Int: PendingToolCall] = [:]
            var roundText = ""
            var roundIsResponding = false
            var finishReason: FamiliarModelFinishReason?
            do {
                for try await event in provider.stream(request: request, apiKey: apiKey) {
                    try Task.checkCancellation()
                    switch event {
                    case .textDelta(let value):
                        emittedContent = true
                        if !roundIsResponding {
                            roundIsResponding = true
                            await emitter.emit(.state(.responding))
                        }
                        roundText += value
                        await emitter.emit(.textDelta(value))
                    case .toolCallDelta(let index, let id, let name, let arguments):
                        emittedContent = true
                        var call = pendingCalls[index] ?? PendingToolCall()
                        if let id, !id.isEmpty { call.id = id }
                        if let name { call.name += name }
                        if let arguments { call.arguments += arguments }
                        pendingCalls[index] = call
                    case .completed(let reason): finishReason = reason
                    }
                }
                return (roundText, pendingCalls, finishReason)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < maximumAttemptsPerRound, !emittedContent else { throw error }
                guard FamiliarRuntimeFailure.kind(for: error).isRetryable else { throw error }
                try await Task.sleep(nanoseconds: Self.retryDelayNanoseconds(attempt: attempt))
            }
        }
    }

    private static func retryDelayNanoseconds(attempt: Int) -> UInt64 {
        let milliseconds: UInt64 = attempt <= 1 ? 300 : (attempt == 2 ? 800 : 1_500)
        return milliseconds * 1_000_000
    }

    private func approve(runID: String, call: FamiliarProviderToolCall, effect: FamiliarToolEffect, title: String, fields: [String: String], target: String?, emitter: FamiliarRuntimeEventEmitter) async throws -> FamiliarToolConfirmationDecision {
        let request = FamiliarToolConfirmationRequest(runID: runID, toolCallID: call.id, toolName: call.name, effect: effect, title: title, fields: fields, target: target)
        await emitter.emit(.state(.awaitingApproval))
        await emitter.emit(.approvalRequested(request))
        let decision = try await confirmationCoordinator.requestConfirmation(request)
        await emitter.emit(.approvalResolved(requestID: request.id, decision: decision))
        return decision
    }

    private func terminal(runID: String, call: FamiliarProviderToolCall, manifest: FamiliarToolManifest, assistantTurnID: String, detail: String, confirmation: FamiliarPersistedConfirmationResult, status: FamiliarToolRunTerminalStatus, startedAt: Date, artifactIdentifier: String? = nil, undoAvailable: Bool = false, sources: [FamiliarSource] = [], webCaptures: [FamiliarWebCapture] = [], artifact: FamiliarArtifactDescriptor? = nil) -> FamiliarToolRunTerminalEvent {
        .init(runID: runID, toolCallID: call.id, toolName: call.name, effect: manifest.effect, assistantTurnID: assistantTurnID, summary: manifest.title, detail: detail, confirmation: confirmation, status: status, startedAt: startedAt, finishedAt: Date(), artifactIdentifier: artifactIdentifier, undoAvailable: undoAvailable, sources: sources, webCaptures: webCaptures, artifact: artifact)
    }

    private func emitTerminal(_ record: FamiliarToolRunTerminalEvent, emitter: FamiliarRuntimeEventEmitter) async {
        let state: FamiliarToolProgressState = switch record.status { case .succeeded: .succeeded; case .cancelled: .cancelled; case .failed: .failed }
        await emitter.emit(.toolProgress(.init(id: record.toolCallID, toolName: record.toolName, title: record.summary, detail: record.detail, state: state, effect: record.effect)))
        await emitter.emit(.toolFinished(record))
    }

    private static func errorResult(message: String) -> String {
        struct Payload: Encodable { let error: String }
        guard let data = try? JSONEncoder().encode(Payload(error: message)) else { return #"{"error":"tool_failed"}"# }
        return String(decoding: data, as: UTF8.self)
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

    private struct PendingToolCall {
        var id = "", name = "", arguments = ""
        func completed() throws -> FamiliarProviderToolCall {
            guard !id.isEmpty, !name.isEmpty else { throw FamiliarAgentError.invalidToolCall }
            guard arguments.count <= 16_000 else { throw FamiliarAgentError.toolArgumentsTooLarge }
            return .init(id: id, name: name, arguments: arguments)
        }
    }
}
