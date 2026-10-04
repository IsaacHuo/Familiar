import Foundation
import Observation
import Testing
@testable import Familiar

@Suite("Streaming observation boundaries")
struct FamiliarStreamingObservationTests {
    @Test("Token and reasoning mutations notify live readers without invalidating history inputs")
    @MainActor
    func liveAndHistoryReaders() {
        let controller = FamiliarChatController(dependencies: .init())
        controller.isSending = true
        let history = FamiliarObservationFlag()
        withObservationTracking {
            _ = controller.messages
            _ = controller.modelSwitches
            _ = controller.agentRuns
            _ = controller.isSending
            _ = controller.settings
        } onChange: { history.mark() }
        let live = FamiliarObservationFlag()
        withObservationTracking {
            _ = controller.streamingResponseBlocks
            _ = controller.streamingReasoningSummary
        } onChange: { live.mark() }
        controller.streamingResponseBlocks.append(.init(assistantTurnID: "run:turn:0", order: 0, startedAt: Date(), content: "First token"))
        controller.streamingReasoningSummary += "Reasoning"
        #expect(live.isMarked)
        #expect(!history.isMarked)
        controller.messages = [.init(id: UUID(), role: .user, content: "New checkpoint", createdAt: Date(), sequence: 0,
            providerID: nil, modelID: nil, attachments: [])]
        #expect(history.isMarked)
    }

    @Test("Non-surface stream events preserve projection while actual activity remains visible")
    func surfaceEventBoundary() {
        var store = FamiliarSurfaceStore()
        store.apply(.init(runID: "run", sequence: 0, timestamp: Date(), assistantTurnID: nil, payload: .runPhaseChanged(.starting)))
        let before = store.orderedSurfaces
        let deltas: [FamiliarRuntimeEventPayload] = [.responseTextDelta("Token"), .reasoningSummaryDelta("Reason"),
            .usage(.init(inputTokens: 1, outputTokens: 2, cachedInputTokens: nil)),
            .modelSelected(.init(providerID: "provider", modelID: "model"))]
        for (index, payload) in deltas.enumerated() {
            #expect(!FamiliarSurfaceStore.affectsPresentation(payload))
            store.apply(.init(runID: "run", sequence: index + 1, timestamp: Date(), assistantTurnID: "run:turn:0", payload: payload))
        }
        #expect(store.orderedSurfaces == before)
        let activity = FamiliarRuntimeActivity(id: "call", toolName: "web_fetch", effect: .read, startedAt: Date())
        #expect(FamiliarSurfaceStore.affectsPresentation(.activityStarted(activity)))
        store.apply(.init(runID: "run", sequence: 5, timestamp: Date(), assistantTurnID: "run:turn:0", payload: .activityStarted(activity)))
        #expect(store.orderedSurfaces.contains { $0.toolCallID == "call" })
    }
}

private final class FamiliarObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false
    func mark() { lock.withLock { marked = true } }
    var isMarked: Bool { lock.withLock { marked } }
}
