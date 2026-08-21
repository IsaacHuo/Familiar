import Foundation
import Security

nonisolated enum FamiliarSearchKeychainStore {
    static let service = "com.isaachuo.familiar.search-provider-api-keys.v1"

    static func load(for providerID: String) -> String? {
        var query = baseQuery(for: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func save(_ value: String, for providerID: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete(for: providerID)
            return
        }

        let query = baseQuery(for: providerID)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: Data(trimmed.utf8)] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw FamiliarKeychainError.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = Data(trimmed.utf8)
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
        load(for: providerID) != nil
    }

    private static func baseQuery(for providerID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}
