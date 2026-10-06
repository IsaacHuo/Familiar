import Foundation

nonisolated enum FamiliarExecutionPolicyDecision: Equatable, Sendable {
    case allow
    case requireApproval
    case deny(String)
}

nonisolated struct FamiliarPolicyEvaluation: Sendable {
    let decision: FamiliarExecutionPolicyDecision
    let approval: FamiliarToolConfirmationRequest?
    let authorizationScope: FamiliarAuthorizationDuration?
    let automatic: Bool
}

/// Single action decision boundary. Runtime transports approvals and enforces deadlines;
/// exact authorization lookup/issuance and permission/scope decisions belong here.
nonisolated struct FamiliarExecutionPolicy: Sendable {
    func scopeViolation(toolName: String, exposed: Bool, skill: FamiliarSkillSnapshot?) -> String? {
        if !exposed { return "tool_not_exposed" }
        if !FamiliarToolGroup.allows(toolName, skill: skill) { return "skill_tool_scope_denied" }
        return nil
    }

    func evaluate(manifest: FamiliarToolManifest, call: FamiliarToolCall, context: FamiliarToolContext,
                  availability: FamiliarCapabilityAvailability, assessment: FamiliarToolAuthorizationAssessment,
                  proposal: FamiliarActionProposal? = nil, authorization: (any FamiliarAuthorizationServicing)?) async throws -> FamiliarPolicyEvaluation {
        func denied(_ reason: String) -> FamiliarPolicyEvaluation {
            .init(decision: .deny(reason), approval: nil, authorizationScope: nil, automatic: false)
        }
        if case .unavailable(let reason) = availability { return denied(reason) }
        if case .denied(let reason) = assessment.disposition { return denied(reason) }
        if manifest.requiredScopes.contains("project"), context.projectID == nil { return denied("This tool requires a Project.") }
        if let reason = scopeViolation(toolName: call.name, exposed: true, skill: context.activeSkill) { return denied(reason) }
        guard assessment.effect == manifest.effect else { return denied("The preflight effect differs from the tool declaration.") }
        let effect = proposal?.effect ?? assessment.effect
        let risk = Self.maximumRisk(manifest.risk, assessment.risk, proposal?.risk ?? manifest.risk)
        let offlineShell = manifest.name == "shell_execute" && manifest.source == .builtIn
            && effect == .reversibleWrite && risk == .low && assessment.disposition == .automatic
        let ordinaryRead = manifest.effect == .read && proposal == nil && risk != .high
            && assessment.disposition == .automatic && availability == .available
        if ordinaryRead || offlineShell {
            return .init(decision: .allow, approval: nil, authorizationScope: nil, automatic: true)
        }
        if manifest.effect != .read, proposal == nil {
            return .init(decision: .requireApproval, approval: nil, authorizationScope: nil, automatic: false)
        }
        let targetKey = proposal?.targetKey ?? assessment.targetKey
        let durations: [FamiliarAuthorizationDuration] = manifest.effect == .read ? [.once, .session] : (proposal?.allowedAuthorizationDurations ?? [.once])
        let mayReuse = manifest.source != .mcp && (effect == .read || (effect == .reversibleWrite && risk != .high))
        let scope = mayReuse ? try await authorization?.matchingAuthorizationScope(manifest: manifest,
            arguments: call.arguments, projectID: context.projectID, targetKey: targetKey) : nil
        let reused = scope.flatMap { durations.contains($0) ? $0 : nil }
        let fields = proposal?.fields ?? (assessment.fields.isEmpty
            ? [.init(id: "access_scope", label: String(localized: "approval.field.scope", defaultValue: "Scope"), type: .text, value: manifest.description)] : assessment.fields)
        let request = FamiliarToolConfirmationRequest(runID: context.runID, toolCallID: call.id, toolName: call.name,
            effect: effect, risk: risk, title: proposal?.title ?? manifest.title, fields: fields,
            target: proposal?.target ?? targetKey,
            consequence: proposal?.consequence ?? (assessment.consequence.isEmpty ? manifest.description : assessment.consequence),
            undoPolicy: proposal?.undoPolicy ?? .unavailable, automaticAuthorization: reused != nil,
            automaticAuthorizationScope: reused, allowedAuthorizationDurations: durations)
        return .init(decision: reused == nil ? .requireApproval : .allow, approval: request,
                     authorizationScope: reused, automatic: false)
    }

    /// Called after permission preparation and immediately before reading/committing.
    /// A changed concrete target, risk or preflight contract invalidates approval.
    func allowsParallelRead(manifest: FamiliarToolManifest, assessment: FamiliarToolAuthorizationAssessment,
                            availability: FamiliarCapabilityAvailability) -> Bool {
        manifest.effect == .read && manifest.supportsParallelism && availability == .available
            && assessment.effect == .read && assessment.disposition == .automatic
            && manifest.risk != .high && assessment.risk != .high
    }

    func revalidate(approved: FamiliarToolAuthorizationAssessment, current: FamiliarToolAuthorizationAssessment,
                    availability: FamiliarCapabilityAvailability) throws {
        guard approved == current else { throw FamiliarPolicyError.changedDuringApproval }
        guard availability == .available else { throw FamiliarPolicyError.permissionUnavailable }
        if case .denied = current.disposition { throw FamiliarPolicyError.changedDuringApproval }
    }

    func validateTarget(_ proposal: FamiliarActionProposal) async throws {
        try await proposal.validateBeforeCommit?()
    }

    func revalidateAuthorization(evaluation: FamiliarPolicyEvaluation, manifest: FamiliarToolManifest,
                                 call: FamiliarToolCall, projectID: UUID?, targetKey: String,
                                 authorization: (any FamiliarAuthorizationServicing)?) async throws {
        guard let scope = evaluation.authorizationScope, scope != .once else { return }
        guard try await authorization?.matchingAuthorizationScope(manifest: manifest, arguments: call.arguments,
            projectID: projectID, targetKey: targetKey) == scope else { throw FamiliarPolicyError.changedDuringApproval }
    }

    func recordApproval(_ decision: FamiliarToolConfirmationDecision, evaluation: FamiliarPolicyEvaluation,
                        manifest: FamiliarToolManifest, call: FamiliarToolCall, projectID: UUID?, targetKey: String,
                        authorization: (any FamiliarAuthorizationServicing)?) async throws {
        guard evaluation.authorizationScope == nil, !evaluation.automatic,
              let duration = decision.authorizationDuration, duration != .once,
              evaluation.approval?.allowedAuthorizationDurations.contains(duration) == true,
              let authorization else { return }
        try await authorization.issueAuthorization(duration: duration, manifest: manifest, arguments: call.arguments,
            projectID: projectID, targetKey: targetKey, evidence: evaluation.approval?.title ?? manifest.title)
    }

    private static func maximumRisk(_ values: FamiliarToolRisk...) -> FamiliarToolRisk {
        if values.contains(.high) { return .high }
        if values.contains(.sensitive) { return .sensitive }
        return .low
    }
}

nonisolated enum FamiliarPolicyError: LocalizedError, FamiliarStructuredToolError, Equatable, Sendable {
    case changedDuringApproval, permissionUnavailable
    var code: String { self == .changedDuringApproval ? "policy_changed_during_approval" : "policy_permission_unavailable" }
    var isRetryable: Bool { false }
    var errorDescription: String? {
        switch self {
        case .changedDuringApproval: "The action target or execution conditions changed. Request fresh approval before retrying."
        case .permissionUnavailable: "The required permission is unavailable. No action was started."
        }
    }
}
