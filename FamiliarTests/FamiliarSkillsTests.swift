import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar Skills")
@MainActor
struct FamiliarSkillsTests {
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

    @Test("Installed Skills resolve snapshots and updates keep identity")
    @MainActor
    func bindingResolutionAndStableHash() throws {
        let container = try FamiliarTestStore.make(name: "SkillBindings")
        let context = container.mainContext
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

        let edited = try service.install(document(
            id: "alpha",
            version: "1",
            instructions: "Edited instructions",
            allowedTools: ["web_fetch", "resource_read"]
        ), in: context)
        #expect(edited.id == originalID)
        #expect(edited.instructions == "Edited instructions")
        #expect(edited.contentHash != originalHash)

        #expect(try service.snapshot(skillID: earlier.id, in: context).stableID == "alpha")
        #expect(try service.snapshot(skillID: later.id, in: context).stableID == "zeta")
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
        #expect(ordinary.skills.map(\.stableID) == ["alpha", "zeta"])
        #expect(ordinary.exposedToolNames == ["resource_read", "web_fetch"])
    }

    @Test("V9 persists immutable Run Skill snapshots across uninstall")
    @MainActor
    func runSnapshotSurvivesUninstall() throws {
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
        let invoked = [try service.snapshot(skillID: skill.id, in: context)]
        let snapshot = try FamiliarProjectContextAssembler.assemble(
            seed: .init(
                projectID: project.id,
                projectName: project.name,
                conversationID: conversation.id,
                projectInstruction: nil,
                resources: [],
                skills: invoked
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
        #expect(try context.fetch(FetchDescriptor<FamiliarRunSkillSnapshotRecord>()).map(\.id) == [record.id])
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
