import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Continuous reply Runtime presentation")
struct FamiliarRuntimePresentationTests {
    private let date = Date(timeIntervalSince1970: 100)

    private func surface(_ id: String, name: String = "web_search", sequence: Int = 1,
                         phase: FamiliarSurfacePhase = .succeeded, envelope: FamiliarToolResultEnvelope? = nil) -> FamiliarSurfaceDescriptor {
        .init(id: "tool:run:\(id)", runID: "run", sequence: sequence, assistantTurnID: "run:turn:0",
              kind: .toolSummary, placement: .trace, phase: phase, title: name, toolCallID: id,
              toolName: name, effect: .read, resultEnvelope: envelope, startedAt: date)
    }
    private func search(_ urls: [String]) throws -> FamiliarToolResultEnvelope {
        try .init(canonicalModelJSON: "{}", presentation: .searchResults(.init(summary: "Results", query: "Query",
            results: urls.enumerated().map { .init(id: "\($0.offset)", title: "Result", url: $0.element, snippet: nil) })))
    }
    private func event(_ sequence: Int, _ payload: FamiliarRuntimeEventPayload) -> FamiliarRuntimeEvent {
        .init(runID: "run", sequence: sequence, timestamp: date, assistantTurnID: "run:turn:0", payload: payload)
    }
    private func completion(_ id: String, status: FamiliarToolRunTerminalStatus = .succeeded) -> FamiliarRuntimeActivityCompletion {
        .init(runID: "run", toolCallID: id, toolName: "web_fetch", effect: .read, assistantTurnID: "run:turn:0",
            detail: status == .failed ? "Timeout" : "", confirmation: .notRequired, status: status,
            startedAt: date, finishedAt: date.addingTimeInterval(1), fileIdentifier: nil, undoAvailable: false,
            automaticApprovalRequest: nil, failureCode: status == .failed ? "timeout" : nil)
    }
    private func groups(_ blocks: [FamiliarAssistantContentBlock]) -> [FamiliarRuntimeActivityGroup] {
        blocks.compactMap { if case .runtime(let group) = $0 { group } else { nil } }
    }

    @Test("Repeated searches aggregate, count independent URLs, and preserve first-call identity")
    func searchAggregation() throws {
        let first = surface("a", envelope: try search(["https://a.test", "https://b.test"]))
        let second = surface("b", sequence: 2, envelope: try search(["https://b.test", "https://c.test"]))
        let blocks = FamiliarAssistantResponseProjection.blocks(text: [], surfaces: [second, first, first])
        let group = try #require(groups(blocks).first)
        #expect(blocks.count == 1)
        #expect(group.activities.map(\.toolCallID) == ["a", "b"])
        #expect(group.searchURLs.count == 3)
        #expect(group.callCount == 2)
        #expect(group.stages.count == 1)
        #expect(group.id == groups(FamiliarAssistantResponseProjection.blocks(text: [], surfaces: [first])).first?.id)
    }

    @Test("Text and user interactions split activity intervals in actual order")
    func boundaries() throws {
        let text = FamiliarAssistantTextBlock(.init(assistantTurnID: "run:turn:1", order: 3, startedAt: date, content: "Continuing"))
        var approval = surface("approval", sequence: 5, phase: .awaitingApproval)
        approval.kind = .approval
        let blocks = FamiliarAssistantResponseProjection.blocks(text: [text], surfaces: [surface("a"), surface("b", sequence: 4), approval, surface("c", sequence: 6)])
        #expect(blocks.map(\.order) == [1, 3, 4, 5, 6])
        #expect(groups(blocks).count == 3)
        #expect(blocks.contains { if case .surface(let value) = $0 { value.kind == .approval } else { false } })
        let empty = FamiliarAssistantTextBlock(.init(assistantTurnID: "run:turn:1", order: 3, startedAt: date))
        #expect(groups(FamiliarAssistantResponseProjection.blocks(text: [empty], surfaces: [surface("a"), surface("b", sequence: 4)])).count == 1)
    }

    @Test("Utility-only answers have no card; utility details remain inside real activity")
    func utilities() throws {
        let utility = surface("load", name: "tools_load", sequence: 0)
        #expect(FamiliarAssistantResponseProjection.blocks(text: [], surfaces: [utility]).isEmpty)
        let group = try #require(groups(FamiliarAssistantResponseProjection.blocks(text: [], surfaces: [utility, surface("a")])).first)
        #expect(group.activities.count == 2)
        #expect(group.callCount == 1)
        #expect(group.stages.map(\.kind) == [.search])
    }

    @Test("Reverse completion and duplicate events update one read, and terminal progress cannot reopen it")
    func concurrentCompletion() throws {
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runPhaseChanged(.starting)))
        store.apply(event(1, .activityStarted(.init(id: "a", toolName: "web_fetch", effect: .read, startedAt: date))))
        store.apply(event(2, .activityStarted(.init(id: "b", toolName: "web_fetch", effect: .read, startedAt: date))))
        store.apply(event(3, .activityCompleted(completion("b", status: .failed))))
        store.apply(event(4, .activityCompleted(completion("a"))))
        store.apply(event(4, .activityCompleted(completion("a"))))
        store.apply(event(5, .activityProgress(.init(id: "b", fractionCompleted: 0.5, detail: "Late"))))
        let group = try #require(groups(FamiliarAssistantResponseProjection.blocks(text: [], surfaces: store.orderedSurfaces)).first)
        #expect(group.activities.map(\.toolCallID) == ["a", "b"])
        #expect(group.status == .warning)
        #expect(group.failedCount == 1)
        #expect(group.activities.last?.failureCode == "timeout")
        store.apply(event(6, .runFinished(.cancelled())))
        store.apply(event(7, .activityProgress(.init(id: "a", fractionCompleted: nil, detail: "Late"))))
        #expect(!store.isActive)
        #expect(!store.orderedSurfaces.contains { !$0.phase.isTerminal })
    }

    @Test("Retry attempts retain call identity without adding tool counts")
    func retryIdentities() throws {
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .activityStarted(.init(id: "a", toolName: "web_fetch", effect: .read, startedAt: date))))
        store.apply(event(1, .activityStarted(.init(id: "b", toolName: "web_fetch", effect: .read, startedAt: date))))
        for (sequence, id) in [(2, "a"), (3, "b"), (4, "a")] {
            store.apply(event(sequence, .runtimeNotice(.init(kind: .retrying, attempt: 2, delay: 0.3, failureKind: .network, toolCallID: id))))
        }
        let group = try #require(groups(FamiliarAssistantResponseProjection.blocks(text: [], surfaces: store.orderedSurfaces)).first)
        #expect(group.callCount == 2)
        #expect(group.notices.count == 3)
        #expect(group.notices.map(\.toolCallID) == ["a", "b", "a"])
    }

    @Test("Partial reads are warnings; missing credentials and uncertain writes stay visible")
    func errorSeverity() throws {
        let failedRead = surface("failed", name: "web_fetch", phase: .failed)
        #expect(FamiliarRuntimeActivityGroup.displayStatus(failedRead) == .warning)
        var needsAction = failedRead
        needsAction.failureCode = "missing_search_api_key"
        let blocks = FamiliarAssistantResponseProjection.blocks(text: [], surfaces: [needsAction])
        #expect(groups(blocks).isEmpty)
        #expect(blocks.contains { if case .surface(let value) = $0 { value.kind == .failure } else { false } })
        var write = failedRead
        write.effect = .reversibleWrite
        write.kind = .failure
        write.failureCode = "tool_commit_unconfirmed"
        #expect(FamiliarRuntimeActivityGroup.displayStatus(write) == .failed)
        #expect(groups(FamiliarAssistantResponseProjection.blocks(text: [], surfaces: [write])).isEmpty)
    }

    @Test("A successful envelope cannot make a failed Shell command appear completed")
    func shellFailure() throws {
        let envelope = try FamiliarToolResultEnvelope(canonicalModelJSON: "{}", presentation: .shellExecution(.init(
            summary: "Failed", taskID: UUID(), command: "false", workingDirectory: "/work", runtime: "ish",
            status: "failed", exitCode: 1, standardOutput: "", standardError: "Error", outputWasTruncated: false, networkEnabled: false)))
        let value = surface("shell", name: "shell_execute", envelope: envelope)
        #expect(FamiliarRuntimeActivityGroup.displayStatus(value) == .warning)
    }

    @Test("The final block identity selects copy text and excludes commentary and reasoning")
    func finalCopy() {
        let first = block("Checking sources", order: 1)
        let final = block("The answer", order: 10)
        let message = FamiliarMessageSnapshot(id: UUID(), role: .assistant, content: "Checking sourcesThe answer",
            createdAt: date, sequence: 1, providerID: nil, modelID: nil, attachments: [],
            responseBlocks: [first, final], finalResponseBlockID: final.id)
        #expect(message.finalAnswerText == "The answer")
        let legacy = FamiliarMessageSnapshot(id: UUID(), role: .assistant, content: "Old answer", createdAt: date,
            sequence: 1, providerID: nil, modelID: nil, attachments: [])
        #expect(legacy.finalAnswerText == "Old answer")
    }

    @Test("Sensitive read consent remains an interval boundary after approval resolves")
    func resolvedConsent() {
        var sensitive = surface("sensitive", name: "health_activity_summary", sequence: 2)
        sensitive.approvalFields = [.init(id: "scope", label: "Scope", type: .text, value: "Health")]
        sensitive.approvalDecision = .approved
        #expect(groups(FamiliarAssistantResponseProjection.blocks(text: [], surfaces: [surface("a"), sensitive, surface("b", sequence: 3)])).count == 3)
    }

    @Test("Cancelling and failing preserve only the unfinished text checkpoint, without a final answer claim")
    @MainActor
    func interruptedText() throws {
        for outcome in [FamiliarRunOutcome.cancelled(), .failed(URLError(.networkConnectionLost))] {
            let fixture = try makeRun()
            defer { withExtendedLifetime(fixture.container) {} }
            let recorder = FamiliarRunPersistenceRecorder()
            let text = FamiliarLiveResponseBlock(assistantTurnID: "run:turn:1", order: 9, startedAt: date, content: "Partial answer")
            try recorder.recordInterruptedText([text], runtimeID: "run", outcome: outcome, at: date, context: fixture.context)
            recorder.finishRun(runtimeID: "run", outcome: outcome, eventSequence: 10, at: date, context: fixture.context)
            let controller = FamiliarChatController(dependencies: .init())
            controller.select(fixture.conversation.id, in: fixture.context)
            let run = try #require(controller.agentRuns.first)
            let saved = try #require(run.responseBlocks.first { $0.kind == .markdown })
            #expect(saved.id == text.id)
            #expect(saved.content == "Partial answer")
            #expect(saved.state == (outcome.status == .cancelled ? .cancelled : .failed))
            #expect(run.responseMessageID == nil)
            let blocks = FamiliarAssistantResponseProjection.blocks(text: [FamiliarAssistantTextBlock(saved)], surfaces: FamiliarSurfaceStore.projectedSurfaces(for: run))
            #expect(blocks.first?.order == 9)
            #expect(blocks.last?.order == 10)
        }
    }

    @Test("Historical File results reconnect to stored file metadata, including missing bytes")
    @MainActor
    func fileReload() throws {
        let fixture = try makeRun(project: true)
        defer { withExtendedLifetime(fixture.container) {} }
        let project = try #require(fixture.conversation.project)
        let file = FamiliarStoredFileVersion(projectID: project.id, identifier: "output", title: "report.md", relativePath: "missing.md",
            byteSize: 123, contentHash: "hash", createdByRunID: "run")
        fixture.context.insert(file)
        let envelope = try FamiliarToolResultEnvelope(canonicalModelJSON: "{}", presentation: .fileMutation(.init(summary: "Saved",
            operation: "write", identifier: "output", title: "report.md", byteSize: 123, contentHash: "hash")))
        let recorder = FamiliarRunPersistenceRecorder()
        let complete = FamiliarRuntimeActivityCompletion(runID: "run", toolCallID: "write", toolName: "file_write", effect: .reversibleWrite,
            assistantTurnID: "run:turn:0", detail: "", confirmation: .confirmed, status: .succeeded, startedAt: date, finishedAt: date,
            fileIdentifier: "output", undoAvailable: false, automaticApprovalRequest: nil)
        try recorder.recordActivityCompleted(complete, eventSequence: 1, conversationID: fixture.conversation.id, context: fixture.context)
        _ = try recorder.recordToolResult(.init(runID: "run", toolCallID: "write", toolName: "file_write", effect: .reversibleWrite,
            assistantTurnID: "run:turn:0", envelope: envelope, sources: [], file: nil, producedAt: date), eventSequence: 2,
            conversationID: fixture.conversation.id, context: fixture.context)
        recorder.finishRun(runtimeID: "run", outcome: .succeeded, eventSequence: 3, at: date, context: fixture.context)
        let controller = FamiliarChatController(dependencies: .init())
        controller.select(fixture.conversation.id, in: fixture.context)
        let run = try #require(controller.agentRuns.first)
        let value = try #require(FamiliarSurfaceStore.projectedSurfaces(for: run).first { $0.kind == .file })
        #expect(value.file?.title == "report.md")
        #expect(value.file?.byteSize == 123)
        #expect(value.file?.format == .markdown)
        #expect(FamiliarFileStore().url(relativePath: "missing.md") == nil)
        fixture.context.delete(file)
        try fixture.context.save()
        controller.reloadMessages(in: fixture.context)
        #expect(controller.agentRuns.first?.toolResults.first?.file == nil)
    }

    @Test("Technical parameters are redacted without changing the original tool contract")
    func parameterRedaction() {
        let original = #"{"api_key":"sk-private","password":"private","query":"SwiftUI"}"#
        let display = FamiliarRuntimeTechnicalText.redacted(original)
        #expect(!display.contains("private"))
        #expect(display.contains("SwiftUI"))
        #expect(original.contains("sk-private"))
    }

    @Test("Declining a read skips that operation instead of claiming the Run stopped")
    func declinedRead() throws {
        var skipped = surface("skipped", name: "web_fetch", phase: .cancelled)
        skipped.approvalDecision = .cancelled
        let group = try #require(groups(FamiliarAssistantResponseProjection.blocks(text: [], surfaces: [skipped])).first)
        #expect(group.failedCount == 0)
        #expect(group.summary.contains(String(format: String(localized: "runtime.ui.skipped_count"), 1)))
        #expect(!group.summary.contains(String(localized: "runtime.ui.stopped")))
    }

    @Test("Length-limited output never becomes a completed assistant turn")
    func truncatedStream() async throws {
        let loop = FamiliarAgentLoop(provider: FamiliarTruncatedPresentationProvider(), registry: try .init(tools: []),
            policy: .init(), confirmationCoordinator: .init(), undoStore: .init())
        var events: [FamiliarRuntimeEvent] = []
        for try await event in loop.stream(contextSnapshot: try familiarTestContextSnapshot(manifests: [])) { events.append(event) }
        #expect(events.contains { if case .responseTextDelta("Partial") = $0.payload { true } else { false } })
        #expect(!events.contains { if case .assistantTurnCompleted = $0.payload { true } else { false } })
        #expect(events.filter { if case .runFinished = $0.payload { true } else { false } }.count == 1)
        #expect(events.contains { if case .runFinished(let outcome) = $0.payload { outcome.status == .failed } else { false } })
    }

    @Test("A committing journal survives cancellation and projects an unconfirmed write")
    @MainActor
    func uncertainJournal() throws {
        let fixture = try makeRun()
        defer { withExtendedLifetime(fixture.container) {} }
        fixture.context.insert(FamiliarToolInvocationRecord(idempotencyKey: "run:write", runtimeID: "run", toolCallID: "write",
            toolName: "file_write", argumentsHash: "hash", state: .committing))
        try FamiliarRunPersistenceRecorder().recordActivityStarted(.init(id: "write", toolName: "file_write", effect: .reversibleWrite,
            startedAt: date), runtimeID: "run", assistantTurnID: "run:turn:0", eventSequence: 1, context: fixture.context)
        FamiliarRunPersistenceRecorder().finishRun(runtimeID: "run", outcome: .cancelled(), eventSequence: 2, at: date, context: fixture.context)
        let controller = FamiliarChatController(dependencies: .init())
        controller.select(fixture.conversation.id, in: fixture.context)
        let run = try #require(controller.agentRuns.first)
        #expect(run.regenerationRequiresInspection)
        #expect(run.uncertainToolCallIDs == ["write"])
        let failure = try #require(FamiliarSurfaceStore.projectedSurfaces(for: run).first { $0.toolCallID == "write" })
        #expect(failure.kind == .failure)
        #expect(failure.failureCode == "tool_commit_unconfirmed")
        #expect(failure.failureRetryable == false)
    }

    private func block(_ content: String, order: Int) -> FamiliarResponseBlockSnapshot {
        .init(id: UUID(), assistantTurnID: "run:turn:\(order)", messageID: nil, kind: .markdown, order: order,
            state: .completed, content: content, payloadJSON: "{}", schemaVersion: 1, startedAt: date, endedAt: date, contentHash: "hash")
    }

    @MainActor
    private func makeRun(project: Bool = false) throws -> (container: ModelContainer, context: ModelContext, conversation: FamiliarConversation) {
        let container = try FamiliarTestStore.make(name: "RuntimePresentation-\(UUID())")
        let context = container.mainContext
        let owner = project ? FamiliarProject(name: "Runtime") : nil
        if let owner { context.insert(owner) }
        let conversation = FamiliarConversation(project: owner)
        context.insert(conversation)
        try context.save()
        let snapshot = try FamiliarContextCompiler.assemble(seed: .init(projectID: owner?.id, projectName: owner?.name,
            conversationID: conversation.id, projectInstruction: nil, resources: []), settings: .defaultValue, messages: [], toolManifests: [])
        FamiliarRunPersistenceRecorder().ensureRun(runtimeID: "run", snapshot: snapshot, startedAt: date, context: context)
        return (container, context, conversation)
    }
}

private struct FamiliarTruncatedPresentationProvider: FamiliarModelProvider {
    let providerID = "fixture"
    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("Partial"))
            continuation.yield(.completed(.length))
            continuation.finish()
        }
    }
}
