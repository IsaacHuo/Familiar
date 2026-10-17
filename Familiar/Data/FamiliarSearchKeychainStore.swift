import Foundation
import Security

/// Result of reading a search API key. Distinguishes "never configured" from
/// "Keychain temporarily unavailable" so the user sees the real cause.
nonisolated enum FamiliarSearchKeyLookup: Equatable, Sendable {
    case found(String)
    case missing
    case locked
    case failed(OSStatus)

    var key: String? {
        if case .found(let value) = self { return value }
        return nil
    }
}

nonisolated enum FamiliarSearchKeychainStore {
    static let service = "com.isaachuo.familiar.search-provider-api-keys.v1"

    /// Removes paste artifacts: surrounding whitespace, quotes, zero-width
    /// characters and a leading `Bearer ` copied from API documentation.
    static func normalized(_ raw: String) -> String {
        let invisible: Set<Character> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"]
        var value = String(raw.filter { !invisible.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes = CharacterSet(charactersIn: "\"'`“”‘’")
        value = value.trimmingCharacters(in: quotes).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("bearer ") {
            value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    static func lookup(for providerID: String) -> FamiliarSearchKeyLookup {
        var query = baseQuery(for: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { return .failed(status) }
            let key = normalized(value)
            return key.isEmpty ? .missing : .found(key)
        case errSecItemNotFound:
            return .missing
        case errSecInteractionNotAllowed:
            return .locked
        default:
            return .failed(status)
        }
    }

    static func load(for providerID: String) -> String? {
        lookup(for: providerID).key
    }

    static func save(_ value: String, for providerID: String) throws {
        let key = normalized(value)
        guard !key.isEmpty else {
            try delete(for: providerID)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: accessibility
        ]
        let query = baseQuery(for: providerID)
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw FamiliarKeychainError.unexpectedStatus(updateStatus)
        }
        let addQuery = query.merging(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw FamiliarKeychainError.unexpectedStatus(addStatus)
        }
    }

    static func delete(for providerID: String) throws {
        let status = SecItemDelete(baseQuery(for: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FamiliarKeychainError.unexpectedStatus(status)
        }
    }

    static func isConfigured(for providerID: String) -> Bool {
        lookup(for: providerID) != .missing
    }

    /// Searches run while a Run is still finishing after the screen locks, so
    /// the key must stay readable after first unlock.
    private static var accessibility: CFString { kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }

    /// Accessibility is not part of the lookup query, so items written with an
    /// earlier accessibility class still match and are upgraded on next save.
    private static func baseQuery(for providerID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID
        ]
    }
}
