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
           authorization?.toolName == manifest.name,
           authorization?.idempotencyKey == idempotencyKey {
            return .execute
        }
        return .requestApproval
    }
}
