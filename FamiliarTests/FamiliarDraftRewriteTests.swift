import Foundation
import Testing
@testable import Familiar

@Suite("AI draft editing")
struct FamiliarDraftRewriteTests {
    @Test("Rewrite sends only the draft and explicit instruction, with no tools")
    @MainActor func isolatedRequest() async throws {
        let capture = RewriteCapture()
        let result = try await FamiliarDraftRewriteService.generate(text: "Original draft", operation: .correct,
            model: .init(providerID: "group", modelID: "group"), maximumInputCharacters: 10_000,
            provider: RewriteProvider(capture: capture), onText: { _ in })
        let request = try #require(await capture.request)
        #expect(request.messages.count == 2)
        #expect(request.messages[1].networkText == "Original draft")
        #expect(request.tools.isEmpty)
        #expect(result.text == "Edited draft")
        #expect(result.model == .init(providerID: "actual", modelID: "actual-model"))
        #expect(result.usage?.outputTokens == 3)
    }

    @Test("Truncated replies and tool calls can never become applicable results")
    @MainActor func incompleteReplies() async {
        for mode in [RewriteProvider.Mode.truncated, .toolCall, .missingTerminal] {
            do {
                _ = try await FamiliarDraftRewriteService.generate(text: "Draft", operation: .style(instruction: "Concise"),
                    model: .init(providerID: "fake", modelID: "fake"), maximumInputCharacters: 10_000,
                    provider: RewriteProvider(capture: RewriteCapture(), mode: mode), onText: { _ in })
                Issue.record("Incomplete response was accepted")
            } catch { #expect(error is FamiliarDraftRewriteError) }
        }
    }

    @Test("Oversized drafts fail before calling the provider")
    @MainActor func inputLimit() async {
        let capture = RewriteCapture()
        do {
            _ = try await FamiliarDraftRewriteService.generate(text: "Too long", operation: .correct,
                model: .init(providerID: "fake", modelID: "fake"), maximumInputCharacters: 1,
                provider: RewriteProvider(capture: capture), onText: { _ in })
            Issue.record("Oversized draft was accepted")
        } catch { #expect(await capture.request == nil) }
    }

    @Test("Apply rejects a stale draft and supports reversible application without sending")
    @MainActor func applyAndUndo() throws {
        let controller = FamiliarChatController(dependencies: .init())
        let result = FamiliarDraftRewriteResult(text: "Edited", model: .init(providerID: "fake", modelID: "fake"), usage: nil)
        controller.draft = "Original"
        let id = controller.draftConversationID, skill = UUID()
        controller.selectedSkillID = skill
        try controller.applyDraftRewrite(result, source: "Original", sourceID: id, selection: nil)
        #expect(controller.draft == "Edited")
        #expect(controller.selectedSkillID == skill)
        #expect(controller.messages.isEmpty)
        #expect(!controller.isSending)
        controller.undoDraftRewrite()
        #expect(controller.draft == "Original")
        controller.draft = "Changed while editing"
        #expect(throws: FamiliarDraftRewriteError.self) {
            try controller.applyDraftRewrite(result, source: "Original", sourceID: id, selection: nil)
        }
        #expect(controller.draft == "Changed while editing")
    }
}

private actor RewriteCapture {
    var request: FamiliarModelRequest?
    func record(_ request: FamiliarModelRequest) { self.request = request }
}

private nonisolated struct RewriteProvider: FamiliarModelProvider {
    enum Mode: Sendable { case valid, truncated, toolCall, missingTerminal }
    let providerID = "fake"
    let capture: RewriteCapture
    var mode: Mode = .valid
    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await capture.record(request)
                continuation.yield(.providerSelection(providerID: "actual", modelID: "actual-model"))
                continuation.yield(.textDelta("Edited draft"))
                continuation.yield(.usage(.init(inputTokens: 2, outputTokens: 3, cachedInputTokens: nil)))
                switch mode {
                case .valid: continuation.yield(.completed(.stop))
                case .truncated: continuation.yield(.completed(.length))
                case .toolCall: continuation.yield(.toolCallDelta(index: 0, id: "call", name: "file_write", arguments: "{}"))
                case .missingTerminal: break
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
