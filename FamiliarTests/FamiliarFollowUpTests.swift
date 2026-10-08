import Foundation
import Testing
@testable import Familiar

private actor FollowUpRequestProbe {
    private var request: FamiliarModelRequest?
    func record(_ value: FamiliarModelRequest) { request = value }
    func snapshot() -> FamiliarModelRequest? { request }
}
private nonisolated struct FollowUpFixtureProvider: FamiliarModelProvider {
    let providerID = "actual-leaf"
    let output: String
    let probe: FollowUpRequestProbe
    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await probe.record(request)
                do {
                    try Task.checkCancellation()
                    if output == "wait" { try await Task.sleep(for: .seconds(60)) }
                    continuation.yield(.providerSelection(providerID: providerID, modelID: request.model))
                    continuation.yield(.textDelta(output))
                    continuation.yield(.usage(.init(inputTokens: 12, outputTokens: 8, cachedInputTokens: nil)))
                    continuation.yield(.completed(.stop)); continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@Suite("Contentual follow-up suggestions")
struct FamiliarFollowUpTests {
    @Test("Suggestions use only the supplied turn, actual model, no tools and a small output budget")
    func groundedRequest() async throws {
        let probe = FollowUpRequestProbe()
        let provider = FollowUpFixtureProvider(output: #"["Which Swift actor should own this state?","How can I test cancellation of this actor?"]"#, probe: probe)
        let model = FamiliarModelReference(providerID: "actual-leaf", modelID: "leaf-model")
        let result = try await FamiliarFollowUpService.generate(question: "How do Swift actors isolate state?",
            answer: "Swift actors isolate mutable state. Cancellation needs explicit checks.", model: model, provider: provider)
        let request = try #require(await probe.snapshot())
        #expect(request.model == model.modelID)
        #expect(request.tools.isEmpty)
        #expect(request.maximumOutputTokens == 512)
        #expect(request.messages.count == 2)
        #expect(request.messages.last?.networkText?.contains("Swift actors isolate mutable state") == true)
        #expect(result.state == .ready)
        #expect(result.questions.count == 2)
        #expect(result.model == model)
        #expect(result.usage?.outputTokens == 8)
    }
    @Test("Malformed output has no generic fallback; valid questions are deduplicated and bounded")
    func invalidAndBounded() async throws {
        let model = FamiliarModelReference(providerID: "actual-leaf", modelID: "leaf-model")
        let result = try await FamiliarFollowUpService.generate(question: "Weather?", answer: "Weather evidence.",
            model: model, provider: FollowUpFixtureProvider(output: "Not JSON", probe: .init()))
        #expect(result.state == .failed)
        #expect(result.questions.isEmpty)
        #expect(result.usage?.inputTokens == 12)
        let parsed = try FamiliarFollowUpSuggestions.parse(#"["  Question?  ","QUESTION?","","One?","Two?","Three?"]"#)
        #expect(parsed == ["Question?", "One?", "Two?"])
        #expect(FamiliarFollowUpSuggestions.read(#"{"format":"markdown"}"#) == nil)
    }
    @Test("Supplement persists separately from response text and reported primary usage")
    func payloadRoundtrip() throws {
        let model = FamiliarModelReference(providerID: "leaf", modelID: "model")
        let result = FamiliarFollowUpSuggestions(state: .ready, questions: ["Which source backs the forecast?"],
            model: model, answerHash: FamiliarHash.sha256("Weather answer"), usage: .init(inputTokens: 20, outputTokens: 10, cachedInputTokens: nil))
        let encoded = try result.adding(to: #"{"format":"markdown","existing":"preserve"}"#)
        #expect(FamiliarFollowUpSuggestions.read(encoded) == result)
        #expect(encoded.contains("preserve"))
        #expect(result.usage?.cachedInputTokens == nil)
    }
    @Test("Cancelling an optional suggestion request does not leave an active generation")
    func cancellation() async throws {
        let task = Task {
            try await FamiliarFollowUpService.generate(question: "A", answer: "B",
                model: .init(providerID: "actual-leaf", modelID: "model"),
                provider: FollowUpFixtureProvider(output: "wait", probe: .init()))
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
