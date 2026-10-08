import Foundation

nonisolated enum FamiliarRunPhase: Equatable, Sendable {
    case starting
    case compactingContext
    case requestingModel
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
    let fileIdentifier: String?
    let undoAvailable: Bool
    let automaticApprovalRequest: FamiliarToolConfirmationRequest?
    let failureCode: String?
    let failureRetryable: Bool?

    init(runID: String, toolCallID: String, toolName: String, effect: FamiliarToolEffect, assistantTurnID: String, detail: String, confirmation: FamiliarPersistedConfirmationResult, status: FamiliarToolRunTerminalStatus, startedAt: Date, finishedAt: Date, fileIdentifier: String?, undoAvailable: Bool, automaticApprovalRequest: FamiliarToolConfirmationRequest?, failureCode: String? = nil, failureRetryable: Bool? = nil) {
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
        self.fileIdentifier = fileIdentifier
        self.undoAvailable = undoAvailable
        self.automaticApprovalRequest = automaticApprovalRequest
        self.failureCode = failureCode
        self.failureRetryable = failureRetryable
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
    let file: FamiliarFileDescriptor?
    let environmentReceipt: FamiliarEnvironmentReceipt?
    let loadedSkill: FamiliarSkillSnapshot?
    let memoryWrite: FamiliarMemoryWriteRequest?
    let loadedTools: [FamiliarToolManifest]?
    let producedAt: Date

    init(
        runID: String,
        toolCallID: String,
        toolName: String,
        effect: FamiliarToolEffect,
        assistantTurnID: String,
        envelope: FamiliarToolResultEnvelope,
        sources: [FamiliarSource],
        file: FamiliarFileDescriptor?,
        environmentReceipt: FamiliarEnvironmentReceipt? = nil,
        loadedSkill: FamiliarSkillSnapshot? = nil,
        memoryWrite: FamiliarMemoryWriteRequest? = nil,
        loadedTools: [FamiliarToolManifest]? = nil,
        producedAt: Date
    ) {
        self.runID = runID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.effect = effect
        self.assistantTurnID = assistantTurnID
        self.envelope = envelope
        self.sources = sources
        self.file = file
        self.environmentReceipt = environmentReceipt
        self.loadedSkill = loadedSkill
        self.memoryWrite = memoryWrite
        self.loadedTools = loadedTools
        self.producedAt = producedAt
    }
}

nonisolated enum FamiliarRuntimeNoticeKind: String, Codable, Equatable, Sendable {
    case retrying
    /// The tool-call budget is spent. This is a closing signal, not a failure: the
    /// run continues with tools withheld so the model must answer from what it has
    /// already gathered, instead of discarding every result collected so far.
    case budgetExhausted
}

nonisolated struct FamiliarRuntimeNotice: Equatable, Sendable {
    let kind: FamiliarRuntimeNoticeKind
    let attempt: Int
    let delay: TimeInterval
    let failureKind: FamiliarRuntimeFailureKind
    let toolCallID: String?

    /// `attempt` and `delay` describe a retry schedule and carry no meaning for a
    /// budget notice, so they default to zero.
    init(
        kind: FamiliarRuntimeNoticeKind,
        attempt: Int = 0,
        delay: TimeInterval = 0,
        failureKind: FamiliarRuntimeFailureKind,
        toolCallID: String? = nil
    ) {
        self.kind = kind
        self.attempt = attempt
        self.delay = delay
        self.failureKind = failureKind
        self.toolCallID = toolCallID
    }
}

nonisolated enum FamiliarRuntimeEventPayload: Sendable {
    case modelSelected(FamiliarModelReference)
    case usage(FamiliarTokenUsage)
    case runPhaseChanged(FamiliarRunPhase)
    case assistantTurnStarted(id: String, index: Int)
    case assistantTurnCompleted(id: String, index: Int, text: String)
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
    private var results: [String: FamiliarToolExecutionResult] = [:]
    private var running: Set<String> = []
    private var attempted: Set<String> = []
    func register(key: String, action: @escaping @Sendable () async throws -> FamiliarToolExecutionResult) {
        guard !attempted.contains(key), actions[key] == nil else { return }
        actions[key] = action
    }
    func execute(key: String) async throws -> FamiliarToolExecutionResult {
        if let result = results[key] { return result }
        guard !running.contains(key) else { throw FamiliarEventKitError.undoUnavailable }
        guard let action = actions.removeValue(forKey: key) else { throw FamiliarEventKitError.undoUnavailable }
        attempted.insert(key)
        running.insert(key)
        defer { running.remove(key) }
        let result = try await action()
        results[key] = result
        return result
    }
    func complete(key: String) { results.removeValue(forKey: key) }
    func hasCompletedResult(key: String) -> Bool { results[key] != nil }
    func clear() { actions.removeAll(); results.removeAll(); attempted.removeAll() }
}

nonisolated enum FamiliarAgentError: LocalizedError, Sendable {
    case emptyResponse, invalidToolCall, incompleteResponse, maxIterationsExceeded
    case contextTooLarge, contextCompactionFailed, toolArgumentsTooLarge, toolResultTooLarge
    case durationExceeded

    var errorDescription: String? {
        switch self {
        case .emptyResponse: String(localized: "error.agent.empty_response")
        case .invalidToolCall: String(localized: "error.agent.invalid_tool_call")
        case .incompleteResponse: String(localized: "error.agent.incomplete_response")
        case .maxIterationsExceeded: String(localized: "error.agent.max_iterations")
        case .contextTooLarge: String(localized: "error.message.context_too_large")
        case .contextCompactionFailed: String(localized: "error.agent.context_compaction_failed", defaultValue: "Context compaction failed. Start a new conversation or try again.")
        case .toolArgumentsTooLarge: String(localized: "error.agent.tool_arguments_too_large")
        case .toolResultTooLarge: String(localized: "error.agent.tool_result_too_large")
        case .durationExceeded: String(localized: "error.agent.duration_exceeded")
        }
    }
}

nonisolated struct FamiliarToolExecutionTimeout: LocalizedError, Sendable {
    let toolName: String

    var errorDescription: String? {
        "工具 \(toolName) 在本次执行时限内未完成。"
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
    private let persistCompilation: (@Sendable (String, FamiliarContextCompilation) async throws -> Void)?
    private let persistResult: FamiliarToolResultPersistence?
    private let willCommit: (@Sendable (FamiliarToolCommitContext) async throws -> Void)?
    private let deferredToolGroups: [FamiliarDeferredToolGroup]
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
        persistCompilation: (@Sendable (String, FamiliarContextCompilation) async throws -> Void)? = nil,
        persistResult: FamiliarToolResultPersistence? = nil,
        willCommit: (@Sendable (FamiliarToolCommitContext) async throws -> Void)? = nil,
        deferredToolGroups: [FamiliarDeferredToolGroup] = [],
        maximumIterations: Int = 24,
        maximumAttemptsPerRound: Int = 2,
        maximumToolCalls: Int = 64,
        maximumDuration: TimeInterval = 1_200
    ) {
        self.persistCompilation = persistCompilation
        self.persistResult = persistResult
        self.willCommit = willCommit
        self.deferredToolGroups = deferredToolGroups
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
        var activeManifests = contextSnapshot.toolManifests
        let loader = FamiliarToolLoader(registry: registry, catalog: contextSnapshot.availableToolManifests, deferred: deferredToolGroups)
        var messages = contextSnapshot.providerMessages
        var contextCompactionCount = 0
        var currentTurnIndex: Int? = messages.last?.role == .user ? messages.count - 1 : nil

        var visibleResponse = ""
        var collectedSources: [FamiliarSource] = []
        let toolState = FamiliarRunState()
        await toolState.discover(contextSnapshot.availableToolManifests)
        var executedToolCalls = 0
        var loadedSkill = contextSnapshot.skills.first
        /// Set once the tool-call budget is spent. From then on tools are withheld
        /// rather than the run being failed, so the work already done survives.
        var toolBudgetExhausted = false

        for iteration in 0..<maximumIterations {
            try Task.checkCancellation()
            try Self.checkDeadline(deadline)
            let withholdTools = toolBudgetExhausted || iteration == maximumIterations - 1
            let manifests = withholdTools ? [] : FamiliarSkillToolScope.manifests(available: activeManifests, skills: loadedSkill.map { [$0] } ?? [])
            await toolState.expose(manifests)
            if let loadedSkill { await toolState.load(loadedSkill) }
            let manifestsByName = Dictionary(uniqueKeysWithValues: manifests.map { ($0.name, $0) })
            let requestFacts = await toolState.snapshot()
            while FamiliarContextCompiler.shouldCompact(
                messages: messages,
                manifests: manifests,
                maximumInputCharacters: contextSnapshot.maximumInputCharacters
            ) || (try? FamiliarContextCompiler.compileRequest(input: contextSnapshot, transcript: messages,
                facts: requestFacts, manifests: manifests, toolsWithheld: withholdTools)) == nil {
                guard contextCompactionCount < 4 else { throw FamiliarAgentError.contextTooLarge }
                await emitter.emit(.runPhaseChanged(.compactingContext))
                let compacted = try await compactContext(
                    messages: messages,
                    protectedPrefixMessageCount: contextSnapshot.protectedPrefixMessageCount,
                    modelID: contextSnapshot.modelID,
                    maximumInputCharacters: contextSnapshot.maximumInputCharacters,
                    protectedTurnIndex: currentTurnIndex,
                    input: contextSnapshot,
                    runID: runID,
                    deadline: deadline,
                    emitter: emitter
                )
                let before = FamiliarContextCompiler.inputCharacterCount(messages: messages, manifests: manifests)
                let after = FamiliarContextCompiler.inputCharacterCount(messages: compacted.messages, manifests: manifests)
                guard after < before else {
                    guard (try? FamiliarContextCompiler.compileRequest(input: contextSnapshot, transcript: messages,
                        facts: requestFacts, manifests: manifests, toolsWithheld: withholdTools)) != nil else {
                        throw FamiliarAgentError.contextTooLarge
                    }
                    break
                }
                messages = compacted.messages
                currentTurnIndex = compacted.currentTurnIndex
                contextCompactionCount += 1
            }
            await emitter.emit(.runPhaseChanged(.requestingModel))
            let characterCount = FamiliarContextCompiler.inputCharacterCount(messages: messages, manifests: manifests)
            guard characterCount <= contextSnapshot.maximumInputCharacters else { throw FamiliarAgentError.contextTooLarge }

            let assistantTurnID = "\(runID):turn:\(iteration)"
            await emitter.beginAssistantTurn(assistantTurnID)
            await emitter.emit(.assistantTurnStarted(id: assistantTurnID, index: iteration))
            let compiled = try FamiliarContextCompiler.compileRequest(input: contextSnapshot, transcript: messages,
                facts: requestFacts, manifests: manifests, toolsWithheld: withholdTools)
            if let persistCompilation { try await Self.withDeadline(deadline) { try await persistCompilation(runID, compiled.manifest) } }
            let request = compiled.request
            let round = try await streamRound(request: request, emitter: emitter, deadline: deadline)
            if round.finishReason == .length || round.finishReason == .unknown { throw FamiliarAgentError.incompleteResponse }
            await emitter.emit(.assistantTurnCompleted(id: assistantTurnID, index: iteration, text: round.text))
            visibleResponse += round.text
            let calls = try round.pendingCalls.sorted { $0.key < $1.key }.map { try $0.value.completed() }
            guard !calls.isEmpty else {
                let answer = visibleResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !answer.isEmpty else { throw FamiliarAgentError.emptyResponse }
                await emitter.emit(.responseCompleted(.init(text: answer, sources: collectedSources)))
                return
            }
            if calls.contains(where: { ["skill_read", "skill_install"].contains($0.name) }), calls.count != 1 {
                throw FamiliarAgentError.invalidToolCall
            }

            messages.append(.assistant(round.text.isEmpty ? nil : round.text, toolCalls: calls))
            await emitter.emit(.runPhaseChanged(.executingActivities(calls.map(\.name))))
            var prepared: [PreparedToolCall] = []
            var toolMessages: [Int: FamiliarProviderMessage] = [:]
            for (index, call) in calls.enumerated() {
                try Task.checkCancellation()
                try Self.checkDeadline(deadline)
                let startedAt = Date()
                let wireManifest = manifestsByName[call.name]
                var auditManifest = wireManifest
                if auditManifest == nil { auditManifest = try? await registry.manifest(named: call.name) }
                let effect = auditManifest?.effect ?? .read
                await emitter.emit(.toolInvocationRequested(id: call.id, name: call.name, arguments: call.arguments, effect: effect))
                await emitter.emit(.activityStarted(.init(id: call.id, toolName: call.name, effect: effect, startedAt: startedAt)))
                let rejection: (code: String, message: String)?
                if executedToolCalls >= maximumToolCalls {
                    if !toolBudgetExhausted {
                        toolBudgetExhausted = true
                        await emitter.emit(.runtimeNotice(.init(kind: .budgetExhausted, failureKind: .maxToolCalls)))
                    }
                    rejection = ("tool_budget_exhausted", String(localized: "error.agent.max_tool_calls"))
                } else {
                    // Attempted calls consume the same budget, including guessed names.
                    executedToolCalls += 1
                    if let reason = policy.scopeViolation(toolName: call.name, exposed: wireManifest != nil, skill: loadedSkill) {
                        rejection = (reason, reason == "tool_not_exposed"
                            ? "This tool was not exposed in the current request. Load an allowed group with tools_load before calling it."
                            : "The loaded Skill does not allow this tool.")
                    } else {
                        rejection = nil
                    }
                }
                if let rejection {
                    await emitter.emit(.activityCompleted(.init(runID: runID, toolCallID: call.id, toolName: call.name, effect: effect,
                        assistantTurnID: assistantTurnID, detail: rejection.message, confirmation: .notRequired, status: .failed,
                        startedAt: startedAt, finishedAt: Date(), fileIdentifier: nil, undoAvailable: false,
                        automaticApprovalRequest: nil, failureCode: rejection.code, failureRetryable: false)))
                    await toolState.record(call: call, status: .failed, detail: rejection.code)
                    toolMessages[index] = .tool(Self.errorResult(code: rejection.code, retryable: false, message: rejection.message), toolCallID: call.id, name: call.name)
                    continue
                }
                guard let manifest = wireManifest else { throw FamiliarAgentError.invalidToolCall }
                prepared.append(.init(index: index, call: call, manifest: manifest, startedAt: startedAt))
            }

            var cursor = 0
            let schemaBudget = max(0, contextSnapshot.maximumInputCharacters - FamiliarContextCompiler.inputCharacterCount(messages: messages, manifests: []))
            while cursor < prepared.count {
                let current = prepared[cursor]
                if try await canRunInParallel(current, runID: runID, input: contextSnapshot, state: toolState, loader: loader, schemaBudget: schemaBudget, skill: loadedSkill, sources: collectedSources, deadline: deadline) {
                    var batch = [current]
                    if cursor + 1 < prepared.count,
                       try await canRunInParallel(prepared[cursor + 1], runID: runID, input: contextSnapshot, state: toolState, loader: loader, schemaBudget: schemaBudget, skill: loadedSkill, sources: collectedSources, deadline: deadline) {
                        batch.append(prepared[cursor + 1])
                    }
                    let batchSkill = loadedSkill
                    let batchSources = collectedSources
                    let outputs = try await withThrowingTaskGroup(of: ToolCallOutput.self) { group in
                        for item in batch {
                            group.addTask {
                                try await executeToolCall(item, runID: runID, assistantTurnID: assistantTurnID, contextSnapshot: contextSnapshot, emitter: emitter, deadline: deadline, toolState: toolState, loader: loader, schemaBudget: schemaBudget, activeSkill: batchSkill, sources: batchSources)
                            }
                        }
                        var values: [ToolCallOutput] = []
                        for try await value in group { values.append(value) }
                        return values.sorted { $0.index < $1.index }
                    }
                    for output in outputs {
                        toolMessages[output.index] = output.message
                        collectedSources = Self.mergingSources(collectedSources, with: output.sources)
                        if let skill = output.loadedSkill { loadedSkill = skill }
                        if let tools = output.loadedTools { activeManifests = tools }

                    }
                    cursor += batch.count
                } else {
                    let output = try await executeToolCall(current, runID: runID, assistantTurnID: assistantTurnID, contextSnapshot: contextSnapshot, emitter: emitter, deadline: deadline, toolState: toolState, loader: loader, schemaBudget: schemaBudget, activeSkill: loadedSkill, sources: collectedSources)
                    toolMessages[output.index] = output.message
                    collectedSources = Self.mergingSources(collectedSources, with: output.sources)
                    if let skill = output.loadedSkill { loadedSkill = skill }
                    if let tools = output.loadedTools { activeManifests = tools }

                    cursor += 1
                }
            }
            for index in calls.indices {
                guard let message = toolMessages[index] else { throw FamiliarAgentError.incompleteResponse }
                messages.append(message)
            }
        }
        // Reaching here means the model kept requesting tools even on the final
        // iteration, where tools were already withheld. Deliver whatever it did say
        // rather than failing the run and discarding the whole turn; only a run with
        // literally nothing to show is a genuine failure.
        let answer = visibleResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw FamiliarAgentError.maxIterationsExceeded }
        await emitter.emit(.responseCompleted(.init(text: answer, sources: collectedSources)))
    }

    private func streamRound(
        request: FamiliarModelRequest,
        emitter: FamiliarRuntimeEventEmitter,
        deadline: ContinuousClock.Instant,
        emitsText: Bool = true
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
                                if emitsText, !roundIsResponding {
                                    roundIsResponding = true
                                    await emitter.emit(.runPhaseChanged(.responding))
                                }
                                roundText += value
                                if emitsText { await emitter.emit(.responseTextDelta(value)) }
                            case .reasoningSummaryDelta(let value):
                                emittedContent = true
                                reasoningSummary += value
                                if emitsText { await emitter.emit(.reasoningSummaryDelta(value)) }
                            case .toolCallDelta(let index, let id, let name, let arguments):
                                emittedContent = true
                                var call = pendingCalls[index] ?? PendingToolCall()
                                if let id, !id.isEmpty { call.id = id }
                                if let name { call.name += name }
                                if let arguments { call.arguments += arguments }
                                pendingCalls[index] = call
                            case .providerSelection(let providerID, let modelID):
                                await emitter.emit(.modelSelected(.init(providerID: providerID, modelID: modelID)))
                            case .usage(let usage):
                                await emitter.emit(.usage(usage))
                            case .completed(let reason):
                                finishReason = reason
                            }
                        }
                        return RoundResult(text: roundText, reasoningSummary: reasoningSummary, pendingCalls: pendingCalls, finishReason: finishReason)
                    } catch {
                        throw RoundAttemptError(underlying: error, emittedContent: emittedContent)
                    }
                }
                if emitsText, !result.reasoningSummary.isEmpty {
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

    private func makeToolContext(runID: String, callID: String, input: FamiliarContextSnapshot,
                                 state: FamiliarRunState, loader: FamiliarToolLoader, schemaBudget: Int,
                                 skill: FamiliarSkillSnapshot?, sources: [FamiliarSource],
                                 emitter: FamiliarRuntimeEventEmitter? = nil) async -> FamiliarToolContext {
        let resources = input.resources.map {
            FamiliarToolContext.Resource(id: $0.resourceID, versionID: $0.resourceVersionID, version: $0.version, displayName: $0.displayName, filename: $0.filename, mimeType: $0.mimeType, contentHash: $0.contentHash, extractedText: $0.extractedText)
        }
        let attachments = input.attachments.map {
            FamiliarToolContext.Attachment(id: $0.id, kind: $0.kind, filename: $0.filename, mimeType: $0.mimeType, relativePath: $0.relativePath, extractedText: $0.extractedText, byteSize: $0.byteSize)
        }
        let workspaceID: FamiliarWorkspaceID = input.projectID.map(FamiliarWorkspaceID.project)
            ?? .conversation(input.conversationID)
        return FamiliarToolContext(
            runID: runID,
            toolCallID: callID,
            projectID: input.projectID,
            conversationID: input.conversationID,
            workspaceID: workspaceID,
            resources: resources,
            attachments: attachments,
            files: await state.files(available: input.files),
            availableSkills: await state.skills(available: input.availableSkills),
            activeSkill: skill,
            loadTools: { groups, names, offset, skill in
                try await loader.load(groups: groups, toolNames: names, offset: offset, skill: skill, schemaBudget: schemaBudget)
            },
            fetchedSources: sources,
            webEvidence: state.webEvidence,
            memories: input.memories,
            progressReporter: { progress in
                let detail: String = switch progress {
                case .status(let value): value
                case .standardOutput(let value): value
                case .standardError(let value): value
                }
                await emitter?.emit(.activityProgress(.init(
                    id: callID,
                    fractionCompleted: nil,
                    detail: detail
                )))
            }
        )
    }

    private func canRunInParallel(_ item: PreparedToolCall, runID: String, input: FamiliarContextSnapshot,
                                  state: FamiliarRunState, loader: FamiliarToolLoader, schemaBudget: Int,
                                  skill: FamiliarSkillSnapshot?, sources: [FamiliarSource], deadline: ContinuousClock.Instant) async throws -> Bool {
        guard item.manifest.effect == .read, item.manifest.supportsParallelism else { return false }
        let context = await makeToolContext(runID: runID, callID: item.call.id, input: input, state: state,
            loader: loader, schemaBudget: schemaBudget, skill: skill, sources: sources)
        // Only side-effect-free, noninteractive preflight can admit concurrent reads.
        // A preflight failure is reported by the normal invocation, not by the batch.
        return try await Self.withDeadline(deadline) {
            guard let assessment = try? await registry.preflight(name: item.call.name, arguments: item.call.arguments, context: context)
            else { return false }
            return policy.allowsParallelRead(manifest: item.manifest, assessment: assessment,
                availability: await registry.availability(for: item.manifest))
        }
    }

    private func executeToolCall(
        _ item: PreparedToolCall,
        runID: String,
        assistantTurnID: String,
        contextSnapshot: FamiliarContextSnapshot,
        emitter: FamiliarRuntimeEventEmitter,
        deadline: ContinuousClock.Instant,
        toolState: FamiliarRunState,
        loader: FamiliarToolLoader,
        schemaBudget: Int,
        activeSkill: FamiliarSkillSnapshot?,
        sources: [FamiliarSource]
    ) async throws -> ToolCallOutput {
        let call = item.call
        let manifest = item.manifest
        var automaticApprovalRequest: FamiliarToolConfirmationRequest?
        /// `.confirmed` only when this call actually interrupted the user. A reused
        /// authorization must not be audited as a fresh confirmation.
        var readConfirmation: FamiliarPersistedConfirmationResult = .notRequired
        let commitContext = FamiliarToolCommitContext(runID: runID, assistantTurnID: assistantTurnID, call: call)
        var writeAttempted = false
        var committedAction: FamiliarCommittedAction?
        var writeConfirmation: FamiliarPersistedConfirmationResult = .notRequired
        var retainedUndo = false
        do {
            await emitter.emit(.activityProgress(.init(id: call.id, fractionCompleted: nil, detail: nil)))
            if manifest.effect != .read,
               await toolState.wasAttempted(call.name + "|" + FamiliarCanonicalJSON.argumentsHash(call.arguments)) {
                let detail = String(localized: "error.tool.duplicate_call")
                await emitter.emit(.activityCompleted(activityCompletion(runID: runID, call: call, manifest: manifest,
                    assistantTurnID: assistantTurnID, detail: detail, confirmation: .notRequired, status: .failed,
                    startedAt: item.startedAt, failureCode: "duplicate_tool_call", failureRetryable: false)))
                return .init(index: item.index, message: .tool(Self.errorResult(code: "duplicate_tool_call", retryable: false, message: detail), toolCallID: call.id, name: call.name), sources: [], failed: true)
            }
            let availability = try await Self.withDeadline(deadline) {
                await registry.availability(for: manifest)
            }
            let toolContext = await makeToolContext(runID: runID, callID: call.id, input: contextSnapshot,
                state: toolState, loader: loader, schemaBudget: schemaBudget, skill: activeSkill, sources: sources, emitter: emitter)
            let authorizationAssessment = try await Self.withDeadline(deadline) {
                try await registry.preflight(
                    name: call.name,
                    arguments: call.arguments,
                    context: toolContext
                )
            }
            let initialEvaluation = try await Self.withDeadline(deadline) {
                try await policy.evaluate(manifest: manifest, call: call, context: toolContext, availability: availability,
                    assessment: authorizationAssessment, authorization: authorizationRuntime)
            }
            if case .deny(let reason) = initialEvaluation.decision { throw FamiliarToolRegistryError.capabilityUnavailable(reason) }
            if manifest.effect == .read {
                var accepted: FamiliarToolConfirmationDecision = .confirmed
                if initialEvaluation.decision == .requireApproval {
                    guard let request = initialEvaluation.approval else { throw FamiliarAgentError.invalidToolCall }
                    accepted = try await approve(request, emitter: emitter, deadline: deadline)
                    guard accepted.isConfirmed else {
                        await emitter.emit(.activityCompleted(activityCompletion(runID: runID, call: call, manifest: manifest,
                            assistantTurnID: assistantTurnID, detail: String(localized: "tool.cancelled_by_user"), confirmation: .cancelled,
                            status: .cancelled, startedAt: item.startedAt)))
                        await toolState.record(call: call, status: .cancelled)
                        return .init(index: item.index, message: .tool(Self.cancelledResult(), toolCallID: call.id, name: call.name), sources: [])
                    }
                    readConfirmation = .confirmed
                } else if initialEvaluation.authorizationScope != nil { automaticApprovalRequest = initialEvaluation.approval }
                let acceptedDecision = accepted
                try await Self.withDeadline(deadline) {
                    try await registry.prepareCapabilities(for: manifest)
                    let current = try await registry.preflight(name: call.name, arguments: call.arguments, context: toolContext)
                    let currentAvailability = await registry.availability(for: manifest)
                    try policy.revalidate(approved: authorizationAssessment, current: current, availability: currentAvailability)
                    try await policy.revalidateAuthorization(evaluation: initialEvaluation, manifest: manifest, call: call,
                        projectID: contextSnapshot.projectID, targetKey: authorizationAssessment.targetKey, authorization: authorizationRuntime)
                    try await policy.recordApproval(acceptedDecision, evaluation: initialEvaluation, manifest: manifest, call: call,
                        projectID: contextSnapshot.projectID, targetKey: authorizationAssessment.targetKey, authorization: authorizationRuntime)
                }
            }
            let readKey = await toolState.fileReadKey(call: call, available: toolContext.files)
            let cached = await toolState.cachedRead(readKey)
            let outcome: FamiliarToolOutcome
            if let cached { outcome = .result(cached.result) }
            else { outcome = try await executeOutcome(
                name: call.name,
                arguments: call.arguments,
                context: toolContext,
                allowsRetry: manifest.effect == .read && call.name != "web_search" && call.name != "web_fetch",
                maximumExecutionDuration: manifest.maximumExecutionDuration ?? 30,
                emitter: emitter,
                deadline: deadline
            ) }
            var undoAvailable = false
            let resolved: (FamiliarToolExecutionResult, FamiliarPersistedConfirmationResult)
            switch outcome {
            case .result(let result):
                resolved = (result, readConfirmation)
            case .action(let proposal):
                let evaluation = try await Self.withDeadline(deadline) {
                    try await policy.evaluate(manifest: manifest, call: call, context: toolContext,
                        availability: await registry.availability(for: manifest), assessment: authorizationAssessment,
                        proposal: proposal, authorization: authorizationRuntime)
                }
                if case .deny(let reason) = evaluation.decision { throw FamiliarToolRegistryError.capabilityUnavailable(reason) }
                let approvalDecision: FamiliarToolConfirmationDecision
                if evaluation.decision == .requireApproval {
                    guard let request = evaluation.approval else { throw FamiliarAgentError.invalidToolCall }
                    approvalDecision = try await approve(request, emitter: emitter, deadline: deadline)
                } else {
                    approvalDecision = .confirmed
                    if evaluation.authorizationScope != nil { automaticApprovalRequest = evaluation.approval }
                }
                guard approvalDecision.isConfirmed else {
                    let completion = activityCompletion(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID,
                        detail: String(localized: "tool.cancelled_by_user"), confirmation: .cancelled, status: .cancelled, startedAt: item.startedAt)
                    await emitter.emit(.activityCompleted(completion))
                    await toolState.record(call: call, status: .cancelled)
                    return .init(index: item.index, message: .tool(Self.cancelledResult(), toolCallID: call.id, name: call.name), sources: [])
                }
                try await Self.withDeadline(deadline) {
                    try await registry.prepareCapabilities(for: manifest)
                    let current = try await registry.preflight(name: call.name, arguments: call.arguments, context: toolContext)
                    let currentAvailability = await registry.availability(for: manifest)
                    try policy.revalidate(approved: authorizationAssessment, current: current, availability: currentAvailability)
                    try await policy.revalidateAuthorization(evaluation: evaluation, manifest: manifest, call: call,
                        projectID: contextSnapshot.projectID, targetKey: proposal.targetKey, authorization: authorizationRuntime)
                    try await policy.validateTarget(proposal)
                    try await policy.recordApproval(approvalDecision, evaluation: evaluation, manifest: manifest, call: call,
                        projectID: contextSnapshot.projectID, targetKey: proposal.targetKey, authorization: authorizationRuntime)
                }
                if let willCommit {
                    try await Self.withDeadline(deadline) { try await willCommit(commitContext) }
                }
                writeConfirmation = evaluation.decision == .allow ? .notRequired : .confirmed
                await toolState.beginWrite(call.name + "|" + FamiliarCanonicalJSON.argumentsHash(call.arguments))
                await toolState.record(call: call, status: .attempted)
                writeAttempted = true
                let commitDeadline = min(deadline, ContinuousClock().now.advanced(by: .seconds(manifest.maximumExecutionDuration ?? 30)))
                let committed = try await Self.withToolDeadline(commitDeadline, toolName: call.name) { try await proposal.commit() }
                committedAction = committed
                // Retain external Undo even if saving its receipt fails. Local bytes
                // have separate compensation and expose Undo only after persistence.
                if committed.rollback == nil, let undo = committed.undo {
                    undoAvailable = true
                    retainedUndo = true
                    await undoStore.register(key: proposal.idempotencyKey, action: undo)
                }
                resolved = (committed.result, writeConfirmation)
            case .clarification(let proposal):
                let request = FamiliarClarificationRequest(
                    runID: runID,
                    toolCallID: call.id,
                    question: proposal.question,
                    options: proposal.options,
                    allowCustom: proposal.allowCustom
                )
                await emitter.emit(.runPhaseChanged(.awaitingClarification))
                let resolution = try await Self.withDeadline(deadline) {
                    try await clarificationCoordinator.requestClarification(request, onPending: {
                        await emitter.emit(.clarificationRequested(request))
                    })
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
            try manifest.resultContract.validate(resolved.0)
            let finishedAt = Date()
            if let persistResult {
                let receipt = try await Self.withDeadline(deadline) { try await persistResult(resolved.0, commitContext) }
                await toolState.admit(files: receipt.files.filter { $0.reference.projectID == contextSnapshot.projectID })
            }
            if let committedAction {
                if let undo = committedAction.undo, !retainedUndo {
                    await undoStore.register(key: commitContext.idempotencyKey, action: undo)
                    undoAvailable = true
                }
                await committedAction.finalize?()
            }
            if let installed = resolved.0.installedSkill { await toolState.admit(installed) }
            await toolState.record(call: call, status: writeAttempted ? .committed : .read, result: resolved.0, at: cached?.observedAt ?? finishedAt)
            if manifest.effect == .read { await toolState.cacheRead(resolved.0, key: readKey, observedAt: finishedAt) }
            let completion = activityCompletion(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID, detail: "", confirmation: resolved.1, status: .succeeded, startedAt: item.startedAt, finishedAt: finishedAt, fileIdentifier: resolved.0.fileIdentifier, undoAvailable: undoAvailable, automaticApprovalRequest: automaticApprovalRequest)
            await emitter.emit(.activityCompleted(completion))
            await emitter.emit(.toolResultProduced(.init(runID: runID, toolCallID: call.id, toolName: call.name, effect: manifest.effect, assistantTurnID: assistantTurnID, envelope: resolved.0.envelope, sources: resolved.0.sources, file: resolved.0.file, environmentReceipt: resolved.0.environmentReceipt, loadedSkill: resolved.0.loadedSkill, memoryWrite: resolved.0.memoryWrite, loadedTools: resolved.0.loadedTools, producedAt: finishedAt)))
            return .init(
                index: item.index,
                message: .tool(resolved.0.modelContent, toolCallID: call.id, name: call.name),
                sources: resolved.0.sources,
                loadedSkill: resolved.0.loadedSkill,
                loadedTools: resolved.0.loadedTools
            )
        } catch {
            var failure = Self.toolFailure(error)
            if writeAttempted {
                let original = failure
                if let rollback = committedAction?.rollback {
                    do {
                        try await rollback()
                        failure = .init(code: "tool_commit_rolled_back", retryable: false,
                            message: String(format: String(localized: "tool.commit.rolled_back"), original.message))
                    } catch {
                        failure = .init(code: "tool_rollback_failed", retryable: false,
                            message: String(format: String(localized: "tool.commit.rollback_failed"), original.message, error.localizedDescription))
                    }
                } else {
                    failure = .init(code: committedAction == nil ? "tool_commit_unconfirmed" : "tool_persistence_failed", retryable: false,
                        message: String(format: String(localized: "tool.commit.unconfirmed"), original.message))
                }
            } else {
                if error is CancellationError { throw CancellationError() }
                if let agent = error as? FamiliarAgentError, case .durationExceeded = agent { throw FamiliarAgentError.durationExceeded }
            }
            await toolState.record(call: call, status: writeAttempted
                ? (failure.code == "tool_commit_rolled_back" ? .undone : .uncertain) : .failed, detail: failure.code)
            let completion = activityCompletion(runID: runID, call: call, manifest: manifest, assistantTurnID: assistantTurnID,
                detail: failure.message, confirmation: writeAttempted ? writeConfirmation : .notRequired, status: .failed,
                startedAt: item.startedAt, fileIdentifier: committedAction?.result.fileIdentifier, undoAvailable: retainedUndo,
                automaticApprovalRequest: automaticApprovalRequest, failureCode: failure.code, failureRetryable: failure.retryable)
            await emitter.emit(.activityCompleted(completion))
            if error is CancellationError { throw CancellationError() }
            if let agent = error as? FamiliarAgentError, case .durationExceeded = agent { throw FamiliarAgentError.durationExceeded }
            return .init(index: item.index, message: .tool(Self.errorResult(code: failure.code, retryable: failure.retryable, message: failure.message), toolCallID: call.id, name: call.name), sources: [], failed: true)
        }
    }

    private func executeOutcome(
        name: String,
        arguments: String,
        context: FamiliarToolContext,
        allowsRetry: Bool,
        maximumExecutionDuration: TimeInterval,
        emitter: FamiliarRuntimeEventEmitter,
        deadline: ContinuousClock.Instant
    ) async throws -> FamiliarToolOutcome {
        let perform: @Sendable () async throws -> FamiliarToolOutcome = {
            let clock = ContinuousClock()
            let attemptDeadline = min(
                deadline,
                clock.now.advanced(by: .seconds(maximumExecutionDuration))
            )
            return try await Self.withToolDeadline(
                attemptDeadline,
                toolName: name
            ) {
                try await registry.execute(name: name, arguments: arguments, context: context)
            }
        }
        do {
            return try await perform()
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
                failureKind: failureKind,
                toolCallID: context.toolCallID
            )))
            try await Self.sleep(for: delay, deadline: deadline)
            return try await perform()
        }
    }

    private func approve(_ request: FamiliarToolConfirmationRequest, emitter: FamiliarRuntimeEventEmitter,
                         deadline: ContinuousClock.Instant) async throws -> FamiliarToolConfirmationDecision {
        await emitter.emit(.runPhaseChanged(.awaitingApproval))
        let decision = try await Self.withDeadline(deadline) {
            try await confirmationCoordinator.requestConfirmation(request, onPending: {
                await emitter.emit(.approvalRequested(request))
            })
        }
        await emitter.emit(.approvalResolved(requestID: request.id, decision: decision))
        await emitter.emit(.runPhaseChanged(.executingActivities([request.toolName])))
        return decision
    }

    private func activityCompletion(runID: String, call: FamiliarToolCall, manifest: FamiliarToolManifest, assistantTurnID: String, detail: String, confirmation: FamiliarPersistedConfirmationResult, status: FamiliarToolRunTerminalStatus, startedAt: Date, finishedAt: Date = Date(), fileIdentifier: String? = nil, undoAvailable: Bool = false, automaticApprovalRequest: FamiliarToolConfirmationRequest? = nil, failureCode: String? = nil, failureRetryable: Bool? = nil) -> FamiliarRuntimeActivityCompletion {
        .init(runID: runID, toolCallID: call.id, toolName: call.name, effect: manifest.effect, assistantTurnID: assistantTurnID, detail: detail, confirmation: confirmation, status: status, startedAt: startedAt, finishedAt: finishedAt, fileIdentifier: fileIdentifier, undoAvailable: undoAvailable, automaticApprovalRequest: automaticApprovalRequest, failureCode: failureCode, failureRetryable: failureRetryable)
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

    private func compactContext(
        messages: [FamiliarProviderMessage],
        protectedPrefixMessageCount: Int,
        modelID: String,
        maximumInputCharacters: Int,
        protectedTurnIndex: Int?,
        input: FamiliarContextSnapshot,
        runID: String,
        deadline: ContinuousClock.Instant,
        emitter: FamiliarRuntimeEventEmitter
    ) async throws -> (messages: [FamiliarProviderMessage], currentTurnIndex: Int?) {
        guard let selection = FamiliarContextCompiler.compaction(messages: messages,
            protectedPrefixMessageCount: protectedPrefixMessageCount, maximumInputCharacters: maximumInputCharacters, protectedTurnIndex: protectedTurnIndex)
        else { return (messages, protectedTurnIndex) }
        let chunks = FamiliarContextCompiler.compactionChunks(messages: selection.entries, maximumInputCharacters: maximumInputCharacters)
        guard !chunks.isEmpty else { throw FamiliarAgentError.contextCompactionFailed }
        var summary = ""
        for chunk in chunks {
            try Task.checkCancellation()
            try Self.checkDeadline(deadline)
            let compiled = try FamiliarContextCompiler.compileCompaction(modelID: modelID, chunk: chunk,
                previousSummary: summary, maximumInputCharacters: maximumInputCharacters, input: input)
            if let persistCompilation { try await Self.withDeadline(deadline) { try await persistCompilation(runID, compiled.manifest) } }
            let round = try await streamRound(request: compiled.request, emitter: emitter, deadline: deadline, emitsText: false)
            guard round.finishReason == .stop, round.pendingCalls.isEmpty else { throw FamiliarAgentError.contextCompactionFailed }
            summary = try FamiliarContextCompiler.acceptedSummary(round.text, sourceCharacters: chunk.count + summary.count,
                maximumInputCharacters: maximumInputCharacters)
        }
        return (selection.replacing(with: summary), selection.currentTurnIndex)
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

    private static func withToolDeadline<T: Sendable>(
        _ deadline: ContinuousClock.Instant,
        toolName: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let clock = ContinuousClock()
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await clock.sleep(until: deadline)
                throw FamiliarToolExecutionTimeout(toolName: toolName)
            }
            guard let result = try await group.next() else {
                throw FamiliarToolExecutionTimeout(toolName: toolName)
            }
            group.cancelAll()
            return result
        }
    }

    private static func errorResult(_ error: any Error) -> String {
        let failure = toolFailure(error)
        return errorResult(code: failure.code, retryable: failure.retryable, message: failure.message)
    }

    /// Audit and model-facing failures must describe the same failed tool commit.
    private static func toolFailure(_ error: any Error) -> FamiliarToolFailure {
        if let structured = error as? any FamiliarStructuredToolError {
            return .init(
                code: structured.code,
                retryable: structured.isRetryable,
                message: structured.localizedDescription
            )
        }
        let kind = FamiliarRuntimeFailure.kind(for: error)
        return .init(code: kind.code, retryable: kind.isRetryable, message: error.localizedDescription)
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
        let loadedSkill: FamiliarSkillSnapshot?
        let loadedTools: [FamiliarToolManifest]?
        let failed: Bool

        init(
            index: Int,
            message: FamiliarProviderMessage,
            sources: [FamiliarSource],
            loadedSkill: FamiliarSkillSnapshot? = nil,
            loadedTools: [FamiliarToolManifest]? = nil,
            failed: Bool = false
        ) {
            self.index = index
            self.message = message
            self.sources = sources
            self.loadedSkill = loadedSkill
            self.loadedTools = loadedTools
            self.failed = failed
        }
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
