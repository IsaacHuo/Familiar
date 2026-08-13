import Foundation
import Testing
@testable import Familiar

private struct FamiliarFakeProvider: FamiliarModelProvider {
    let providerID = "fake"
    let mode: Mode
    enum Mode: Sendable { case text, toolThenText, repeatedTool }

    func stream(request: FamiliarModelRequest, apiKey: String) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let hasToolResult = request.messages.contains { $0.role == .tool }
            switch mode {
            case .text:
                continuation.yield(.textDelta("Hello"))
                continuation.yield(.completed(.stop))
            case .toolThenText where hasToolResult:
                continuation.yield(.textDelta("Done"))
                continuation.yield(.completed(.stop))
            case .toolThenText, .repeatedTool:
                continuation.yield(.toolCallDelta(index: 0, id: "call", name: "fake_read", arguments: "{}"))
                continuation.yield(.completed(.toolCalls))
            }
            continuation.finish()
        }
    }
}

private struct FamiliarFakeTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    let manifest = FamiliarToolManifest(name: "fake_read", title: "Fake read", description: "Reads a fixture", parameters: .init(type: .object), effect: .read, risk: .low, requirements: [])
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        .result(.init(modelContent: #"{"ok":true}"#, displayContent: "OK"))
    }
}

@Suite("Familiar runtime")
struct FamiliarRuntimeTests {
    @Test("Runtime events have one run ID and strictly increasing sequence")
    func orderedEvents() async throws {
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarFakeTool())])
        let loop = FamiliarAgentLoop(provider: FamiliarFakeProvider(mode: .toolThenText), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init())
        var events: [FamiliarRuntimeEvent] = []
        for try await event in loop.stream(messages: [], settings: .defaultValue, apiKey: "key") { events.append(event) }
        #expect(Set(events.map(\.runID)).count == 1)
        #expect(events.map(\.sequence) == Array(0..<events.count))
        if case .runStarted = events.first?.payload {} else { Issue.record("Missing runStarted") }
        if case .runCompleted = events.last?.payload {} else { Issue.record("Missing runCompleted") }
        #expect(events.contains { if case .toolFinished = $0.payload { true } else { false } })
    }

    @Test("Runtime fails after the configured maximum rounds")
    func maximumIterations() async throws {
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarFakeTool())])
        let loop = FamiliarAgentLoop(provider: FamiliarFakeProvider(mode: .repeatedTool), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init(), maximumIterations: 2)
        var failed = false
        do {
            for try await event in loop.stream(messages: [], settings: .defaultValue, apiKey: "key") {
                if case .runFailed = event.payload { failed = true }
            }
        } catch FamiliarAgentError.maxIterationsExceeded {
            failed = true
        }
        #expect(failed)
    }

    @Test("Runtime enters responding on the first text delta")
    func respondingState() async throws {
        let registry = try FamiliarToolRegistry(tools: [])
        let loop = FamiliarAgentLoop(provider: FamiliarFakeProvider(mode: .text), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init())
        var payloads: [FamiliarRuntimeEventPayload] = []
        for try await event in loop.stream(messages: [], settings: .defaultValue, apiKey: "key") {
            payloads.append(event.payload)
        }
        let responding = payloads.firstIndex { if case .state(.responding) = $0 { true } else { false } }
        let delta = payloads.firstIndex { if case .textDelta = $0 { true } else { false } }
        #expect(responding != nil)
        #expect(delta != nil)
        #expect(responding! < delta!)
    }

    @Test("Runtime rejects oversized context before provider execution")
    func contextLimit() async throws {
        let registry = try FamiliarToolRegistry(tools: [])
        let loop = FamiliarAgentLoop(provider: FamiliarFakeProvider(mode: .text), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init())
        let message = FamiliarMessageSnapshot(id: UUID(), role: .user, content: String(repeating: "x", count: 400_000), createdAt: Date(), sequence: 0, providerID: nil, modelID: nil, attachments: [])
        await #expect(throws: FamiliarAgentError.self) {
            for try await _ in loop.stream(messages: [message], settings: .defaultValue, apiKey: "key") {}
        }
    }
}
