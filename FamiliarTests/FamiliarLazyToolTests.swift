import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Lazy tool exposure")
struct FamiliarLazyToolTests {
    @Test("A direct answer exposes only base tools and does not discover remote groups")
    func directAnswerIsLazy() async throws {
        let probe = FamiliarLazyProbe()
        let registry = try registry(probe: probe, names: ["web_fetch", "calendar_events", "shell_execute"])
        let source = remoteGroup(probe: probe)
        let events = try await run(registry: registry, probe: probe, steps: [.answer], sources: [source])
        let requests = await probe.requests()
        #expect(requests.count == 1)
        #expect(Set(requests[0].tools.map(\.name)) == FamiliarToolGroup.baseToolNames)
        #expect(await probe.count("discover") == 0)
        #expect(await probe.count("web_fetch") == 0)
        #expect(outcomes(events) == [.succeeded])
    }

    @Test("Loading another group replaces old schemas while tool execution stays in one Loop")
    func groupReplacement() async throws {
        let probe = FamiliarLazyProbe()
        let registry = try registry(probe: probe, names: ["web_fetch", "calendar_events"])
        let steps: [FamiliarLazyStep] = [
            .calls([call("load-web", "tools_load", #"{"groups":["web"]}"#)]),
            .calls([call("web", "web_fetch")]),
            .calls([call("load-calendar", "tools_load", #"{"groups":["calendar"]}"#)]),
            .calls([call("calendar", "calendar_events")]), .answer
        ]
        let events = try await run(registry: registry, probe: probe, steps: steps)
        let requests = await probe.requests()
        #expect(requests.count == 5)
        #expect(Set(requests[1].tools.map(\.name)) == FamiliarToolGroup.baseToolNames.union(["web_fetch"]))
        #expect(Set(requests[3].tools.map(\.name)) == FamiliarToolGroup.baseToolNames.union(["calendar_events"]))
        #expect(await probe.count("web_fetch") == 1)
        #expect(await probe.count("calendar_events") == 1)
        #expect(Set(events.map(\.runID)).count == 1)
        #expect(outcomes(events) == [.succeeded])
    }

    @Test("A guessed tool, including one batched with its loader, cannot run before exposure")
    func guessedToolCannotRun() async throws {
        let probe = FamiliarLazyProbe()
        let registry = try registry(probe: probe, names: ["web_fetch"])
        let events = try await run(registry: registry, probe: probe, steps: [
            .calls([call("load", "tools_load", #"{"groups":["web"]}"#), call("guess", "web_fetch")]), .answer
        ])
        #expect(await probe.count("web_fetch") == 0)
        #expect(events.contains { event in
            if case .activityCompleted(let activity) = event.payload { return activity.failureCode == "tool_not_exposed" }
            return false
        })
        #expect(outcomes(events) == [.succeeded])
    }

    @Test("Explicit Skill scope blocks group loading and has no shell or delivery bypass")
    func skillScopeCannotEscalate() async throws {
        let probe = FamiliarLazyProbe()
        let registry = try registry(probe: probe, names: ["web_fetch", "calendar_events", "shell_execute", "file_publish"])
        let skill = FamiliarSkillSnapshot(stableID: "calendar-only", version: "1", name: "Calendar",
            contentHash: String(repeating: "a", count: 64), instructions: "Only query calendars.", allowedTools: ["calendar_events"])
        let events = try await run(registry: registry, probe: probe, steps: [
            .calls([call("load", "tools_load", #"{"groups":["shell"]}"#)]), .answer
        ], skill: skill)
        #expect(await probe.count("shell_execute") == 0)
        let requests = await probe.requests()
        #expect(requests.count == 2)
        #expect(Set(requests[1].tools.map(\.name)) == FamiliarToolGroup.baseToolNames)
        #expect(events.contains { if case .activityCompleted(let value) = $0.payload { value.failureCode == "tool_load_failed" } else { false } })
        #expect(!FamiliarToolGroup.allows("file_publish", skill: skill))
    }

    @Test("Remote discovery is cached and schemas need exact selection; actions still need approval")
    func remoteSelectionAndApproval() async throws {
        let probe = FamiliarLazyProbe()
        let registry = try registry(probe: probe)
        let events = try await run(registry: registry, probe: probe, steps: [
            .calls([call("directory", "tools_load", #"{"groups":["mcp.fixture"]}"#)]),
            .calls([call("select", "tools_load", #"{"groups":["mcp.fixture"],"toolNames":["mcp_fixture_action"]}"#)]),
            .calls([call("action", "mcp_fixture_action"), call("duplicate", "mcp_fixture_action")]), .answer
        ], sources: [remoteGroup(probe: probe)])
        let requests = await probe.requests()
        #expect(Set(requests[1].tools.map(\.name)) == FamiliarToolGroup.baseToolNames)
        #expect(Set(requests[2].tools.map(\.name)) == FamiliarToolGroup.baseToolNames.union(["mcp_fixture_action"]))
        #expect(await probe.count("discover") == 1)
        #expect(await probe.count("mcp_fixture_action") == 1)
        let approvals = events.compactMap { event -> FamiliarToolConfirmationRequest? in
            if case .approvalRequested(let value) = event.payload { value } else { nil }
        }
        #expect(approvals.count == 1)
        #expect(approvals.first?.allowedAuthorizationDurations == [.once])
        #expect(events.contains { if case .activityCompleted(let value) = $0.payload { value.failureCode == "duplicate_tool_call" } else { false } })
        #expect(outcomes(events) == [.succeeded])
    }

    @Test("Discovery failure remains a failed load, with no remote tool exposure")
    func remoteFailure() async throws {
        let probe = FamiliarLazyProbe()
        let source = FamiliarDeferredToolGroup(summary: .init(id: "mcp.fixture", title: "Fixture", summary: "Remote fixture"), discover: {
            throw FamiliarToolLoadError("Fixture server unavailable")
        })
        let events = try await run(registry: registry(probe: probe), probe: probe, steps: [
            .calls([call("load", "tools_load", #"{"groups":["mcp.fixture"]}"#)]), .answer
        ], sources: [source])
        let requests = await probe.requests()
        #expect(Set(requests[1].tools.map(\.name)) == FamiliarToolGroup.baseToolNames)
        #expect(events.contains { if case .activityCompleted(let value) = $0.payload { value.failureCode == "tool_load_failed" } else { false } })
        #expect(outcomes(events) == [.succeeded])
    }

    @Test("Large remote directories page descriptions and activate only selected schemas")
    func remoteDirectoryPagination() async throws {
        let probe = FamiliarLazyProbe()
        let registry = try registry(probe: probe)
        let source = FamiliarDeferredToolGroup(summary: .init(id: "mcp.large", title: "Large fixture", summary: "Paged directory"), discover: {
            await probe.record("discover")
            return (0..<70).map { AnyFamiliarTool(FamiliarLazyTool(name: "mcp_slot_\($0)", probe: probe, remote: true)) }
        })
        let loader = FamiliarToolLoader(registry: registry, catalog: await registry.snapshot(), deferred: [source])
        let first = try await loader.load(groups: ["mcp.large"], toolNames: nil, offset: 0, skill: nil, schemaBudget: 100_000)
        #expect(first.report.availableTools.count == 32)
        #expect(first.report.nextOffset == 32)
        #expect(Set(first.manifests.map(\.name)) == FamiliarToolGroup.baseToolNames)
        let second = try await loader.load(groups: ["mcp.large"], toolNames: nil, offset: 32, skill: nil, schemaBudget: 100_000)
        #expect(second.report.nextOffset == 64)
        let selected = try await loader.load(groups: ["mcp.large"], toolNames: ["mcp_slot_69"], offset: 64, skill: nil, schemaBudget: 100_000)
        #expect(selected.report.availableTools.count == 6)
        #expect(selected.report.nextOffset == nil)
        #expect(Set(selected.manifests.map(\.name)) == FamiliarToolGroup.baseToolNames.union(["mcp_slot_69"]))
        #expect(await probe.count("discover") == 1)
    }

    @Test("An unavailable tool reports its actual reason and is not exposed")
    func unavailableGroupMember() async throws {
        let probe = FamiliarLazyProbe()
        let tool = FamiliarLazyTool(name: "web_fetch", probe: probe, requirements: [.contactsRead])
        let registry = try FamiliarToolRegistry(tools: baseTools() + [AnyFamiliarTool(tool)],
            capabilities: FamiliarFakeCapabilities(.unavailable(reason: "Fixture permission denied")))
        let loader = FamiliarToolLoader(registry: registry, catalog: await registry.snapshot(), deferred: [])
        let result = try await loader.load(groups: ["web"], toolNames: nil, offset: 0, skill: nil, schemaBudget: 100_000)
        #expect(result.report.unavailable.first?.reason == "Fixture permission denied")
        #expect(Set(result.manifests.map(\.name)) == FamiliarToolGroup.baseToolNames)
        #expect(await probe.count("web_fetch") == 0)
    }

    @Test("Remote discovery is bounded by the same Run deadline")
    func discoveryDeadline() async throws {
        let probe = FamiliarLazyProbe()
        let source = FamiliarDeferredToolGroup(summary: .init(id: "mcp.fixture", title: "Fixture", summary: "Slow fixture"), discover: {
            try await Task.sleep(for: .seconds(5))
            return []
        })
        let clock = ContinuousClock()
        let start = clock.now
        let events = try await run(registry: registry(probe: probe), probe: probe,
            steps: [.calls([call("load", "tools_load", #"{"groups":["mcp.fixture"]}"#)])], sources: [source], duration: 0.5)
        #expect(start.duration(to: clock.now) < .seconds(2))
        let outcomes = outcomes(events)
        #expect(outcomes.count == 1)
        #expect(outcomes.first?.failureKind == .durationExceeded)
    }

    @Test("Tool budgets include loaders and finish with the gathered context")
    func loaderUsesToolBudget() async throws {
        let probe = FamiliarLazyProbe()
        let events = try await run(registry: registry(probe: probe, names: ["web_fetch"]), probe: probe, steps: [
            .calls([call("load", "tools_load", #"{"groups":["web"]}"#)]),
            .calls([call("read", "web_fetch")]), .answer
        ], toolBudget: 1)
        let requests = await probe.requests()
        #expect(requests.last?.tools.isEmpty == true)
        #expect(await probe.count("web_fetch") == 0)
        #expect(outcomes(events) == [.succeeded])
    }

    @Test("Parameter schemas count toward input budget and oversized loads do not activate")
    func schemaBudget() async throws {
        let probe = FamiliarLazyProbe()
        let huge = FamiliarLazyTool(name: "web_fetch", probe: probe, description: String(repeating: "x", count: 5_000))
        let registry = try FamiliarToolRegistry(tools: baseTools() + [AnyFamiliarTool(huge)])
        let loader = FamiliarToolLoader(registry: registry, catalog: await registry.snapshot(), deferred: [])
        let count = FamiliarContextCompiler.inputCharacterCount(messages: [], manifests: [huge.manifest])
        #expect(count > huge.manifest.name.count + huge.manifest.description.count + 5_000)
        await #expect(throws: FamiliarToolLoadError.self) {
            _ = try await loader.load(groups: ["web"], toolNames: nil, offset: 0, skill: nil, schemaBudget: 1_000)
        }
    }

    @Test("Concurrent guest preparation shares one flight and warm calls do not prepare again")
    func sharedGuestPreparation() async throws {
        let probe = FamiliarPreparationProbe()
        let preparation = FamiliarISHPreparation(bridge: FamiliarPreparationBridge(probe: probe),
            configuration: .init(maximumProcessCount: 16, maximumMemoryBytes: 512 * 1_024 * 1_024))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 { group.addTask { try await preparation.prepare() } }
            try await group.waitForAll()
        }
        try await preparation.prepare()
        #expect(await probe.count() == 1)
    }

    @Test("Cancelling a preparation waiter returns before shared setup finishes")
    func cancelledGuestWaiter() async throws {
        let probe = FamiliarPreparationProbe()
        let preparation = FamiliarISHPreparation(bridge: FamiliarPreparationBridge(probe: probe, delay: .seconds(1.5)),
            configuration: .init(maximumProcessCount: 16, maximumMemoryBytes: 512 * 1_024 * 1_024))
        let waiter = Task { try await preparation.prepare() }
        try await Task.sleep(for: .milliseconds(10))
        waiter.cancel()
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(start.duration(to: clock.now) < .seconds(1))
        try await preparation.prepare()
        #expect(await probe.count() == 1)
    }

    @Test("Defaults are core-only and explicit Project selections remain authoritative")
    @MainActor
    func projectDefaultScope() async throws {
        let container = try FamiliarTestStore.make(name: "LazyProjectDefaults")
        let service = FamiliarProjectService()
        let project = try service.create(name: "Scope", in: container.mainContext)
        let probe = FamiliarLazyProbe()
        let registry = try registry(probe: probe, names: ["web_fetch", "shell_execute", "file_publish", "health_activity_summary"])
        let all = await registry.snapshot()
        let initial = try service.filterCapabilities(all, projectID: project.id, in: container.mainContext)
        #expect(initial.map(\.name).contains("web_fetch"))
        #expect(!initial.map(\.name).contains("shell_execute"))
        try service.setCapability("shell_execute", enabled: true, allCapabilities: all, projectID: project.id, in: container.mainContext)
        let enabled = try service.filterCapabilities(all, projectID: project.id, in: container.mainContext)
        #expect(enabled.map(\.name).contains("shell_execute"))
        #expect(!enabled.map(\.name).contains("file_publish"))
        #expect(!enabled.map(\.name).contains("health_activity_summary"))
        try service.setCapability("web_fetch", enabled: false, allCapabilities: all, projectID: project.id, in: container.mainContext)
        let disabled = try service.filterCapabilities(all, projectID: project.id, in: container.mainContext)
        #expect(!disabled.map(\.name).contains("web_fetch"))
    }

    private func baseTools() -> [AnyFamiliarTool] {
        [AnyFamiliarTool(FamiliarCurrentDateTimeTool()), AnyFamiliarTool(FamiliarAskUserTool()), AnyFamiliarTool(FamiliarToolsLoadTool())]
    }

    private func registry(probe: FamiliarLazyProbe, names: [String] = []) throws -> FamiliarToolRegistry {
        try FamiliarToolRegistry(tools: baseTools() + names.map { AnyFamiliarTool(FamiliarLazyTool(name: $0, probe: probe)) })
    }

    private func call(_ id: String, _ name: String, _ arguments: String = "{}") -> FamiliarToolCall {
        .init(id: id, name: name, arguments: arguments)
    }

    private func remoteGroup(probe: FamiliarLazyProbe) -> FamiliarDeferredToolGroup {
        .init(summary: .init(id: "mcp.fixture", title: "Fixture", summary: "Remote fixture"), discover: {
            await probe.record("discover")
            return [AnyFamiliarTool(FamiliarLazyTool(name: "mcp_fixture_action", probe: probe, remote: true))]
        })
    }

    private func run(registry: FamiliarToolRegistry, probe: FamiliarLazyProbe, steps: [FamiliarLazyStep],
                     sources: [FamiliarDeferredToolGroup] = [], skill: FamiliarSkillSnapshot? = nil,
                     duration: TimeInterval = 30, toolBudget: Int = 64) async throws -> [FamiliarRuntimeEvent] {
        let coordinator = FamiliarToolConfirmationCoordinator()
        let loop = FamiliarAgentLoop(provider: FamiliarLazyProvider(probe: probe, steps: steps), registry: registry, policy: .init(),
            confirmationCoordinator: coordinator, undoStore: .init(), deferredToolGroups: sources, maximumToolCalls: toolBudget, maximumDuration: duration)
        let seed = FamiliarProjectContextSeed(projectID: FamiliarProject.dailyProjectID, projectName: "Daily Chat", conversationID: UUID(),
            projectInstruction: nil, resources: [], skills: skill.map { [$0] } ?? [])
        let snapshot = try FamiliarContextCompiler.assemble(seed: seed, settings: .defaultValue,
            messages: [], toolManifests: await registry.snapshot(), additionalToolGroups: sources.map(\.summary))
        var events: [FamiliarRuntimeEvent] = []
        for try await event in loop.stream(contextSnapshot: snapshot) {
            events.append(event)
            if case .approvalRequested(let request) = event.payload {
                await coordinator.resolve(requestID: request.id, decision: .confirmedOnce)
            }
        }
        return events
    }

    private func outcomes(_ events: [FamiliarRuntimeEvent]) -> [FamiliarRunOutcome] {
        events.compactMap { if case .runFinished(let outcome) = $0.payload { outcome } else { nil } }
    }
}

private actor FamiliarPreparationProbe {
    private var prepares = 0
    func begin() { prepares += 1 }
    func count() -> Int { prepares }
}

private nonisolated struct FamiliarPreparationBridge: FamiliarISHBridge {
    let probe: FamiliarPreparationProbe
    var delay: Duration = .milliseconds(150)
    func prepare(configuration: FamiliarISHRuntimeConfiguration) async throws {
        await probe.begin()
        try await Task.sleep(for: delay)
    }
    func execute(taskID: UUID, command: String, workingDirectory: String, mounts: [FamiliarISHMount],
                 networkPolicy: FamiliarShellNetworkPolicy, timeout: TimeInterval) -> AsyncThrowingStream<FamiliarISHProcessEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: FamiliarShellExecutorError.unavailable) }
    }
    func cancel(taskID: UUID) async {}
}

private actor FamiliarLazyProbe {
    private var values: [FamiliarModelRequest] = []
    private var counts: [String: Int] = [:]
    func capture(_ request: FamiliarModelRequest) -> Int { values.append(request); return values.count - 1 }
    func record(_ name: String) { counts[name, default: 0] += 1 }
    func count(_ name: String) -> Int { counts[name] ?? 0 }
    func requests() -> [FamiliarModelRequest] { values }
}

private nonisolated enum FamiliarLazyStep: Sendable {
    case answer
    case calls([FamiliarToolCall])
}

private nonisolated struct FamiliarLazyProvider: FamiliarModelProvider {
    let providerID = "lazy-fixture"
    let probe: FamiliarLazyProbe
    let steps: [FamiliarLazyStep]
    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let index = await probe.capture(request)
                let step = index < steps.count ? steps[index] : .answer
                switch step {
                case .answer:
                    continuation.yield(.textDelta("Answer from existing context"))
                    continuation.yield(.completed(.stop))
                case .calls(let calls):
                    for (index, call) in calls.enumerated() {
                        continuation.yield(.toolCallDelta(index: index, id: call.id, name: call.name, arguments: call.arguments))
                    }
                    continuation.yield(.completed(.toolCalls))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private nonisolated struct FamiliarLazyTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    let manifest: FamiliarToolManifest
    let probe: FamiliarLazyProbe
    init(name: String, probe: FamiliarLazyProbe, remote: Bool = false, description: String = "Fixture field", requirements: [FamiliarCapabilityRequirement] = []) {
        self.probe = probe
        manifest = .init(name: name, title: name, description: "Fixture capability",
            parameters: .object(["value": .string(description)], required: []),
            effect: remote ? .destructiveWrite : .read, risk: remote ? .high : .low,
            requirements: requirements,
            source: remote ? .mcp : .builtIn)
    }
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let result = FamiliarToolExecutionResult(envelope: try .init(model: ["ok": true], presentation: .scalar(.init(summary: "Fixture result", value: "OK"))))
        if manifest.source == .mcp {
            return .action(.init(title: "Remote fixture", fields: [], target: "fixture", effect: .destructiveWrite, risk: .high,
                consequence: "Run the fixture action", undoPolicy: .unavailable, idempotencyKey: context.idempotencyKey,
                allowedAuthorizationDurations: [.once], commit: {
                    await probe.record(manifest.name)
                    return .init(result: result)
                }))
        }
        await probe.record(manifest.name)
        return .result(result)
    }
}
