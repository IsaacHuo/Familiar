import Foundation
import Testing
@testable import Familiar

private struct FamiliarFakeProvider: FamiliarModelProvider {
    let providerID = "fake"
    let mode: Mode
    enum Mode: Sendable { case text, reasoning, toolThenText, repeatedTool }

    func stream(request: FamiliarModelRequest, apiKey: String) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let toolCount = request.messages.filter { $0.role == .tool }.count
            switch mode {
            case .text:
                continuation.yield(.textDelta("Hello"))
                continuation.yield(.completed(.stop))
            case .reasoning:
                continuation.yield(.reasoningSummaryDelta("Checked the fixture."))
                continuation.yield(.textDelta("Answer"))
                continuation.yield(.completed(.stop))
            case .toolThenText where toolCount > 0:
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
    let manifest = FamiliarToolManifest(name: "fake_read", title: "Fake read", description: "Reads a fixture", parameters: .init(type: .object), effect: .read, risk: .low, requirements: [], supportsParallelism: true)
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        .result(.init(envelope: try .init(canonicalModelJSON: #"{"ok":true}"#, presentation: .scalar(.init(summary: "OK", value: "true")))))
    }
}

private actor FamiliarAttemptCounter {
    private var value = 0
    func next() -> Int { value += 1; return value }
    func count() -> Int { value }
}

private struct FamiliarFlakyProvider: FamiliarModelProvider {
    let providerID = "fake"
    let counter: FamiliarAttemptCounter

    func stream(request: FamiliarModelRequest, apiKey: String) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                if await counter.next() == 1 {
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

private struct FamiliarHangingProvider: FamiliarModelProvider {
    let providerID = "fake"
    func stream(request: FamiliarModelRequest, apiKey: String) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                try await Task.sleep(for: .seconds(10))
                continuation.yield(.textDelta("late"))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private actor FamiliarConcurrencyProbe {
    private var active = 0
    private var maximum = 0
    func begin() { active += 1; maximum = max(maximum, active) }
    func end() { active -= 1 }
    func maximumObserved() -> Int { maximum }
}

private actor FamiliarToolResultOrderRecorder {
    private var values: [String] = []
    func record(_ resultValues: [String]) { values = resultValues }
    func snapshot() -> [String] { values }
}

private struct FamiliarParallelProvider: FamiliarModelProvider {
    let providerID = "fake"
    let recorder: FamiliarToolResultOrderRecorder
    func stream(request: FamiliarModelRequest, apiKey: String) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let results = request.messages.filter { $0.role == .tool }.compactMap(\.networkText)
            if results.isEmpty {
                for index in 0..<3 {
                    continuation.yield(.toolCallDelta(index: index, id: "call-\(index)", name: "fake_count", arguments: #"{"n":\#(index)}"#))
                }
                continuation.yield(.completed(.toolCalls))
                continuation.finish()
            } else {
                Task {
                    await recorder.record(results)
                    continuation.yield(.textDelta("Done"))
                    continuation.yield(.completed(.stop))
                    continuation.finish()
                }
            }
        }
    }
}

private struct FamiliarCountingTool: FamiliarTool {
    struct Input: Decodable, Sendable { let n: Int }
    let probe: FamiliarConcurrencyProbe?
    let manifest = FamiliarToolManifest(name: "fake_count", title: "Fake count", description: "Counts", parameters: .init(type: .object), effect: .read, risk: .low, requirements: [], supportsParallelism: true)
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        if let probe {
            await probe.begin()
            try await Task.sleep(for: .milliseconds(40))
            await probe.end()
        }
        return .result(.init(envelope: try .init(canonicalModelJSON: #"{"n":\#(input.n)}"#, presentation: .scalar(.init(summary: "OK", value: String(input.n))))))
    }
}

private struct FamiliarBudgetProvider: FamiliarModelProvider {
    let providerID = "fake"
    func stream(request: FamiliarModelRequest, apiKey: String) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let count = request.messages.filter { $0.role == .tool }.count
            continuation.yield(.toolCallDelta(index: 0, id: "call-\(count)", name: "fake_count", arguments: #"{"n":\#(count)}"#))
            continuation.yield(.completed(.toolCalls))
            continuation.finish()
        }
    }
}

private struct FamiliarRetryingReadTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    let counter: FamiliarAttemptCounter
    let manifest = FamiliarToolManifest(name: "fake_read", title: "Fake read", description: "Reads", parameters: .init(type: .object), effect: .read, risk: .low, requirements: [], supportsParallelism: true)
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard await counter.next() > 1 else { throw URLError(.timedOut) }
        return .result(.init(envelope: try .init(canonicalModelJSON: #"{"ok":true}"#, presentation: .scalar(.init(summary: "OK", value: "true")))))
    }
}

@Suite("Familiar runtime")
struct FamiliarRuntimeTests {
    @Test("Runtime emits one typed finish event with contiguous sequence")
    func orderedEvents() async throws {
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarFakeTool())])
        let events = try await collect(FamiliarAgentLoop(provider: FamiliarFakeProvider(mode: .toolThenText), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init()), manifests: await registry.manifests())
        #expect(Set(events.map(\.runID)).count == 1)
        #expect(events.map(\.sequence) == Array(0..<events.count))
        if case .runPhaseChanged(.starting) = events.first?.payload {} else { Issue.record("Missing initial run phase") }
        let finishes = events.compactMap { if case .runFinished(let outcome) = $0.payload { outcome } else { nil } }
        #expect(finishes == [.succeeded])
        #expect(events.contains { if case .activityCompleted = $0.payload { true } else { false } })
        #expect(events.contains { if case .toolResultProduced = $0.payload { true } else { false } })
    }

    @Test("Runtime failure still emits exactly one runFinished")
    func singleFailedFinish() async throws {
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarFakeTool())])
        let events = try await collect(FamiliarAgentLoop(provider: FamiliarFakeProvider(mode: .repeatedTool), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init(), maximumIterations: 2), manifests: await registry.manifests())
        let finishes = events.compactMap { if case .runFinished(let outcome) = $0.payload { outcome } else { nil } }
        #expect(finishes.count == 1)
        #expect(finishes.first?.status == .failed)
        #expect(finishes.first?.failureKind == .maxIterations)
    }

    @Test("Response phase precedes the first text delta")
    func respondingPhase() async throws {
        let registry = try FamiliarToolRegistry(tools: [])
        let events = try await collect(FamiliarAgentLoop(provider: FamiliarFakeProvider(mode: .text), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init()))
        let responding = events.firstIndex { if case .runPhaseChanged(.responding) = $0.payload { true } else { false } }
        let delta = events.firstIndex { if case .responseTextDelta = $0.payload { true } else { false } }
        #expect(responding != nil && delta != nil && responding! < delta!)
    }

    @Test("Provider reasoning summary is separate from response text")
    func reasoningSummary() async throws {
        let registry = try FamiliarToolRegistry(tools: [])
        let events = try await collect(FamiliarAgentLoop(provider: FamiliarFakeProvider(mode: .reasoning), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init()))
        let reasoning = events.compactMap { if case .reasoningSummaryDelta(let value) = $0.payload { value } else { nil } }.joined()
        let completed = events.compactMap { if case .reasoningSummaryCompleted(let value) = $0.payload { value } else { nil } }
        let response = events.compactMap { if case .responseTextDelta(let value) = $0.payload { value } else { nil } }.joined()
        #expect(reasoning == "Checked the fixture.")
        #expect(completed == [reasoning])
        #expect(response == "Answer")
    }

    @Test("Transient provider retry emits an auditable typed notice")
    func transientRetryNotice() async throws {
        let registry = try FamiliarToolRegistry(tools: [])
        let events = try await collect(FamiliarAgentLoop(provider: FamiliarFlakyProvider(counter: FamiliarAttemptCounter()), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init()))
        let notices = events.compactMap { if case .runtimeNotice(let notice) = $0.payload { notice } else { nil } }
        #expect(notices.count == 1)
        #expect(notices.first?.kind == .retrying)
        #expect(notices.first?.attempt == 2)
        #expect(notices.first?.failureKind == .transientServer)
    }

    @Test("Hard run deadline bounds a provider stream")
    func hardDeadline() async throws {
        let registry = try FamiliarToolRegistry(tools: [])
        let clock = ContinuousClock()
        let started = clock.now
        let events = try await collect(FamiliarAgentLoop(provider: FamiliarHangingProvider(), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init(), maximumAttemptsPerRound: 1, maximumDuration: 0.05))
        let elapsed = started.duration(to: clock.now)
        let finish = events.compactMap { if case .runFinished(let outcome) = $0.payload { outcome } else { nil } }.first
        #expect(finish?.failureKind == .durationExceeded)
        #expect(elapsed < .seconds(1))
    }

    @Test("Parallel read calls never exceed two and results retain call order")
    func parallelReadLimit() async throws {
        let probe = FamiliarConcurrencyProbe()
        let orderRecorder = FamiliarToolResultOrderRecorder()
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarCountingTool(probe: probe))])
        let events = try await collect(FamiliarAgentLoop(provider: FamiliarParallelProvider(recorder: orderRecorder), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init()), manifests: await registry.manifests())
        #expect(await probe.maximumObserved() == 2)
        #expect(await orderRecorder.snapshot() == [#"{"n":0}"#, #"{"n":1}"#, #"{"n":2}"#])
        let results = events.compactMap { if case .toolResultProduced(let result) = $0.payload { result.toolCallID } else { nil } }
        #expect(Set(results) == Set(["call-0", "call-1", "call-2"]))
        let completed = events.compactMap { if case .responseCompleted(let response) = $0.payload { response.text } else { nil } }
        #expect(completed.last == "Done")
    }

    @Test("A failed read execution is retried once inside Runtime")
    func readRetry() async throws {
        let counter = FamiliarAttemptCounter()
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarRetryingReadTool(counter: counter))])
        let events = try await collect(FamiliarAgentLoop(provider: FamiliarFakeProvider(mode: .toolThenText), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init()), manifests: await registry.manifests())
        #expect(await counter.count() == 2)
        #expect(events.contains { if case .runFinished(.succeeded) = $0.payload { true } else { false } })
    }

    @Test("A run stops after the configured tool-call budget")
    func toolCallBudget() async throws {
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarCountingTool(probe: nil))])
        let events = try await collect(FamiliarAgentLoop(provider: FamiliarBudgetProvider(), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init(), maximumToolCalls: 1), manifests: await registry.manifests())
        let finish = events.compactMap { if case .runFinished(let outcome) = $0.payload { outcome } else { nil } }.first
        #expect(finish?.failureKind == .maxToolCalls)
    }

    @Test("Provider failures retain typed classification")
    func failureClassification() {
        #expect(FamiliarRuntimeFailure.kind(for: FamiliarProviderRequestError.server(provider: "x", statusCode: 429, message: "")) == .rateLimited)
        #expect(FamiliarRuntimeFailure.kind(for: FamiliarProviderRequestError.server(provider: "x", statusCode: 500, message: "")) == .transientServer)
        #expect(FamiliarRuntimeFailure.kind(for: FamiliarProviderRequestError.server(provider: "x", statusCode: 401, message: "")) == .authentication)
        #expect(FamiliarRuntimeFailure.kind(for: FamiliarAgentError.contextTooLarge) == .contextTooLarge)
        #expect(FamiliarRuntimeFailure.kind(for: URLError(.timedOut)) == .network)
    }

    private func collect(_ loop: FamiliarAgentLoop, manifests: [FamiliarToolManifest] = []) async throws -> [FamiliarRuntimeEvent] {
        var events: [FamiliarRuntimeEvent] = []
        let snapshot = try familiarTestContextSnapshot(manifests: manifests)
        for try await event in loop.stream(contextSnapshot: snapshot, apiKey: "key") { events.append(event) }
        return events
    }
}
