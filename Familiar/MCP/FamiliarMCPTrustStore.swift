import Foundation

/// Per-server trust for HTTP MCP. Untrusted servers are level 4: every remote call
/// asks again, with no reusable grant. Trusted servers are level 3: the first call
/// asks once and the card may then be answered with "always allow this kind".
/// Trust is a user setting, never derived from remote tool annotations, and lives in
/// UserDefaults because it is not secret.
nonisolated struct FamiliarMCPTrustStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(serverID: UUID) -> String {
        "mcp.trust." + serverID.uuidString
    }

    func isTrusted(serverID: UUID) -> Bool {
        defaults.bool(forKey: key(serverID: serverID))
    }

    func setTrusted(_ trusted: Bool, serverID: UUID) {
        if trusted {
            defaults.set(true, forKey: key(serverID: serverID))
        } else {
            removeTrust(serverID: serverID)
        }
    }

    func removeTrust(serverID: UUID) {
        defaults.removeObject(forKey: key(serverID: serverID))
    }
}
