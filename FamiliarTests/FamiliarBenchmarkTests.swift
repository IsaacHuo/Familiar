import Foundation
import SwiftData
import Testing
import UIKit
@testable import Familiar

enum FamiliarBenchmarkScenario: String, CaseIterable, Sendable {
    case calendarRead = "calendar-read"
    case reminderWrite = "reminder-write"
    case posterImagePreflight = "poster-image-preflight"
    case documentQuestion = "document-question"
    case documentCalendar = "document-calendar"
    case weatherCapabilityGate = "weather-capability-gate"
    case webReminder = "web-reminder"
    case toolFailureRecovery = "tool-failure-recovery"

    var expectedTools: [String] {
        switch self {
        case .calendarRead: ["calendar_events"]
        case .reminderWrite: ["create_reminder"]
        case .documentCalendar: ["calendar_events", "create_calendar_event"]
        case .webReminder: ["web_search", "web_fetch", "create_reminder"]
        case .toolFailureRecovery: ["failing_tool"]
        case .posterImagePreflight, .documentQuestion, .weatherCapabilityGate: []
        }
    }

    var expectedApprovals: [String] {
        switch self {
        case .reminderWrite: ["create_reminder"]
        case .documentCalendar: ["create_calendar_event"]
        case .webReminder: ["create_reminder"]
        default: []
        }
    }
}

private actor FamiliarBenchmarkRequestRecorder {
    private var requests: [FamiliarModelRequest] = []

    func append(_ request: FamiliarModelRequest) {
        requests.append(request)
    }

    func snapshot() -> [FamiliarModelRequest] {
        requests
    }
}

private struct FamiliarBenchmarkProvider: FamiliarModelProvider {
    let providerID = "benchmark-fixture"
    let scenario: FamiliarBenchmarkScenario
    let recorder: FamiliarBenchmarkRequestRecorder

    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await recorder.append(request)
                let completedTools = request.messages.compactMap { message in
                    message.role == .tool ? message.name : nil
                }

                switch scenario {
                case .calendarRead:
                    if completedTools.isEmpty {
                        emitTool(
                            id: "calendar-read",
                            name: "calendar_events",
                            arguments: #"{"startISO8601":"2026-08-15T12:00:00Z","endISO8601":"2026-08-15T18:00:00Z","limit":20}"#,
                            into: continuation
                        )
                    } else {
                        emitText("明天下午有一项安排。", into: continuation)
                    }

                case .reminderWrite:
                    if completedTools.isEmpty {
                        emitTool(
                            id: "reminder-write",
                            name: "create_reminder",
                            arguments: #"{"title":"交作业","dueISO8601":"2026-08-15T15:00:00Z","listIdentifier":null,"priority":0,"notes":null}"#,
                            into: continuation
                        )
                    } else {
                        emitText("提醒已经创建。", into: continuation)
                    }

                case .documentQuestion:
                    emitText("考试日期是 2026 年 12 月 18 日。", into: continuation)

                case .documentCalendar:
                    if completedTools.isEmpty {
                        emitTool(
                            id: "document-calendar-read",
                            name: "calendar_events",
                            arguments: #"{"startISO8601":"2026-12-18T00:00:00Z","endISO8601":"2026-12-19T00:00:00Z","limit":20}"#,
                            into: continuation
                        )
                    } else if !completedTools.contains("create_calendar_event") {
                        emitTool(
                            id: "document-calendar-write",
                            name: "create_calendar_event",
                            arguments: #"{"title":"期末考试","startISO8601":"2026-12-18T09:00:00Z","endISO8601":"2026-12-18T11:00:00Z","isAllDay":false,"location":"教学楼 A101","notes":"来自 syllabus.pdf","urlString":null,"calendarIdentifier":null}"#,
                            into: continuation
                        )
                    } else {
                        emitText("考试日程已经创建。", into: continuation)
                    }

                case .weatherCapabilityGate:
                    emitText("当前没有天气工具，无法核验周六天气。", into: continuation)

                case .webReminder:
                    if completedTools.isEmpty {
                        emitTool(
                            id: "web-search",
                            name: "web_search",
                            arguments: #"{"query":"Familiar fixture activity","maxResults":3}"#,
                            into: continuation
                        )
                    } else if !completedTools.contains("web_fetch") {
                        emitTool(
                            id: "web-fetch",
                            name: "web_fetch",
                            arguments: #"{"url":"https://example.com/activity"}"#,
                            into: continuation
                        )
                    } else if !completedTools.contains("create_reminder") {
                        emitTool(
                            id: "web-reminder",
                            name: "create_reminder",
                            arguments: #"{"title":"参加 Fixture 活动","dueISO8601":"2026-08-20T09:00:00Z","listIdentifier":null,"priority":0,"notes":"https://example.com/activity"}"#,
                            into: continuation
                        )
                    } else {
                        emitText("活动提醒已经创建 [[src_fixture_activity]]。", into: continuation)
                    }

                case .toolFailureRecovery:
                    if completedTools.isEmpty {
                        emitTool(id: "failing-call", name: "failing_tool", arguments: "{}", into: continuation)
                    } else {
                        emitText("工具失败了，请提供可用的数据源后再试。", into: continuation)
                    }

                case .posterImagePreflight:
                    continuation.finish(throwing: FamiliarBenchmarkError.providerMustNotRun)
                }
            }
        }
    }

    private func emitTool(
        id: String,
        name: String,
        arguments: String,
        into continuation: AsyncThrowingStream<FamiliarModelStreamEvent, Error>.Continuation
    ) {
        continuation.yield(.toolCallDelta(index: 0, id: id, name: name, arguments: arguments))
        continuation.yield(.completed(.toolCalls))
        continuation.finish()
    }

    private func emitText(
        _ text: String,
        into continuation: AsyncThrowingStream<FamiliarModelStreamEvent, Error>.Continuation
    ) {
        continuation.yield(.textDelta(text))
        continuation.yield(.completed(.stop))
        continuation.finish()
    }
}

private actor FamiliarBenchmarkEventKitService: FamiliarEventKitServicing {
    private var commits: [String: FamiliarWriteCommitResult] = [:]

    func availability(for requirement: FamiliarCapabilityRequirement) -> FamiliarCapabilityAvailability {
        .available
    }

    func request(_ requirement: FamiliarCapabilityRequirement) {}

    func targetDescription(for request: FamiliarPendingWriteRequest) -> String {
        switch request {
        case .event, .eventUpdate, .eventDelete: "Benchmark Calendar"
        case .reminder, .reminderUpdate, .reminderDelete: "Benchmark Reminders"
        }
    }

    func events(from startISO8601: String, to endISO8601: String, limit: Int) -> [FamiliarCalendarEvent] {
        [FamiliarCalendarEvent(
            id: "fixture-event",
            title: "实验课",
            startISO8601: "2026-08-15T14:00:00Z",
            endISO8601: "2026-08-15T16:00:00Z",
            isAllDay: false,
            location: "实验楼",
            notes: nil,
            calendarIdentifier: "fixture-calendar",
            calendarTitle: "Benchmark Calendar"
        )]
    }

    func reminders(
        from startISO8601: String?,
        to endISO8601: String?,
        text: String?,
        limit: Int
    ) -> [FamiliarReminder] {
        []
    }

    func commit(
        _ request: FamiliarPendingWriteRequest,
        idempotencyKey: String
    ) throws -> FamiliarWriteCommitResult {
        if let existing = commits[idempotencyKey] {
            return existing
        }
        let kind: FamiliarEventKitAccessKind = switch request {
        case .event, .eventUpdate, .eventDelete: .events
        case .reminder, .reminderUpdate, .reminderDelete: .reminders
        }
        let result = FamiliarWriteCommitResult(
            idempotencyKey: idempotencyKey,
            kind: kind,
            identifier: "fixture-\(commits.count + 1)"
        )
        commits[idempotencyKey] = result
        return result
    }

    func undoCommit(idempotencyKey: String) throws -> FamiliarToolExecutionResult {
        guard commits[idempotencyKey] != nil else {
            throw FamiliarEventKitError.undoUnavailable
        }
        return .init(envelope: try .init(canonicalModelJSON: #"{"undone":true}"#, presentation: .mutationReceipt(.init(summary: "Undone", operation: "undo", targetIdentifier: nil, succeeded: true, undoAvailable: false))))
    }

    func commitCount() -> Int {
        commits.count
    }
}

private struct FamiliarBenchmarkWebSearchTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let query: String
        let maxResults: Int?
    }

    let manifest = FamiliarToolManifest(
        name: "web_search",
        title: "Fixture Web Search",
        description: "Searches a deterministic public fixture.",
        parameters: .init(
            type: .object,
            properties: [
                "query": .init(type: .string),
                "maxResults": .init(type: .integer)
            ],
            required: ["query"]
        ),
        effect: .read,
        risk: .sensitive,
        requirements: []
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let source = FamiliarSource(
            id: "src_fixture_search",
            kind: .searchResult,
            title: "Fixture activity",
            url: URL(string: "https://example.com/activity")!,
            siteName: "example.com",
            snippet: "Fixture activity starts on August 20.",
            retrievedAt: Date(timeIntervalSince1970: 0)
        )
        return .result(.init(
            envelope: try .init(
                canonicalModelJSON: #"{"results":[{"url":"https://example.com/activity"}]}"#,
                presentation: .searchResults(.init(summary: "Found 1 result", query: input.query, results: [.init(id: source.id, title: source.title, url: source.url.absoluteString, snippet: source.snippet)]))
            ),
            sources: [source]
        ))
    }
}

private struct FamiliarBenchmarkWebFetchTool: FamiliarTool {
    struct Input: Decodable, Sendable { let url: String }

    let manifest = FamiliarToolManifest(
        name: "web_fetch",
        title: "Fixture Web Fetch",
        description: "Reads deterministic fixture content.",
        parameters: .init(
            type: .object,
            properties: ["url": .init(type: .string)],
            required: ["url"]
        ),
        effect: .read,
        risk: .sensitive,
        requirements: []
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let source = FamiliarSource(
            id: "src_fixture_activity",
            kind: .fetchedPage,
            title: "Fixture activity",
            url: URL(string: input.url)!,
            siteName: "example.com",
            snippet: "The activity starts on August 20 at 10:00.",
            retrievedAt: Date(timeIntervalSince1970: 0)
        )
        return .result(.init(
            envelope: try .init(
                canonicalModelJSON: #"{"text":"The activity starts on August 20 at 10:00."}"#,
                presentation: .document(.init(summary: "Read fixture activity", title: source.title, text: "The activity starts on August 20 at 10:00.", url: source.url.absoluteString))
            ),
            sources: [source]
        ))
    }
}

private struct FamiliarBenchmarkFailingTool: FamiliarTool {
    struct Input: Decodable, Sendable {}

    let manifest = FamiliarToolManifest(
        name: "failing_tool",
        title: "Failing Fixture",
        description: "Always fails so recovery remains observable.",
        parameters: .init(type: .object),
        effect: .read,
        risk: .low,
        requirements: []
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        throw FamiliarBenchmarkError.fixtureToolFailure
    }
}

private enum FamiliarBenchmarkError: LocalizedError {
    case fixtureToolFailure
    case providerMustNotRun

    var errorDescription: String? {
        switch self {
        case .fixtureToolFailure: "The deterministic fixture tool failed."
        case .providerMustNotRun: "The provider ran despite the image capability gate."
        }
    }
}

private struct FamiliarBenchmarkResult {
    let scenario: FamiliarBenchmarkScenario
    let modelRounds: Int
    let toolSequence: [String]
    let approvalSequence: [String]
    let terminalStatuses: [String]
    let durationMilliseconds: Int
    let failures: [String]

    var diagnostic: String {
        let failureText = failures.isEmpty ? "none" : failures.joined(separator: "; ")
        return "scenario=\(scenario.rawValue) rounds=\(modelRounds) tools=\(toolSequence) approvals=\(approvalSequence) terminals=\(terminalStatuses) durationMs=\(durationMilliseconds) usage=unavailable failures=\(failureText)"
    }
}

@Suite("Familiar MVP benchmarks", .serialized)
struct FamiliarBenchmarkTests {
    @MainActor
    @Test("Deterministic product scenario", arguments: FamiliarBenchmarkScenario.allCases)
    func productScenario(_ scenario: FamiliarBenchmarkScenario) async throws {
        let result = try await run(scenario)
        print("BENCHMARK \(result.diagnostic)")
        if !result.failures.isEmpty {
            Issue.record(Comment(rawValue: result.diagnostic))
        }
    }

    @MainActor
    private func run(_ scenario: FamiliarBenchmarkScenario) async throws -> FamiliarBenchmarkResult {
        if scenario == .posterImagePreflight {
            return try imagePreflightResult()
        }

        let startedAt = Date()
        let recorder = FamiliarBenchmarkRequestRecorder()
        let eventKit = FamiliarBenchmarkEventKitService()
        let confirmationCoordinator = FamiliarToolConfirmationCoordinator()
        let tools: [AnyFamiliarTool] = [
            AnyFamiliarTool(FamiliarCalendarEventsTool(service: eventKit)),
            AnyFamiliarTool(FamiliarCreateCalendarEventTool(service: eventKit)),
            AnyFamiliarTool(FamiliarRemindersTool(service: eventKit)),
            AnyFamiliarTool(FamiliarCreateReminderTool(service: eventKit)),
            AnyFamiliarTool(FamiliarBenchmarkWebSearchTool()),
            AnyFamiliarTool(FamiliarBenchmarkWebFetchTool()),
            AnyFamiliarTool(FamiliarBenchmarkFailingTool())
        ]
        let registry = try FamiliarToolRegistry(tools: tools, capabilities: eventKit)
        let loop = FamiliarAgentLoop(
            provider: FamiliarBenchmarkProvider(scenario: scenario, recorder: recorder),
            registry: registry,
            policy: FamiliarExecutionPolicy(),
            confirmationCoordinator: confirmationCoordinator,
            undoStore: FamiliarUndoStore()
        )
        let snapshot = try familiarTestContextSnapshot(
            messages: messages(for: scenario),
            manifests: await registry.manifests()
        )
        var events: [FamiliarRuntimeEvent] = []
        for try await event in loop.stream(contextSnapshot: snapshot) {
            events.append(event)
            if case .approvalRequested(let request) = event.payload {
                await confirm(request, with: confirmationCoordinator)
            }
        }

        let requests = await recorder.snapshot()
        let commitCount = await eventKit.commitCount()
        let toolSequence = events.compactMap { event in
            if case .toolInvocationRequested(_, let name, _, _) = event.payload { return name }
            return nil
        }
        let approvalSequence = events.compactMap { event in
            if case .approvalRequested(let request) = event.payload { return request.toolName }
            return nil
        }
        let terminals = events.compactMap { event -> FamiliarRuntimeActivityCompletion? in
            if case .activityCompleted(let terminal) = event.payload { return terminal }
            return nil
        }
        let response = events.compactMap { event -> FamiliarCompletedResponse? in
            if case .responseCompleted(let response) = event.payload { return response }
            return nil
        }.last

        var failures: [String] = []
        if toolSequence != scenario.expectedTools {
            failures.append("expected tools \(scenario.expectedTools), got \(toolSequence)")
        }
        if approvalSequence != scenario.expectedApprovals {
            failures.append("expected approvals \(scenario.expectedApprovals), got \(approvalSequence)")
        }
        if events.map(\.sequence) != Array(0..<events.count) {
            failures.append("runtime event sequence was not contiguous")
        }
        if response == nil {
            failures.append("missing completed response")
        }
        if !events.contains(where: { if case .runFinished(let outcome) = $0.payload { return outcome.status == .succeeded }; return false }) {
            failures.append("missing successful runFinished")
        }

        switch scenario {
        case .calendarRead:
            if requests.count != 2 { failures.append("expected 2 model rounds") }
            if commitCount != 0 { failures.append("read scenario committed a write") }

        case .reminderWrite:
            if requests.count != 2 { failures.append("expected 2 model rounds") }
            if commitCount != 1 { failures.append("expected one reminder commit") }
            if terminals.last?.confirmation != .confirmed { failures.append("write was not confirmed") }

        case .documentQuestion:
            let documentText = requests.first?.messages.compactMap(\.networkText).joined(separator: "\n") ?? ""
            if !documentText.contains("[Document: syllabus.pdf]") || !documentText.contains("2026-12-18") {
                failures.append("document content did not enter provider context")
            }

        case .documentCalendar:
            if requests.count != 3 { failures.append("expected 3 model rounds") }
            if commitCount != 1 { failures.append("expected one calendar commit") }

        case .weatherCapabilityGate:
            if requests.first?.tools.contains(where: { $0.name.contains("weather") }) == true {
                failures.append("weather capability was exposed")
            }
            if response?.text.contains("没有天气工具") != true {
                failures.append("weather boundary was not explicit")
            }

        case .webReminder:
            if requests.count != 4 { failures.append("expected 4 model rounds") }
            if commitCount != 1 { failures.append("expected one reminder commit") }
            if response?.sources.map(\.id) != ["src_fixture_activity"] {
                failures.append("fetched source was not preserved and deduplicated")
            }

        case .toolFailureRecovery:
            if terminals.map(\.status) != [.failed] {
                failures.append("tool failure was not observable")
            }
            if response?.text.contains("请提供") != true {
                failures.append("provider did not recover by asking for input")
            }

        case .posterImagePreflight:
            break
        }

        return FamiliarBenchmarkResult(
            scenario: scenario,
            modelRounds: requests.count,
            toolSequence: toolSequence,
            approvalSequence: approvalSequence,
            terminalStatuses: terminals.map { "\($0.toolName):\($0.status.rawValue)" },
            durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
            failures: failures
        )
    }

    @MainActor
    private func imagePreflightResult() throws -> FamiliarBenchmarkResult {
        let startedAt = Date()
        let container = try FamiliarTestStore.make()
        let controller = FamiliarChatController(dependencies: FamiliarAppDependencies())
        controller.draft = "把海报加到日历"
        controller.draftImages = [FamiliarDraftImage(image: Self.testImage())]
        controller.startSending(in: container.mainContext)

        var failures: [String] = []
        if controller.errorMessage != nil { failures.append("image preflight reported an immediate error") }
        if !controller.isSending { failures.append("image preflight did not start") }
        if !controller.messages.isEmpty { failures.append("image preflight created a message before evidence was ready") }
        if controller.draftImages.isEmpty { failures.append("image preflight discarded the draft image") }
        let conversations = try container.mainContext.fetch(FetchDescriptor<FamiliarConversation>())
        if !conversations.isEmpty { failures.append("image preflight created a conversation before evidence was ready") }
        controller.cancelSending(in: container.mainContext)

        return FamiliarBenchmarkResult(
            scenario: .posterImagePreflight,
            modelRounds: 0,
            toolSequence: [],
            approvalSequence: [],
            terminalStatuses: ["vision-preflight"],
            durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
            failures: failures
        )
    }

    private static func testImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func messages(for scenario: FamiliarBenchmarkScenario) -> [FamiliarMessageSnapshot] {
        let content: String
        let attachments: [FamiliarAttachmentSnapshot]
        switch scenario {
        case .calendarRead:
            content = "明天下午有什么安排？"
            attachments = []
        case .reminderWrite:
            content = "明天下午三点提醒我交作业"
            attachments = []
        case .documentQuestion:
            content = "考试什么时候？"
            attachments = [documentAttachment()]
        case .documentCalendar:
            content = "找到考试时间，检查安排后加到日历"
            attachments = [documentAttachment()]
        case .weatherCapabilityGate:
            content = "看看周六安排和天气"
            attachments = []
        case .webReminder:
            content = "从这个 URL 找活动并创建提醒"
            attachments = []
        case .toolFailureRecovery:
            content = "读取不可用的数据源"
            attachments = []
        case .posterImagePreflight:
            content = "把海报加到日历"
            attachments = []
        }
        return [FamiliarMessageSnapshot(
            id: UUID(),
            role: .user,
            content: content,
            createdAt: Date(timeIntervalSince1970: 0),
            sequence: 0,
            providerID: nil,
            modelID: nil,
            attachments: attachments
        )]
    }

    private func documentAttachment() -> FamiliarAttachmentSnapshot {
        FamiliarAttachmentSnapshot(
            id: UUID(),
            kind: .document,
            filename: "syllabus.pdf",
            mimeType: "application/pdf",
            relativePath: "Messages/fixture/syllabus.pdf",
            extractedText: "期末考试日期：2026-12-18，时间 09:00-11:00，地点 教学楼 A101。",
            byteSize: 1_024,
            extractionEngine: "benchmark-fixture",
            extractionVersion: "1",
            detectedFormat: "pdf",
            usedOCR: false
        )
    }

    private func confirm(
        _ request: FamiliarToolConfirmationRequest,
        with coordinator: FamiliarToolConfirmationCoordinator
    ) async {
        while !Task.isCancelled {
            if await coordinator.pendingRequests().contains(where: { $0.id == request.id }) {
                await coordinator.resolve(requestID: request.id, decision: .confirmed)
                return
            }
            await Task.yield()
        }
    }
}
