import Foundation

nonisolated struct FamiliarRunFacts: Sendable {
    let discoveredTools: [String]
    let exposedTools: [String]
    let loadedSkills: [FamiliarSkillSnapshot]
    let observations: [FamiliarRunObservation]
    let files: [FamiliarFileSnapshot]
}

nonisolated struct FamiliarRunObservation: Codable, Sendable {
    enum Status: String, Codable, Sendable { case read, attempted, committed, failed, uncertain, undone, cancelled }
    let callID: String
    let tool: String
    let argumentsHash: String
    let status: Status
    let observedAt: Date
    let resultReference: String?
    let readIdentities: [String]
    let resultHash: String?
    let truncated: Bool
    let summary: String
    let sources: [FamiliarSource]
}

/// Facts and bounded immutable-file read reuse. Never plans or schedules actions.
nonisolated struct FamiliarCachedFileRead: Sendable {
    let result: FamiliarToolExecutionResult
    let observedAt: Date
}

actor FamiliarRunState {
    nonisolated let webEvidence = FamiliarWebEvidenceState()
    private var installedSkills: [FamiliarSkillSnapshot] = []
    private var loadedSkills: [String: FamiliarSkillSnapshot] = [:]
    private var attemptedWrites: Set<String> = []
    private var committedFiles: [UUID: FamiliarFileSnapshot] = [:]
    private var discoveredTools: Set<String> = []
    private var exposedTools: [String] = []
    private var observations: [String: FamiliarRunObservation] = [:]
    private var readCache: [String: FamiliarCachedFileRead] = [:]
    private var cachedCharacters = 0

    func discover(_ manifests: [FamiliarToolManifest]) { discoveredTools.formUnion(manifests.map(\.name)) }

    func expose(_ manifests: [FamiliarToolManifest]) {
        exposedTools = manifests.map(\.name).sorted()
        discoveredTools.formUnion(exposedTools)
    }

    func load(_ skill: FamiliarSkillSnapshot) { loadedSkills[skill.stableID] = skill }

    func record(call: FamiliarToolCall, status: FamiliarRunObservation.Status,
                result: FamiliarToolExecutionResult? = nil, detail: String = "", at: Date = Date()) {
        let modelObject = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.modelContent.utf8)) }
        let object = modelObject as? [String: Any]
        let readIDs = (modelObject as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
        let reference = result?.fileIdentifier ?? object?["fileIdentifier"] as? String
        observations[call.id] = .init(callID: call.id, tool: call.name,
            argumentsHash: FamiliarCanonicalJSON.argumentsHash(call.arguments), status: status, observedAt: at,
            resultReference: reference, readIdentities: readIDs,
            resultHash: result.map { FamiliarHash.sha256(Data($0.modelContent.utf8)) },
            truncated: object?["truncated"] as? Bool ?? false,
            summary: String((detail.isEmpty ? result?.summary ?? "" : detail).prefix(320)),
            sources: result?.sources ?? [])
        if let manifests = result?.loadedTools { discoveredTools.formUnion(manifests.map(\.name)) }
        if let skill = result?.loadedSkill { load(skill) }
    }

    func snapshot() -> FamiliarRunFacts {
        .init(discoveredTools: discoveredTools.sorted(), exposedTools: exposedTools,
              loadedSkills: loadedSkills.values.sorted { $0.stableID < $1.stableID },
              observations: observations.values.sorted {
                  $0.observedAt == $1.observedAt ? $0.callID < $1.callID : $0.observedAt < $1.observedAt
              }, files: committedFiles.values.sorted { $0.reference.versionID.uuidString < $1.reference.versionID.uuidString })
    }

    /// Only exact known FileVersions qualify. No Web, Native, Memory or MCP caching.
    func fileReadKey(call: FamiliarToolCall, available: [FamiliarFileSnapshot]) -> String? {
        guard call.name == "file_read",
              let object = try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any],
              let identifier = object["identifier"] as? String,
              let file = available.first(where: { "file_" + $0.reference.versionID.uuidString == identifier })
        else { return nil }
        return file.reference.projectID.uuidString + "|" + file.reference.versionID.uuidString + "|" + file.contentHash
            + "|" + FamiliarCanonicalJSON.argumentsHash(call.arguments)
    }

    func cachedRead(_ key: String?) -> FamiliarCachedFileRead? { key.flatMap { readCache[$0] } }
    func cacheRead(_ result: FamiliarToolExecutionResult, key: String?, observedAt: Date = Date()) {
        guard let key, readCache[key] == nil, cachedCharacters + result.modelContent.count <= 64_000 else { return }
        readCache[key] = .init(result: result, observedAt: observedAt)
        cachedCharacters += result.modelContent.count
    }

    func admit(files: [FamiliarFileSnapshot]) {
        for file in files { committedFiles[file.reference.versionID] = file }
    }

    func files(available: [FamiliarFileSnapshot]) -> [FamiliarFileSnapshot] {
        var result = Dictionary(available.map { ($0.reference.versionID, $0) }, uniquingKeysWith: { _, new in new })
        for (id, file) in committedFiles { result[id] = file }
        return result.values.sorted { $0.reference.versionID.uuidString < $1.reference.versionID.uuidString }
    }

    func skills(available: [FamiliarSkillSnapshot]) -> [FamiliarSkillSnapshot] {
        var all = Dictionary(available.map { ($0.stableID, $0) }, uniquingKeysWith: { _, new in new })
        for skill in installedSkills { all[skill.stableID] = skill }
        return all.values.sorted { $0.stableID < $1.stableID }
    }

    func admit(_ skill: FamiliarSkillSnapshot) { installedSkills.append(skill) }
    func wasAttempted(_ fingerprint: String) -> Bool { attemptedWrites.contains(fingerprint) }
    func beginWrite(_ fingerprint: String) { attemptedWrites.insert(fingerprint) }
}
