import Foundation
import Testing
@testable import Familiar

@Suite("Evidence-backed task execution")
struct FamiliarExecutionContractTests {
    @Test func completionRequiresEvidence() async throws {
        let state = FamiliarRunExecutionState()
        let pending = plan(status: .running)
        try await state.apply(pending)
        await #expect(throws: FamiliarExecutionContractError.self) { try await state.apply(plan(status: .completed)) }
        let call = FamiliarToolCall(id: "read-1", name: "web_fetch", arguments: "{}")
        let result = FamiliarToolExecutionResult(envelope: try .init(model: ["text": "retrieved"], presentation: .scalar(.init(summary: "Read", label: nil, value: "retrieved"))))
        try await state.record(call: call, result: result)
        try await state.apply(plan(status: .completed))
        #expect(await state.unfinishedSteps().isEmpty)
    }

    @Test func revisionCannotDropOrWeakenDeliverables() async throws {
        let state = FamiliarRunExecutionState()
        let required = FamiliarDeliverableSpec(id: "report", title: "Report", format: "docx", requiredText: ["北京"], minimumSources: 2)
        try await state.apply(plan(deliverables: [required]))
        await #expect(throws: FamiliarExecutionContractError.self) { try await state.apply(plan()) }
        await #expect(throws: FamiliarExecutionContractError.self) {
            try await state.apply(plan(deliverables: [.init(id: "report", title: "Report", format: "docx")]))
        }
    }

    @Test func sameFormatDeliverablesRemainDistinct() async throws {
        let state = FamiliarRunExecutionState()
        let specs = ["a", "b"].map { FamiliarDeliverableSpec(id: $0, title: $0, format: "docx") }
        try await state.apply(plan(deliverables: specs))
        #expect(await state.missing().map(\.id) == ["a", "b"])
        await #expect(throws: FamiliarExecutionContractError.self) { _ = try await state.spec(id: "unknown", format: "docx") }
        await #expect(throws: FamiliarExecutionContractError.self) { _ = try await state.spec(id: "a", format: "pdf") }
    }

    @Test func repairIsBounded() async throws {
        let state = FamiliarRunExecutionState()
        #expect(try await state.beginRepair() == 1)
        #expect(try await state.beginRepair() == 2)
        await #expect(throws: FamiliarExecutionContractError.self) { _ = try await state.beginRepair() }
    }

    @Test func skillImportIsImmutableAndConfined() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("input", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data("---\nname: document-writer\ndescription: Make documents\n---\nUse Python to generate files.".utf8).write(to: source.appendingPathComponent("SKILL.md"))
        try Data("print('document')".utf8).write(to: source.appendingPathComponent("scripts/generate.py"))
        let store = FamiliarSkillPackageStore(root: root.appendingPathComponent("packages"))
        let prepared = try store.prepare(url: source)
        let snapshot = try store.commit(prepared)
        #expect(snapshot.resources?.contains("scripts/generate.py") == true)
        #expect(throws: FamiliarSkillParserError.self) { _ = try store.resource(hash: snapshot.contentHash, path: "../SKILL.md") }
        let file = try store.resource(hash: snapshot.contentHash, path: "scripts/generate.py")
        try Data("changed".utf8).write(to: file)
        #expect(throws: FamiliarSkillParserError.self) { _ = try store.resource(hash: snapshot.contentHash, path: "scripts/generate.py") }
    }

    @Test func skillImportRejectsSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("SKILL.md"), withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
        #expect(throws: FamiliarSkillParserError.self) { _ = try FamiliarSkillPackageStore().prepare(url: root) }
    }

    private func plan(status: FamiliarToolPresentationPayload.TaskStatus = .running, deliverables: [FamiliarDeliverableSpec] = []) -> FamiliarToolPresentationPayload.TaskList {
        .init(planID: "plan", title: "Research", tasks: [.init(id: "step", title: "Research", status: status, detail: nil, progress: nil)], expectedDeliverables: deliverables)
    }
}
