import Foundation
import SwiftData

nonisolated public enum FamiliarAuthorizationDuration: String, Codable, CaseIterable, Sendable {
    case once
    case session
    case always
}

nonisolated protocol FamiliarAuthorizationServicing: Sendable {
    func matchingAuthorizationScope(manifest: FamiliarToolManifest, arguments: String, projectID: UUID?, targetKey: String) async -> FamiliarAuthorizationDuration?
    func issueAuthorization(duration: FamiliarAuthorizationDuration, manifest: FamiliarToolManifest, arguments: String, projectID: UUID?, targetKey: String, evidence: String) async throws
}

@MainActor
final class FamiliarAuthorizationRuntime: FamiliarAuthorizationServicing {
    private let context: ModelContext
    private let sessionID: String

    init(context: ModelContext, sessionID: String) {
        self.context = context
        self.sessionID = sessionID
    }

    func matchingAuthorizationScope(manifest: FamiliarToolManifest, arguments: String, projectID: UUID?, targetKey: String) -> FamiliarAuthorizationDuration? {
        let now = Date()
        let records = (try? context.fetch(FetchDescriptor<FamiliarAuthorizationRuleRecord>())) ?? []
        let argumentHash = FamiliarAuthorizationGrant.argumentsHash(arguments)
        guard let record = records.first(where: {
            $0.revokedAt == nil && $0.expiresAt > now && $0.projectID == projectID
                && $0.capabilityID == manifest.id && $0.capabilityVersion == manifest.version
                && $0.targetKey == targetKey
                && $0.argumentsHash == argumentHash
                && ($0.duration != .session || $0.sessionID == sessionID)
        }) else { return nil }
        record.lastUsedAt = now
        if record.duration == .once { record.revokedAt = now }
        try? context.save()
        return record.duration
    }

    func issueAuthorization(duration: FamiliarAuthorizationDuration, manifest: FamiliarToolManifest, arguments: String, projectID: UUID?, targetKey: String, evidence: String) throws {
        let now = Date()
        let lifetime: TimeInterval = switch duration {
        case .once: 10 * 60
        case .session: 24 * 60 * 60
        case .always: 365 * 24 * 60 * 60
        }
        context.insert(FamiliarAuthorizationRuleRecord(
            projectID: projectID,
            capabilityID: manifest.id,
            capabilityVersion: manifest.version,
            targetKey: targetKey,
            argumentsHash: FamiliarAuthorizationGrant.argumentsHash(arguments),
            duration: duration,
            sessionID: duration == .session ? sessionID : nil,
            expiresAt: now.addingTimeInterval(lifetime),
            evidence: evidence
        ))
        try context.save()
    }
}
