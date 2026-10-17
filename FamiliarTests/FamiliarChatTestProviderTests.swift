#if DEBUG && targetEnvironment(simulator)
import Testing
@testable import Familiar

@Suite("Deterministic Chat test provider")
struct FamiliarChatTestProviderTests {
    @Test("Catalog notices after an answered question cannot start an unrelated file workflow")
    func answeredQuestionKeepsOriginalTask() async throws {
        let response = try await FamiliarChatTestProvider().generate(request: .init(model: "test", messages: [
            .user("question"),
            .tool(#"{"answer":"Short version"}"#, toolCallID: "presentation-question", name: "ask_user"),
            .user("Loaded tools: files")
        ], tools: []))
        #expect(response.toolCalls.isEmpty)
        #expect(response.text.contains("Reply complete."))
    }
    @Test("Tool-result pairing completes the fixture even when optional tool names are omitted")
    func toolResultPairing() async throws {
        let provider = FamiliarChatTestProvider()
        let read = FamiliarChatTestReadTool()
        let first = try await provider.generate(request: .init(model: "test", messages: [.user("tools")], tools: [read.manifest]))
        #expect(first.toolCalls.count == 3)
        #expect(first.toolCalls.first?.arguments == #"{"identifier":"file_fixture_0"}"#)
        let results = first.toolCalls.map { call in
            FamiliarProviderMessage(role: .tool, contentParts: [.text("{}")], toolCallID: call.id)
        }
        let final = try await provider.generate(request: .init(model: "test", messages: [.user("tools")] + results, tools: [read.manifest]))
        #expect(final.toolCalls.isEmpty)
        #expect(final.text.contains("Reply complete."))
    }
}
#endif
