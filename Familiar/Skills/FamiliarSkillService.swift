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
    case alreadyInstalled
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidStoredAllowedTools(let stableID):
            String(format: String(localized: "error.skill.invalid_stored_allowed_tools"), stableID)
        case .alreadyInstalled:
            String(localized: "error.skill.already_installed", defaultValue: "A Skill with this identifier already exists.")
        case .unavailable:
            String(localized: "error.skill.unavailable", defaultValue: "This Skill is no longer installed.")
        }
    }
}

@MainActor
struct FamiliarSkillService {
    private static let exampleSeedKey = "familiar.skills.example.seeded.v1"

    static var exampleDocument: FamiliarSkillDocument {
        FamiliarSkillDocument(
            format: "familiar.skill",
            formatVersion: 1,
            id: "clear-writing",
            version: "1.0.0",
            name: String(localized: "settings.skills.example.name", defaultValue: "Clear Writing"),
            description: String(localized: "settings.skills.example.description", defaultValue: "Turn rough ideas into clear, concise writing."),
            instructions: String(
                localized: "settings.skills.example.instructions",
                defaultValue: "Understand the user's goal first. Write clearly and concretely, remove filler, preserve important details, and state uncertainty when information is missing."
            ),
            allowedTools: [],
            examples: []
        )
    }

    func installExampleIfNeeded(in context: ModelContext) throws {
        guard !UserDefaults.standard.bool(forKey: Self.exampleSeedKey) else { return }
        let stableID = Self.exampleDocument.id
        let existing = try context.fetch(FetchDescriptor<FamiliarSkill>(
            predicate: #Predicate { $0.stableID == stableID }
        )).first
        if existing == nil {
            _ = try install(Self.exampleDocument, in: context)
        }
        UserDefaults.standard.set(true, forKey: Self.exampleSeedKey)
    }

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
        let hash = FamiliarHash.sha256(data)
        let stableID = normalized.id
        if let existing = try context.fetch(FetchDescriptor<FamiliarSkill>(predicate: #Predicate { $0.stableID == stableID })).first {
            existing.version = normalized.version; existing.name = normalized.name; existing.descriptionText = normalized.description; existing.instructions = normalized.instructions
            existing.examplesJSON = String(decoding: try JSONEncoder().encode(normalized.examples), as: UTF8.self); existing.allowedToolsJSON = String(decoding: try JSONEncoder().encode(normalized.allowedTools), as: UTF8.self); existing.contentHash = hash; existing.updatedAt = Date(); try context.save(); return existing
        }
        let skill = FamiliarSkill(stableID: normalized.id, version: normalized.version, name: normalized.name, descriptionText: normalized.description, instructions: normalized.instructions, examplesJSON: String(decoding: try JSONEncoder().encode(normalized.examples), as: UTF8.self), allowedToolsJSON: String(decoding: try JSONEncoder().encode(normalized.allowedTools), as: UTF8.self), contentHash: hash)
        context.insert(skill); try context.save(); return skill
    }

    func snapshot(skillID: UUID, in context: ModelContext) throws -> FamiliarSkillSnapshot {
        let id = skillID
        guard let skill = try context.fetch(FetchDescriptor<FamiliarSkill>(
            predicate: #Predicate { $0.id == id }
        )).first else {
            throw FamiliarSkillServiceError.unavailable
        }
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

    func uninstall(_ skill: FamiliarSkill, in context: ModelContext) throws {
        context.delete(skill)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

nonisolated struct FamiliarSkillListTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    private struct Output: Encodable {
        let skills: [Metadata]
    }
    private struct Metadata: Encodable {
        let id: String
        let version: String
        let name: String
        let allowedTools: [String]
    }

    let manifest = FamiliarToolManifest(
        name: "skill_list",
        title: "List Project Skills",
        description: "List metadata for Skills attached to the current Project. Skill bodies are not loaded until skill_read is called.",
        parameters: .init(type: .object, properties: [:], required: []),
        effect: .read,
        risk: .low,
        dataDomains: ["project.skills"],
        privacyLabels: ["metadata-only"],
        supportsParallelism: false,
        requiredScopes: ["project"]
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let metadata = context.availableSkills.map {
            Metadata(id: $0.stableID, version: $0.version, name: $0.name, allowedTools: $0.allowedTools)
        }
        let records = metadata.map { skill in
            FamiliarToolPresentationPayload.Record(id: skill.id, fields: [
                .init(name: "name", value: skill.name),
                .init(name: "version", value: skill.version),
                .init(name: "allowedTools", value: skill.allowedTools.joined(separator: ", "))
            ])
        }
        return .result(.init(envelope: try .init(
            model: Output(skills: metadata),
            presentation: .recordCollection(.init(
                summary: metadata.isEmpty ? "当前 Project 没有可用 Skill。" : "已列出当前 Project 可按需加载的 Skill。",
                recordType: "projectSkill",
                records: records
            ))
        )))
    }
}

nonisolated struct FamiliarSkillReadTool: FamiliarTool {
    struct Input: Decodable, Sendable { let id: String }
    private struct Output: Encodable {
        let id: String
        let version: String
        let contentHash: String
        let instructions: String
        let allowedTools: [String]
    }

    let manifest = FamiliarToolManifest(
        name: "skill_read",
        title: "Load Project Skill",
        description: "Load one attached Project Skill during planning. Loading freezes its version and narrows subsequent execution to its allowed tools plus core planning and delivery tools.",
        parameters: .init(
            type: .object,
            properties: ["id": .init(type: .string, description: "Stable Skill identifier from skill_list.")],
            required: ["id"]
        ),
        effect: .read,
        risk: .low,
        dataDomains: ["project.skills"],
        privacyLabels: ["instruction-only", "run-snapshot"],
        supportsParallelism: false,
        requiredScopes: ["project"]
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let stableID = input.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let skill = context.availableSkills.first(where: { $0.stableID == stableID }) else {
            throw FamiliarSkillServiceError.unavailable
        }
        let output = Output(
            id: skill.stableID,
            version: skill.version,
            contentHash: skill.contentHash,
            instructions: skill.instructions,
            allowedTools: skill.allowedTools
        )
        return .result(.init(
            envelope: try .init(
                model: output,
                presentation: .document(.init(
                    summary: "已为本次 Run 加载 Skill：\(skill.name)",
                    title: skill.name,
                    text: skill.instructions,
                    mimeType: "text/plain",
                    truncated: false
                ))
            ),
            loadedSkill: skill
        ))
    }
}
