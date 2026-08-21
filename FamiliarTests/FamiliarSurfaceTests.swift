import Foundation
import Testing
@testable import Familiar

@Suite("Assistant turn surface projection")
struct FamiliarSurfaceTests {
    private func event(_ sequence: Int, _ payload: FamiliarRuntimeEventPayload, turnID: String? = "run-1:turn:0") -> FamiliarRuntimeEvent {
        FamiliarRuntimeEvent(
            runID: "run-1",
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: Double(sequence)),
            assistantTurnID: turnID,
            payload: payload
        )
    }

    private func completion(
        toolName: String,
        effect: FamiliarToolEffect,
        status: FamiliarToolRunTerminalStatus = .succeeded
    ) -> FamiliarRuntimeActivityCompletion {
        FamiliarRuntimeActivityCompletion(
            runID: "run-1",
            toolCallID: "call-1",
            toolName: toolName,
            effect: effect,
            assistantTurnID: "run-1:turn:0",
            detail: status == .failed ? "Unavailable" : "Complete",
            confirmation: .notRequired,
            status: status,
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            artifactIdentifier: nil,
            undoAvailable: false,
            automaticApprovalRequest: nil
        )
    }

    private func result(toolName: String, effect: FamiliarToolEffect, envelope: FamiliarToolResultEnvelope, callID: String = "call-1") -> FamiliarToolResultProduced {
        .init(runID: "run-1", toolCallID: callID, toolName: toolName, effect: effect, assistantTurnID: "run-1:turn:0", envelope: envelope, sources: [], webCaptures: [], artifact: nil, producedAt: Date(timeIntervalSince1970: 2))
    }

    @Test("Write lifecycle projects one compact top-level surface")
    func writeLifecycle() throws {
        let envelope = try FamiliarToolResultEnvelope(
            canonicalModelJSON: #"{"created":true}"#,
            presentation: .mutationReceipt(.init(summary: "Event created", operation: "create", targetIdentifier: "event-1", succeeded: true, undoAvailable: true))
        )
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runPhaseChanged(.starting), turnID: nil))
        store.apply(event(1, .activityStarted(.init(id: "call-1", toolName: "create_calendar_event", effect: .reversibleWrite, startedAt: Date(timeIntervalSince1970: 1)))))
        store.apply(event(2, .activityCompleted(completion(toolName: "create_calendar_event", effect: .reversibleWrite))))
        store.apply(event(3, .toolResultProduced(result(toolName: "create_calendar_event", effect: .reversibleWrite, envelope: envelope))))

        let receipt = try #require(store.orderedSurfaces.first { $0.kind == .mutationReceipt })
        #expect(receipt.id == "tool:run-1:call-1")
        #expect(receipt.placement == .topLevel)
        #expect(receipt.phase == .succeeded)
        #expect(store.orderedSurfaces.filter { $0.id == receipt.id }.count == 1)
    }

    @Test("Typed approval remains an intervention until resolved")
    func approvalProjection() throws {
        let request = FamiliarToolConfirmationRequest(
            id: UUID(),
            runID: "run-1",
            toolCallID: "call-1",
            toolName: "create_reminder",
            effect: .reversibleWrite,
            risk: .sensitive,
            title: "Create reminder",
            fields: [.init(id: "title", label: "Title", type: .text, value: "Review")],
            target: "Reminders",
            consequence: "Creates one reminder",
            undoPolicy: .durable
        )
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runPhaseChanged(.starting), turnID: nil))
        store.apply(event(1, .approvalRequested(request)))

        let approval = try #require(store.orderedSurfaces.first { $0.kind == .approval })
        #expect(approval.phase == .awaitingApproval)
        #expect(approval.approvalFields.map(\.id) == ["title"])
        #expect(store.pendingApprovalIDs == [request.id])

        store.apply(event(2, .approvalResolved(requestID: request.id, decision: .confirmed)))
        let summary = try #require(store.orderedSurfaces.first { $0.id == approval.id })
        #expect(summary.kind == .toolSummary)
        #expect(summary.phase == .running)
        #expect(store.pendingApprovalIDs.isEmpty)
    }

    @Test("Date scalar is trace-only and never a top-level surface")
    func dateToolHasNoTopLevelSurface() throws {
        let envelope = try FamiliarToolResultEnvelope(
            canonicalModelJSON: #"{"date":"2026-08-21"}"#,
            presentation: .scalar(.init(summary: "Current date", label: "Date", value: "2026-08-21"))
        )
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .runPhaseChanged(.starting), turnID: nil))
        store.apply(event(1, .activityStarted(.init(id: "call-1", toolName: "current_date_time", effect: .read, startedAt: Date(timeIntervalSince1970: 1)))))
        store.apply(event(2, .activityCompleted(completion(toolName: "current_date_time", effect: .read))))
        store.apply(event(3, .toolResultProduced(result(toolName: "current_date_time", effect: .read, envelope: envelope))))

        let typed = try #require(store.orderedSurfaces.first { $0.kind == .context })
        #expect(typed.placement == .trace)
        #expect(store.orderedSurfaces.filter { $0.placement == .topLevel && $0.kind != .runStatus && $0.kind != .activityTrace }.isEmpty)
    }

    @Test("Structured surface policy keeps utility reads in trace and promotes content accessories")
    func structuredSurfacePolicy() throws {
        let payloads: [(String, FamiliarToolPresentationPayload, FamiliarSurfaceKind, FamiliarSurfacePlacement)] = [
            ("app_information", .scalar(.init(summary: "App", label: "Version", value: "1.0")), .context, .trace),
            ("web_search", .searchResults(.init(summary: "Search", query: "query", results: [])), .search, .trace),
            ("web_fetch", .document(.init(summary: "Page", title: "Page", text: "Body", url: "https://example.com")), .context, .trace),
            ("resource_search", .contextMatches(.init(summary: "Match", query: "body", matches: [.init(resourceID: UUID(), versionID: UUID(), version: 2, title: "Source", excerpt: "Body")])), .context, .topLevel),
            ("calendar_events", .recordCollection(.init(summary: "Events", recordType: "calendarEvent", records: [.init(id: "1", fields: [.init(name: "title", value: "Review")])])), .records, .topLevel),
            ("artifact_edit", .diff(.init(summary: "Changed", before: "old", after: "new")), .diff, .topLevel),
            ("typed_code", .code(.init(summary: "Example", language: "swift", filename: "Example.swift", code: "let value = 1")), .code, .topLevel)
        ]

        var store = FamiliarSurfaceStore()
        for (index, item) in payloads.enumerated() {
            let envelope = try FamiliarToolResultEnvelope(canonicalModelJSON: "{}", presentation: item.1)
            store.apply(event(index, .toolResultProduced(result(toolName: item.0, effect: .read, envelope: envelope, callID: "policy-\(index)"))))
        }

        for (index, item) in payloads.enumerated() {
            let surface = try #require(store.orderedSurfaces.first { $0.toolCallID == "policy-\(index)" })
            #expect(surface.kind == item.2)
            #expect(surface.placement == item.3)
        }
    }

    @Test("Structured accessories follow assistant Markdown and expose bounded detail actions")
    func structuredAccessoryStaticContracts() throws {
        let presentation = try source("Familiar/Presentation/FamiliarChatMessageViews.swift")
        let markdown = try source("Familiar/Presentation/FamiliarMarkdownWebView.swift")
        let renderer = try source("Familiar/Resources/FamiliarMarkdownRenderer/renderer.js")

        let bodyPosition = try #require(presentation.range(of: "FamiliarMarkdownWebView(markdown: message.content"))
        let accessoriesPosition = try #require(presentation.range(of: "ForEach(responseAccessoryItems)"))
        #expect(bodyPosition.lowerBound < accessoriesPosition.lowerBound)
        #expect(presentation.contains("surface.context.details"))
        #expect(presentation.contains("surface.records.details"))
        #expect(presentation.contains("surface.diff.details"))
        #expect(presentation.contains("surface.code.details"))
        #expect(presentation.contains("fullScreenCover(isPresented: $showsAllRecords)"))
        #expect(presentation.contains("fullScreenCover(isPresented: $showsDiff)"))
        #expect(presentation.contains("fullScreenCover(isPresented: $showsFullCode)"))
        #expect(presentation.contains("BarMark("))
        #expect(markdown.contains("mermaidPreviewMessageName = \"previewMermaid\""))
        #expect(markdown.contains("allowsMermaidPreview: false"))
        #expect(renderer.contains("post(\"previewMermaid\", source)"))
        #expect(renderer.contains("source.length > 320"))
        #expect(markdown.contains("connect-src 'none'"))
    }

    @Test("Persisted snapshots replay through the same projection")
    func historicalReplay() throws {
        let envelope = try FamiliarToolResultEnvelope(
            canonicalModelJSON: #"{"results":[]}"#,
            presentation: .searchResults(.init(summary: "2 results", query: "Familiar", results: []))
        )
        let activityID = "tool:history:search-1"
        let run = FamiliarAgentRunSnapshot(
            id: "history",
            responseMessageID: UUID(),
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 3),
            context: nil,
            activities: [.init(activityID: activityID, parentID: "turn:history", assistantTurnID: "history:turn:0", kind: .tool, effect: .read, phase: .succeeded, toolName: "web_search", toolCallID: "search-1", summary: "Search", detail: "Complete", progress: 1, resultRecordID: UUID(), approvalRecordID: nil, sequence: 1, startedAt: Date(timeIntervalSince1970: 1), endedAt: Date(timeIntervalSince1970: 2))],
            approvals: [],
            toolResults: [.init(id: UUID(), activityID: activityID, toolCallID: "search-1", envelope: envelope, envelopeJSON: "{}", schemaVersion: 1, payloadName: "searchResults", payloadHash: "hash", trust: .untrusted, truncated: false)],
            responseBlocks: []
        )

        let surfaces = FamiliarSurfaceStore.projectedSurfaces(for: run)
        #expect(surfaces.contains { $0.kind == .activityTrace })
        #expect(surfaces.contains { $0.kind == .search && $0.placement == .trace })
        #expect(!surfaces.contains { $0.kind == .search && $0.placement == .topLevel })
    }

    @Test("Failed run without an assistant message projects durable recovery")
    func failedRunRecovery() {
        let run = FamiliarAgentRunSnapshot(
            id: "failed-history",
            responseMessageID: nil,
            status: .failed,
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            context: nil,
            activities: [.init(activityID: "notice:failed-history:terminal", parentID: nil, assistantTurnID: "failed-history:runtime", kind: .runtimeNotice, effect: nil, phase: .failed, toolName: nil, toolCallID: nil, summary: "Run failed", detail: "Provider unavailable", progress: 1, resultRecordID: nil, approvalRecordID: nil, sequence: 1, startedAt: Date(timeIntervalSince1970: 1), endedAt: Date(timeIntervalSince1970: 2))],
            approvals: [],
            toolResults: [],
            responseBlocks: [.init(id: UUID(), assistantTurnID: "failed-history:runtime", messageID: nil, kind: .runtimeNotice, order: 0, state: .failed, content: "Provider unavailable", payloadJSON: "{}", schemaVersion: 1, startedAt: Date(timeIntervalSince1970: 1), endedAt: Date(timeIntervalSince1970: 2), contentHash: "hash")]
        )

        let failure = FamiliarSurfaceStore.projectedSurfaces(for: run).first { $0.kind == .failure }
        #expect(failure?.placement == .topLevel)
        #expect(failure?.detail == "Provider unavailable")
    }

    @Test("Task revisions replace one stable top-level surface")
    func taskRevisionProjection() throws {
        var store = FamiliarSurfaceStore()
        for (index, status) in [FamiliarToolPresentationPayload.TaskStatus.pending, .completed].enumerated() {
            let envelope = try FamiliarToolResultEnvelope(
                canonicalModelJSON: #"{"planID":"release"}"#,
                presentation: .taskList(.init(planID: "release", title: "Release", tasks: [.init(id: "build", title: "Build", status: status)]))
            )
            store.apply(event(index, .toolResultProduced(result(toolName: "task_plan", effect: .read, envelope: envelope, callID: "call-\(index)"))))
        }

        let plans = store.orderedSurfaces.filter { $0.kind == .taskList }
        #expect(plans.count == 1)
        #expect(plans.first?.id == "task-plan:run-1:release")
        if case .taskList(let plan) = plans.first?.resultEnvelope?.presentation.content {
            #expect(plan.tasks.first?.status == .completed)
        } else {
            Issue.record("Expected latest task plan")
        }
    }

    @Test("Recommendation and insight project as top-level typed surfaces")
    func beautifulResultProjection() throws {
        let recommendation = try FamiliarToolResultEnvelope(canonicalModelJSON: #"{"title":"Next"}"#, presentation: .recommendation(.init(title: "Next", explanation: "Verify", nextPrompt: "Verify", alternatives: [], confidenceLevel: .high)))
        let insight = try FamiliarToolResultEnvelope(canonicalModelJSON: #"{"title":"Latency"}"#, presentation: .insight(.init(title: "Latency", explanation: "Improved", metrics: [.init(label: "P95", value: 120, unit: "ms")])))
        var store = FamiliarSurfaceStore()
        store.apply(event(0, .toolResultProduced(result(toolName: "present_recommendation", effect: .read, envelope: recommendation, callID: "recommend"))))
        store.apply(event(1, .toolResultProduced(result(toolName: "present_insight", effect: .read, envelope: insight, callID: "insight"))))

        #expect(store.orderedSurfaces.contains { $0.kind == .recommendation && $0.placement == .topLevel })
        #expect(store.orderedSurfaces.contains { $0.kind == .insight && $0.placement == .topLevel })
    }

    @Test("Haptics mark approval, success, and failure boundaries")
    func haptics() {
        #expect(FamiliarHapticPolicy.feedback(from: .running, to: .awaitingApproval) == .warning)
        #expect(FamiliarHapticPolicy.feedback(from: .running, to: .succeeded) == .success)
        #expect(FamiliarHapticPolicy.feedback(from: .running, to: .failed) == .error)
        #expect(FamiliarHapticPolicy.feedback(from: .queued, to: .running) == nil)
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
