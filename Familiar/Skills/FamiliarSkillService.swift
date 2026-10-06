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
        if let root = Bundle.main.resourceURL?.appendingPathComponent("Skills/research-document"),
           FileManager.default.fileExists(atPath: root.appendingPathComponent("SKILL.md").path) {
            let id = "research-document"
            if try context.fetch(FetchDescriptor<FamiliarSkill>(predicate: #Predicate { $0.stableID == id })).isEmpty {
                let packages = FamiliarSkillPackageStore()
                let prepared = try packages.prepare(url: root, source: "bundled:research-document")
                try packages.persistInstallation(packages.commit(prepared), context: context)
            }
        }
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
        let skill = try stageInstallation(document, in: context)
        do { try context.save() } catch { context.rollback(); throw error }
        return skill
    }

    func stageInstallation(_ document: FamiliarSkillDocument, in context: ModelContext) throws -> FamiliarSkill {
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
            existing.examplesJSON = String(decoding: try JSONEncoder().encode(normalized.examples), as: UTF8.self); existing.allowedToolsJSON = String(decoding: try JSONEncoder().encode(normalized.allowedTools), as: UTF8.self); existing.contentHash = hash; existing.updatedAt = Date(); return existing
        }
        let skill = FamiliarSkill(stableID: normalized.id, version: normalized.version, name: normalized.name, descriptionText: normalized.description, instructions: normalized.instructions, examplesJSON: String(decoding: try JSONEncoder().encode(normalized.examples), as: UTF8.self), allowedToolsJSON: String(decoding: try JSONEncoder().encode(normalized.allowedTools), as: UTF8.self), contentHash: hash)
        context.insert(skill); return skill
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
            allowedTools: Array(Set(allowedTools.map(FamiliarStoredToolIdentity.currentName))).sorted(),
            resources: (try? FamiliarSkillPackageStore().manifest(hash: skill.contentHash))?.files.keys.sorted(),
            description: skill.descriptionText
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
        let description: String?
        let resources: [String]
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
            Metadata(id: $0.stableID, version: $0.version, name: $0.name, allowedTools: $0.allowedTools, description: $0.description, resources: $0.resources ?? [])
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
    struct Input: Decodable, Sendable { let id: String; var path: String? }
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
        description: "Load one relevant attached Project Skill when needed. Loading freezes its version and narrows subsequent tool execution; it does not grant permissions.",
        parameters: .init(
            type: .object,
            properties: ["id": .init(type: .string, description: "Stable Skill identifier from skill_list."), "path": .init(type: .string, description: "Optional relative resource path from the Skill manifest. Omit to load SKILL.md instructions.")],
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
        if let path = input.path {
            let url = try FamiliarSkillPackageStore().resource(hash: skill.contentHash, path: path)
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else { throw FamiliarSkillParserError.unsupported }
            let excerpt = String(text.prefix(32_000))
            return .result(.init(envelope: try .init(model: ["path": path, "text": excerpt, "truncated": text.count > excerpt.count ? "true" : "false"],
                presentation: .document(.init(summary: path, title: path, text: excerpt, truncated: text.count > excerpt.count))), loadedSkill: skill))
        }
        let output = Output(
            id: skill.stableID,
            version: skill.version,
            contentHash: skill.contentHash,
            instructions: skill.instructions + "\n\nResources (read-only): " + (skill.resources ?? []).map { "/workspace/files/Skills/\(skill.stableID)/\($0)" }.joined(separator: "\n"),
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
