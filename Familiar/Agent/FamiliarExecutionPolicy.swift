import Foundation

nonisolated enum FamiliarExecutionPolicyDecision: Equatable, Sendable {
    case execute
    case requestApproval
    case deny(String)
}

/// Pure, stateless gate applied before any tool runs.
///
/// Persisted authorizations are matched only by `FamiliarAuthorizationRuntime`
/// against exact arguments, target, Project, capability version and session.
nonisolated struct FamiliarExecutionPolicy: Sendable {
    func decide(
        manifest: FamiliarToolManifest,
        availability: FamiliarCapabilityAvailability
    ) -> FamiliarExecutionPolicyDecision {
        if case .unavailable(let reason) = availability { return .deny(reason) }
        if manifest.effect == .destructiveWrite || manifest.risk == .high { return .requestApproval }
        if manifest.effect == .read { return availability == .requestable ? .requestApproval : .execute }
        return .requestApproval
    }
}
