import Foundation

nonisolated enum FamiliarSurfaceKind: String, Sendable, Equatable {
    case runStatus
    case activityTrace
    case toolSummary
    case approval
    case search
    case context
    case records
    case diff
    case mutationReceipt
    case artifact
    case taskList
    case recommendation
    case insight
    case clarification
    case code
    case share
    case shell
    case failure
}

nonisolated enum FamiliarSurfacePlacement: String, Sendable, Equatable {
    case topLevel
    case trace
}

nonisolated enum FamiliarSurfacePhase: String, Sendable, Equatable {
    case queued
    case planning
    case running
    case awaitingApproval
    case awaitingClarification
    case succeeded
    case failed
    case cancelled
    case undone

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .undone: true
        case .queued, .planning, .running, .awaitingApproval, .awaitingClarification: false
        }
    }
}

nonisolated struct FamiliarSurfaceDescriptor: Identifiable, Sendable, Equatable {
    let id: String
    let runID: String
    var assistantTurnID: String?
    var kind: FamiliarSurfaceKind
    var placement: FamiliarSurfacePlacement
    var phase: FamiliarSurfacePhase
    var title: String
    var detail: String?
    var toolCallID: String?
    var toolName: String?
    var effect: FamiliarToolEffect?
    var approvalRequestID: UUID?
    var approvalFields: [FamiliarApprovalField]
    var approvalTarget: String?
    var approvalRisk: FamiliarToolRisk?
    var approvalConsequence: String?
    var approvalUndoPolicy: FamiliarApprovalUndoPolicy?
    var approvalAllowedAuthorizationDurations: [FamiliarAuthorizationDuration]
    var clarificationRequestID: UUID?
    var clarificationOptions: [FamiliarClarificationOption]
    var clarificationAllowsCustom: Bool
    var clarificationResolution: FamiliarClarificationResolution?
    var resultEnvelope: FamiliarToolResultEnvelope?
    var artifact: FamiliarArtifactDescriptor?
    var context: FamiliarRunContextSummary?
    var startedAt: Date?
    var finishedAt: Date?

    init(
        id: String,
        runID: String,
        assistantTurnID: String? = nil,
        kind: FamiliarSurfaceKind,
        placement: FamiliarSurfacePlacement,
        phase: FamiliarSurfacePhase,
        title: String,
        detail: String? = nil,
        toolCallID: String? = nil,
        toolName: String? = nil,
        effect: FamiliarToolEffect? = nil,
        approvalRequestID: UUID? = nil,
        approvalFields: [FamiliarApprovalField] = [],
        approvalTarget: String? = nil,
        approvalRisk: FamiliarToolRisk? = nil,
        approvalConsequence: String? = nil,
        approvalUndoPolicy: FamiliarApprovalUndoPolicy? = nil,
        approvalAllowedAuthorizationDurations: [FamiliarAuthorizationDuration] = [.once, .session, .always],
        clarificationRequestID: UUID? = nil,
        clarificationOptions: [FamiliarClarificationOption] = [],
        clarificationAllowsCustom: Bool = false,
        clarificationResolution: FamiliarClarificationResolution? = nil,
        resultEnvelope: FamiliarToolResultEnvelope? = nil,
        artifact: FamiliarArtifactDescriptor? = nil,
        context: FamiliarRunContextSummary? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.runID = runID
        self.assistantTurnID = assistantTurnID
        self.kind = kind
        self.placement = placement
        self.phase = phase
        self.title = title
        self.detail = detail
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.effect = effect
        self.approvalRequestID = approvalRequestID
        self.approvalFields = approvalFields
        self.approvalTarget = approvalTarget
        self.approvalRisk = approvalRisk
        self.approvalConsequence = approvalConsequence
        self.approvalUndoPolicy = approvalUndoPolicy
        self.approvalAllowedAuthorizationDurations = approvalAllowedAuthorizationDurations
        self.clarificationRequestID = clarificationRequestID
        self.clarificationOptions = clarificationOptions
        self.clarificationAllowsCustom = clarificationAllowsCustom
        self.clarificationResolution = clarificationResolution
        self.resultEnvelope = resultEnvelope
        self.artifact = artifact
        self.context = context
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    var canUndo: Bool { phase == .succeeded && effect != .read }
}

nonisolated struct FamiliarSurfaceStore: Sendable, Equatable {
    private var descriptors: [String: FamiliarSurfaceDescriptor] = [:]
    private var order: [String] = []
    private var approvalToolIDs: [UUID: String] = [:]

    var orderedSurfaces: [FamiliarSurfaceDescriptor] {
        order.compactMap { descriptors[$0] }
    }

    var isActive: Bool {
        orderedSurfaces.contains { $0.kind == .runStatus && !$0.phase.isTerminal }
    }

    var activeRunID: String? {
        orderedSurfaces.first { $0.kind == .runStatus && !$0.phase.isTerminal }?.runID
    }

    var pendingApprovalIDs: [UUID] {
        orderedSurfaces.compactMap { $0.phase == .awaitingApproval ? $0.approvalRequestID : nil }
    }

    var pendingClarificationIDs: [UUID] {
        orderedSurfaces.compactMap { $0.phase == .awaitingClarification ? $0.clarificationRequestID : nil }
    }

    init() {}

    init(projecting run: FamiliarAgentRunSnapshot) {
        project(run)
    }

    static func projectedSurfaces(for run: FamiliarAgentRunSnapshot) -> [FamiliarSurfaceDescriptor] {
        FamiliarSurfaceStore(projecting: run).orderedSurfaces
    }

    mutating func reset() {
        descriptors.removeAll()
        order.removeAll()
        approvalToolIDs.removeAll()
    }

    mutating func apply(_ event: FamiliarRuntimeEvent) {
        switch event.payload {
        case .runPhaseChanged(let phase):
            updateRunStatus(runID: event.runID, phase: phase, at: event.timestamp)
        case .assistantTurnStarted(let id, _):
            ensureTrace(runID: event.runID, assistantTurnID: id, context: nil, startedAt: event.timestamp)
        case .activityStarted(let activity):
            beginTool(runID: event.runID, assistantTurnID: event.assistantTurnID, toolCallID: activity.id, toolName: activity.toolName, effect: activity.effect, at: activity.startedAt)
        case .activityProgress(let progress):
            updateTool(runID: event.runID, progress: progress, at: event.timestamp)
        case .activityCompleted(let completion):
            finishActivity(completion)
        case .toolResultProduced(let result):
            showResult(result)
        case .toolInvocationRequested:
            break
        case .approvalRequested(let request):
            showApproval(request, assistantTurnID: event.assistantTurnID, at: event.timestamp)
        case .approvalResolved(let requestID, let decision):
            resolveApproval(requestID, decision: decision)
        case .clarificationRequested(let request):
            showClarification(request, assistantTurnID: event.assistantTurnID, at: event.timestamp)
        case .clarificationResolved(let requestID, let resolution):
            resolveClarification(requestID, resolution: resolution, at: event.timestamp)
        case .runtimeNotice(let notice):
            showRuntimeNotice(notice, runID: event.runID, assistantTurnID: event.assistantTurnID, at: event.timestamp)
        case .runFinished(let outcome):
            let phase: FamiliarSurfacePhase = switch outcome.status { case .succeeded: .succeeded; case .cancelled: .cancelled; case .failed: .failed }
            finishRun(runID: event.runID, phase: phase, detail: outcome.message, at: event.timestamp)
        case .responseTextDelta, .reasoningSummaryDelta, .reasoningSummaryCompleted, .responseCompleted:
            break
        }
    }

    private mutating func project(_ run: FamiliarAgentRunSnapshot) {
        if run.status == .running {
            upsert(.init(
                id: runStatusID(run.id),
                runID: run.id,
                kind: .runStatus,
                placement: .topLevel,
                phase: .running,
                title: String(localized: "agent.status.thinking"),
                startedAt: run.startedAt
            ))
        }
        ensureTrace(runID: run.id, assistantTurnID: run.activities.first?.assistantTurnID, context: run.context, startedAt: run.startedAt)

        let approvalsByActivity = Dictionary(uniqueKeysWithValues: run.approvals.map { ($0.activityID, $0) })
        let clarificationsByActivity = Dictionary(uniqueKeysWithValues: run.clarifications.map { ($0.activityID, $0) })
        let resultsByActivity = Dictionary(uniqueKeysWithValues: run.toolResults.map { ($0.activityID, $0) })
        for activity in run.activities where activity.kind == .tool {
            if let approval = approvalsByActivity[activity.activityID], approval.decision == nil {
                upsert(approvalDescriptor(approval, runID: run.id, phase: .awaitingApproval))
                continue
            }
            if let clarification = clarificationsByActivity[activity.activityID] {
                upsert(clarificationDescriptor(clarification, runID: run.id))
                continue
            }
            let result = resultsByActivity[activity.activityID]
            let phase = surfacePhase(activity.phase)
            if activity.effect == .read {
                if let result, let envelope = result.envelope {
                    let placement: FamiliarSurfacePlacement = isTopLevelPresentation(envelope.presentation.name) ? .topLevel : .trace
                    upsert(resultDescriptor(activity: activity, envelope: envelope, placement: placement, artifact: nil))
                } else {
                    upsert(toolDescriptor(activity: activity))
                }
            } else if phase == .failed || phase == .cancelled {
                upsert(failureDescriptor(activity: activity, phase: phase))
            } else if let result, let envelope = result.envelope {
                upsert(resultDescriptor(activity: activity, envelope: envelope, placement: .topLevel, artifact: nil))
            } else {
                upsert(toolDescriptor(activity: activity))
            }
        }
        for activity in run.activities where activity.kind == .runtimeNotice && activity.activityID.contains(":retrying:") {
            upsert(.init(
                id: activity.activityID,
                runID: run.id,
                assistantTurnID: activity.assistantTurnID,
                kind: .activityTrace,
                placement: .trace,
                phase: surfacePhase(activity.phase),
                title: String(localized: "runtime.notice.retrying", defaultValue: "Retrying provider request"),
                detail: runtimeNoticeDetail(activity.detail),
                startedAt: activity.startedAt,
                finishedAt: activity.endedAt
            ))
        }

        if run.status == .failed || run.status == .cancelled {
            let notice = run.responseBlocks.first { $0.kind == .runtimeNotice }
            upsert(.init(
                id: failureID(run.id),
                runID: run.id,
                assistantTurnID: notice?.assistantTurnID,
                kind: .failure,
                placement: .topLevel,
                phase: run.status == .cancelled ? .cancelled : .failed,
                title: run.status == .cancelled ? String(localized: "settings.runs.cancelled", defaultValue: "Cancelled") : String(localized: "settings.runs.failed", defaultValue: "Failed"),
                detail: notice?.content,
                startedAt: run.startedAt,
                finishedAt: run.finishedAt
            ))
        }
    }

    private mutating func beginTool(runID: String, assistantTurnID: String?, toolCallID: String, toolName: String, effect: FamiliarToolEffect, at date: Date) {
        ensureTrace(runID: runID, assistantTurnID: assistantTurnID, context: nil, startedAt: date)
        upsert(.init(
            id: toolID(runID, toolCallID),
            runID: runID,
            assistantTurnID: assistantTurnID,
            kind: .toolSummary,
            placement: effect == .read ? .trace : .topLevel,
            phase: .queued,
            title: FamiliarToolPresentationName.title(for: toolName),
            toolCallID: toolCallID,
            toolName: toolName,
            effect: effect,
            startedAt: date
        ))
    }

    private mutating func updateTool(runID: String, progress: FamiliarRuntimeActivityProgress, at date: Date) {
        ensureTrace(runID: runID, assistantTurnID: nil, context: nil, startedAt: date)
        let id = toolID(runID, progress.id)
        guard var descriptor = descriptors[id] else { return }
        descriptor.phase = .running
        descriptor.detail = progress.detail
        upsert(descriptor)
    }

    private mutating func showApproval(_ request: FamiliarToolConfirmationRequest, assistantTurnID: String?, at date: Date) {
        let id = toolID(request.runID, request.toolCallID)
        approvalToolIDs[request.id] = id
        upsert(.init(
            id: id,
            runID: request.runID,
            assistantTurnID: assistantTurnID,
            kind: .approval,
            placement: .topLevel,
            phase: .awaitingApproval,
            title: FamiliarToolPresentationName.title(for: request.toolName),
            toolCallID: request.toolCallID,
            toolName: request.toolName,
            effect: request.effect,
            approvalRequestID: request.id,
            approvalFields: request.fields,
            approvalTarget: request.target,
            approvalRisk: request.risk,
            approvalConsequence: request.consequence,
            approvalUndoPolicy: request.undoPolicy,
            approvalAllowedAuthorizationDurations: request.allowedAuthorizationDurations,
            startedAt: date
        ))
    }

    private mutating func resolveApproval(_ requestID: UUID, decision: FamiliarToolConfirmationDecision) {
        guard let id = approvalToolIDs[requestID], var descriptor = descriptors[id] else { return }
        descriptor.kind = .toolSummary
        descriptor.phase = decision.isConfirmed ? .running : .cancelled
        descriptor.approvalRequestID = nil
        descriptor.approvalFields = []
        descriptor.detail = decision.isConfirmed ? nil : String(localized: "tool.cancelled_by_user")
        upsert(descriptor)
    }

    private mutating func showClarification(_ request: FamiliarClarificationRequest, assistantTurnID: String?, at date: Date) {
        upsert(.init(
            id: clarificationID(request.runID, request.id),
            runID: request.runID,
            assistantTurnID: assistantTurnID,
            kind: .clarification,
            placement: .topLevel,
            phase: .awaitingClarification,
            title: request.question,
            toolCallID: request.toolCallID,
            toolName: "ask_user",
            effect: .read,
            clarificationRequestID: request.id,
            clarificationOptions: request.options,
            clarificationAllowsCustom: request.allowCustom,
            startedAt: date
        ))
    }

    private mutating func resolveClarification(_ requestID: UUID, resolution: FamiliarClarificationResolution, at date: Date) {
        guard let key = descriptors.keys.first(where: { descriptors[$0]?.clarificationRequestID == requestID }),
              var descriptor = descriptors[key]
        else { return }
        descriptor.phase = resolution.answer == nil ? .cancelled : .succeeded
        descriptor.clarificationResolution = resolution
        descriptor.finishedAt = date
        upsert(descriptor)
    }

    private mutating func finishActivity(_ event: FamiliarRuntimeActivityCompletion) {
        ensureTrace(runID: event.runID, assistantTurnID: event.assistantTurnID, context: nil, startedAt: event.startedAt)
        let phase = surfacePhase(event.status)
        guard event.effect != .read else { return }
        if phase == .failed || phase == .cancelled {
            upsert(failureDescriptor(activity: transientActivity(event, phase: phase), phase: phase))
        } else {
            upsert(toolDescriptor(activity: transientActivity(event, phase: phase)))
        }
    }

    private mutating func showResult(_ event: FamiliarToolResultProduced) {
        ensureTrace(runID: event.runID, assistantTurnID: event.assistantTurnID, context: nil, startedAt: event.producedAt)
        let activity = FamiliarActivitySnapshot(activityID: toolID(event.runID, event.toolCallID), parentID: traceID(event.runID), assistantTurnID: event.assistantTurnID, kind: .tool, effect: event.effect, phase: .succeeded, toolName: event.toolName, toolCallID: event.toolCallID, summary: event.toolName, detail: nil, progress: 1, resultRecordID: nil, approvalRecordID: nil, sequence: 0, startedAt: descriptors[toolID(event.runID, event.toolCallID)]?.startedAt ?? event.producedAt, endedAt: event.producedAt)
        let placement: FamiliarSurfacePlacement = event.effect == .read && !isTopLevelPresentation(event.envelope.presentation.name) ? .trace : .topLevel
        let result = resultDescriptor(activity: activity, envelope: event.envelope, placement: placement, artifact: event.artifact)
        if result.id != activity.activityID {
            descriptors.removeValue(forKey: activity.activityID)
        }
        upsert(result)
    }

    private mutating func showRuntimeNotice(_ notice: FamiliarRuntimeNotice, runID: String, assistantTurnID: String?, at date: Date) {
        ensureTrace(runID: runID, assistantTurnID: assistantTurnID, context: nil, startedAt: date)
        let detail = String(format: String(localized: "runtime.notice.retrying.detail", defaultValue: "Attempt %lld in %.1f s (%@)"), notice.attempt, notice.delay, notice.failureKind.code)
        upsert(.init(id: "notice:\(runID):\(notice.kind.rawValue):\(notice.attempt)", runID: runID, assistantTurnID: assistantTurnID, kind: .activityTrace, placement: .trace, phase: .running, title: String(localized: "runtime.notice.retrying", defaultValue: "Retrying provider request"), detail: detail, startedAt: date))
    }

    private mutating func updateRunStatus(runID: String, phase: FamiliarRunPhase, at date: Date) {
        var descriptor = descriptors[runStatusID(runID)] ?? .init(id: runStatusID(runID), runID: runID, kind: .runStatus, placement: .topLevel, phase: .queued, title: String(localized: "agent.status.thinking"), startedAt: date)
        descriptor.phase = switch phase {
        case .awaitingApproval: .awaitingApproval
        case .awaitingClarification: .awaitingClarification
        default: .planning
        }
        descriptor.title = switch phase {
        case .starting, .reasoning: String(localized: "agent.status.thinking")
        case .responding: String(localized: "agent.status.responding")
        case .awaitingApproval: String(localized: "agent.status.awaiting_confirmation")
        case .awaitingClarification: String(localized: "clarification.awaiting", defaultValue: "Waiting for your answer")
        case .executingActivities(let names):
            names.count == 1
                ? String(format: String(localized: "agent.status.using_tool"), FamiliarToolPresentationName.title(for: names[0]))
                : String(localized: "agent.status.using_tools", defaultValue: "Using tools")
        }
        upsert(descriptor)
    }

    private mutating func finishRun(runID: String, phase: FamiliarSurfacePhase, detail: String?, at date: Date) {
        if var status = descriptors[runStatusID(runID)] {
            status.phase = phase
            status.detail = detail
            status.finishedAt = date
            upsert(status)
        }
        guard phase == .failed || phase == .cancelled else { return }
        upsert(.init(
            id: failureID(runID),
            runID: runID,
            kind: .failure,
            placement: .topLevel,
            phase: phase,
            title: phase == .cancelled ? String(localized: "settings.runs.cancelled", defaultValue: "Cancelled") : String(localized: "settings.runs.failed", defaultValue: "Failed"),
            detail: detail,
            finishedAt: date
        ))
    }

    private mutating func ensureTrace(runID: String, assistantTurnID: String?, context: FamiliarRunContextSummary?, startedAt: Date) {
        let id = traceID(runID)
        if var existing = descriptors[id] {
            existing.assistantTurnID = existing.assistantTurnID ?? assistantTurnID
            existing.context = existing.context ?? context
            upsert(existing)
            return
        }
        upsert(.init(
            id: id,
            runID: runID,
            assistantTurnID: assistantTurnID,
            kind: .activityTrace,
            placement: .topLevel,
            phase: .running,
            title: String(localized: "message.operation_trace", defaultValue: "Activity"),
            context: context,
            startedAt: startedAt
        ))
    }

    private mutating func upsert(_ descriptor: FamiliarSurfaceDescriptor) {
        if descriptors[descriptor.id] == nil { order.append(descriptor.id) }
        descriptors[descriptor.id] = descriptor
    }

    private func approvalDescriptor(_ approval: FamiliarApprovalSnapshot, runID: String, phase: FamiliarSurfacePhase) -> FamiliarSurfaceDescriptor {
        .init(
            id: approval.activityID,
            runID: runID,
            assistantTurnID: approval.assistantTurnID,
            kind: .approval,
            placement: .topLevel,
            phase: phase,
            title: FamiliarToolPresentationName.title(for: approval.toolName),
            toolCallID: approval.toolCallID,
            toolName: approval.toolName,
            effect: approval.effect,
            approvalRequestID: approval.id,
            approvalFields: approval.fields,
            approvalTarget: approval.target,
            approvalRisk: approval.risk,
            approvalConsequence: approval.consequence,
            approvalUndoPolicy: approval.undoPolicy,
            startedAt: approval.requestedAt,
            finishedAt: approval.resolvedAt
        )
    }

    private func clarificationDescriptor(_ clarification: FamiliarClarificationSnapshot, runID: String) -> FamiliarSurfaceDescriptor {
        let phase: FamiliarSurfacePhase = switch clarification.state {
        case .requested: .awaitingClarification
        case .resolved: .succeeded
        case .cancelled: .cancelled
        case .interrupted: .failed
        }
        return .init(
            id: clarificationID(runID, clarification.id),
            runID: runID,
            assistantTurnID: clarification.assistantTurnID,
            kind: .clarification,
            placement: .topLevel,
            phase: phase,
            title: clarification.question,
            detail: clarification.state == .interrupted ? String(localized: "clarification.interrupted", defaultValue: "This question was interrupted and can no longer be answered.") : nil,
            toolCallID: clarification.toolCallID,
            toolName: "ask_user",
            effect: .read,
            clarificationRequestID: clarification.state == .requested ? clarification.id : nil,
            clarificationOptions: clarification.options,
            clarificationAllowsCustom: clarification.allowCustom,
            clarificationResolution: clarification.resolution,
            startedAt: clarification.requestedAt,
            finishedAt: clarification.resolvedAt
        )
    }

    private func toolDescriptor(activity: FamiliarActivitySnapshot) -> FamiliarSurfaceDescriptor {
        .init(
            id: activity.activityID,
            runID: runtimeID(from: activity.activityID),
            assistantTurnID: activity.assistantTurnID,
            kind: .toolSummary,
            placement: activity.effect == .read ? .trace : .topLevel,
            phase: surfacePhase(activity.phase),
            title: activity.toolName.map { FamiliarToolPresentationName.title(for: $0) } ?? activity.summary,
            detail: activity.detail,
            toolCallID: activity.toolCallID,
            toolName: activity.toolName,
            effect: activity.effect,
            startedAt: activity.startedAt,
            finishedAt: activity.endedAt
        )
    }

    private func failureDescriptor(activity: FamiliarActivitySnapshot, phase: FamiliarSurfacePhase) -> FamiliarSurfaceDescriptor {
        .init(
            id: activity.activityID,
            runID: runtimeID(from: activity.activityID),
            assistantTurnID: activity.assistantTurnID,
            kind: .failure,
            placement: .topLevel,
            phase: phase,
            title: activity.toolName.map { FamiliarToolPresentationName.title(for: $0) } ?? activity.summary,
            detail: activity.detail,
            toolCallID: activity.toolCallID,
            toolName: activity.toolName,
            effect: activity.effect,
            startedAt: activity.startedAt,
            finishedAt: activity.endedAt
        )
    }

    private func resultDescriptor(activity: FamiliarActivitySnapshot, envelope: FamiliarToolResultEnvelope, placement: FamiliarSurfacePlacement, artifact: FamiliarArtifactDescriptor?) -> FamiliarSurfaceDescriptor {
        let isFileExport = activity.toolName == "prepare_file_export"
        return .init(
            id: resultSurfaceID(activity: activity, envelope: envelope),
            runID: runtimeID(from: activity.activityID),
            assistantTurnID: activity.assistantTurnID,
            kind: isFileExport ? .share : surfaceKind(envelope.presentation.name, hasArtifact: artifact != nil),
            placement: isFileExport ? .topLevel : placement,
            phase: surfacePhase(activity.phase),
            title: envelope.summary,
            detail: activity.detail,
            toolCallID: activity.toolCallID,
            toolName: activity.toolName,
            effect: activity.effect,
            resultEnvelope: envelope,
            artifact: artifact,
            startedAt: activity.startedAt,
            finishedAt: activity.endedAt
        )
    }

    private func transientActivity(_ event: FamiliarRuntimeActivityCompletion, phase: FamiliarSurfacePhase) -> FamiliarActivitySnapshot {
        .init(
            activityID: toolID(event.runID, event.toolCallID),
            parentID: traceID(event.runID),
            assistantTurnID: event.assistantTurnID,
            kind: .tool,
            effect: event.effect,
            phase: activityPhase(phase),
            toolName: event.toolName,
            toolCallID: event.toolCallID,
            summary: event.toolName,
            detail: event.detail,
            progress: 1,
            resultRecordID: nil,
            approvalRecordID: nil,
            sequence: 0,
            startedAt: event.startedAt,
            endedAt: event.finishedAt
        )
    }

    private func surfaceKind(_ name: FamiliarToolPresentationPayload.Name, hasArtifact: Bool) -> FamiliarSurfaceKind {
        if hasArtifact { return .artifact }
        return switch name {
        case .searchResults: .search
        case .contextMatches, .document, .scalar: .context
        case .recordCollection: .records
        case .mutationReceipt: .mutationReceipt
        case .diff: .diff
        case .artifactMutation: .artifact
        case .taskList: .taskList
        case .recommendation: .recommendation
        case .insight: .insight
        case .code: .code
        case .shareDraft: .share
        case .shellExecution: .shell
        }
    }

    private func isTopLevelPresentation(_ name: FamiliarToolPresentationPayload.Name) -> Bool {
        switch name {
        case .contextMatches, .recordCollection, .diff, .taskList, .recommendation, .insight, .code, .shareDraft, .shellExecution: true
        case .scalar, .searchResults, .document, .mutationReceipt, .artifactMutation: false
        }
    }

    private func resultSurfaceID(activity: FamiliarActivitySnapshot, envelope: FamiliarToolResultEnvelope) -> String {
        if case .taskList(let taskList) = envelope.presentation.content {
            return "task-plan:\(runtimeID(from: activity.activityID)):\(taskList.planID)"
        }
        return activity.activityID
    }

    private func surfacePhase(_ phase: FamiliarActivityPhase) -> FamiliarSurfacePhase {
        switch phase {
        case .queued: .queued
        case .running: .running
        case .awaitingApproval: .awaitingApproval
        case .awaitingClarification: .awaitingClarification
        case .succeeded: .succeeded
        case .failed: .failed
        case .cancelled: .cancelled
        case .undone: .undone
        }
    }

    private func surfacePhase(_ status: FamiliarToolRunTerminalStatus) -> FamiliarSurfacePhase {
        switch status {
        case .succeeded: .succeeded
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }

    private func activityPhase(_ phase: FamiliarSurfacePhase) -> FamiliarActivityPhase {
        switch phase {
        case .queued: .queued
        case .planning, .running: .running
        case .awaitingApproval: .awaitingApproval
        case .awaitingClarification: .awaitingClarification
        case .succeeded: .succeeded
        case .failed: .failed
        case .cancelled: .cancelled
        case .undone: .undone
        }
    }

    private func runtimeID(from activityID: String) -> String {
        let parts = activityID.split(separator: ":", maxSplits: 2)
        return parts.count > 1 ? String(parts[1]) : activityID
    }

}

nonisolated enum FamiliarToolPresentationName {
    static func title(for name: String) -> String {
        switch name {
        case "current_date_time": String(localized: "tool.date_time")
        case "app_information": String(localized: "tool.app_information")
        case "contacts_search": String(localized: "tool.contacts_search", defaultValue: "Search contacts")
        case "current_location": String(localized: "tool.current_location", defaultValue: "Current location")
        case "clipboard_read": String(localized: "tool.clipboard_read", defaultValue: "Read clipboard")
        case "clipboard_write": String(localized: "tool.clipboard_write", defaultValue: "Write clipboard")
        case "prepare_share": String(localized: "tool.prepare_share", defaultValue: "Prepare share")
        case "familiar_search": String(localized: "tool.familiar_search", defaultValue: "Search Familiar")
        case "web_search": String(localized: "tool.web_search", defaultValue: "Search the web")
        case "web_fetch": String(localized: "tool.web_fetch", defaultValue: "Read web page")
        case "calendar_events": String(localized: "tool.calendar_query")
        case "create_calendar_event": String(localized: "tool.calendar_create")
        case "update_calendar_event": String(localized: "tool.calendar_update", defaultValue: "Update calendar event")
        case "delete_calendar_event": String(localized: "tool.calendar_delete", defaultValue: "Delete calendar event")
        case "reminders": String(localized: "tool.reminders_query")
        case "create_reminder": String(localized: "tool.reminder_create")
        case "update_reminder": String(localized: "tool.reminder_update", defaultValue: "Update reminder")
        case "delete_reminder": String(localized: "tool.reminder_delete", defaultValue: "Delete reminder")
        case "photos_save_output": String(localized: "tool.photos_save_output", defaultValue: "Save image to Photos")
        case "prepare_file_export": String(localized: "tool.prepare_file_export", defaultValue: "Prepare file export")
        case "shell_execute": String(localized: "tool.shell_execute", defaultValue: "Run Workspace Shell")
        case "workspace_list": String(localized: "tool.workspace_list", defaultValue: "List workspace files")
        case "workspace_read": String(localized: "tool.workspace_read", defaultValue: "Read workspace file")
        case "workspace_search": String(localized: "tool.workspace_search", defaultValue: "Search workspace files")
        case "workspace_write": String(localized: "tool.workspace_write", defaultValue: "Write workspace output")
        case "workspace_image_list": String(localized: "tool.workspace_image_list", defaultValue: "List workspace images")
        case "resource_list": String(localized: "tool.resource_list", defaultValue: "List project resources")
        case "resource_read": String(localized: "tool.resource_read", defaultValue: "Read project resource")
        case "resource_search": String(localized: "tool.resource_search", defaultValue: "Search project resources")
        case "artifact_write": String(localized: "tool.artifact_write", defaultValue: "Write artifact")
        case "artifact_edit": String(localized: "tool.artifact_edit", defaultValue: "Edit artifact")
        case "task_plan": String(localized: "tool.task_plan", defaultValue: "Task plan")
        case "present_recommendation": String(localized: "tool.present_recommendation", defaultValue: "Recommendation")
        case "present_insight": String(localized: "tool.present_insight", defaultValue: "Insight")
        case "ask_user": String(localized: "tool.ask_user", defaultValue: "Clarification")
        default: name.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }
    }
}

private extension FamiliarSurfaceStore {
    nonisolated func runtimeNoticeDetail(_ value: String?) -> String? {
        guard let value else { return nil }
        let fields = Dictionary(uniqueKeysWithValues: value.split(separator: ";").compactMap { component -> (String, String)? in
            let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
            return pair.count == 2 ? (pair[0], pair[1]) : nil
        })
        guard let attempt = fields["attempt"].flatMap(Int.init),
              let delay = fields["delay"].flatMap(Double.init),
              let failure = fields["failure"]
        else { return value }
        return String(format: String(localized: "runtime.notice.retrying.detail", defaultValue: "Attempt %lld in %.1f s (%@)"), attempt, delay, failure)
    }

    nonisolated private func runStatusID(_ runID: String) -> String { "run-status:\(runID)" }
    nonisolated private func traceID(_ runID: String) -> String { "trace:\(runID)" }
    nonisolated private func toolID(_ runID: String, _ toolCallID: String) -> String { "tool:\(runID):\(toolCallID)" }
    nonisolated private func failureID(_ runID: String) -> String { "failure:\(runID)" }
    nonisolated private func clarificationID(_ runID: String, _ requestID: UUID) -> String { "clarification:\(runID):\(requestID.uuidString)" }
}
