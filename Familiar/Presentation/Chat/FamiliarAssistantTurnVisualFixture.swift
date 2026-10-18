import Observation
import SwiftData
import SwiftUI
import UIKit

#if DEBUG
struct FamiliarAssistantTurnVisualFixture: View {
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var sendCount = 0

    @State private var runtimeDisclosure = FamiliarRuntimeDisclosureState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXL) {
                fixtureSection(String(localized: "visual.fixture.loading", defaultValue: "Loading"), id: "loading") {
                    HStack(spacing: FamiliarSpacing.small) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "runtime.ui.preparing_reply")).font(FamiliarTypography.caption).foregroundStyle(.secondary)
                    }
                }
                fixtureSection(String(localized: "visual.fixture.search", defaultValue: "Search"), id: "search") {
                    FamiliarTypedResult(surface: Self.searchSurface, readURLs: ["https://example.com/read"])
                }
                fixtureSection(String(localized: "visual.fixture.tool_results", defaultValue: "Tool results"), id: "tool-results") {
                    ForEach(FamiliarAssistantResponseProjection.blocks(text: [], surfaces: Self.executionSurfaces)) { block in
                        switch block {
                        case .runtime(let activity): FamiliarRuntimeCard(activity: activity, disclosure: runtimeDisclosure)
                        case .surface(let surface): turnSurface(surface)
                        case .text: EmptyView()
                        }
                    }
                }
                fixtureSection(String(localized: "runtime.ui.running"), id: "runtime-running") {
                    FamiliarRuntimeCard(activity: .init(activities: [Self.fixtureActivity("running", tool: "web_fetch", sequence: 1, phase: .running)], notices: []), disclosure: runtimeDisclosure)
                }
                fixtureSection(String(localized: "runtime.ui.stopped"), id: "runtime-stopped") {
                    FamiliarRuntimeCard(activity: .init(activities: [Self.fixtureActivity("stopped", tool: "web_fetch", sequence: 1, phase: .cancelled)], notices: []), disclosure: runtimeDisclosure)
                }
                fixtureSection(String(localized: "visual.fixture.approval", defaultValue: "Approval"), id: "approval") {
                    turnSurface(Self.approvalSurface)
                }
                fixtureSection(String(localized: "visual.fixture.clarification", defaultValue: "Clarification"), id: "clarification") {
                    turnSurface(Self.clarificationSurface)
                }
                fixtureSection(String(localized: "visual.fixture.receipt", defaultValue: "Receipt"), id: "receipt") {
                    turnSurface(Self.receiptSurface)
                }
                fixtureSection(String(localized: "visual.fixture.failure", defaultValue: "Failure"), id: "failure") {
                    turnSurface(Self.failureSurface)
                }
                fixtureSection(String(localized: "visual.fixture.selection", defaultValue: "Selection"), id: "selection") {
                    FamiliarSelectionActions(selection: String(localized: "visual.fixture.selection.quote", defaultValue: "The selected fixture passage.")) { draft = $0 }
                    TextField(String(localized: "composer.placeholder"), text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("visual-fixture.composer")
                    Text(sendCount, format: .number)
                        .font(.caption2.monospaced())
                        .foregroundStyle(FamiliarTheme.inkTertiary)
                        .accessibilityIdentifier("visual-fixture.send-count")
                        .accessibilityLabel(String(localized: "visual.fixture.send_count", defaultValue: "Send count"))
                        .accessibilityValue(Text(sendCount, format: .number))
                }
                fixtureSection(String(localized: "visual.fixture.sources", defaultValue: "Sources"), id: "sources") {
                    FamiliarAssistantFooter(
                        message: Self.sourceMessage,
                        onRetryMessage: {},
                        onInsertPrompt: { draft = $0 }
                    )
                }
            }
            .padding(FamiliarAISurfaceMetric.spaceL)
            .frame(maxWidth: FamiliarAISurfaceMetric.timelineWidth)
            .frame(maxWidth: .infinity)
        }
        .background(FamiliarTheme.page)
        .navigationTitle(String(localized: "visual.fixture.title", defaultValue: "Assistant Turn Fixture"))
    }

    private func fixtureSection<Content: View>(_ title: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(FamiliarTheme.inkTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("visual-fixture.\(id)")
    }

    private func turnSurface(_ surface: FamiliarSurfaceDescriptor) -> some View {
        FamiliarTurnSurface(
            surface: surface,
            canUndo: surface.kind == .mutationReceipt,
            onUndo: {},
            onRetry: {}
        )
    }

    private static let searchSurface = FamiliarSurfaceDescriptor(
        id: "fixture-search",
        runID: "fixture",
        kind: .search,
        placement: .trace,
        phase: .succeeded,
        title: String(localized: "tool.web_search", defaultValue: "Web search"),
        resultEnvelope: envelope(.searchResults(.init(
            summary: String(localized: "visual.fixture.search.summary", defaultValue: "3 results"),
            query: String(localized: "visual.fixture.search.query", defaultValue: "native AI interface patterns"),
            results: [
                .init(id: "read", title: String(localized: "visual.fixture.search.read_result", defaultValue: "Read result"), url: "https://example.com/read", snippet: nil),
                .init(id: "one", title: String(localized: "visual.fixture.search.found_result", defaultValue: "Found result"), url: "https://example.org/one", snippet: nil),
                .init(id: "two", title: String(localized: "visual.fixture.search.another_result", defaultValue: "Another result"), url: "https://example.net/two", snippet: nil)
            ]
        )))
    )

    private static let approvalSurface = FamiliarSurfaceDescriptor(
        id: "fixture-approval",
        runID: "fixture",
        kind: .approval,
        placement: .topLevel,
        phase: .awaitingApproval,
        title: String(localized: "visual.fixture.approval.title", defaultValue: "Create reminder"),
        approvalRequestID: UUID(),
        approvalFields: [.init(id: "title", label: String(localized: "eventkit.field.title", defaultValue: "Title"), type: .text, value: String(localized: "visual.fixture.approval.value", defaultValue: "Review the release"))],
        approvalTarget: String(localized: "settings.permissions.reminders", defaultValue: "Reminders"),
        approvalRisk: .sensitive,
        approvalConsequence: String(localized: "visual.fixture.approval.consequence", defaultValue: "Creates one reminder on this iPhone."),
        approvalUndoPolicy: .durable
    )

    private static let executionSurfaces: [FamiliarSurfaceDescriptor] = {
        let first = envelope(.searchResults(.init(summary: "Results", query: "SwiftUI", results: [
            .init(id: "apple", title: "SwiftUI", url: "https://developer.apple.com/documentation/swiftui", snippet: nil),
            .init(id: "swift", title: "Swift", url: "https://www.swift.org/documentation/", snippet: nil)
        ])))
        let second = envelope(.searchResults(.init(summary: "Results", query: "SwiftUI state", results: [
            .init(id: "apple", title: "SwiftUI", url: "https://developer.apple.com/documentation/swiftui", snippet: nil)
        ])))
        return [
            fixtureActivity("load", tool: "tools_load", sequence: 1, payload: envelope(.scalar(.init(summary: "Ready", value: "Web")))),
            fixtureActivity("search-1", tool: "web_search", sequence: 2, payload: first),
            fixtureActivity("search-2", tool: "web_search", sequence: 3, payload: second),
            fixtureActivity("failed-1", tool: "web_fetch", sequence: 4, phase: .failed),
            fixtureActivity("failed-2", tool: "web_fetch", sequence: 5, phase: .failed),
            fixtureActivity("read", tool: "web_fetch", sequence: 6, payload: envelope(.document(.init(
                summary: "Read source", title: "SwiftUI", text: "SwiftUI helps you build interfaces across Apple platforms.",
                url: "https://developer.apple.com/documentation/swiftui")))),
            FamiliarSurfaceDescriptor(id: "fixture-receipt", runID: "fixture", sequence: 7, kind: .mutationReceipt,
                placement: .topLevel, phase: .succeeded, title: String(localized: "visual.fixture.receipt.title"),
                toolCallID: "write", toolName: "create_reminder", effect: .reversibleWrite,
                resultEnvelope: envelope(.mutationReceipt(.init(summary: "Saved", operation: "create", targetIdentifier: nil, succeeded: true, undoAvailable: true))))
        ]
    }()

    private static func fixtureActivity(_ id: String, tool: String, sequence: Int,
                                        phase: FamiliarSurfacePhase = .succeeded,
                                        payload: FamiliarToolResultEnvelope? = nil) -> FamiliarSurfaceDescriptor {
        FamiliarSurfaceDescriptor(id: "tool:fixture:\(id)", runID: "fixture", sequence: sequence,
            assistantTurnID: "fixture:turn:0", kind: .toolSummary, placement: .trace, phase: phase,
            title: FamiliarToolPresentationName.title(for: tool), detail: phase == .failed ? "Fixture timeout" : nil,
            failureCode: phase == .failed ? "timeout" : nil, toolCallID: id, toolName: tool, effect: .read,
            resultEnvelope: payload)
    }

    private static let clarificationSurface = FamiliarSurfaceDescriptor(
        id: "fixture-clarification",
        runID: "fixture",
        kind: .clarification,
        placement: .topLevel,
        phase: .awaitingClarification,
        title: String(localized: "visual.fixture.clarification.question", defaultValue: "Which version should I use?"),
        clarificationRequestID: UUID(),
        clarificationOptions: [
            .init(id: "short", label: String(localized: "visual.fixture.clarification.short", defaultValue: "Short version")),
            .init(id: "full", label: String(localized: "visual.fixture.clarification.full", defaultValue: "Full version"))
        ],
        clarificationAllowsCustom: true
    )

    private static let receiptSurface = FamiliarSurfaceDescriptor(
        id: "fixture-receipt",
        runID: "fixture",
        kind: .mutationReceipt,
        placement: .topLevel,
        phase: .succeeded,
        title: String(localized: "visual.fixture.receipt.title", defaultValue: "Reminder created"),
        toolCallID: "receipt",
        toolName: "create_reminder",
        effect: .reversibleWrite,
        resultEnvelope: envelope(.mutationReceipt(.init(summary: String(localized: "visual.fixture.receipt.title", defaultValue: "Reminder created"), operation: String(localized: "common.create", defaultValue: "Create"), targetIdentifier: "fixture-reminder", succeeded: true, undoAvailable: true)))
    )

    private static let failureSurface = FamiliarSurfaceDescriptor(
        id: "fixture-failure",
        runID: "fixture",
        kind: .failure,
        placement: .topLevel,
        phase: .failed,
        title: String(localized: "settings.runs.failed", defaultValue: "Failed"),
        detail: String(localized: "visual.fixture.failure.detail", defaultValue: "The provider request timed out before a response arrived.")
    )

    private static let sources = [
        FamiliarSource(id: "fixture-apple", kind: .fetchedPage, title: String(localized: "visual.fixture.source.read", defaultValue: "Read source fixture"), url: URL(string: "https://developer.apple.com/documentation/swiftui")!, siteName: "Apple Developer", snippet: nil, retrievedAt: Date()),
        FamiliarSource(id: "fixture-swift", kind: .searchResult, title: String(localized: "visual.fixture.source.discovered", defaultValue: "Discovered source fixture"), url: URL(string: "https://www.swift.org/documentation/")!, siteName: "Swift.org", snippet: nil, retrievedAt: Date()),
        FamiliarSource(id: "fixture-webkit", kind: .searchResult, title: "WebKit", url: URL(string: "https://webkit.org/")!, siteName: "WebKit", snippet: nil, retrievedAt: Date())
    ]

    private static let sourceMessage = FamiliarMessageSnapshot(
        id: UUID(),
        role: .assistant,
        content: String(localized: "visual.fixture.reasoning.detail", defaultValue: "Compared the request with the available context and checked the important constraints."),
        createdAt: Date(),
        sequence: 0,
        providerID: "deepseek",
        modelID: "deepseek-v4-flash",
        attachments: [],
        sources: sources
    )

    private static func resultSurface(id: String, kind: FamiliarSurfaceKind, payload: FamiliarToolPresentationPayload) -> FamiliarSurfaceDescriptor {
        FamiliarSurfaceDescriptor(
            id: id,
            runID: "fixture",
            kind: kind,
            placement: .topLevel,
            phase: .succeeded,
            title: payload.summary,
            resultEnvelope: envelope(payload)
        )
    }

    private static func envelope(_ payload: FamiliarToolPresentationPayload) -> FamiliarToolResultEnvelope {
        try! FamiliarToolResultEnvelope(canonicalModelJSON: "{}", presentation: payload)
    }
}

#Preview("Assistant Turn Fixture - Light") {
    NavigationStack { FamiliarAssistantTurnVisualFixture() }
        .preferredColorScheme(.light)
}

#Preview("Assistant Turn Fixture - Dark") {
    NavigationStack { FamiliarAssistantTurnVisualFixture() }
        .preferredColorScheme(.dark)
}
#endif
