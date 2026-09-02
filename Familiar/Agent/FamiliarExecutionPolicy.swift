import Foundation

nonisolated enum FamiliarExecutionPolicyDecision: Equatable, Sendable {
    case execute
    case requestApproval
    case deny(String)
}

/// Pure, stateless gate applied before any tool runs.
///
/// Persisted authorizations are matched by `FamiliarAuthorizationRuntime`, which
/// requires SwiftData and a session identity. An earlier overload accepted a
/// `FamiliarAuthorizationGrant` here, but production always passed `nil`, so it
/// was a second authorization path that never actually granted anything. The
/// source-based `FamiliarOneShotAuthorization` overload had no production caller
/// at all. Both are removed rather than kept as unused branches.
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
