import CryptoKit
import Foundation

nonisolated enum FamiliarCapabilitySource: String, Codable, Sendable {
    case builtIn
    case projectBinding
    case shareExtension
    case appIntent
    case deepLink
    case mcp
}

nonisolated struct FamiliarCapabilityBinding: Codable, Equatable, Sendable {
    let capabilityID: String
    let version: String
    let projectID: UUID?
    let enabled: Bool
    let updatedAt: Date
}

nonisolated struct FamiliarCapabilitySnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let projectID: UUID?
    let manifests: [FamiliarToolManifest]
}

nonisolated struct FamiliarCapabilityCatalog: Sendable {
    let manifests: [FamiliarToolManifest]

    init(manifests: [FamiliarToolManifest]) {
        self.manifests = manifests.sorted { $0.id < $1.id }
    }

    func snapshot(projectID: UUID? = nil, bindings: [FamiliarCapabilityBinding] = [], available: Set<String>? = nil, now: Date = Date()) -> FamiliarCapabilitySnapshot {
        let enabled = Set(bindings.filter { $0.enabled && $0.projectID == projectID }.map(\.capabilityID))
        let selected = manifests.filter { manifest in
            let inScope = projectID == nil ? manifest.source == .builtIn : (enabled.isEmpty || enabled.contains(manifest.id) || manifest.source == .builtIn)
            let isAvailable = available.map { $0.contains(manifest.id) } ?? true
            return inScope && isAvailable
        }
        return FamiliarCapabilitySnapshot(id: UUID(), createdAt: now, projectID: projectID, manifests: selected)
    }
}

nonisolated enum FamiliarAuthorizationGrantState: String, Codable, Sendable {
    case issued
    case consumed
    case expired
    case rejected
}

nonisolated struct FamiliarAuthorizationGrant: Codable, Equatable, Sendable {
    let id: UUID
    let userAction: String
    let source: FamiliarCapabilitySource
    let capabilityID: String
    let capabilityVersion: String
    let argumentsHash: String
    let projectID: UUID?
    let expiresAt: Date
    let singleUse: Bool
    let evidence: String
    var consumedAt: Date?
    var state: FamiliarAuthorizationGrantState

    func isValid(for manifest: FamiliarToolManifest, arguments: String, projectID: UUID?, now: Date = Date()) -> Bool {
        (source == .builtIn || source == .mcp) && state == .issued && expiresAt > now && self.projectID == projectID
            && capabilityID == manifest.id && capabilityVersion == manifest.version
            && argumentsHash == Self.argumentsHash(arguments)
    }

    static func argumentsHash(_ arguments: String) -> String {
        let data = FamiliarCanonicalJSON.data(for: arguments)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum FamiliarCanonicalJSON {
    static func data(for source: String) -> Data {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let input = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: input),
              JSONSerialization.isValidJSONObject(object),
              let canonical = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys, .withoutEscapingSlashes]
              )
        else {
            return Data(trimmed.utf8)
        }
        return canonical
    }

    static func string(for source: String) -> String {
        String(decoding: data(for: source), as: UTF8.self)
    }
}

nonisolated enum FamiliarCapabilityResolver {
    static func resolve(
        catalog: FamiliarCapabilityCatalog,
        projectID: UUID?,
        bindings: [FamiliarCapabilityBinding],
        available: Set<String>? = nil,
        now: Date = Date()
    ) -> FamiliarCapabilitySnapshot {
        catalog.snapshot(projectID: projectID, bindings: bindings, available: available, now: now)
    }
}
