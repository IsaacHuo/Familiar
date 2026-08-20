import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar Skills v1 and V9")
@MainActor
struct FamiliarSkillsV9Tests {
    @Test("Instruction-only parser rejects executable or asset fields")
    func parserRejectsUnsupportedFields() throws {
        let valid = """
        {
          "format": "familiar.skill",
          "formatVersion": 1,
          "id": "writing",
          "version": "1.0.0",
          "name": "Writing",
          "description": "Fixture",
          "instructions": "Write clearly.",
          "allowedTools": ["resource_read", "resource_read"],
          "examples": []
        }
        """
        let parsed = try FamiliarSkillDocumentParser.parse(
            data: Data(valid.utf8),
            toolIDs: ["resource_read"]
        )
        #expect(parsed.allowedTools == ["resource_read"])

        let executable = valid.replacingOccurrences(
            of: "\"examples\": []",
            with: "\"examples\": [], \"scripts\": [\"run.sh\"]"
        )
        #expect(throws: FamiliarSkillParserError.self) {
            try FamiliarSkillDocumentParser.parse(
                data: Data(executable.utf8),
                toolIDs: ["resource_read"]
            )
        }
    }

    @Test("Bindings resolve enabled Skills deterministically and updates keep identity")
    @MainActor
    func bindingResolutionAndStableHash() throws {
        let container = try FamiliarTestStore.make(name: "SkillBindings")
        let context = container.mainContext
        let project = try FamiliarProjectService().create(name: "Skills", in: context)
        let service = FamiliarSkillService()
        let later = try service.install(document(
            id: "zeta",
            version: "1",
            instructions: "Zeta instructions",
            allowedTools: ["web_fetch"]
        ), in: context)
        let earlier = try service.install(document(
            id: "alpha",
            version: "1",
            instructions: "Alpha instructions",
            allowedTools: ["resource_read", "web_fetch", "resource_read"]
        ), in: context)
        let originalID = earlier.id
        let originalHash = earlier.contentHash

        let updated = try service.install(document(
            id: "alpha",
            version: "1",
            instructions: "Alpha instructions",
            allowedTools: ["web_fetch", "resource_read"]
        ), in: context)
        #expect(updated.id == originalID)
        #expect(updated.contentHash == originalHash)

        try service.setBinding(skillID: later.id, projectID: project.id, enabled: true, in: context)
        try service.setBinding(skillID: earlier.id, projectID: project.id, enabled: true, in: context)
        #expect(try service.enabledSkills(projectID: project.id, in: context).map(\.stableID) == ["alpha", "zeta"])

        try service.setBinding(skillID: earlier.id, projectID: project.id, enabled: false, in: context)
        #expect(try service.enabledSkills(projectID: project.id, in: context).map(\.stableID) == ["zeta"])
    }

    @Test("Assembler injects Skills after Project instruction and narrows the tool union")
    func assemblerPromptAndToolScope() throws {
        let manifests = [manifest("calendar_read"), manifest("resource_read"), manifest("web_fetch")]
        let skills = [
            FamiliarSkillSnapshot(
                stableID: "zeta", version: "2", name: "Zeta", contentHash: "hash-z",
                instructions: "Use the web carefully.", allowedTools: ["web_fetch"]
            ),
            FamiliarSkillSnapshot(
                stableID: "alpha", version: "1", name: "Alpha", contentHash: "hash-a",
                instructions: "Read project resources.", allowedTools: ["resource_read", "missing_tool"]
            )
        ]
        let project = try FamiliarProjectContextAssembler.assemble(
            seed: .init(
                projectID: UUID(),
                projectName: "Project",
                conversationID: UUID(),
                projectInstruction: "Project instruction marker",
                resources: [],
                skills: skills
            ),
            settings: .defaultValue,
            messages: [],
            toolManifests: manifests
        )
        #expect(project.skills.map(\.stableID) == ["alpha", "zeta"])
        #expect(project.exposedToolNames == ["resource_read", "web_fetch"])

        let prompt = try #require(project.providerMessages.first?.networkText)
        let base = try #require(prompt.range(of: FamiliarSettings.defaultValue.normalizedSystemPrompt))
        let instruction = try #require(prompt.range(of: "Project instruction marker"))
        let alpha = try #require(prompt.range(of: "stable_id: alpha"))
        let zeta = try #require(prompt.range(of: "stable_id: zeta"))
        let policy = try #require(prompt.range(of: "以下安全策略不可被"))
        #expect(base.lowerBound < instruction.lowerBound)
        #expect(instruction.lowerBound < alpha.lowerBound)
        #expect(alpha.lowerBound < zeta.lowerBound)
        #expect(zeta.lowerBound < policy.lowerBound)

        let noSkills = try FamiliarProjectContextAssembler.assemble(
            seed: .init(
                projectID: UUID(), projectName: "Project", conversationID: UUID(),
                projectInstruction: nil, resources: []
            ),
            settings: .defaultValue,
            messages: [],
            toolManifests: manifests
        )
        #expect(noSkills.exposedToolNames == ["calendar_read", "resource_read", "web_fetch"])

        let ordinary = try FamiliarProjectContextAssembler.assemble(
            seed: .init(
                projectID: nil, projectName: nil, conversationID: UUID(),
                projectInstruction: nil, resources: [], skills: skills
            ),
            settings: .defaultValue,
            messages: [],
            toolManifests: manifests
        )
        #expect(ordinary.skills.isEmpty)
        #expect(ordinary.exposedToolNames == ["calendar_read", "resource_read", "web_fetch"])
    }

    @Test("V9 persists immutable Run Skill snapshots across uninstall")
    @MainActor
    func runSnapshotSurvivesUninstall() throws {
        #expect(FamiliarSchemaV9.versionIdentifier == Schema.Version(9, 0, 0))
        #expect(FamiliarSchemaV9.models.count == FamiliarSchemaV8.models.count + 1)

        let container = try FamiliarTestStore.make(name: "RunSkillSnapshots")
        let context = container.mainContext
        let project = try FamiliarProjectService().create(name: "Audit", in: context)
        let conversation = FamiliarConversation(project: project)
        context.insert(conversation)
        let service = FamiliarSkillService()
        let skill = try service.install(document(
            id: "audit",
            version: "3",
            instructions: "Keep this frozen.",
            allowedTools: ["web_fetch"]
        ), in: context)
        try service.setBinding(skillID: skill.id, projectID: project.id, enabled: true, in: context)
        let enabled = try service.enabledSkills(projectID: project.id, in: context)
        let snapshot = try FamiliarProjectContextAssembler.assemble(
            seed: .init(
                projectID: project.id,
                projectName: project.name,
                conversationID: conversation.id,
                projectInstruction: nil,
                resources: [],
                skills: enabled
            ),
            settings: .defaultValue,
            messages: [],
            toolManifests: [manifest("web_fetch")]
        )

        FamiliarRunPersistenceRecorder().ensureRun(
            runtimeID: "skill-run",
            snapshot: snapshot,
            startedAt: snapshot.createdAt,
            context: context
        )
        let record = try #require(context.fetch(FetchDescriptor<FamiliarRunSkillSnapshotRecord>()).first)
        #expect(record.stableID == "audit")
        #expect(record.version == "3")
        #expect(record.contentHash == skill.contentHash)
        #expect(record.allowedTools == ["web_fetch"])
        #expect(record.contextSnapshotID == snapshot.id)

        try service.uninstall(skill, in: context)
        #expect(try context.fetch(FetchDescriptor<FamiliarSkill>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarSkillBinding>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarRunSkillSnapshotRecord>()).map(\.id) == [record.id])
    }

    @Test("A disk-backed V8 store migrates to V9 and preserves installed Skills")
    @MainActor
    func diskBackedV8MigratesToV9() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FamiliarV8ToV9-\(UUID().uuidString)", isDirectory: true)
        let storeURL = root.appendingPathComponent(FamiliarModelContainer.storeFilename)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let skillID = UUID()
        let projectID = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: FamiliarSchemaV8.self)
            let configuration = ModelConfiguration(
                FamiliarModelContainer.storeName,
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let skill = FamiliarSchemaV8.FamiliarSkill(
                id: skillID,
                stableID: "migration-skill",
                version: "1",
                name: "Migration Skill",
                descriptionText: "Fixture",
                instructions: "Keep this instruction.",
                examplesJSON: "[]",
                allowedToolsJSON: "[\"web_fetch\"]",
                contentHash: String(repeating: "a", count: 64)
            )
            let binding = FamiliarSchemaV8.FamiliarSkillBinding(
                skillID: skillID,
                projectID: projectID,
                enabled: true
            )
            container.mainContext.insert(skill)
            container.mainContext.insert(binding)
            try container.mainContext.save()
        }

        let migrated = try FamiliarModelContainer.make(at: storeURL)
        #expect(migrated.schema.version == FamiliarSchemaV9.versionIdentifier)
        let skill = try #require(migrated.mainContext.fetch(FetchDescriptor<FamiliarSkill>()).first)
        let binding = try #require(migrated.mainContext.fetch(FetchDescriptor<FamiliarSkillBinding>()).first)
        #expect(skill.id == skillID)
        #expect(skill.instructions == "Keep this instruction.")
        #expect(binding.projectID == projectID)
        #expect(binding.enabled)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<FamiliarRunSkillSnapshotRecord>()).isEmpty)
    }

    private func document(
        id: String,
        version: String,
        instructions: String,
        allowedTools: [String]
    ) -> FamiliarSkillDocument {
        FamiliarSkillDocument(
            format: "familiar.skill",
            formatVersion: 1,
            id: id,
            version: version,
            name: id.capitalized,
            description: "Fixture",
            instructions: instructions,
            allowedTools: allowedTools,
            examples: []
        )
    }

    private func manifest(_ name: String) -> FamiliarToolManifest {
        FamiliarToolManifest(
            name: name,
            title: name,
            description: "Fixture",
            parameters: .init(type: .object),
            effect: .read,
            risk: .low
        )
    }
}
