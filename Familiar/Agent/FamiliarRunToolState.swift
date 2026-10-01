import Foundation

/// Run-local tool facts shared by parallel reads. This does not plan or schedule work.
actor FamiliarRunToolState {
    private var installedSkills: [FamiliarSkillSnapshot] = []
    private var attemptedWrites: Set<String> = []

    func skills(available: [FamiliarSkillSnapshot]) -> [FamiliarSkillSnapshot] {
        var all = Dictionary(available.map { ($0.stableID, $0) }, uniquingKeysWith: { _, new in new })
        for skill in installedSkills { all[skill.stableID] = skill }
        return all.values.sorted { $0.stableID < $1.stableID }
    }

    func admit(_ skill: FamiliarSkillSnapshot) { installedSkills.append(skill) }
    func wasAttempted(_ fingerprint: String) -> Bool { attemptedWrites.contains(fingerprint) }
    func beginWrite(_ fingerprint: String) { attemptedWrites.insert(fingerprint) }
}
