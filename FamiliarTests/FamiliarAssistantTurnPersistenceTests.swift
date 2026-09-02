import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Assistant turn persistence")
struct FamiliarAssistantTurnPersistenceTests {
    @Test("Tool results preserve the structured envelope and projection metadata")
    @MainActor
    func toolResultPersistence() throws {
        let fixture = try makeRun(runtimeID: "tool-run")
        let recorder = FamiliarRunPersistenceRecorder()
        let envelope = try FamiliarToolResultEnvelope(
            canonicalModelJSON: #"{"text":"fixture"}"#,
            presentation: .document(.init(summary: "Fetched", title: "Fixture", text: "body", truncated: true))
        )
        let completion = FamiliarRuntimeActivityCompletion(
            runID: "tool-run",
            toolCallID: "call-1",
            toolName: "web_fetch",
            effect: .read,
            assistantTurnID: "tool-run:turn:0",
            detail: "Fetched",
            confirmation: .notRequired,
            status: .succeeded,
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 12),
            artifactIdentifier: nil,
            undoAvailable: false,
            automaticApprovalRequest: nil
        )
        let event = FamiliarToolResultProduced(runID: "tool-run", toolCallID: "call-1", toolName: "web_fetch", effect: .read, assistantTurnID: "tool-run:turn:0", envelope: envelope, sources: [], webCaptures: [], artifact: nil, producedAt: Date(timeIntervalSince1970: 12))

        try recorder.recordActivityCompleted(completion, eventSequence: 3, conversationID: fixture.conversation.id, context: fixture.context)
        #expect(try recorder.recordToolResult(event, eventSequence: 4, conversationID: fixture.conversation.id, context: fixture.context))

        let result = try #require(fixture.context.fetch(FetchDescriptor<FamiliarToolResultRecord>()).first)
        let activity = try #require(fixture.context.fetch(FetchDescriptor<FamiliarActivityRecord>()).first { $0.kind == .tool })
        #expect(try JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(result.envelopeJSON.utf8)) == envelope)
        #expect(result.schemaVersion == FamiliarToolPresentationPayload.currentSchemaVersion)
        #expect(result.payloadName == FamiliarToolPresentationPayload.Name.document.rawValue)
        #expect(result.payloadHash.count == 64)
        #expect(result.trust == .untrusted)
        #expect(result.truncated)
        #expect(activity.resultRecordID == result.id)
        #expect(activity.assistantTurnID == "tool-run:turn:0")
        #expect(activity.phase == .succeeded)
    }

    @Test("Approval fields retain order and authorization audit data")
    @MainActor
    func approvalPersistence() throws {
        let fixture = try makeRun(runtimeID: "approval-run")
        let recorder = FamiliarRunPersistenceRecorder()
        let requestedAt = Date(timeIntervalSince1970: 20)
        let resolvedAt = Date(timeIntervalSince1970: 21)
        let request = FamiliarToolConfirmationRequest(
            runID: "approval-run",
            toolCallID: "call-2",
            toolName: "create_calendar_event",
            effect: .reversibleWrite,
            risk: .sensitive,
            title: "Create event",
            fields: [
                .init(id: "title", label: "Title", type: .text, value: "Review"),
                .init(id: "start", label: "Start", type: .date, value: "2026-08-21T10:00:00Z"),
                .init(id: "all_day", label: "All day", type: .boolean, value: "false")
            ],
            target: "Calendar",
            consequence: "Creates one event",
            undoPolicy: .durable,
            automaticAuthorization: true,
            automaticAuthorizationScope: .always,
            allowedAuthorizationDurations: [.once]
        )

        try recorder.recordApprovalRequested(request, assistantTurnID: "approval-run:turn:0", eventSequence: 3, at: requestedAt, context: fixture.context)
        try recorder.recordApprovalResolved(requestID: request.id, decision: .confirmedAlways, eventSequence: 4, at: resolvedAt, context: fixture.context)

        let record = try #require(fixture.context.fetch(FetchDescriptor<FamiliarApprovalRecord>()).first)
        let fields = try JSONDecoder().decode([FamiliarApprovalField].self, from: Data(record.orderedFieldsJSON.utf8))
        #expect(fields.map(\.id) == ["title", "start", "all_day"])
        #expect(record.target == "Calendar")
        #expect(record.effect == .reversibleWrite)
        #expect(record.risk == .sensitive)
        #expect(record.consequence == "Creates one event")
        #expect(record.undoPolicy == .durable)
        #expect(try JSONDecoder().decode([FamiliarAuthorizationDuration].self, from: Data(record.allowedAuthorizationDurationsJSON.utf8)) == [.once])
        #expect(record.decision == .approved)
        #expect(record.scope == .always)
        #expect(record.requestedAt == requestedAt)
        #expect(record.resolvedAt == resolvedAt)
        #expect(record.automaticAuthorization)
    }

    @Test("Completed assistant messages reload with a markdown response block")
    @MainActor
    func responseBlockReload() throws {
        let fixture = try makeRun(runtimeID: "response-run")
        let recorder = FamiliarRunPersistenceRecorder()
        let messageID = UUID()
        let blockID = UUID()
        let message = FamiliarMessage(
            id: messageID,
            role: .assistant,
            content: "**Answer**",
            sequence: 0,
            runtimeID: "response-run",
            assistantTurnID: "response-run:turn:0",
            responseBlockID: blockID,
            conversation: fixture.conversation
        )
        fixture.context.insert(message)
        _ = try recorder.recordResponseBlock(
            id: blockID,
            runtimeID: "response-run",
            assistantTurnID: "response-run:turn:0",
            messageID: messageID,
            kind: .markdown,
            state: .completed,
            content: "**Answer**",
            endedAt: Date(timeIntervalSince1970: 30),
            context: fixture.context
        )

        let controller = FamiliarChatController(dependencies: FamiliarAppDependencies())
        controller.select(fixture.conversation.id, in: fixture.context)

        let block = try #require(controller.messages.first?.responseBlocks.first)
        let runBlock = try #require(controller.agentRuns.first?.responseBlocks.first)
        #expect(block.id == blockID)
        #expect(block.kind == .markdown)
        #expect(block.state == .completed)
        #expect(block.content == "**Answer**")
        #expect(block.contentHash.count == 64)
        #expect(runBlock == block)
    }

    @Test("Multiple assistant turns retain runtime order when attached to one message")
    @MainActor
    func orderedResponseBlockReload() throws {
        let fixture = try makeRun(runtimeID: "ordered-response-run")
        let recorder = FamiliarRunPersistenceRecorder()
        let messageID = UUID()
        let firstID = UUID()
        let finalID = UUID()
        let message = FamiliarMessage(
            id: messageID,
            role: .assistant,
            content: "Checking\n\nDone",
            sequence: 0,
            runtimeID: "ordered-response-run",
            assistantTurnID: "ordered-response-run:turn:1",
            responseBlockID: finalID,
            conversation: fixture.conversation
        )
        fixture.context.insert(message)

        _ = try recorder.recordResponseBlock(id: firstID, runtimeID: "ordered-response-run", assistantTurnID: "ordered-response-run:turn:0", messageID: nil, kind: .markdown, state: .completed, content: "Checking", order: 2, endedAt: Date(timeIntervalSince1970: 2), context: fixture.context)
        _ = try recorder.recordResponseBlock(id: firstID, runtimeID: "ordered-response-run", assistantTurnID: "ordered-response-run:turn:0", messageID: messageID, kind: .markdown, state: .completed, content: "Checking", order: 2, endedAt: Date(timeIntervalSince1970: 2), context: fixture.context)
        _ = try recorder.recordResponseBlock(id: finalID, runtimeID: "ordered-response-run", assistantTurnID: "ordered-response-run:turn:1", messageID: messageID, kind: .markdown, state: .completed, content: "Done", order: 9, endedAt: Date(timeIntervalSince1970: 9), context: fixture.context)

        let controller = FamiliarChatController(dependencies: FamiliarAppDependencies())
        controller.select(fixture.conversation.id, in: fixture.context)

        let blocks = try #require(controller.messages.first?.responseBlocks)
        #expect(blocks.map(\.id) == [firstID, finalID])
        #expect(blocks.map(\.order) == [2, 9])
        #expect(blocks.map(\.content) == ["Checking", "Done"])
    }

    @Test("A completed reasoning summary is persisted as one response block")
    @MainActor
    func reasoningSummaryPersistence() throws {
        let fixture = try makeRun(runtimeID: "reasoning-run")
        let recorder = FamiliarRunPersistenceRecorder()
        _ = try recorder.recordResponseBlock(
            runtimeID: "reasoning-run",
            assistantTurnID: "reasoning-run:turn:0",
            messageID: UUID(),
            kind: .reasoningSummary,
            state: .completed,
            content: "Checked the explicit provider reasoning field.",
            endedAt: Date(timeIntervalSince1970: 35),
            context: fixture.context
        )

        let blocks = try fixture.context.fetch(FetchDescriptor<FamiliarResponseBlockRecord>())
        #expect(blocks.count == 1)
        #expect(blocks.first?.kind == .reasoningSummary)
        #expect(blocks.first?.content == "Checked the explicit provider reasoning field.")
    }

    @Test("Failed runs retain projectable notice records")
    @MainActor
    func failedRunProjection() throws {
        let fixture = try makeRun(runtimeID: "failed-run")
        let recorder = FamiliarRunPersistenceRecorder()
        recorder.finishRun(
            runtimeID: "failed-run",
            outcome: .init(status: .failed, failureKind: .transientServer, message: "Provider unavailable"),
            eventSequence: 2,
            at: Date(timeIntervalSince1970: 40),
            context: fixture.context
        )

        let block = try #require(fixture.context.fetch(FetchDescriptor<FamiliarResponseBlockRecord>()).first)
        let activity = try #require(fixture.context.fetch(FetchDescriptor<FamiliarActivityRecord>()).first)
        #expect(block.kind == .runtimeNotice)
        #expect(block.state == .failed)
        #expect(block.content == "Provider unavailable")
        #expect(activity.kind == .runtimeNotice)
        #expect(activity.phase == .failed)
        #expect(activity.endedAt != nil)
    }

    @Test("Task plan updates persist only the latest revision")
    @MainActor
    func taskPlanRevision() throws {
        let fixture = try makeRun(runtimeID: "plan-run")
        let recorder = FamiliarRunPersistenceRecorder()
        for (index, status) in [FamiliarToolPresentationPayload.TaskStatus.pending, .completed].enumerated() {
            let callID = "plan-call-\(index)"
            let completion = FamiliarRuntimeActivityCompletion(runID: "plan-run", toolCallID: callID, toolName: "task_plan", effect: .read, assistantTurnID: "plan-run:turn:0", detail: "", confirmation: .notRequired, status: .succeeded, startedAt: Date(timeIntervalSince1970: Double(index + 2)), finishedAt: Date(timeIntervalSince1970: Double(index + 3)), artifactIdentifier: nil, undoAvailable: false, automaticApprovalRequest: nil)
            try recorder.recordActivityCompleted(completion, eventSequence: index * 2, conversationID: fixture.conversation.id, context: fixture.context)
            let payload = FamiliarToolPresentationPayload.taskList(.init(planID: "release", title: "Release", tasks: [.init(id: "build", title: "Build", status: status)]))
            let envelope = try FamiliarToolResultEnvelope(canonicalModelJSON: #"{"planID":"release"}"#, presentation: payload)
            let result = FamiliarToolResultProduced(runID: "plan-run", toolCallID: callID, toolName: "task_plan", effect: .read, assistantTurnID: "plan-run:turn:0", envelope: envelope, sources: [], webCaptures: [], artifact: nil, producedAt: Date(timeIntervalSince1970: Double(index + 3)))
            _ = try recorder.recordToolResult(result, eventSequence: index * 2 + 1, conversationID: fixture.conversation.id, context: fixture.context)
        }

        let records = try fixture.context.fetch(FetchDescriptor<FamiliarToolResultRecord>())
        let record = try #require(records.first)
        let envelope = try JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(record.envelopeJSON.utf8))
        #expect(records.count == 1)
        #expect(record.semanticID == "release")
        #expect(record.revision == 2)
        if case .taskList(let plan) = envelope.presentation.content {
            #expect(plan.tasks.first?.status == .completed)
        } else {
            Issue.record("Expected task plan payload")
        }
    }

    @Test("Interrupted clarification reloads as non-interactive")
    @MainActor
    func interruptedClarificationProjection() throws {
        let fixture = try makeRun(runtimeID: "clarification-run")
        let recorder = FamiliarRunPersistenceRecorder()
        let request = FamiliarClarificationRequest(runID: "clarification-run", toolCallID: "question", question: "Choose a scope", options: [.init(id: "project", label: "Project")], allowCustom: true)
        try recorder.recordClarificationRequested(request, assistantTurnID: "clarification-run:turn:0", eventSequence: 2, at: Date(timeIntervalSince1970: 2), context: fixture.context)

        #expect(try FamiliarRunRecoveryService().recoverInterruptedRuns(in: fixture.context) == 1)
        let controller = FamiliarChatController(dependencies: FamiliarAppDependencies())
        controller.select(fixture.conversation.id, in: fixture.context)
        let run = try #require(controller.agentRuns.first)
        let clarification = try #require(FamiliarSurfaceStore.projectedSurfaces(for: run).first { $0.kind == .clarification })

        #expect(clarification.phase == .failed)
        #expect(clarification.clarificationRequestID == nil)
        #expect(clarification.clarificationResolution == .interrupted)
    }

    @MainActor
    private func makeRun(runtimeID: String) throws -> (container: ModelContainer, context: ModelContext, conversation: FamiliarConversation) {
        let container = try FamiliarTestStore.make(name: "AssistantTurn-\(runtimeID)")
        let context = container.mainContext
        let conversation = FamiliarConversation()
        context.insert(conversation)
        try context.save()
        let snapshot = try FamiliarProjectContextAssembler.assemble(
            seed: .init(projectID: nil, projectName: nil, conversationID: conversation.id, projectInstruction: nil, resources: []),
            settings: .defaultValue,
            messages: [],
            toolManifests: []
        )
        FamiliarRunPersistenceRecorder().ensureRun(runtimeID: runtimeID, snapshot: snapshot, startedAt: Date(timeIntervalSince1970: 1), context: context)
        return (container, context, conversation)
    }
}
