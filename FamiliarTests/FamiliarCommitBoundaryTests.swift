import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Commit and persistence boundaries")
struct FamiliarCommitBoundaryTests {
    @Test("A failed commit journal stops the action before any write")
    func journalFailurePreventsWrite() async throws {
        let probe = FamiliarCommitProbe()
        let events = try await run(probe: probe, willCommit: { _ in throw FamiliarCommitFixtureError() })
        #expect(await probe.count("write") == 0)
        #expect(!events.contains { if case .toolResultProduced = $0.payload { true } else { false } })
    }

    @Test("A successful action followed by save failure is retained and cannot be repeated")
    func failedSaveBlocksReplay() async throws {
        let probe = FamiliarCommitProbe()
        let events = try await run(probe: probe, repeatCall: true, persist: { _, _ in throw FamiliarCommitFixtureError() })
        #expect(await probe.count("write") == 1)
        #expect(failures(events) == ["tool_persistence_failed", "duplicate_tool_call"])
        #expect(!events.contains { if case .toolResultProduced = $0.payload { true } else { false } })
        #expect(events.contains { if case .activityCompleted(let value) = $0.payload { value.status == .failed && value.undoAvailable } else { false } })
    }

    @Test("A commit that throws after an effect is uncertain and cannot be replayed")
    func uncertainCommitBlocksReplay() async throws {
        let probe = FamiliarCommitProbe()
        let events = try await run(probe: probe, repeatCall: true, mode: .throwAfterWrite)
        #expect(await probe.count("write") == 1)
        #expect(failures(events) == ["tool_commit_unconfirmed", "duplicate_tool_call"])
    }

    @Test("Local compensation runs after save failure, without finalizing or exposing Undo")
    func localRollback() async throws {
        let probe = FamiliarCommitProbe()
        let events = try await run(probe: probe, mode: .local, persist: { _, _ in throw FamiliarCommitFixtureError() })
        #expect(await probe.count("rollback") == 1)
        #expect(await probe.count("finalize") == 0)
        #expect(failures(events) == ["tool_commit_rolled_back"])
        #expect(!events.contains { if case .activityCompleted(let value) = $0.payload { value.undoAvailable } else { false } })
    }

    @Test("Local housekeeping runs only after authoritative persistence")
    func finalizeAfterSave() async throws {
        let probe = FamiliarCommitProbe()
        let events = try await run(probe: probe, mode: .local, persist: { _, _ in await probe.record("persist"); return .init() })
        #expect(await probe.trace() == ["write", "persist", "finalize"])
        #expect(events.contains { if case .toolResultProduced = $0.payload { true } else { false } })
    }

    @Test("Undo save retries reuse the successful native result rather than executing again")
    func undoResultIsCached() async throws {
        let probe = FamiliarCommitProbe()
        let store = FamiliarUndoStore()
        await store.register(key: "run:call") {
            await probe.record("undo")
            return try fixtureResult()
        }
        _ = try await store.execute(key: "run:call")
        _ = try await store.execute(key: "run:call")
        #expect(await probe.count("undo") == 1)
        await store.complete(key: "run:call")
        await #expect(throws: FamiliarEventKitError.self) { _ = try await store.execute(key: "run:call") }
    }

    @Test("Interrupted write journals stay uncertain and block destructive regeneration")
    @MainActor
    func interruptedCommitJournal() throws {
        let container = try FamiliarTestStore.make(name: "CommitJournalRecovery")
        let context = container.mainContext
        let conversation = FamiliarConversation()
        let run = FamiliarAgentRun(runtimeID: "run", conversation: conversation)
        context.insert(conversation); context.insert(run); try context.save()
        let service = FamiliarRunRecoveryService()
        try service.beginCommit(.init(runID: "run", assistantTurnID: "turn", call: .init(id: "call", name: "write", arguments: "{}")), in: context)
        #expect(try service.requiresInspection(run, in: context))
        _ = try service.recoverInterruptedRuns(in: context)
        #expect(try context.fetch(FetchDescriptor<FamiliarToolInvocationRecord>()).first?.state == .committing)
        #expect(try service.requiresInspection(run, in: context))
    }

    @Test("Read-only completion and runtime notices still permit regeneration")
    @MainActor
    func readOnlyRegeneration() throws {
        let container = try FamiliarTestStore.make(name: "ReadOnlyRegeneration")
        let context = container.mainContext
        let run = FamiliarAgentRun(runtimeID: "read-run")
        context.insert(run)
        context.insert(FamiliarActivityRecord(activityID: "read", runtimeID: "read-run", assistantTurnID: "turn", kind: .tool,
            effect: .read, phase: .succeeded, toolName: "web_fetch", toolCallID: "call", summary: "Read", sequence: 0, startedAt: Date()))
        context.insert(FamiliarActivityRecord(activityID: "notice", runtimeID: "read-run", assistantTurnID: "turn", kind: .runtimeNotice,
            phase: .succeeded, summary: "Notice", sequence: 1, startedAt: Date()))
        try context.save()
        #expect(try !FamiliarRunRecoveryService().requiresInspection(run, in: context))
    }

    @Test("Environment save compensation restores the previous directory")
    func environmentRollback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarWorkspaceStore(rootURL: root)
        let projectID = UUID()
        let original = try store.projectEnvironmentURL(projectID)
        try Data("old".utf8).write(to: original.appendingPathComponent("version.txt"))
        let view = try store.prepareShellTaskView(taskID: UUID(), workspaceID: .project(projectID), resources: [], attachments: [], useStagingEnvironment: true)
        let revision = UUID()
        let receipt = FamiliarEnvironmentReceipt(schemaVersion: 2, projectID: projectID, revision: revision, state: .ready,
            requestedPackages: ["fixture"], packageIndex: "https://pypi.org/simple",
            lock: .init(pythonVersion: "3", resolvedPackages: ["fixture==1"], contentHash: "hash"), byteSize: 3, preparedAt: Date())
        try JSONEncoder().encode(receipt).write(to: view.environment.appendingPathComponent(FamiliarEnvironmentStore.receiptFilename))
        try Data("new".utf8).write(to: view.environment.appendingPathComponent("version.txt"))
        let previous = try store.commitProjectEnvironment(from: view, projectID: projectID)
        #expect(try String(contentsOf: original.appendingPathComponent("version.txt"), encoding: .utf8) == "new")
        try store.rollbackProjectEnvironment(previous, revision: revision, projectID: projectID)
        #expect(try String(contentsOf: original.appendingPathComponent("version.txt"), encoding: .utf8) == "old")
    }

    @Test("Skill record, package hash and binding can roll back together before their one save")
    @MainActor
    func stagedSkillIsAtomic() throws {
        let container = try FamiliarTestStore.make(name: "SkillStageRollback")
        let context = container.mainContext
        let document = FamiliarSkillDocument(format: "familiar.skill", formatVersion: 1, id: "fixture", version: "1",
            name: "Fixture", description: "Fixture", instructions: "Use existing context", allowedTools: [], examples: [])
        let skill = try FamiliarSkillService().stageInstallation(document, in: context)
        skill.contentHash = String(repeating: "a", count: 64)
        try FamiliarProjectService().stageSkill(skill.id, enabled: true, projectID: UUID(), in: context)
        context.rollback()
        #expect(try context.fetch(FetchDescriptor<FamiliarSkill>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarProjectSkillBindingRecord>()).isEmpty)
    }

    @Test("Failed File persistence removes only the newly created bytes")
    func fileSaveFailureCompensates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarFileStore(rootURL: root)
        let projectID = UUID()
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarFileWriteTool(store: store))])
        let coordinator = FamiliarToolConfirmationCoordinator()
        let loop = FamiliarAgentLoop(provider: FamiliarCommitProvider(repeatCall: false, name: "file_write",
            arguments: #"{"title":"Note","content":"New text","format":"plainText"}"#), registry: registry, policy: .init(),
            confirmationCoordinator: coordinator, undoStore: .init(), persistResult: { _, _ in throw FamiliarCommitFixtureError() })
        let snapshot = try familiarTestContextSnapshot(manifests: await registry.snapshot(), projectID: projectID)
        var events: [FamiliarRuntimeEvent] = []
        for try await event in loop.stream(contextSnapshot: snapshot) {
            events.append(event)
            if case .approvalRequested(let value) = event.payload {
                await coordinator.resolve(requestID: value.id, decision: .confirmedOnce)
            }
        }
        #expect(failures(events) == ["tool_commit_rolled_back"])
        let folder = root.appendingPathComponent("Projects/\(projectID.uuidString)/Files")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test("File revisions and Undo preserve independent predecessor bytes and metadata")
    @MainActor
    func fileRevisionAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try FamiliarTestStore.make(name: "FileRevisions")
        let context = container.mainContext
        let store = FamiliarFileStore(rootURL: root)
        let service = FamiliarFileService(store: store)
        let projectID = UUID()
        let firstOutcome = try await FamiliarFileWriteTool(store: store).execute(.init(title: "Original", content: "Original text", format: .plainText), context: .init(projectID: projectID))
        guard case .action(let firstProposal) = firstOutcome else { Issue.record("Expected File write"); return }
        let first = try #require(try await firstProposal.commit().result.file)
        try service.persist(first, in: context)
        let editOutcome = try await FamiliarFileEditTool(store: store).execute(.init(identifier: first.identifier, content: "Revised text", title: nil), context: .init(projectID: projectID))
        guard case .action(let editProposal) = editOutcome else { Issue.record("Expected File revision"); return }
        let committed = try await editProposal.commit()
        let second = try #require(committed.result.file)
        try service.persist(second, in: context)
        #expect(try store.read(relativePath: first.relativePath) == Data("Original text".utf8))
        let row = try #require(service.storedFile(id: second.id, in: context))
        #expect(row.lineageID == first.id)
        #expect(row.version == 2)
        let undo = try #require(committed.undo)
        _ = try await undo()
        // The store deletion and its metadata commit share the authoritative service.
        try service.delete(row, in: context)
        #expect(service.latestVersion(inLineage: first.id, in: context)?.version == 1)
        #expect(try store.read(relativePath: first.relativePath) == Data("Original text".utf8))
        #expect(store.url(relativePath: second.relativePath) == nil)
    }

    private func run(probe: FamiliarCommitProbe, repeatCall: Bool = false, mode: FamiliarCommitFixtureTool.Mode = .external,
                     willCommit: (@Sendable (FamiliarToolCommitContext) async throws -> Void)? = nil,
                     persist: FamiliarToolResultPersistence? = nil) async throws -> [FamiliarRuntimeEvent] {
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarCommitFixtureTool(probe: probe, mode: mode))])
        let coordinator = FamiliarToolConfirmationCoordinator()
        let loop = FamiliarAgentLoop(provider: FamiliarCommitProvider(repeatCall: repeatCall), registry: registry, policy: .init(),
            confirmationCoordinator: coordinator, undoStore: .init(), persistResult: persist, willCommit: willCommit)
        let snapshot = try familiarTestContextSnapshot(manifests: await registry.snapshot())
        var events: [FamiliarRuntimeEvent] = []
        for try await event in loop.stream(contextSnapshot: snapshot) {
            events.append(event)
            if case .approvalRequested(let request) = event.payload {
                await coordinator.resolve(requestID: request.id, decision: .confirmedOnce)
            }
        }
        return events
    }
    private func failures(_ events: [FamiliarRuntimeEvent]) -> [String] {
        events.compactMap { if case .activityCompleted(let value) = $0.payload { value.failureCode } else { nil } }
    }
}

private actor FamiliarCommitProbe {
    private var values: [String] = []
    func record(_ value: String) { values.append(value) }
    func count(_ value: String) -> Int { values.filter { $0 == value }.count }
    func trace() -> [String] { values }
}

private nonisolated struct FamiliarCommitFixtureError: LocalizedError, FamiliarStructuredToolError {
    var errorDescription: String? { "Fixture save failed" }
    var code: String { "fixture_save_failed" }
    var isRetryable: Bool { false }
}

private nonisolated func fixtureResult() throws -> FamiliarToolExecutionResult {
    .init(envelope: try .init(model: ["ok": true], presentation: .scalar(.init(summary: "Fixture", value: "OK"))))
}

private nonisolated struct FamiliarCommitProvider: FamiliarModelProvider {
    let providerID = "commit-fixture"
    let repeatCall: Bool
    var name = "fixture_write"
    var arguments = "{}"
    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let count = request.messages.filter { $0.role == .tool }.count
            if count == 0 || (repeatCall && count == 1) {
                continuation.yield(.toolCallDelta(index: 0, id: "call-\(count)", name: name, arguments: arguments))
                continuation.yield(.completed(.toolCalls))
            } else {
                continuation.yield(.textDelta("Result inspected")); continuation.yield(.completed(.stop))
            }
            continuation.finish()
        }
    }
}

private nonisolated struct FamiliarCommitFixtureTool: FamiliarTool {
    enum Mode: Sendable { case external, local, throwAfterWrite }
    struct Input: Decodable, Sendable {}
    let probe: FamiliarCommitProbe
    let mode: Mode
    let manifest = FamiliarToolManifest(name: "fixture_write", title: "Fixture write", description: "Fixture", parameters: .object([:], required: []), effect: .reversibleWrite, risk: .low)
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        .action(.init(title: "Fixture write", fields: [], target: "fixture", effect: .reversibleWrite, risk: .low,
            consequence: "Write a fixture", undoPolicy: .currentSession, idempotencyKey: context.idempotencyKey, commit: {
                await probe.record("write")
                if mode == .throwAfterWrite { throw FamiliarCommitFixtureError() }
                let rollback: (@Sendable () async throws -> Void)?
                let finalize: (@Sendable () async -> Void)?
                if mode == .local {
                    rollback = { await probe.record("rollback") }
                    finalize = { await probe.record("finalize") }
                } else { rollback = nil; finalize = nil }
                return .init(result: try fixtureResult(), undo: {
                    await probe.record("undo"); return try fixtureResult()
                }, rollback: rollback, finalize: finalize)
            }))
    }
}
