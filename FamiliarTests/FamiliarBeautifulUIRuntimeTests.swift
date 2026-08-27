import Foundation
import Testing
@testable import Familiar

private struct FamiliarClarificationProvider: FamiliarModelProvider {
    let providerID = "clarification-fixture"

    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            if request.messages.contains(where: { $0.role == .tool }) {
                continuation.yield(.textDelta("Resolved"))
                continuation.yield(.completed(.stop))
            } else {
                continuation.yield(.toolCallDelta(index: 0, id: "question-1", name: "ask_user", arguments: #"{"allowCustom":true,"options":[{"id":"swift","label":"Swift"},{"id":"web","label":"Web"}],"question":"Which platform?"}"#))
                continuation.yield(.completed(.toolCalls))
            }
            continuation.finish()
        }
    }
}

private struct FamiliarRecommendationProvider: FamiliarModelProvider {
    let providerID = "recommendation-fixture"

    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            if request.messages.contains(where: { $0.role == .tool }) {
                continuation.yield(.textDelta("Choose when ready."))
                continuation.yield(.completed(.stop))
            } else {
                continuation.yield(.toolCallDelta(index: 0, id: "recommendation-1", name: "present_recommendation", arguments: #"{"alternatives":[],"confidenceLevel":"high","explanation":"Verify first.","nextPrompt":"Verify the build","title":"Next step"}"#))
                continuation.yield(.completed(.toolCalls))
            }
            continuation.finish()
        }
    }
}

@Suite("Beautiful UI runtime flows")
struct FamiliarBeautifulUIRuntimeTests {
    @Test("Recommendation is read-only and never requests authorization")
    func recommendationDoesNotAuthorize() async throws {
        let tool = FamiliarPresentRecommendationTool()
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(tool)])
        let loop = FamiliarAgentLoop(provider: FamiliarRecommendationProvider(), registry: registry, policy: .init(), confirmationCoordinator: .init(), undoStore: .init())

        let events = try await collect(loop, manifests: await registry.manifests())

        #expect(tool.manifest.effect == .read)
        #expect(!events.contains { if case .approvalRequested = $0.payload { true } else { false } })
        #expect(events.contains { event in
            guard case .toolResultProduced(let result) = event.payload else { return false }
            return result.envelope.presentation.name == .recommendation
        })
    }

    @Test("Clarification pauses and resumes the same run")
    func clarificationResume() async throws {
        let coordinator = FamiliarClarificationCoordinator()
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarAskUserTool())])
        let loop = FamiliarAgentLoop(provider: FamiliarClarificationProvider(), registry: registry, policy: .init(), confirmationCoordinator: .init(), clarificationCoordinator: coordinator, undoStore: .init())
        let snapshot = try familiarTestContextSnapshot(manifests: await registry.manifests())
        let collector = Task {
            var events: [FamiliarRuntimeEvent] = []
            for try await event in loop.stream(contextSnapshot: snapshot) { events.append(event) }
            return events
        }

        let request = try await pendingRequest(in: coordinator)
        #expect(request.question == "Which platform?")
        #expect(request.options.map(\.id) == ["swift", "web"])
        _ = await coordinator.resolve(requestID: request.id, resolution: .selectedOption(id: "swift", label: "Swift"))
        let events = try await collector.value

        #expect(events.contains { if case .clarificationRequested = $0.payload { true } else { false } })
        #expect(events.contains { if case .clarificationResolved(_, .selectedOption(id: "swift", label: "Swift")) = $0.payload { true } else { false } })
        #expect(events.contains { if case .responseCompleted(let response) = $0.payload { response.text == "Resolved" } else { false } })
        #expect(events.contains { if case .runFinished(.succeeded) = $0.payload { true } else { false } })
    }

    @Test("Cancelling a run cancels its pending clarification")
    func clarificationCancellation() async throws {
        let coordinator = FamiliarClarificationCoordinator()
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarAskUserTool())])
        let loop = FamiliarAgentLoop(provider: FamiliarClarificationProvider(), registry: registry, policy: .init(), confirmationCoordinator: .init(), clarificationCoordinator: coordinator, undoStore: .init())
        let snapshot = try familiarTestContextSnapshot(manifests: await registry.manifests())
        let collector = Task {
            for try await _ in loop.stream(contextSnapshot: snapshot) {}
        }

        _ = try await pendingRequest(in: coordinator)
        collector.cancel()
        _ = await collector.result

        #expect(await coordinator.pendingRequests().isEmpty)
    }

    private func collect(_ loop: FamiliarAgentLoop, manifests: [FamiliarToolManifest]) async throws -> [FamiliarRuntimeEvent] {
        let snapshot = try familiarTestContextSnapshot(manifests: manifests)
        var events: [FamiliarRuntimeEvent] = []
        for try await event in loop.stream(contextSnapshot: snapshot) { events.append(event) }
        return events
    }

    private func pendingRequest(in coordinator: FamiliarClarificationCoordinator) async throws -> FamiliarClarificationRequest {
        for _ in 0..<100 {
            if let request = await coordinator.pendingRequests().first { return request }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CancellationError()
    }
}
