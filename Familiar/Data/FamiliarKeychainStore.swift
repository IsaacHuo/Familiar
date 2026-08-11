import Foundation
import Security

nonisolated enum FamiliarKeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            String(
                format: String(localized: "error.keychain"),
                status
            )
        }
    }
}

nonisolated enum FamiliarKeychainStore {
    private static let service = "com.isaachuo.familiar.provider-api-keys"
    private static let legacyDeepSeekService = "com.isaachuo.familiar.deepseek"
    private static let legacyAccount = "api-key"

    static func load(for provider: FamiliarProvider) -> String? {
        if let value = load(query: baseQuery(for: provider)) {
            return value
        }
        guard provider == .deepSeek else { return nil }
        return load(query: legacyDeepSeekQuery)
    }

    static func save(_ value: String, for provider: FamiliarProvider) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete(for: provider)
            return
        }

        let query = baseQuery(for: provider)
        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw FamiliarKeychainError.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw FamiliarKeychainError.unexpectedStatus(addStatus)
        }
    }

    static func delete(for provider: FamiliarProvider) throws {
        try delete(query: baseQuery(for: provider))
        if provider == .deepSeek {
            try delete(query: legacyDeepSeekQuery)
        }
    }

    static func isConfigured(for provider: FamiliarProvider) -> Bool {
        load(for: provider) != nil
    }

    private static func load(query: [String: Any]) -> String? {
        var query = query
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

    private static func delete(query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FamiliarKeychainError.unexpectedStatus(status)
        }
    }

    private static func baseQuery(for provider: FamiliarProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }

    private static var legacyDeepSeekQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyDeepSeekService,
            kSecAttrAccount as String: legacyAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}
