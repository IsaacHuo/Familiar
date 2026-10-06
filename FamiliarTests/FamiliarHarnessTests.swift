import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("One Agent natural tool loop")
struct FamiliarHarnessTests {
    @Test("Ordinary, Daily Chat and Project answers need one model request and no tool")
    func directAnswersDoNotRequirePlans() async throws {
        for projectID in [nil, FamiliarProject.dailyProjectID, UUID()] {
            let probe = FamiliarHarnessProbe()
            let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarTaskPlanTool())])
            let events = try await run(provider: .init(probe: probe, mode: .direct), registry: registry, projectID: projectID)
            #expect(await probe.count() == 1)
            #expect(!events.contains { if case .toolInvocationRequested = $0.payload { true } else { false } })
            #expect(events.contains { if case .responseTextDelta("Hello") = $0.payload { true } else { false } })
            #expect(outcomes(events) == [.succeeded])
        }
    }

    @Test("An optional pending checklist does not schedule work or prevent an answer")
    func optionalChecklistDoesNotGateCompletion() async throws {
        let probe = FamiliarHarnessProbe()
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarTaskPlanTool())])
        let events = try await run(provider: .init(probe: probe, mode: .checklist), registry: registry, projectID: UUID())
        #expect(await probe.count() == 2)
        #expect(outcomes(events) == [.succeeded])
        #expect(events.contains { event in
            if case .toolResultProduced(let result) = event.payload,
               case .taskList(let list) = result.envelope.presentation.content {
                return list.tasks.first?.status == .pending
            }
            return false
        })
    }

    @Test("Text File write needs approval but no prior plan")
    func fileWriteWithoutPlan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarFileStore(rootURL: root)
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarFileWriteTool(store: store))])
        let probe = FamiliarHarnessProbe()
        let events = try await run(provider: .init(probe: probe, mode: .file), registry: registry, projectID: UUID())
        #expect(await probe.count() == 2)
        #expect(outcomes(events) == [.succeeded])
        let file = try #require(events.compactMap { event -> FamiliarFileDescriptor? in
            if case .toolResultProduced(let result) = event.payload { return result.file }
            return nil
        }.first)
        #expect(String(decoding: try store.read(relativePath: file.relativePath), as: UTF8.self) == "Verified text")
        #expect(events.contains { if case .approvalRequested = $0.payload { true } else { false } })
    }

    @Test("Memory save failure reaches the model without a successful receipt")
    func failedMemoryCommitDoesNotReportSuccess() async throws {
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarMemoryRememberTool())])
        let probe = FamiliarHarnessProbe()
        let events = try await run(provider: .init(probe: probe, mode: .memory), registry: registry, projectID: nil, persistResult: { result, _ in
            if result.memoryWrite != nil { throw FamiliarHarnessCommitFailure() }
            return .init()
        })
        #expect(!events.contains { if case .toolResultProduced = $0.payload { true } else { false } })
        #expect(events.contains { event in
            if case .activityCompleted(let activity) = event.payload {
                return activity.toolName == "memory_remember" && activity.status == .failed && activity.failureCode == "tool_persistence_failed"
            }
            return false
        })
        #expect(await probe.lastToolContent().contains("tool_persistence_failed"))
        #expect(outcomes(events) == [.succeeded])
    }

    @Test("Memory is visible in storage before its success event")
    @MainActor
    func successfulMemoryCommitPrecedesReceipt() async throws {
        let container = try FamiliarTestStore.make(name: "HarnessMemoryCommit")
        let context = container.mainContext
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarMemoryRememberTool())])
        let coordinator = FamiliarToolConfirmationCoordinator()
        let loop = FamiliarAgentLoop(provider: FamiliarHarnessProvider(probe: .init(), mode: .memory), registry: registry,
            policy: .init(), confirmationCoordinator: coordinator, undoStore: .init(), persistResult: { @MainActor result, _ in
                if let memory = result.memoryWrite { try FamiliarMemoryService().persist(memory, in: context) }
                return .init()
            })
        let snapshot = try familiarTestContextSnapshot(manifests: await registry.manifests())
        var receivedMemory = false
        for try await event in loop.stream(contextSnapshot: snapshot) {
            if case .approvalRequested(let request) = event.payload {
                await coordinator.resolve(requestID: request.id, decision: .confirmedOnce)
            }
            if case .toolResultProduced(let result) = event.payload, result.toolName == "memory_remember" {
                receivedMemory = true
                let saved = try #require(context.fetch(FetchDescriptor<FamiliarMemoryItem>()).first)
                #expect(saved.content == "I prefer concise answers")
                #expect(saved.creator == .agentConfirmed)
            }
        }
        #expect(receivedMemory)
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

    private func run(provider: FamiliarHarnessProvider, registry: FamiliarToolRegistry, projectID: UUID?, persistResult: FamiliarToolResultPersistence? = nil) async throws -> [FamiliarRuntimeEvent] {
        let coordinator = FamiliarToolConfirmationCoordinator()
        let loop = FamiliarAgentLoop(provider: provider, registry: registry, policy: .init(), confirmationCoordinator: coordinator, undoStore: .init(), persistResult: persistResult)
        let snapshot = try familiarTestContextSnapshot(manifests: await registry.manifests(), projectID: projectID)
        var events: [FamiliarRuntimeEvent] = []
        for try await event in loop.stream(contextSnapshot: snapshot) {
            events.append(event)
            if case .approvalRequested(let request) = event.payload {
                await coordinator.resolve(requestID: request.id, decision: .confirmedOnce)
            }
        }
        return events
    }

    private func outcomes(_ events: [FamiliarRuntimeEvent]) -> [FamiliarRunOutcome] {
        events.compactMap { if case .runFinished(let outcome) = $0.payload { outcome } else { nil } }
    }
}

private actor FamiliarHarnessProbe {
    private var requests = 0
    private var toolContent = ""
    func next(_ request: FamiliarModelRequest) -> Int {
        requests += 1
        toolContent = request.messages.filter { $0.role == .tool }.compactMap(\.networkText).joined()
        return requests
    }
    func count() -> Int { requests }
    func lastToolContent() -> String { toolContent }
}

private nonisolated struct FamiliarHarnessCommitFailure: LocalizedError, FamiliarStructuredToolError {
    var errorDescription: String? { "Fixture could not persist memory." }
    var code: String { "fixture_commit_failed" }
    var isRetryable: Bool { false }
}

private struct FamiliarHarnessProvider: FamiliarModelProvider {
    enum Mode: Sendable { case direct, checklist, file, memory }
    let providerID = "harness-fixture"
    let probe: FamiliarHarnessProbe
    let mode: Mode

    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let firstRequest = await probe.next(request) == 1
                if firstRequest, mode == .checklist {
                    continuation.yield(.toolCallDelta(index: 0, id: "plan", name: "task_plan", arguments: #"{"planID":"plan","title":"Optional checklist","tasks":[{"id":"step","title":"Consider options","status":"pending"}]}"#))
                    continuation.yield(.completed(.toolCalls))
                } else if firstRequest, mode == .file {
                    continuation.yield(.toolCallDelta(index: 0, id: "write", name: "file_write", arguments: #"{"title":"Note","content":"Verified text","format":"plainText"}"#))
                    continuation.yield(.completed(.toolCalls))
                } else if firstRequest, mode == .memory {
                    continuation.yield(.toolCallDelta(index: 0, id: "remember", name: "memory_remember", arguments: #"{"content":"I prefer concise answers","scope":"global"}"#))
                    continuation.yield(.completed(.toolCalls))
                } else {
                    continuation.yield(.textDelta("Hello"))
                    continuation.yield(.completed(.stop))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
