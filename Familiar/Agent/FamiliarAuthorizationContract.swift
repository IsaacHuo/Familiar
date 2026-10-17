import Foundation

nonisolated public enum FamiliarAuthorizationDuration: String, Codable, CaseIterable, Sendable {
    case once
    case session
    case always
}

nonisolated protocol FamiliarAuthorizationServicing: Sendable {
    func matchingAuthorizationScope(manifest: FamiliarToolManifest, arguments: String, scope: FamiliarWorkScope?, targetKey: String) async throws -> FamiliarAuthorizationDuration?
    func issueAuthorization(duration: FamiliarAuthorizationDuration, manifest: FamiliarToolManifest, arguments: String, scope: FamiliarWorkScope?, targetKey: String, evidence: String) async throws
}

