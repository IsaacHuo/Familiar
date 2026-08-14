import Foundation
import SwiftData
import Testing
@testable import Familiar

private actor FamiliarSnapshotCapabilitySpy: FamiliarCapabilityProviding {
    private(set) var availabilityChecks = 0
    private(set) var requests = 0

    func availability(for requirement: FamiliarCapabilityRequirement) -> FamiliarCapabilityAvailability {
        availabilityChecks += 1
        return .unavailable(reason: "Denied")
    }

    func request(_ requirement: FamiliarCapabilityRequirement) {
        requests += 1
    }
}

private struct FamiliarSnapshotTool: FamiliarTool {
    struct Input: Decodable, Sendable {}

    let manifest: FamiliarToolManifest

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        .result(.init(modelContent: "{}", displayContent: "OK"))
    }
}

@Suite("WP1 boundaries")
struct FamiliarWP1Tests {
    @Test("Registry snapshot reports exact membership without capability access")
    func registrySnapshotIsReadOnlyMembership() async throws {
        let capabilities = FamiliarSnapshotCapabilitySpy()
        let restricted = FamiliarSnapshotTool(manifest: .init(
            name: "restricted_tool",
            title: "Restricted",
            description: "",
            parameters: .init(type: .object),
            effect: .read,
            risk: .sensitive,
            requirements: [.calendarFullAccess]
        ))
        let generic = FamiliarSnapshotTool(manifest: .init(
            name: "future_tool",
            title: "Future",
            description: "",
            parameters: .init(type: .object),
            effect: .read,
            risk: .low,
            requirements: []
        ))
        let registry = try FamiliarToolRegistry(
            tools: [AnyFamiliarTool(restricted), AnyFamiliarTool(generic)],
            capabilities: capabilities
        )

        let snapshot = await registry.snapshot()

        #expect(snapshot.map(\.name) == ["future_tool", "restricted_tool"])
        #expect(await capabilities.availabilityChecks == 0)
        #expect(await capabilities.requests == 0)
        #expect(FamiliarToolPresentation.symbol(for: "future_tool") == "wrench.and.screwdriver")
    }

    @Test("Run recorder preserves timeline ordering and terminal idempotence")
    @MainActor
    func runRecorderLifecycle() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let conversation = FamiliarConversation()
        context.insert(conversation)
        context.insert(FamiliarMessage(role: .user, content: "Prompt", sequence: 2, conversation: conversation))
        context.insert(FamiliarModelSwitchRecord(
            previousProviderID: "old",
            previousModelID: "old",
            currentProviderID: "new",
            currentModelID: "new",
            sequence: 4,
            conversation: conversation
        ))
        try context.save()

        let recorder = FamiliarRunPersistenceRecorder()
        let startedAt = Date(timeIntervalSince1970: 10)
        let finishedAt = Date(timeIntervalSince1970: 20)
        let snapshot = try FamiliarProjectContextAssembler.assemble(
            seed: .init(projectID: nil, projectName: nil, conversationID: conversation.id, projectInstruction: nil, resources: []),
            settings: .defaultValue,
            messages: [],
            toolManifests: []
        )
        recorder.ensureRun(runtimeID: "run", snapshot: snapshot, startedAt: startedAt, context: context)
        recorder.ensureRun(runtimeID: "run", snapshot: snapshot, startedAt: .distantFuture, context: context)
        recorder.recordCheckpoint(
            type: .model,
            runtimeID: "run",
            eventSequence: 1,
            summary: "Model",
            detail: "Started",
            context: context
        )
        let toolEvent = FamiliarToolRunTerminalEvent(
            runID: "run",
            toolCallID: "call",
            toolName: "future_tool",
            summary: "Tool",
            detail: "Done",
            confirmation: .notRequired,
            status: .succeeded,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
        #expect(try recorder.recordTool(toolEvent, eventSequence: 2, conversationID: conversation.id, context: context))
        #expect(try !recorder.recordTool(toolEvent, eventSequence: 2, conversationID: conversation.id, context: context))
        recorder.finishRun(runtimeID: "run", status: .completed, reason: "completed", eventSequence: 3, at: finishedAt, context: context)
        recorder.finishRun(runtimeID: "run", status: .completed, reason: "completed", eventSequence: 3, at: finishedAt, context: context)

        let runs = try context.fetch(FetchDescriptor<FamiliarAgentRun>())
        let run = try #require(runs.first)
        let orderedSteps = run.steps.sorted { $0.timelineSequence < $1.timelineSequence }
        #expect(runs.count == 1)
        #expect(run.startedAt == startedAt)
        #expect(run.status == .completed)
        #expect(run.finishedAt == finishedAt)
        #expect(orderedSteps.map(\.type) == [.model, .tool, .result])
        #expect(orderedSteps.map(\.timelineSequence) == [5, 6, 7])
        #expect(run.steps.filter { $0.type == .result }.count == 1)
        #expect(conversation.updatedAt == finishedAt)
    }
}
