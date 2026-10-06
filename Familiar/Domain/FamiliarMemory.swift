import Foundation

nonisolated enum FamiliarMemoryScope: String, Codable, Sendable, CaseIterable { case global, project, conversation }
nonisolated enum FamiliarMemoryCreator: String, Codable, Sendable { case user, agentConfirmed }

/// A memory the Agent proposed and the user approved. Tools are `nonisolated` and have
/// no SwiftData access, so the controller's commit callback persists the write before
/// the runtime emits its successful result.
nonisolated struct FamiliarMemoryWriteRequest: Equatable, Sendable {
    let content: String
    let scope: FamiliarMemoryScope
    let projectID: UUID?
    let conversationID: UUID?
    let provenance: String
}


nonisolated enum FamiliarMemoryPolicy {
    // `nonisolated` because the tool layer is nonisolated and must apply the same limit
    // and the same sensitive-content rule as the persistence boundary. Duplicating them
    // there would let the two drift apart.
    nonisolated static let maximumContentLength = 2_000

    /// Refused at the write boundary rather than cleaned up afterwards: once a secret is
    /// stored it is also already eligible to be compiled back into a prompt.
    nonisolated static func looksSensitive(_ content: String) -> Bool {
        let value = content.lowercased()
        let markers = [
            "api key", "api-key", "apikey", "secret", "password", "passphrase",
            "private key", "access token", "bearer ", "credit card", "cvv",
            "身份证", "密码", "密钥", "银行卡", "验证码"
        ]
        if markers.contains(where: value.contains) { return true }
        // Common provider key shapes, which carry no descriptive marker of their own.
        if value.contains("sk-") || value.contains("ghp_") || value.contains("xoxb-") { return true }
        return false
    }

}
