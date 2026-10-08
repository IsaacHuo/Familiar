#if DEBUG && targetEnvironment(simulator)
import Testing
@testable import Familiar

@Suite("Deterministic Chat test provider")
struct FamiliarChatTestProviderTests {
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
