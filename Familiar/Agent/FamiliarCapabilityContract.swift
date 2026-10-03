import Foundation

nonisolated enum FamiliarCapabilitySource: String, Codable, Sendable {
    case builtIn
    case projectBinding
    case shareExtension
    case appIntent
    case deepLink
    case mcp
}

nonisolated struct FamiliarCapabilitySnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let projectID: UUID?
    let manifests: [FamiliarToolManifest]
}

nonisolated enum FamiliarCanonicalJSON {
    static func argumentsHash(_ arguments: String) -> String {
        FamiliarHash.sha256(data(for: arguments))
    }

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
