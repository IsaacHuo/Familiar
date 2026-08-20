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

private actor FamiliarAttemptCounter {
    private var value = 0
    func next() -> Int { value += 1; return value }
}

private struct FamiliarFlakyProvider: FamiliarModelProvider {
    let providerID = "fake"
    let counter: FamiliarAttemptCounter

    func stream(request: FamiliarModelRequest, apiKey: String) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let attempt = await counter.next()
                if attempt == 1 {
                    continuation.finish(throwing: FamiliarProviderRequestError.server(provider: "fake", statusCode: 500, message: "transient"))
                } else {
                    continuation.yield(.textDelta("Recovered"))
                    continuation.yield(.completed(.stop))
                    continuation.finish()
                }
            }
        }
    }
}

private struct FamiliarCountingTool: FamiliarTool {
    struct Input: Decodable, Sendable { let n: Int }
    let manifest = FamiliarToolManifest(name: "fake_count", title: "Fake count", description: "Counts", parameters: .init(type: .object), effect: .read, risk: .low, requirements: [])
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        .result(.init(modelContent: #"{"ok":true}"#, displayContent: "OK"))
    }
}

private struct FamiliarBudgetProvider: FamiliarModelProvider {
    let providerID = "fake"

    func stream(request: FamiliarModelRequest, apiKey: String) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let toolCount = request.messages.filter { $0.role == .tool }.count
            let arguments = #"{"n":\#(toolCount)}"#
            continuation.yield(.toolCallDelta(index: 0, id: "call-\(toolCount)", name: "fake_count", arguments: arguments))
            continuation.yield(.completed(.toolCalls))
            continuation.finish()
        }
    }
}

@Suite("Familiar runtime")
struct FamiliarRuntimeTests {
    @Test("Runtime events have one run ID and strictly increasing sequence")
    func orderedEvents() async throws {
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarFakeTool())])
        let loop = FamiliarAgentLoop(provider: FamiliarFakeProvider(mode: .toolThenText), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init())
        var events: [FamiliarRuntimeEvent] = []
        let snapshot = try familiarTestContextSnapshot(manifests: await registry.manifests())
        for try await event in loop.stream(contextSnapshot: snapshot, apiKey: "key") { events.append(event) }
        #expect(Set(events.map(\.runID)).count == 1)
        #expect(events.map(\.sequence) == Array(0..<events.count))
        if case .runStarted = events.first?.payload {} else { Issue.record("Missing runStarted") }
        if case .runCompleted = events.last?.payload {} else { Issue.record("Missing runCompleted") }
        #expect(events.contains { if case .toolFinished = $0.payload { true } else { false } })
        #expect(events.contains {
            if case .toolInvocationRequested(let id, let name, let arguments, _) = $0.payload {
                return id == "call" && name == "fake_read" && arguments == "{}"
            }
            return false
        })
    }

    @Test("Runtime fails after the configured maximum rounds")
    func maximumIterations() async throws {
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarFakeTool())])
        let loop = FamiliarAgentLoop(provider: FamiliarFakeProvider(mode: .repeatedTool), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init(), maximumIterations: 2)
        var failed = false
        do {
            let snapshot = try familiarTestContextSnapshot(manifests: await registry.manifests())
            for try await event in loop.stream(contextSnapshot: snapshot, apiKey: "key") {
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
        let snapshot = try familiarTestContextSnapshot()
        for try await event in loop.stream(contextSnapshot: snapshot, apiKey: "key") {
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
        let message = FamiliarMessageSnapshot(id: UUID(), role: .user, content: String(repeating: "x", count: 400_000), createdAt: Date(), sequence: 0, providerID: nil, modelID: nil, attachments: [])
        #expect(throws: FamiliarAgentError.self) {
            _ = try familiarTestContextSnapshot(messages: [message])
        }
    }

    @Test("Transient provider failures retry before any content is emitted")
    func transientRetry() async throws {
        let registry = try FamiliarToolRegistry(tools: [])
        let loop = FamiliarAgentLoop(
            provider: FamiliarFlakyProvider(counter: FamiliarAttemptCounter()),
            registry: registry,
            policy: .init(),
            confirmationCoordinator: .init(),
            undoStore: .init()
        )
        var text = ""
        let snapshot = try familiarTestContextSnapshot()
        for try await event in loop.stream(contextSnapshot: snapshot, apiKey: "key") {
            if case .textDelta(let delta) = event.payload { text += delta }
        }
        #expect(text == "Recovered")
    }

    @Test("Provider failures classify into retryable and non-retryable kinds")
    func failureClassification() {
        let rateLimited = FamiliarRuntimeFailure.kind(for: FamiliarProviderRequestError.server(provider: "x", statusCode: 429, message: ""))
        let server = FamiliarRuntimeFailure.kind(for: FamiliarProviderRequestError.server(provider: "x", statusCode: 500, message: ""))
        let auth = FamiliarRuntimeFailure.kind(for: FamiliarProviderRequestError.server(provider: "x", statusCode: 401, message: ""))
        #expect(rateLimited == .rateLimited)
        #expect(server == .transientServer)
        #expect(auth == .authentication)
        #expect(rateLimited.isRetryable)
        #expect(server.isRetryable)
        #expect(!auth.isRetryable)
        #expect(FamiliarRuntimeFailure.kind(for: FamiliarAgentError.contextTooLarge) == .contextTooLarge)
        #expect(!FamiliarRuntimeFailure.kind(for: FamiliarAgentError.contextTooLarge).isRetryable)
        #expect(FamiliarRuntimeFailure.kind(for: URLError(.timedOut)) == .network)
        #expect(FamiliarRuntimeFailure.kind(for: CancellationError()) == .cancelled)
    }

    @Test("A run stops after the configured tool-call budget")
    func toolCallBudget() async throws {
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarCountingTool())])
        let loop = FamiliarAgentLoop(
            provider: FamiliarBudgetProvider(),
            registry: registry,
            policy: .init(),
            confirmationCoordinator: .init(),
            undoStore: .init(),
            maximumToolCalls: 1
        )
        var failed = false
        do {
            let snapshot = try familiarTestContextSnapshot(manifests: await registry.manifests())
            for try await event in loop.stream(contextSnapshot: snapshot, apiKey: "key") {
                if case .runFailed = event.payload { failed = true }
            }
        } catch FamiliarAgentError.maxToolCallsExceeded {
            failed = true
        }
        #expect(failed)
    }
}
