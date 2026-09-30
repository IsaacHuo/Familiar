import Foundation

/// Persisted descriptors contain configuration only. Credentials remain in Keychain,
/// keyed by the stable instance ID, including the original `deepseek` instance.
nonisolated enum FamiliarProviderInstanceStore {
    private static let key = "familiar.provider.instances.v1"

    static func load() -> [FamiliarProviderDescriptor] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FamiliarProviderDescriptor].self, from: data)) ?? []
    }

    @MainActor static func save(_ descriptor: FamiliarProviderDescriptor) throws {
        try validate(descriptor)
        var values = load().filter { $0.id != descriptor.id }
        values.append(descriptor)
        UserDefaults.standard.set(try JSONEncoder().encode(values), forKey: key)
    }

    @MainActor static func remove(_ id: String) throws {
        try FamiliarKeychainStore.delete(for: id)
        try FamiliarKeychainStore.delete(for: "oauth." + id)
        UserDefaults.standard.set(try JSONEncoder().encode(load().filter { $0.id != id }), forKey: key)
    }

    static func validate(_ descriptor: FamiliarProviderDescriptor) throws {
        let url = descriptor.baseURL
        guard descriptor.routes == nil else { throw FamiliarProviderConnectionError.invalidResponse }
        guard !descriptor.id.isEmpty, !descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              descriptor.oauthKind == nil || (descriptor.oauthKind == "kimi" && url.host == "api.kimi.com" && descriptor.authStyle == .bearer) || (descriptor.oauthKind == "codex" && url.host == "chatgpt.com" && descriptor.authStyle == .bearer),
              !descriptor.chatPath.contains("://"),
              descriptor.additionalHeaders.keys.allSatisfy({ ["anthropic-version", "openai-organization", "openai-project", "http-referer", "x-title", "user-agent"].contains($0.lowercased()) }),
              Set(descriptor.curatedModels.map(\.id)).count == descriptor.curatedModels.count,
              descriptor.curatedModels.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw FamiliarProviderRequestError.invalidConfiguration(provider: descriptor.displayName) }
    }
}
