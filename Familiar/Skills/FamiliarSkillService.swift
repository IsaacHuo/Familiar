import CryptoKit
import Foundation
import SwiftData

struct FamiliarSkillDocument: Codable, Sendable, Equatable, Identifiable {
    let format: String
    let formatVersion: Int
    let id: String
    let version: String
    let name: String
    let description: String
    let instructions: String
    let allowedTools: [String]
    let examples: [String]
}

nonisolated struct FamiliarSkillSnapshot: Codable, Sendable, Equatable, Identifiable {
    var id: String { stableID }

    let stableID: String
    let version: String
    let name: String
    let contentHash: String
    let instructions: String
    let allowedTools: [String]
}

enum FamiliarSkillParserError: LocalizedError, Sendable {
    case invalid
    case unsupported
    case tooLarge
    case unknownTool(String)
    case emptyInstructions

    var errorDescription: String? {
        switch self {
        case .invalid:
            String(localized: "error.skill.invalid")
        case .unsupported:
            String(localized: "error.skill.unsupported")
        case .tooLarge:
            String(localized: "error.skill.too_large")
        case .unknownTool(let name):
            String(format: String(localized: "error.skill.unknown_tool"), name)
        case .emptyInstructions:
            String(localized: "error.skill.empty_instructions")
        }
    }
}

enum FamiliarSkillDocumentParser {
    private static let supportedKeys: Set<String> = [
        "format", "formatVersion", "id", "version", "name", "description",
        "instructions", "allowedTools", "examples"
    ]

    static func parse(data: Data, toolIDs: Set<String>) throws -> FamiliarSkillDocument {
        guard data.count <= 256 * 1024 else { throw FamiliarSkillParserError.tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { throw FamiliarSkillParserError.invalid }
        guard Set(dictionary.keys).isSubset(of: supportedKeys) else {
            throw FamiliarSkillParserError.unsupported
        }
        let decoder = JSONDecoder()
        guard let document = try? decoder.decode(FamiliarSkillDocument.self, from: data) else { throw FamiliarSkillParserError.invalid }
        guard document.format == "familiar.skill", document.formatVersion == 1, !document.id.isEmpty, !document.version.isEmpty, !document.name.isEmpty else { throw FamiliarSkillParserError.invalid }
        guard !document.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FamiliarSkillParserError.emptyInstructions }
        guard document.instructions.count <= 32_000, document.examples.count <= 8 else { throw FamiliarSkillParserError.tooLarge }
        for tool in Set(document.allowedTools) where !toolIDs.contains(tool) { throw FamiliarSkillParserError.unknownTool(tool) }
        return FamiliarSkillDocument(format: document.format, formatVersion: document.formatVersion, id: document.id, version: document.version, name: document.name, description: String(document.description.prefix(2_000)), instructions: document.instructions, allowedTools: Array(Set(document.allowedTools)).sorted(), examples: document.examples.map { String($0.prefix(2_000)) })
    }
}

nonisolated enum FamiliarSkillToolScope {
    static func manifests(
        available: [FamiliarToolManifest],
        skills: [FamiliarSkillSnapshot]
    ) -> [FamiliarToolManifest] {
        let sorted = available.sorted { $0.name < $1.name }
        guard !skills.isEmpty else { return sorted }
        let allowed = Set(skills.flatMap(\.allowedTools))
        return sorted.filter { allowed.contains($0.name) }
    }
}

enum FamiliarSkillServiceError: LocalizedError, Sendable {
    case invalidStoredAllowedTools(String)

    var errorDescription: String? {
        switch self {
        case .invalidStoredAllowedTools(let stableID):
            String(format: String(localized: "error.skill.invalid_stored_allowed_tools"), stableID)
        }
    }
}

@MainActor
struct FamiliarSkillService {
    func install(_ document: FamiliarSkillDocument, in context: ModelContext) throws -> FamiliarSkill {
        let normalized = FamiliarSkillDocument(
            format: document.format,
            formatVersion: document.formatVersion,
            id: document.id,
            version: document.version,
            name: document.name,
            description: document.description,
            instructions: document.instructions,
            allowedTools: Array(Set(document.allowedTools)).sorted(),
            examples: document.examples
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(normalized)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let stableID = normalized.id
        if let existing = try context.fetch(FetchDescriptor<FamiliarSkill>(predicate: #Predicate { $0.stableID == stableID })).first {
            existing.version = normalized.version; existing.name = normalized.name; existing.descriptionText = normalized.description; existing.instructions = normalized.instructions
            existing.examplesJSON = String(decoding: try JSONEncoder().encode(normalized.examples), as: UTF8.self); existing.allowedToolsJSON = String(decoding: try JSONEncoder().encode(normalized.allowedTools), as: UTF8.self); existing.contentHash = hash; existing.updatedAt = Date(); try context.save(); return existing
        }
        let skill = FamiliarSkill(stableID: normalized.id, version: normalized.version, name: normalized.name, descriptionText: normalized.description, instructions: normalized.instructions, examplesJSON: String(decoding: try JSONEncoder().encode(normalized.examples), as: UTF8.self), allowedToolsJSON: String(decoding: try JSONEncoder().encode(normalized.allowedTools), as: UTF8.self), contentHash: hash)
        context.insert(skill); try context.save(); return skill
    }

    func setBinding(skillID: UUID, projectID: UUID, enabled: Bool, in context: ModelContext) throws {
        if let binding = try context.fetch(FetchDescriptor<FamiliarSkillBinding>(predicate: #Predicate { $0.skillID == skillID && $0.projectID == projectID })).first { binding.enabled = enabled; binding.updatedAt = Date() }
        else { context.insert(FamiliarSkillBinding(skillID: skillID, projectID: projectID, enabled: enabled)) }
        try context.save()
    }

    func enabledSkills(projectID: UUID, in context: ModelContext) throws -> [FamiliarSkillSnapshot] {
        let bindings = try context.fetch(FetchDescriptor<FamiliarSkillBinding>(
            predicate: #Predicate { $0.projectID == projectID && $0.enabled }
        ))
        let enabledIDs = Set(bindings.map(\.skillID))
        guard !enabledIDs.isEmpty else { return [] }

        return try context.fetch(FetchDescriptor<FamiliarSkill>())
            .filter { enabledIDs.contains($0.id) }
            .map { skill in
                guard let data = skill.allowedToolsJSON.data(using: .utf8),
                      let allowedTools = try? JSONDecoder().decode([String].self, from: data)
                else { throw FamiliarSkillServiceError.invalidStoredAllowedTools(skill.stableID) }
                return FamiliarSkillSnapshot(
                    stableID: skill.stableID,
                    version: skill.version,
                    name: skill.name,
                    contentHash: skill.contentHash,
                    instructions: skill.instructions,
                    allowedTools: Array(Set(allowedTools)).sorted()
                )
            }
            .sorted {
                if $0.stableID == $1.stableID { return $0.version < $1.version }
                return $0.stableID < $1.stableID
            }
    }

    func uninstall(_ skill: FamiliarSkill, in context: ModelContext) throws {
        let skillID = skill.id
        for binding in try context.fetch(FetchDescriptor<FamiliarSkillBinding>(
            predicate: #Predicate { $0.skillID == skillID }
        )) {
            context.delete(binding)
        }
        context.delete(skill)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
