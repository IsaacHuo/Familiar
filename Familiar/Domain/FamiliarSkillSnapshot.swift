import Foundation

nonisolated struct FamiliarSkillSnapshot: Codable, Sendable, Equatable, Identifiable {
    var id: String { stableID }

    let stableID: String
    let version: String
    let name: String
    let contentHash: String
    let instructions: String
    let allowedTools: [String]
    var resources: [String]? = nil
    var description: String? = nil
}


nonisolated enum FamiliarSkillToolScope {
    static func manifests(
        available: [FamiliarToolManifest],
        skills: [FamiliarSkillSnapshot]
    ) -> [FamiliarToolManifest] {
        let sorted = available.sorted { $0.name < $1.name }
        guard !skills.isEmpty else { return sorted }
        // A Skill that lists no tools has declared no restriction, so it must not narrow
        // anything. Treating the empty set as "deny everything" stripped every tool from
        // the run: the bundled example Skill and every Skill created in the editor ship
        // with an empty list, so selecting one silently left the model with no capabilities
        // at all. Narrowing can only ever remove tools, never add them, so ignoring an
        // unspecified list grants nothing.
        let declared = skills.filter { !$0.allowedTools.isEmpty }
        guard !declared.isEmpty else { return sorted }
        let allowed = Set(declared.flatMap(\.allowedTools))
        return sorted.filter { FamiliarToolGroup.baseToolNames.contains($0.name) || allowed.contains($0.name) }
    }
}

