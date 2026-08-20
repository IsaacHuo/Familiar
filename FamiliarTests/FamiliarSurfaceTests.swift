import Foundation
import Testing
@testable import Familiar

@Suite("Familiar surface reducer")
struct FamiliarSurfaceTests {

    private func event(
        _ sequence: Int,
        _ payload: FamiliarRuntimeEventPayload,
        runID: String = "run-1"
    ) -> FamiliarRuntimeEvent {
        FamiliarRuntimeEvent(
            runID: runID,
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: Double(sequence)),
            assistantTurnID: runID + ":turn:0",
            payload: payload
        )
    }

    private func progress(
        _ id: String,
        state: FamiliarToolProgressState,
        title: String = "Web 搜索",
        detail: String? = nil
    ) -> FamiliarRuntimeEventPayload {
        .toolProgress(.init(id: id, toolName: "web_search", title: title, detail: detail, state: state, effect: .reversibleWrite))
    }

    private func approval(
        requestID: UUID = UUID(),
        toolCallID: String = "call-1",
        effect: FamiliarToolEffect = .reversibleWrite,
        title: String = "创建日历事件",
        fields: [String: String] = ["title": "复习"],
        target: String? = "日历"
    ) -> FamiliarRuntimeEventPayload {
        .approvalRequested(FamiliarToolConfirmationRequest(
            id: requestID,
            runID: "run-1",
            toolCallID: toolCallID,
            toolName: "create_calendar_event",
            effect: effect,
            title: title,
            fields: fields,
            target: target
        ))
    }

    private func terminal(
        toolCallID: String = "call-1",
        status: FamiliarToolRunTerminalStatus,
        summary: String = "Web 搜索",
        detail: String = "完成"
    ) -> FamiliarRuntimeEventPayload {
        .toolFinished(FamiliarToolRunTerminalEvent(
            runID: "run-1",
            toolCallID: toolCallID,
            toolName: "web_search",
            effect: .reversibleWrite,
            assistantTurnID: "run-1:turn:0",
            summary: summary,
            detail: detail,
            confirmation: .notRequired,
            status: status,
            startedAt: Date(),
            finishedAt: Date()
        ))
    }

    private func toolSurface(_ store: FamiliarSurfaceStore) -> [FamiliarSurfaceDescriptor] {
        store.orderedSurfaces.filter { $0.kind == .toolActivity }
    }

    @Test("One tool keeps a single stable surface id across its whole lifecycle")
    func stableIdentity() {
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runStarted))
        store.apply(event(1, .toolRequested(id: "call-1", name: "web_search", effect: .reversibleWrite)))
        store.apply(event(2, progress("call-1", state: .running)))
        store.apply(event(3, approval(toolCallID: "call-1")))
        let requestID = store.orderedSurfaces.first { $0.kind == .toolActivity }?.approvalRequestID
        #expect(requestID != nil)
        store.apply(event(4, .approvalResolved(requestID: requestID!, decision: .confirmed)))
        store.apply(event(5, progress("call-1", state: .succeeded)))
        store.apply(event(6, terminal(status: .succeeded)))

        let tools = toolSurface(store)
        #expect(tools.count == 1)
        #expect(tools[0].id == "tool:run-1:call-1")
        #expect(tools[0].phase == .succeeded)
    }

    @Test("Terminal state is not overwritten by a stale event")
    func terminalNotOverwrittenByStaleEvent() {
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runStarted))
        store.apply(event(1, .toolRequested(id: "call-1", name: "web_search", effect: .reversibleWrite)))
        store.apply(event(2, terminal(status: .succeeded)))

        #expect(toolSurface(store)[0].phase == .succeeded)

        store.apply(event(1, progress("call-1", state: .running)))
        #expect(toolSurface(store)[0].phase == .succeeded)
    }

    @Test("Approval morphs the same surface into awaiting approval then running")
    func approvalLifecycle() {
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runStarted))
        store.apply(event(1, .toolRequested(id: "call-1", name: "create_calendar_event", effect: .reversibleWrite)))
        let requestID = UUID()
        store.apply(event(2, approval(requestID: requestID)))

        var tool = toolSurface(store)[0]
        #expect(tool.phase == .awaitingApproval)
        #expect(tool.approvalRequestID == requestID)
        #expect(tool.effect == .reversibleWrite)
        #expect(tool.fields.map(\.label) == ["title"])
        #expect(store.pendingApprovalIDs == [requestID])

        store.apply(event(3, .approvalResolved(requestID: requestID, decision: .confirmed)))
        tool = toolSurface(store)[0]
        #expect(tool.phase == .running)
        #expect(tool.approvalRequestID == nil)
        #expect(tool.fields.isEmpty)
        #expect(store.pendingApprovalIDs.isEmpty)
    }

    @Test("Rejecting approval cancels the surface")
    func approvalRejected() {
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runStarted))
        store.apply(event(1, .toolRequested(id: "call-1", name: "create_calendar_event", effect: .reversibleWrite)))
        let requestID = UUID()
        store.apply(event(2, approval(requestID: requestID)))
        store.apply(event(3, .approvalResolved(requestID: requestID, decision: .cancelled)))
        #expect(toolSurface(store)[0].phase == .cancelled)
    }

    @Test("Distinct tools produce distinct ordered surfaces")
    func multipleTools() {
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runStarted))
        store.apply(event(1, .toolRequested(id: "call-1", name: "web_search", effect: .reversibleWrite)))
        store.apply(event(2, .toolRequested(id: "call-2", name: "web_fetch", effect: .reversibleWrite)))
        store.apply(event(3, terminal(toolCallID: "call-1", status: .succeeded)))
        store.apply(event(4, terminal(toolCallID: "call-2", status: .failed)))

        let tools = toolSurface(store)
        #expect(tools.count == 2)
        #expect(tools[0].id == "tool:run-1:call-1")
        #expect(tools[1].id == "tool:run-1:call-2")
        #expect(tools[0].phase == .succeeded)
        #expect(tools[1].phase == .failed)
    }

    @Test("Run failure marks the agent surface failed with a detail")
    func runFailure() {
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runStarted))
        store.apply(event(1, .runFailed("network unreachable")))
        let agent = store.agentSurface
        #expect(agent?.phase == .failed)
        #expect(agent?.detail == "network unreachable")
    }

    @Test("Run cancellation cancels non-terminal tools")
    func runCancellation() {
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runStarted))
        store.apply(event(1, .toolRequested(id: "call-1", name: "web_search", effect: .reversibleWrite)))
        store.apply(event(2, progress("call-1", state: .running)))
        store.apply(event(3, .runCancelled))

        #expect(store.agentSurface?.phase == .cancelled)
        #expect(toolSurface(store)[0].phase == .cancelled)
    }

    @Test("Reset clears every surface")
    func reset() {
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runStarted))
        store.apply(event(1, .toolRequested(id: "call-1", name: "web_search", effect: .reversibleWrite)))
        store.reset()
        #expect(store.orderedSurfaces.isEmpty)
        #expect(store.agentSurface == nil)
        #expect(!store.isActive)
    }

    @Test("Haptic policy only fires on meaningful boundaries")
    func hapticPolicy() {
        #expect(FamiliarHapticPolicy.feedback(from: .running, to: .awaitingApproval) == .warning)
        #expect(FamiliarHapticPolicy.feedback(from: .running, to: .succeeded) == .success)
        #expect(FamiliarHapticPolicy.feedback(from: .running, to: .failed) == .error)
        #expect(FamiliarHapticPolicy.feedback(from: .queued, to: .running) == nil)
        #expect(FamiliarHapticPolicy.feedback(from: .running, to: .running) == nil)
        #expect(FamiliarHapticPolicy.feedback(from: .running, to: .cancelled) == nil)
    }

    @Test("A finished tool carries its artifact descriptor onto the surface")
    func artifactPropagation() {
        let artifact = FamiliarArtifactDescriptor(
            id: UUID(),
            identifier: "artifact_test",
            projectID: UUID(),
            title: "复习总结",
            format: .markdown,
            relativePath: "Projects/test/Artifacts/test/summary.md",
            byteSize: 128,
            contentHash: "abc",
            source: .generated,
            sourceURLString: nil,
            sourceResourceID: nil,
            sourceResourceVersionID: nil,
            sourceCaptureID: nil,
            createdByRunID: "run-1"
        )
        let terminalEvent = FamiliarToolRunTerminalEvent(
            runID: "run-1",
            toolCallID: "call-1",
            toolName: "artifact_write",
            effect: .reversibleWrite,
            assistantTurnID: "run-1:turn:0",
            summary: "写入 Artifact",
            detail: "已写入 复习总结",
            confirmation: .confirmed,
            status: .succeeded,
            startedAt: Date(),
            finishedAt: Date(),
            artifact: artifact
        )

        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runStarted))
        store.apply(event(1, .toolRequested(id: "call-1", name: "artifact_write", effect: .reversibleWrite)))
        store.apply(event(2, .toolFinished(terminalEvent)))

        let tool = toolSurface(store)[0]
        #expect(tool.phase == .succeeded)
        #expect(tool.artifact?.identifier == "artifact_test")
        #expect(tool.artifact?.title == "复习总结")
    }

    @Test("Read tools stay in the agent status row instead of creating cards")
    func readToolHasNoCard() {
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runStarted))
        store.apply(event(1, .toolRequested(id: "read-1", name: "web_search", effect: .read)))
        store.apply(event(2, .toolProgress(.init(id: "read-1", toolName: "web_search", title: "Web 搜索", detail: nil, state: .running, effect: .read))))
        #expect(store.toolSurfaces.isEmpty)
        #expect(store.agentSurface?.title.contains("Web 搜索") == true)
    }
}
