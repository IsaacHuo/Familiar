import Foundation

/// Session-only identity of what was actually validated. No credential is persisted.
nonisolated struct FamiliarProviderVerificationIdentity: Equatable {
    let configurationHash: String
    let modelID: String
    let credentialHash: String
    init(descriptor: FamiliarProviderDescriptor, modelID: String, credential: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        configurationHash = FamiliarHash.sha256(try encoder.encode(descriptor))
        self.modelID = modelID
        credentialHash = FamiliarHash.sha256(credential)
    }
}
