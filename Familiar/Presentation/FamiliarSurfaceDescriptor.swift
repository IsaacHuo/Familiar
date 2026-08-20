import Foundation

nonisolated enum FamiliarSurfaceKind: String, Sendable, Equatable {
    case agentStatus
    case toolActivity
}

nonisolated enum FamiliarSurfacePhase: String, Sendable, Equatable {
    case queued
    case planning
    case running
    case awaitingApproval
    case succeeded
    case failed
    case cancelled
    case undone

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .undone: true
        case .queued, .planning, .running, .awaitingApproval: false
        }
    }
}

nonisolated struct FamiliarSurfaceField: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let value: String
}

/// A stable, semantic description of a single runtime surface. The `id` never
/// changes for the whole lifetime of a surface, so SwiftUI can morph one card
/// through queued -> approval -> running -> terminal without recreating it.
nonisolated struct FamiliarSurfaceDescriptor: Identifiable, Sendable, Equatable {
    var id: String
    var runID: String
    var toolCallID: String?
    var assistantTurnID: String?
    var kind: FamiliarSurfaceKind
    var phase: FamiliarSurfacePhase
    var title: String
    var detail: String?
    var effect: FamiliarToolEffect?
    var fields: [FamiliarSurfaceField]
    var target: String?
    var approvalRequestID: UUID?
    var artifact: FamiliarArtifactDescriptor?
    var startedAt: Date?
    var finishedAt: Date?
    var eventSequence: Int

    init(
        id: String,
        runID: String,
        toolCallID: String? = nil,
        assistantTurnID: String? = nil,
        kind: FamiliarSurfaceKind,
        phase: FamiliarSurfacePhase,
        title: String,
        detail: String? = nil,
        effect: FamiliarToolEffect? = nil,
        fields: [FamiliarSurfaceField] = [],
        target: String? = nil,
        approvalRequestID: UUID? = nil,
        artifact: FamiliarArtifactDescriptor? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        eventSequence: Int
    ) {
        self.id = id
        self.runID = runID
        self.toolCallID = toolCallID
        self.assistantTurnID = assistantTurnID
        self.kind = kind
        self.phase = phase
        self.title = title
        self.detail = detail
        self.effect = effect
        self.fields = fields
        self.target = target
        self.approvalRequestID = approvalRequestID
        self.artifact = artifact
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.eventSequence = eventSequence
    }

    init(snapshot: FamiliarToolRunSnapshot, isUndone: Bool = false) {
        self.init(
            id: FamiliarSurfaceStore.toolID(runID: snapshot.runID, toolCallID: snapshot.toolCallID),
            runID: snapshot.runID,
            toolCallID: snapshot.toolCallID,
            kind: .toolActivity,
            phase: isUndone ? .undone : Self.phase(for: snapshot.status),
            title: snapshot.summary,
            detail: snapshot.detail,
            startedAt: snapshot.startedAt,
            finishedAt: snapshot.finishedAt,
            eventSequence: snapshot.sequence
        )
    }

    static func phase(for status: FamiliarToolRunTerminalStatus) -> FamiliarSurfacePhase {
        switch status {
        case .succeeded: .succeeded
        case .cancelled: .cancelled
        case .failed: .failed
        }
    }

    var isWrite: Bool {
        guard let effect else { return false }
        return effect != .read
    }

    var symbol: String {
        switch phase {
        case .succeeded: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .undone: "arrow.uturn.backward.circle.fill"
        case .awaitingApproval: isWrite ? "checklist.checked" : "hand.raised.fill"
        case .queued: "hourglass"
        case .planning, .running: "circle.dotted"
        }
    }
}

/// Pure reducer that maps `FamiliarRuntimeEvent` into stable surfaces keyed by
/// `runID:toolCallID`. It is a value type so it can be unit-tested without any
/// actor or SwiftUI dependency. Stale events (older sequence) are ignored so a
/// terminal state can never be overwritten by an out-of-order event.
nonisolated struct FamiliarSurfaceStore: Sendable, Equatable {
    private(set) var toolSurfaces: [FamiliarSurfaceDescriptor] = []
    private(set) var agentSurface: FamiliarSurfaceDescriptor?
    private var toolIndex: [String: Int] = [:]

    var orderedSurfaces: [FamiliarSurfaceDescriptor] {
        var result: [FamiliarSurfaceDescriptor] = []
        if let agentSurface {
            result.append(agentSurface)
        }
        result.append(contentsOf: toolSurfaces)
        return result
    }

    var isActive: Bool {
        agentSurface != nil
    }

    var activeRunID: String? {
        agentSurface?.runID
    }

    var pendingApprovalIDs: [UUID] {
        toolSurfaces.filter { $0.phase == .awaitingApproval }.compactMap(\.approvalRequestID)
    }

    static func agentID(runID: String) -> String { "run:\(runID)" }
    static func toolID(runID: String, toolCallID: String) -> String { "tool:\(runID):\(toolCallID)" }

    mutating func reset() {
        toolSurfaces = []
        toolIndex = [:]
        agentSurface = nil
    }

    mutating func apply(_ event: FamiliarRuntimeEvent) {
        switch event.payload {
        case .runStarted:
            upsertAgent(
                runID: event.runID,
                phase: .queued,
                title: String(localized: "agent.status.thinking"),
                eventSequence: event.sequence,
                startedAt: event.timestamp
            )
        case .state(let state):
            updateAgent(state: state, runID: event.runID, eventSequence: event.sequence)
        case .toolRequested(let id, let name, let effect):
            handleToolStart(runID: event.runID, toolCallID: id, assistantTurnID: event.assistantTurnID, title: name, effect: effect, eventSequence: event.sequence)
        case .toolInvocationRequested(let id, let name, _, let effect):
            handleToolStart(runID: event.runID, toolCallID: id, assistantTurnID: event.assistantTurnID, title: name, effect: effect, eventSequence: event.sequence)
        case .toolProgress(let progress):
            updateToolProgress(progress, runID: event.runID, eventSequence: event.sequence)
        case .approvalRequested(let request):
            markAwaitingApproval(request, eventSequence: event.sequence)
        case .approvalResolved(let requestID, let decision):
            resolveApproval(requestID: requestID, decision: decision, eventSequence: event.sequence)
        case .toolFinished(let record):
            finishTool(record, eventSequence: event.sequence)
        case .responseCompleted:
            break
        case .runCompleted:
            finishAgent(runID: event.runID, phase: .succeeded, eventSequence: event.sequence)
        case .runCancelled:
            cancelRun(runID: event.runID, eventSequence: event.sequence)
        case .runFailed(let message):
            failRun(runID: event.runID, message: message, eventSequence: event.sequence)
        case .textDelta:
            break
        }
    }

    // MARK: - Agent status

    private mutating func upsertAgent(
        runID: String,
        phase: FamiliarSurfacePhase,
        title: String,
        eventSequence: Int,
        startedAt: Date
    ) {
        let id = Self.agentID(runID: runID)
        if let existing = agentSurface, existing.runID == runID {
            if eventSequence >= existing.eventSequence {
                agentSurface = FamiliarSurfaceDescriptor(
                    id: id,
                    runID: runID,
                    kind: .agentStatus,
                    phase: phase,
                    title: title,
                    startedAt: existing.startedAt ?? startedAt,
                    eventSequence: eventSequence
                )
            }
            return
        }
        agentSurface = FamiliarSurfaceDescriptor(
            id: id,
            runID: runID,
            kind: .agentStatus,
            phase: phase,
            title: title,
            startedAt: startedAt,
            eventSequence: eventSequence
        )
    }

    private mutating func updateAgent(state: FamiliarRuntimeState, runID: String, eventSequence: Int) {
        guard let existing = agentSurface, existing.runID == runID else { return }
        guard eventSequence >= existing.eventSequence else { return }
        let phase: FamiliarSurfacePhase
        switch state {
        case .thinking: phase = .planning
        case .usingTool: phase = .planning
        case .awaitingApproval: phase = .awaitingApproval
        case .responding: phase = .planning
        }
        agentSurface?.phase = phase
        agentSurface?.title = state.title
        agentSurface?.eventSequence = eventSequence
    }

    private mutating func finishAgent(runID: String, phase: FamiliarSurfacePhase, eventSequence: Int) {
        guard let existing = agentSurface, existing.runID == runID else { return }
        guard eventSequence >= existing.eventSequence else { return }
        agentSurface?.phase = phase
        agentSurface?.eventSequence = eventSequence
    }

    private mutating func failRun(runID: String, message: String, eventSequence: Int) {
        guard let existing = agentSurface, existing.runID == runID else { return }
        guard eventSequence >= existing.eventSequence else { return }
        agentSurface?.phase = .failed
        agentSurface?.detail = message
        agentSurface?.eventSequence = eventSequence
    }

    private mutating func cancelRun(runID: String, eventSequence: Int) {
        finishAgent(runID: runID, phase: .cancelled, eventSequence: eventSequence)
        for index in toolSurfaces.indices where toolSurfaces[index].runID == runID && !toolSurfaces[index].phase.isTerminal {
            toolSurfaces[index].phase = .cancelled
            toolSurfaces[index].eventSequence = eventSequence
        }
    }

    // MARK: - Tool activity

    @discardableResult
    private mutating func upsertTool(
        runID: String,
        toolCallID: String,
        assistantTurnID: String? = nil,
        title: String,
        effect: FamiliarToolEffect? = nil,
        eventSequence: Int
    ) -> Int {
        let surfaceID = Self.toolID(runID: runID, toolCallID: toolCallID)
        if let index = toolIndex[surfaceID] {
            if eventSequence >= toolSurfaces[index].eventSequence, !toolSurfaces[index].phase.isTerminal {
                toolSurfaces[index].title = title
                toolSurfaces[index].assistantTurnID = assistantTurnID ?? toolSurfaces[index].assistantTurnID
                toolSurfaces[index].effect = effect ?? toolSurfaces[index].effect
                toolSurfaces[index].eventSequence = eventSequence
            }
            return index
        }
        let descriptor = FamiliarSurfaceDescriptor(
            id: surfaceID,
            runID: runID,
            toolCallID: toolCallID,
            assistantTurnID: assistantTurnID,
            kind: .toolActivity,
            phase: .queued,
            title: title,
            effect: effect,
            startedAt: Date(),
            eventSequence: eventSequence
        )
        toolSurfaces.append(descriptor)
        toolIndex[surfaceID] = toolSurfaces.count - 1
        return toolSurfaces.count - 1
    }

    private mutating func handleToolStart(runID: String, toolCallID: String, assistantTurnID: String?, title: String, effect: FamiliarToolEffect, eventSequence: Int) {
        if effect == .read {
            guard let existing = agentSurface, existing.runID == runID, eventSequence >= existing.eventSequence else { return }
            agentSurface?.phase = .planning
            agentSurface?.title = FamiliarRuntimeState.usingTool(title).title
            agentSurface?.eventSequence = eventSequence
            return
        }
        upsertTool(runID: runID, toolCallID: toolCallID, assistantTurnID: assistantTurnID, title: title, effect: effect, eventSequence: eventSequence)
    }

    private mutating func updateToolProgress(
        _ progress: FamiliarToolProgress,
        runID: String,
        eventSequence: Int
    ) {
        if progress.effect == .read {
            if progress.state == .running {
                handleToolStart(runID: runID, toolCallID: progress.id, assistantTurnID: nil, title: progress.title, effect: .read, eventSequence: eventSequence)
            }
            return
        }
        let index = upsertTool(runID: runID, toolCallID: progress.id, title: progress.title, effect: progress.effect, eventSequence: eventSequence)
        guard eventSequence >= toolSurfaces[index].eventSequence else { return }
        let phase: FamiliarSurfacePhase
        switch progress.state {
        case .running: phase = .running
        case .succeeded: phase = .succeeded
        case .cancelled: phase = .cancelled
        case .failed: phase = .failed
        }
        toolSurfaces[index].phase = phase
        toolSurfaces[index].title = progress.title
        toolSurfaces[index].detail = progress.detail
        toolSurfaces[index].eventSequence = eventSequence
    }

    private mutating func markAwaitingApproval(
        _ request: FamiliarToolConfirmationRequest,
        eventSequence: Int
    ) {
        let index = upsertTool(runID: request.runID, toolCallID: request.toolCallID, title: request.title, eventSequence: eventSequence)
        guard eventSequence >= toolSurfaces[index].eventSequence else { return }
        let fields = request.fields.keys.sorted().map {
            FamiliarSurfaceField(id: $0, label: $0, value: request.fields[$0] ?? "")
        }
        toolSurfaces[index].phase = .awaitingApproval
        toolSurfaces[index].title = request.title
        toolSurfaces[index].effect = request.effect
        toolSurfaces[index].fields = fields
        toolSurfaces[index].target = request.target
        toolSurfaces[index].approvalRequestID = request.id
        toolSurfaces[index].eventSequence = eventSequence
    }

    private mutating func resolveApproval(
        requestID: UUID,
        decision: FamiliarToolConfirmationDecision,
        eventSequence: Int
    ) {
        guard let index = toolSurfaces.firstIndex(where: { $0.approvalRequestID == requestID }) else { return }
        guard eventSequence >= toolSurfaces[index].eventSequence else { return }
        toolSurfaces[index].phase = decision.isConfirmed ? .running : .cancelled
        toolSurfaces[index].fields = []
        toolSurfaces[index].approvalRequestID = nil
        toolSurfaces[index].eventSequence = eventSequence
    }

    private mutating func finishTool(_ record: FamiliarToolRunTerminalEvent, eventSequence: Int) {
        guard record.effect != .read else { return }
        let index = upsertTool(runID: record.runID, toolCallID: record.toolCallID, assistantTurnID: record.assistantTurnID, title: record.summary, effect: record.effect, eventSequence: eventSequence)
        guard eventSequence >= toolSurfaces[index].eventSequence else { return }
        toolSurfaces[index].phase = FamiliarSurfaceDescriptor.phase(for: record.status)
        toolSurfaces[index].title = record.summary
        toolSurfaces[index].detail = record.detail
        toolSurfaces[index].approvalRequestID = nil
        toolSurfaces[index].artifact = record.artifact
        toolSurfaces[index].startedAt = record.startedAt
        toolSurfaces[index].finishedAt = record.finishedAt
        toolSurfaces[index].eventSequence = eventSequence
    }
}
