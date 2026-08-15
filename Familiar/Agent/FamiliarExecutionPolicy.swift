import Foundation

nonisolated struct FamiliarOneShotAuthorization: Sendable, Equatable {
    enum Source: String, Sendable { case shareExtension, appIntent, deepLink }

    let toolName: String
    let idempotencyKey: String
    let source: Source
}

nonisolated enum FamiliarExecutionPolicyDecision: Equatable, Sendable {
    case execute
    case requestApproval
    case deny(String)
}

nonisolated struct FamiliarExecutionPolicy: Sendable {
    func decide(
        manifest: FamiliarToolManifest,
        availability: FamiliarCapabilityAvailability,
        authorization: FamiliarOneShotAuthorization? = nil,
        idempotencyKey: String
    ) -> FamiliarExecutionPolicyDecision {
        if case .unavailable(let reason) = availability { return .deny(reason) }
        if manifest.effect == .destructiveWrite || manifest.risk == .high { return .requestApproval }
        if manifest.effect == .read {
            return availability == .requestable ? .requestApproval : .execute
        }
        if manifest.effect == .reversibleWrite,
           authorization != nil { return .requestApproval }
        return .requestApproval
    }

    func decide(
        manifest: FamiliarToolManifest,
        availability: FamiliarCapabilityAvailability,
        grant: FamiliarAuthorizationGrant?,
        arguments: String,
        projectID: UUID?,
        now: Date = Date()
    ) -> FamiliarExecutionPolicyDecision {
        if case .unavailable(let reason) = availability { return .deny(reason) }
        if manifest.effect == .destructiveWrite || manifest.risk == .high { return .requestApproval }
        if manifest.effect == .read { return availability == .requestable ? .requestApproval : .execute }
        guard let grant, grant.isValid(for: manifest, arguments: arguments, projectID: projectID, now: now) else {
            return .requestApproval
        }
        return .execute
    }
}
