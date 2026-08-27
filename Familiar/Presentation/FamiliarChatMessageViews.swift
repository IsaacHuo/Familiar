import Charts
import SwiftUI
import UIKit

private struct FamiliarReplyMetrics: Equatable {
    let startedAt: Date?
    let finishedAt: Date?
    let firstTokenAt: Date?

    var duration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return max(0, finishedAt.timeIntervalSince(startedAt))
    }
    var timeToFirstToken: TimeInterval? {
        guard let startedAt, let firstTokenAt else { return nil }
        return max(0, firstTokenAt.timeIntervalSince(startedAt))
    }
}

struct FamiliarMessageTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let messages: [FamiliarMessageSnapshot]
    let modelSwitches: [FamiliarModelSwitchSnapshot]
    let agentRuns: [FamiliarAgentRunSnapshot]
    let surfaces: [FamiliarSurfaceDescriptor]
    let streamingMessageID: UUID?
    let streamingText: String
    let streamingReasoningSummary: String
    let availableUndoKeys: Set<String>
    let completedUndoKeys: Set<String>
    let onResolveConfirmation: (UUID, FamiliarToolConfirmationDecision) -> Void
    let onResolveClarification: (UUID, FamiliarClarificationResolution) -> Void
    let onInsertPrompt: (String) -> Void
    let onUndo: (String, String) -> Void
    let onEdit: (FamiliarMessageSnapshot) -> Void
    let onRetry: (FamiliarMessageSnapshot) -> Void
    let onRetryRecovery: (String) -> Void

    @State private var isFollowingLatest = true
    @AccessibilityFocusState private var focusedConfirmationID: UUID?

    private var pendingApprovalIDs: [UUID] {
        surfaces.compactMap { $0.phase == .awaitingApproval ? $0.approvalRequestID : nil }
    }

    private var timelineItems: [FamiliarTimelineItem] {
        var items = messages.map(FamiliarTimelineItem.message)
        items += modelSwitches.map(FamiliarTimelineItem.modelSwitch)
        items += agentRuns
            .filter { $0.responseMessageID == nil && ($0.status == .failed || $0.status == .cancelled) }
            .map(FamiliarTimelineItem.recovery)
        return items.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: FamiliarAISurfaceMetric.spaceXL) {
                        ForEach(timelineItems) { item in
                            switch item {
                            case .message(let message):
                                FamiliarMessageRow(
                                    message: message,
                                    run: agentRuns.first { $0.responseMessageID == message.id },
                                    availableUndoKeys: availableUndoKeys,
                                    completedUndoKeys: completedUndoKeys,
                                    onResolveApproval: onResolveConfirmation,
                                    onResolveClarification: onResolveClarification,
                                    onInsertPrompt: onInsertPrompt,
                                    onUndo: onUndo,
                                    onEdit: onEdit,
                                    onRetry: onRetry,
                                    onRetryRecovery: onRetryRecovery
                                )
                                .id(item.id)
                            case .modelSwitch(let marker):
                                FamiliarModelSwitchRow(marker: marker)
                                    .id(item.id)
                            case .recovery(let run):
                                FamiliarAssistantTurn(
                                    message: nil,
                                    run: run,
                                    surfaces: FamiliarSurfaceStore.projectedSurfaces(for: run),
                                    streamingText: "",
                                    streamingReasoningSummary: "",
                                    availableUndoKeys: availableUndoKeys,
                                    completedUndoKeys: completedUndoKeys,
                                    onResolveApproval: onResolveConfirmation,
                                    onResolveClarification: onResolveClarification,
                                    onInsertPrompt: onInsertPrompt,
                                    onUndo: onUndo,
                                    onRetryRecovery: onRetryRecovery
                                )
                                .id(item.id)
                            }
                        }

                        if !surfaces.isEmpty || !streamingText.isEmpty || !streamingReasoningSummary.isEmpty {
                            FamiliarAssistantTurn(
                                message: nil,
                                run: nil,
                                surfaces: surfaces,
                                streamingText: streamingText,
                                streamingReasoningSummary: streamingReasoningSummary,
                                availableUndoKeys: availableUndoKeys,
                                completedUndoKeys: completedUndoKeys,
                                onResolveApproval: onResolveConfirmation,
                                onResolveClarification: onResolveClarification,
                                onInsertPrompt: onInsertPrompt,
                                onUndo: onUndo,
                                onRetryRecovery: onRetryRecovery
                            )
                            .id(streamingMessageID?.uuidString ?? "active-assistant-turn")
                        }

                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: FamiliarBottomPositionPreferenceKey.self,
                                value: geometry.frame(in: .named("conversation-scroll")).maxY
                            )
                        }
                        .frame(height: FamiliarAISurfaceMetric.hairline)
                        .id("conversation-bottom")
                    }
                    .padding(.horizontal, FamiliarAISurfaceMetric.spaceL)
                    .padding(.top, FamiliarAISurfaceMetric.spaceL)
                    .padding(.bottom, FamiliarAISurfaceMetric.spaceM)
                    .frame(maxWidth: FamiliarAISurfaceMetric.timelineWidth)
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "conversation-scroll")
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(FamiliarBottomPositionPreferenceKey.self) { bottomY in
                    isFollowingLatest = bottomY <= viewport.size.height + 120
                }
                .onChange(of: messages.count) { _, _ in scrollToLatest(proxy) }
                .onChange(of: streamingText) { _, _ in scrollToLatest(proxy, animated: false) }
                .onChange(of: streamingReasoningSummary) { _, _ in scrollToLatest(proxy, animated: false) }
                .onChange(of: surfaces) { _, _ in scrollToLatest(proxy) }
                .onChange(of: pendingApprovalIDs) { previous, current in
                    focusedConfirmationID = current.first { !previous.contains($0) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isFollowingLatest {
                        Button {
                            isFollowingLatest = true
                            scrollToLatest(proxy)
                        } label: {
                            Image(systemName: "arrow.down")
                                .frame(width: FamiliarAISurfaceMetric.rowHeight, height: FamiliarAISurfaceMetric.rowHeight)
                        }
                        .buttonStyle(.plain)
                        .familiarGlassCircle(interactive: true)
                        .padding(FamiliarAISurfaceMetric.spaceL)
                        .accessibilityLabel(String(localized: "conversation.scroll_latest"))
                    }
                }
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard isFollowingLatest else { return }
        if animated && !reduceMotion {
            withAnimation(FamiliarMotion.response) {
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("conversation-bottom", anchor: .bottom)
        }
    }
}

private enum FamiliarTimelineItem: Identifiable {
    case message(FamiliarMessageSnapshot)
    case modelSwitch(FamiliarModelSwitchSnapshot)
    case recovery(FamiliarAgentRunSnapshot)

    var id: String {
        switch self {
        case .message(let message): "message:\(message.id.uuidString)"
        case .modelSwitch(let marker): "model-switch:\(marker.id.uuidString)"
        case .recovery(let run): "recovery:\(run.id)"
        }
    }

    var createdAt: Date {
        switch self {
        case .message(let message): message.createdAt
        case .modelSwitch(let marker): marker.createdAt
        case .recovery(let run): run.finishedAt ?? run.startedAt
        }
    }
}

private struct FamiliarMessageRow: View {
    let message: FamiliarMessageSnapshot
    let run: FamiliarAgentRunSnapshot?
    let availableUndoKeys: Set<String>
    let completedUndoKeys: Set<String>
    let onResolveApproval: (UUID, FamiliarToolConfirmationDecision) -> Void
    let onResolveClarification: (UUID, FamiliarClarificationResolution) -> Void
    let onInsertPrompt: (String) -> Void
    let onUndo: (String, String) -> Void
    let onEdit: (FamiliarMessageSnapshot) -> Void
    let onRetry: (FamiliarMessageSnapshot) -> Void
    let onRetryRecovery: (String) -> Void

    @State private var previewAttachment: FamiliarAttachmentSnapshot?

    var body: some View {
        Group {
            if message.role == .user {
                userMessage
            } else {
                FamiliarAssistantTurn(
                    message: message,
                    run: run,
                    surfaces: run.map(FamiliarSurfaceStore.projectedSurfaces) ?? [],
                    streamingText: "",
                    streamingReasoningSummary: "",
                    availableUndoKeys: availableUndoKeys,
                    completedUndoKeys: completedUndoKeys,
                    onResolveApproval: onResolveApproval,
                    onResolveClarification: onResolveClarification,
                    onInsertPrompt: onInsertPrompt,
                    onUndo: onUndo,
                    onRetryRecovery: onRetryRecovery,
                    onRetryMessage: { onRetry(message) }
                )
            }
        }
        .sheet(item: $previewAttachment) { attachment in
            if let url = FamiliarAttachmentStore.url(for: attachment.relativePath) {
                FamiliarAttachmentQuickLookView(url: url).ignoresSafeArea()
            } else {
                ContentUnavailableView(
                    String(localized: "attachment.unavailable.title"),
                    systemImage: "doc.badge.ellipsis",
                    description: Text(String(localized: "attachment.unavailable.detail"))
                )
            }
        }
    }

    private var userMessage: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: FamiliarAISurfaceMetric.rowHeight)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
                ForEach(message.attachments) { attachment in
                    Button { previewAttachment = attachment } label: {
                        if attachment.kind == .image {
                            FamiliarImageAttachmentView(relativePath: attachment.relativePath)
                        } else {
                            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                                Image(systemName: attachment.mimeType == "application/pdf" ? "doc.richtext" : "doc.text")
                                    .foregroundStyle(FamiliarAISurfaceColor.accent)
                                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                                    Text(attachment.filename).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Text("\(attachment.detectedFormat.uppercased()) · \(ByteCountFormatter.string(fromByteCount: attachment.byteSize, countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: String(localized: "attachment.preview"), attachment.filename))
                }
                if !message.content.isEmpty {
                    Text(message.content).font(.body).textSelection(.enabled)
                }
            }
            .padding(FamiliarAISurfaceMetric.spaceM)
            .background(FamiliarTheme.userFill, in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.window, style: .continuous))
            .contextMenu {
                if !message.content.isEmpty {
                    Button { UIPasteboard.general.string = message.content } label: {
                        Label(String(localized: "common.copy"), systemImage: "doc.on.doc")
                    }
                }
                Button { onEdit(message) } label: {
                    Label(String(localized: "common.edit"), systemImage: "pencil")
                }
            }
        }
    }
}

private struct FamiliarAssistantTurn: View {
    let message: FamiliarMessageSnapshot?
    let run: FamiliarAgentRunSnapshot?
    let surfaces: [FamiliarSurfaceDescriptor]
    let streamingText: String
    let streamingReasoningSummary: String
    let availableUndoKeys: Set<String>
    let completedUndoKeys: Set<String>
    let onResolveApproval: (UUID, FamiliarToolConfirmationDecision) -> Void
    let onResolveClarification: (UUID, FamiliarClarificationResolution) -> Void
    let onInsertPrompt: (String) -> Void
    let onUndo: (String, String) -> Void
    let onRetryRecovery: (String) -> Void
    var onRetryMessage: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var runID: String? { run?.id ?? surfaces.first?.runID }
    private var status: FamiliarSurfaceDescriptor? { surfaces.first { $0.kind == .runStatus } }
    private var trace: FamiliarSurfaceDescriptor? { surfaces.first { $0.kind == .activityTrace } }
    private var traceItems: [FamiliarSurfaceDescriptor] { surfaces.filter { $0.placement == .trace } }
    private var interventionItems: [FamiliarSurfaceDescriptor] {
        surfaces.filter { $0.placement == .topLevel && $0.kind != .runStatus && $0.kind != .activityTrace }
            .filter { $0.kind == .approval || $0.kind == .clarification || $0.kind == .failure }
    }
    private var responseAccessoryItems: [FamiliarSurfaceDescriptor] {
        surfaces.filter { $0.placement == .topLevel && $0.kind != .runStatus && $0.kind != .activityTrace }
            .filter { $0.kind != .approval && $0.kind != .clarification && $0.kind != .failure }
    }
    private var reasoningSummary: String? {
        let value = streamingReasoningSummary.isEmpty
            ? message?.responseBlocks.first(where: { $0.kind == .reasoningSummary })?.content ?? ""
            : streamingReasoningSummary
        return value.isEmpty ? nil : value
    }

    private var searchSurfaces: [FamiliarSurfaceDescriptor] { surfaces.filter { $0.kind == .search } }
    private var toolSurfaces: [FamiliarSurfaceDescriptor] {
        surfaces.filter {
            ($0.kind == .toolSummary || $0.kind == .activityTrace)
                && ($0.placement == .trace || $0.toolName != nil)
        }
    }
    private var taskSurfaces: [FamiliarSurfaceDescriptor] { surfaces.filter { $0.kind == .taskList } }
    private var hasThinkingContent: Bool {
        reasoningSummary != nil || !searchSurfaces.isEmpty || !toolSurfaces.isEmpty || !taskSurfaces.isEmpty
    }

    private func thinkingContent(status: FamiliarSurfaceDescriptor) -> FamiliarThinkingContent {
        let isWorking = !status.phase.isTerminal
        if let reasoning = reasoningSummary, !reasoning.isEmpty {
            let lines = reasoning.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return FamiliarThinkingContent(
                variant: .reasoning,
                isWorking: isWorking,
                header: status.title,
                settledHeader: thoughtFor(status),
                query: nil,
                rows: lines.enumerated().map { index, line in
                    FamiliarThinkingRow(
                        id: "reasoning-\(index)",
                        primary: line,
                        secondary: nil,
                        mono: false,
                        add: nil,
                        del: nil,
                        href: nil,
                        tone: .accent,
                        phase: .succeeded
                    )
                },
                truncatedCount: 0
            )
        }

        if let search = searchSurfaces.first, let searchContent = searchPayload(search), !searchContent.results.isEmpty {
            let shown = Array(searchContent.results.prefix(4))
            let rows = shown.enumerated().map { index, result in
                FamiliarThinkingRow(
                    id: "search-\(result.id)-\(index)",
                    primary: result.title,
                    secondary: hostname(result.url),
                    mono: false,
                    add: nil,
                    del: nil,
                    href: result.url,
                    tone: [FamiliarThinkingTone.accent, .orange, .green][index % 3],
                    phase: .succeeded
                )
            }
            return FamiliarThinkingContent(
                variant: .search,
                isWorking: isWorking,
                header: status.title,
                settledHeader: String(localized: "agent.status.searched_web", defaultValue: "Searched the web"),
                query: searchContent.query,
                rows: rows,
                truncatedCount: max(0, searchContent.results.count - shown.count)
            )
        }

        if !toolSurfaces.isEmpty {
            return FamiliarThinkingContent(
                variant: .coding,
                isWorking: isWorking,
                header: status.title,
                settledHeader: String(format: String(localized: "agent.status.ran_tools", defaultValue: "Ran %lld tools"), toolSurfaces.count),
                query: nil,
                rows: toolSurfaces.map { activity in
                    FamiliarThinkingRow(
                        id: activity.id,
                        primary: activity.title,
                        secondary: activity.detail ?? activity.toolName,
                        mono: true,
                        add: nil,
                        del: nil,
                        href: nil,
                        tone: .accent,
                        phase: surfacePhase(activity.phase)
                    )
                },
                truncatedCount: 0
            )
        }

        return FamiliarThinkingContent(
            variant: .steps,
            isWorking: isWorking,
            header: status.title,
            settledHeader: thoughtFor(status),
            query: nil,
            rows: taskSurfaces.flatMap(taskRows),
            truncatedCount: 0
        )
    }

    private func thoughtFor(_ surface: FamiliarSurfaceDescriptor) -> String {
        String(format: String(localized: "agent.status.thought_for", defaultValue: "Thought for %.1f s"), duration(surface))
    }

    private func duration(_ surface: FamiliarSurfaceDescriptor) -> Double {
        guard let start = surface.startedAt else { return 0 }
        let end = surface.finishedAt ?? surface.startedAt.map { _ in Date() } ?? start
        return max(0, end.timeIntervalSince(start))
    }

    private func surfacePhase(_ phase: FamiliarSurfacePhase) -> FamiliarSurfacePhase {
        switch phase {
        case .queued, .planning, .running, .awaitingApproval, .awaitingClarification: phase
        default: .succeeded
        }
    }

    private func taskRows(_ surface: FamiliarSurfaceDescriptor) -> [FamiliarThinkingRow] {
        guard case .taskList(let list)? = surface.resultEnvelope?.presentation.content else { return [] }
        return list.tasks.map { task in
            FamiliarThinkingRow(
                id: task.id,
                primary: task.title,
                secondary: task.detail,
                mono: false,
                add: nil,
                del: nil,
                href: nil,
                tone: .accent,
                phase: taskPhase(task.status)
            )
        }
    }

    private func taskPhase(_ status: FamiliarToolPresentationPayload.TaskStatus) -> FamiliarSurfacePhase {
        switch status {
        case .completed: .succeeded
        case .running: .running
        case .pending, .failed: .queued
        }
    }

    private func searchPayload(_ surface: FamiliarSurfaceDescriptor) -> FamiliarToolPresentationPayload.SearchResults? {
        if case .searchResults(let search)? = surface.resultEnvelope?.presentation.content { return search }
        return nil
    }

    private func hostname(_ url: String) -> String {
        guard let components = URLComponents(string: url), let host = components.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var replyMetrics: FamiliarReplyMetrics? {
        guard let startedAt = run?.startedAt ?? status?.startedAt else { return nil }
        return FamiliarReplyMetrics(
            startedAt: startedAt,
            finishedAt: run?.finishedAt ?? status?.finishedAt,
            firstTokenAt: run?.firstTokenAt
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
            if let status, (!status.phase.isTerminal || hasThinkingContent) {
                FamiliarThinkingState(
                    content: thinkingContent(status: status),
                    onSettled: nil,
                    reduceMotion: reduceMotion
                )
            }

            ForEach(interventionItems) { surface in
                FamiliarTurnSurface(
                    surface: adjustedUndoPhase(surface),
                    canUndo: canUndo(surface),
                    onResolveApproval: onResolveApproval,
                    onResolveClarification: onResolveClarification,
                    onInsertPrompt: onInsertPrompt,
                    onUndo: { onUndo(surface.runID, surface.toolCallID ?? "") },
                    onRetry: surface.kind == .failure ? retryAction : nil
                )
            }

            if !streamingText.isEmpty {
                FamiliarMarkdownWebView(
                    markdown: streamingText,
                    sources: [],
                    isStreaming: true
                )
            } else if let message, !message.content.isEmpty {
                FamiliarMarkdownWebView(markdown: message.content, sources: message.sources)
            }

            ForEach(responseAccessoryItems) { surface in
                FamiliarTurnSurface(
                    surface: adjustedUndoPhase(surface),
                    canUndo: canUndo(surface),
                    onResolveApproval: onResolveApproval,
                    onResolveClarification: onResolveClarification,
                    onInsertPrompt: onInsertPrompt,
                    onUndo: { onUndo(surface.runID, surface.toolCallID ?? "") },
                    onRetry: nil
                )
            }

            if let message, !message.sources.isEmpty {
                FamiliarInlineSources(sources: message.sources)
            }

            if let trace, trace.context != nil || !traceItems.isEmpty {
                FamiliarActivityTrace(
                    surface: trace,
                    items: traceItems,
                    finishedAt: run?.finishedAt,
                    metrics: replyMetrics
                )
            }

            if let message {
                assistantActions(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adjustedUndoPhase(_ surface: FamiliarSurfaceDescriptor) -> FamiliarSurfaceDescriptor {
        guard let toolCallID = surface.toolCallID,
              completedUndoKeys.contains(surface.runID + ":" + toolCallID)
        else { return surface }
        var value = surface
        value.phase = .undone
        return value
    }

    private func canUndo(_ surface: FamiliarSurfaceDescriptor) -> Bool {
        guard let toolCallID = surface.toolCallID else { return false }
        return availableUndoKeys.contains(surface.runID + ":" + toolCallID)
    }

    private var retryAction: (() -> Void)? {
        guard let runID else { return nil }
        return { onRetryRecovery(runID) }
    }

    private func assistantActions(_ message: FamiliarMessageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
            if let providerID = message.providerID, let modelID = message.modelID {
                Text(sourceLabel(providerID: providerID, modelID: modelID))
                    .font(.caption2)
                    .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
            }
            HStack(spacing: 0) {
                FamiliarMessageAction(symbol: "doc.on.doc", label: String(localized: "common.copy")) {
                    UIPasteboard.general.string = message.content
                }
                ShareLink(item: message.content) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: FamiliarAISurfaceMetric.rowHeight, height: FamiliarAISurfaceMetric.rowHeight, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "common.share"))
                if let onRetryMessage {
                    FamiliarMessageAction(symbol: "arrow.clockwise", label: String(localized: "message.retry"), action: onRetryMessage)
                }
            }
            .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
        }
    }

    private func sourceLabel(providerID: String, modelID: String) -> String {
        let provider = FamiliarProviderCatalog.descriptor(for: providerID)
        return "\(provider?.displayName ?? providerID) · \(provider?.model(for: modelID).displayName ?? modelID)"
    }
}

private struct FamiliarShimmerLabel: View {
    let text: String
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FamiliarAISurfaceColor.ink)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let cycle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [FamiliarAISurfaceColor.inkSecondary, FamiliarAISurfaceColor.ink, FamiliarAISurfaceColor.inkSecondary],
                            startPoint: UnitPoint(x: CGFloat(cycle * 2 - 1), y: 0.5),
                            endPoint: UnitPoint(x: CGFloat(cycle * 2), y: 0.5)
                        )
                    )
            }
        }
    }
}

enum FamiliarThinkingVariant: Equatable {
    case steps, reasoning, search, coding
}

enum FamiliarThinkingTone {
    case accent, orange, green
}

struct FamiliarThinkingRow: Identifiable {
    let id: String
    let primary: String
    let secondary: String?
    let mono: Bool
    let add: Int?
    let del: Int?
    let href: String?
    let tone: FamiliarThinkingTone
    let phase: FamiliarSurfacePhase
}

struct FamiliarThinkingContent {
    let variant: FamiliarThinkingVariant
    let isWorking: Bool
    let header: String
    let settledHeader: String
    let query: String?
    let rows: [FamiliarThinkingRow]
    let truncatedCount: Int
}

private struct FamiliarThinkingState: View {
    let content: FamiliarThinkingContent
    let onSettled: (() -> Void)?
    let reduceMotion: Bool

    @State private var manualExpanded: Bool?
    @State private var hasSettled = false

    private var autoExpanded: Bool { content.isWorking }
    private var expanded: Bool { manualExpanded ?? autoExpanded }
    private var settled: Bool { !content.isWorking }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded },
            set: { manualExpanded = $0 }
        )) {
            traceBody
                .padding(.top, FamiliarAISurfaceMetric.spaceXS)
                .padding(.leading, FamiliarAISurfaceMetric.traceIndent)
        } label: {
            header
        }
        .tint(FamiliarAISurfaceColor.inkSecondary)
        .onChange(of: content.isWorking) { _, working in
            if !working, !hasSettled {
                hasSettled = true
                onSettled?()
            }
        }
    }

    private var header: some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(settled ? FamiliarAISurfaceColor.inkTertiary : FamiliarAISurfaceColor.ink)
            if settled {
                Text(content.settledHeader)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
            } else {
                FamiliarShimmerLabel(text: content.header, reduceMotion: reduceMotion)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .animation(FamiliarMotion.micro, value: expanded)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.isWorking ? content.header : content.settledHeader)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }

    @ViewBuilder
    private var traceBody: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
            if let query = content.query { queryRow(query) }
            ForEach(Array(content.rows.enumerated()), id: \.element.id) { index, row in
                rowView(row, index: index)
            }
            if content.truncatedCount > 0 {
                Text(String(format: String(localized: "search.more", defaultValue: "+%lld more"), content.truncatedCount))
                    .font(.caption)
                    .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
    }

    private func queryRow(_ query: String) -> some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
            Text(query)
                .font(.caption)
                .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                .lineLimit(1)
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private func rowView(_ row: FamiliarThinkingRow, index: Int) -> some View {
        switch content.variant {
        case .reasoning:
            FamiliarThinkingRowView(row: row, index: index) { _ in
                Text(row.primary)
                    .font(.callout)
                    .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .search:
            FamiliarThinkingRowView(row: row, index: index, isLink: row.href != nil) { _ in
                FamiliarThinkingDot(color: toneColor(row.tone))
                Text(row.primary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FamiliarAISurfaceColor.ink)
                    .lineLimit(1)
                if let secondary = row.secondary {
                    Text(secondary)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                        .lineLimit(1)
                }
            }
        case .steps:
            FamiliarThinkingRowView(row: row, index: index) { _ in
                if row.phase == .succeeded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                        .frame(width: 14, height: 14)
                } else {
                    FamiliarThinkingSpinner(reduceMotion: reduceMotion)
                }
                Text(row.primary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FamiliarAISurfaceColor.ink)
                    .lineLimit(1)
                if let secondary = row.secondary {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                        .lineLimit(1)
                }
            }
        case .coding:
            FamiliarThinkingRowView(row: row, index: index, selectable: true) { _ in
                Text(row.primary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FamiliarAISurfaceColor.ink)
                    .lineLimit(1)
                if let secondary = row.secondary {
                    Text(secondary)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                        .lineLimit(1)
                }
                if row.add != nil || row.del != nil {
                    Text((row.add.map { "+\($0)" } ?? "") + " " + (row.del.map { "−\($0)" } ?? ""))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(row.add != nil ? FamiliarAISurfaceColor.success : FamiliarAISurfaceColor.inkTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func toneColor(_ tone: FamiliarThinkingTone) -> Color {
        switch tone {
        case .accent: FamiliarAISurfaceColor.accent
        case .orange: FamiliarAISurfaceColor.warning
        case .green: FamiliarAISurfaceColor.success
        }
    }
}

private struct FamiliarThinkingRowView<Content: View>: View {
    let row: FamiliarThinkingRow
    let index: Int
    var isLink = false
    var selectable = false
    private let buildContent: (Int) -> Content

    init(
        row: FamiliarThinkingRow,
        index: Int,
        isLink: Bool = false,
        selectable: Bool = false,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.row = row
        self.index = index
        self.isLink = isLink
        self.selectable = selectable
        self.buildContent = content
    }

    @Environment(\.openURL) private var openURL
    @State private var selected = false
    @State private var visible = false

    var body: some View {
        Group {
            if let href = row.href, isLink {
                Button { if let url = URL(string: href) { openURL(url) } } label: { rowLabel }
                    .buttonStyle(.plain)
            } else if selectable {
                Button { selected.toggle() } label: { rowLabel }
                    .buttonStyle(.plain)
            } else {
                rowLabel
            }
        }
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 5)
        .animation(FamiliarMotion.reveal.delay(min(Double(index) * 0.1, 0.4)), value: visible)
        .onAppear { visible = true }
    }

    private var rowLabel: some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
            buildContent(index)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? FamiliarAISurfaceColor.inset : .clear)
        )
    }
}

private struct FamiliarThinkingSpinner: View {
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(FamiliarAISurfaceColor.lineStrong, lineWidth: 1.5)
                .frame(width: 14, height: 14)
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    Circle()
                        .trim(from: 0, to: 0.68)
                        .stroke(FamiliarAISurfaceColor.inkSecondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 14, height: 14)
                        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.7) / 0.7 * 360))
                }
            }
        }
        .frame(width: 14, height: 14)
    }
}

private struct FamiliarThinkingDot: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(color).frame(width: 14, height: 14)
            Image(systemName: "globe")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct FamiliarTurnSurface: View {
    let surface: FamiliarSurfaceDescriptor
    let canUndo: Bool
    let onResolveApproval: (UUID, FamiliarToolConfirmationDecision) -> Void
    let onResolveClarification: (UUID, FamiliarClarificationResolution) -> Void
    let onInsertPrompt: (String) -> Void
    let onUndo: () -> Void
    let onRetry: (() -> Void)?

    var body: some View {
        Group {
            switch surface.kind {
            case .approval:
                FamiliarApprovalIntervention(surface: surface, onResolve: onResolveApproval)
            case .mutationReceipt, .artifact:
                FamiliarWriteReceipt(surface: surface, canUndo: canUndo, onUndo: onUndo)
            case .failure:
                FamiliarFailureRecovery(surface: surface, onRetry: onRetry)
            case .taskList:
                FamiliarTaskListSurface(surface: surface)
            case .recommendation:
                FamiliarRecommendationSurface(surface: surface, onInsertPrompt: onInsertPrompt)
            case .insight:
                FamiliarInsightSurface(surface: surface)
            case .clarification:
                FamiliarClarificationSurface(surface: surface, onResolve: onResolveClarification)
            case .code:
                FamiliarCodeSurface(surface: surface)
            case .diff:
                FamiliarDiffSurface(surface: surface)
            case .toolSummary:
                FamiliarCompactToolSummary(surface: surface, canUndo: canUndo, onUndo: onUndo)
            case .context:
                FamiliarContextMatchesSurface(surface: surface)
            case .records:
                FamiliarRecordCollectionSurface(surface: surface)
            case .search:
                FamiliarTypedResult(surface: surface)
            case .runStatus, .activityTrace:
                EmptyView()
            }
        }
        .sensoryFeedback(trigger: surface.phase) { old, new in
            FamiliarHapticPolicy.feedback(from: old, to: new)
        }
    }
}

private struct FamiliarTaskListSurface: View {
    let surface: FamiliarSurfaceDescriptor

    var body: some View {
        if case .taskList(let plan) = surface.resultEnvelope?.presentation.content {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                    Image(systemName: "checklist")
                        .foregroundStyle(FamiliarAISurfaceColor.accent)
                    Text(plan.title)
                        .font(.headline)
                        .foregroundStyle(FamiliarAISurfaceColor.ink)
                    Spacer(minLength: 0)
                    Text("\(plan.tasks.filter { $0.status == .completed }.count)/\(plan.tasks.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(plan.tasks.enumerated()), id: \.element.id) { index, task in
                        FamiliarTaskRow(task: task)
                        if index < plan.tasks.count - 1 {
                            Rectangle()
                                .fill(FamiliarAISurfaceColor.line)
                                .frame(height: FamiliarAISurfaceMetric.hairline)
                                .padding(.leading, FamiliarAISurfaceMetric.icon + FamiliarAISurfaceMetric.spaceM)
                        }
                    }
                }
            }
            .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(FamiliarAISurfaceColor.accent)
                    .frame(width: 3)
                    .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
                    .offset(x: -FamiliarAISurfaceMetric.spaceM)
            }
        }
    }
}

private struct FamiliarTaskRow: View {
    let task: FamiliarToolPresentationPayload.TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceM) {
            Image(systemName: symbol)
                .font(.system(size: FamiliarAISurfaceMetric.compactIcon, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: FamiliarAISurfaceMetric.icon, height: FamiliarAISurfaceMetric.icon)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FamiliarAISurfaceColor.ink)
                if let detail = task.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                }
                if let progress = task.progress, progress.isFinite {
                    HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                        ProgressView(value: progress)
                            .tint(tone)
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                    }
                    .accessibilityLabel(String(localized: "task.progress", defaultValue: "Progress"))
                    .accessibilityValue(Text(progress, format: .percent))
                }
            }
            Spacer(minLength: 0)
            Text(statusTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tone)
                .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
                .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
                .background(tone.opacity(0.1), in: Capsule())
        }
        .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch task.status {
        case .pending: "circle"
        case .running: "circle.dotted"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var tone: Color {
        switch task.status {
        case .pending: FamiliarAISurfaceColor.inkTertiary
        case .running: FamiliarAISurfaceColor.accent
        case .completed: FamiliarAISurfaceColor.success
        case .failed: FamiliarAISurfaceColor.failure
        }
    }

    private var statusTitle: String {
        switch task.status {
        case .pending: String(localized: "task.status.pending", defaultValue: "Pending")
        case .running: String(localized: "task.status.running", defaultValue: "Running")
        case .completed: String(localized: "task.status.completed", defaultValue: "Completed")
        case .failed: String(localized: "task.status.failed", defaultValue: "Failed")
        }
    }
}

private struct FamiliarRecommendationSurface: View {
    let surface: FamiliarSurfaceDescriptor
    let onInsertPrompt: (String) -> Void

    var body: some View {
        if case .recommendation(let recommendation) = surface.resultEnvelope?.presentation.content {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                HStack(alignment: .firstTextBaseline, spacing: FamiliarAISurfaceMetric.spaceS) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(FamiliarAISurfaceColor.accent)
                    Text(recommendation.title)
                        .font(.headline)
                        .foregroundStyle(FamiliarAISurfaceColor.ink)
                    Spacer(minLength: 0)
                    if let confidence = recommendation.confidenceLevel {
                        Text(confidenceTitle(confidence))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(FamiliarAISurfaceColor.accentInk)
                            .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
                            .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
                            .background(FamiliarAISurfaceColor.accentTint, in: Capsule())
                    }
                }
                Text(recommendation.explanation)
                    .font(.subheadline)
                    .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onInsertPrompt(recommendation.nextPrompt)
                } label: {
                    HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                        Text(recommendation.nextPrompt)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left")
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
                    .frame(minHeight: FamiliarAISurfaceMetric.rowHeight)
                    .background(FamiliarAISurfaceColor.accent, in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "recommendation.fill_hint", defaultValue: "Fills the composer without sending"))

                ForEach(recommendation.alternatives) { alternative in
                    Button {
                        onInsertPrompt(alternative.prompt)
                    } label: {
                        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                            Text(alternative.title)
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: 0)
                            Image(systemName: "plus")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(FamiliarAISurfaceColor.ink)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(String(localized: "recommendation.fill_hint", defaultValue: "Fills the composer without sending"))
                }
            }
            .padding(FamiliarAISurfaceMetric.spaceL)
            .background(FamiliarAISurfaceColor.accentTint.opacity(0.55), in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.window, style: .continuous))
        }
    }

    private func confidenceTitle(_ confidence: FamiliarToolPresentationPayload.ConfidenceLevel) -> String {
        switch confidence {
        case .low: String(localized: "confidence.low", defaultValue: "Low confidence")
        case .medium: String(localized: "confidence.medium", defaultValue: "Medium confidence")
        case .high: String(localized: "confidence.high", defaultValue: "High confidence")
        case .needsReview: String(localized: "confidence.needs_review", defaultValue: "Needs review")
        }
    }
}

private struct FamiliarInsightSurface: View {
    let surface: FamiliarSurfaceDescriptor

    var body: some View {
        if case .insight(let insight) = surface.resultEnvelope?.presentation.content {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                Label(insight.title, systemImage: "chart.xyaxis.line")
                    .font(.headline)
                    .foregroundStyle(FamiliarAISurfaceColor.ink)
                Text(insight.explanation)
                    .font(.subheadline)
                    .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)

                if !insight.metrics.isEmpty {
                    Chart(Array(insight.metrics.enumerated()), id: \.offset) { _, metric in
                        BarMark(
                            x: .value(String(localized: "insight.metric.value", defaultValue: "Value"), metric.value),
                            y: .value(String(localized: "insight.metric.name", defaultValue: "Metric"), metric.label)
                        )
                        .foregroundStyle(metric.value < 0 ? FamiliarAISurfaceColor.warning : FamiliarAISurfaceColor.accent)
                        .annotation(position: metric.value < 0 ? .leading : .trailing, alignment: .center) {
                            VStack(alignment: metric.value < 0 ? .trailing : .leading, spacing: 1) {
                                Text(metricValue(metric))
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                if let change = metric.change {
                                    Text(change, format: .number.sign(strategy: .always()))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(change < 0 ? FamiliarAISurfaceColor.failure : FamiliarAISurfaceColor.success)
                                }
                            }
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisValueLabel()
                                .font(.caption)
                                .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                        }
                    }
                    .frame(minHeight: max(96, CGFloat(insight.metrics.count) * 44))
                    .accessibilityLabel(String(localized: "insight.metrics", defaultValue: "Insight metrics"))
                }
            }
            .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
        }
    }

    private func metricValue(_ metric: FamiliarToolPresentationPayload.InsightMetric) -> String {
        let value = metric.value.formatted(.number.precision(.fractionLength(0...2)))
        guard let unit = metric.unit, !unit.isEmpty else { return value }
        return value + " " + unit
    }
}

private struct FamiliarClarificationSurface: View {
    let surface: FamiliarSurfaceDescriptor
    let onResolve: (UUID, FamiliarClarificationResolution) -> Void
    @State private var customResponse = ""

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
            HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceS) {
                Image(systemName: surface.phase == .failed ? "questionmark.circle" : "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(surface.phase == .failed ? FamiliarAISurfaceColor.inkTertiary : FamiliarAISurfaceColor.accent)
                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                    Text(String(localized: "clarification.title", defaultValue: "One question"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                    Text(surface.title)
                        .font(.headline)
                        .foregroundStyle(FamiliarAISurfaceColor.ink)
                }
            }

            if surface.phase == .awaitingClarification, let requestID = surface.clarificationRequestID {
                ForEach(surface.clarificationOptions) { option in
                    Button {
                        onResolve(requestID, .selectedOption(id: option.id, label: option.label))
                    } label: {
                        HStack {
                            Text(option.label)
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                        }
                        .foregroundStyle(FamiliarAISurfaceColor.ink)
                        .padding(.horizontal, FamiliarAISurfaceMetric.spaceXS)
                        .frame(minHeight: FamiliarAISurfaceMetric.rowHeight)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(FamiliarAISurfaceColor.line).frame(height: FamiliarAISurfaceMetric.hairline)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if surface.clarificationAllowsCustom {
                    HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                        TextField(String(localized: "clarification.custom", defaultValue: "Write another answer"), text: $customResponse, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                        Button {
                            let answer = customResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !answer.isEmpty { onResolve(requestID, .custom(answer)) }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle(customResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FamiliarAISurfaceColor.inkTertiary : FamiliarAISurfaceColor.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(customResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel(String(localized: "clarification.submit", defaultValue: "Submit answer"))
                    }
                    .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
                    .frame(minHeight: FamiliarAISurfaceMetric.rowHeight)
                    .background(FamiliarAISurfaceColor.field, in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.control, style: .continuous))
                }
            } else if let answer = surface.clarificationResolution?.answer {
                Label(answer, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(FamiliarAISurfaceColor.success)
            } else if let detail = surface.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
            }
        }
        .padding(FamiliarAISurfaceMetric.spaceL)
        .background(FamiliarAISurfaceColor.inset, in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.window, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct FamiliarCodeSurface: View {
    let surface: FamiliarSurfaceDescriptor
    @State private var showsFullCode = false

    var body: some View {
        if case .code(let code) = surface.resultEnvelope?.presentation.content {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
                HStack(alignment: .firstTextBaseline, spacing: FamiliarAISurfaceMetric.spaceS) {
                    Label(code.summary, systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.string = code.code
                    } label: {
                        Label(String(localized: "common.copy"), systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "common.copy"))
                }
                .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)

                if code.filename != nil || code.language != nil {
                    HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                        if let filename = code.filename, !filename.isEmpty {
                            Label(filename, systemImage: "doc")
                        }
                        if let language = code.language, !language.isEmpty {
                            Text(language)
                        }
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                }

                ScrollView(.horizontal) {
                    Text(codePreview(code.code))
                        .font(.caption.monospaced())
                        .foregroundStyle(FamiliarAISurfaceColor.ink)
                        .textSelection(.enabled)
                        .padding(FamiliarAISurfaceMetric.spaceM)
                }
                .background(FamiliarAISurfaceColor.inset, in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.control, style: .continuous))

                if isLong(code.code) {
                    Button {
                        showsFullCode = true
                    } label: {
                        Label(String(localized: "code.view_full", defaultValue: "View full code"), systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FamiliarAISurfaceColor.accentInk)
                    .accessibilityIdentifier("surface.code.details")
                }
            }
            .fullScreenCover(isPresented: $showsFullCode) {
                FamiliarCodeDetailView(code: code)
            }
        }
    }

    private func isLong(_ value: String) -> Bool {
        value.count > 1_200 || value.split(separator: "\n", omittingEmptySubsequences: false).count > 12
    }

    private func codePreview(_ value: String) -> String {
        guard isLong(value) else { return value }
        return value.split(separator: "\n", omittingEmptySubsequences: false).prefix(12).joined(separator: "\n") + "\n..."
    }
}

private struct FamiliarCodeDetailView: View {
    let code: FamiliarToolPresentationPayload.Code
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Text(code.code)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .padding(FamiliarAISurfaceMetric.spaceL)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(FamiliarAISurfaceColor.inset)
            .navigationTitle(code.filename ?? code.summary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = code.code
                    } label: {
                        Label(String(localized: "common.copy"), systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}

private struct FamiliarContextMatchesSurface: View {
    let surface: FamiliarSurfaceDescriptor
    @State private var showsDetails = false

    var body: some View {
        if case .contextMatches(let context) = surface.resultEnvelope?.presentation.content {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                HStack(alignment: .firstTextBaseline, spacing: FamiliarAISurfaceMetric.spaceS) {
                    Label(context.summary, systemImage: "text.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FamiliarAISurfaceColor.ink)
                    Spacer(minLength: 0)
                    Text(context.query)
                        .font(.caption)
                        .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                        .lineLimit(1)
                }

                if context.matches.isEmpty {
                    Text(String(localized: "context.matches.empty", defaultValue: "No matching context"))
                        .font(.caption)
                        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                } else {
                    ForEach(context.matches.prefix(2), id: \.versionID) { match in
                        FamiliarContextChunk(match: match)
                    }
                }

                if context.matches.count > 2 {
                    Button {
                        showsDetails = true
                    } label: {
                        Label(
                            String(format: String(localized: "context.matches.view_all", defaultValue: "View all %lld matches"), context.matches.count),
                            systemImage: "list.bullet"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FamiliarAISurfaceColor.accentInk)
                    .accessibilityIdentifier("surface.context.details")
                }
            }
            .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
            .sheet(isPresented: $showsDetails) {
                FamiliarContextMatchesDetailView(context: context)
            }
        }
    }
}

private struct FamiliarContextChunk: View {
    let match: FamiliarToolPresentationPayload.ContextMatch

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
            HStack(alignment: .firstTextBaseline, spacing: FamiliarAISurfaceMetric.spaceS) {
                Text(match.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FamiliarAISurfaceColor.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(metadata)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
            }
            Text(match.excerpt)
                .font(.caption)
                .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(.leading, FamiliarAISurfaceMetric.spaceM)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(FamiliarAISurfaceColor.accentTint)
                .frame(width: 3)
        }
        .accessibilityElement(children: .combine)
    }

    private var metadata: String {
        String(
            format: String(localized: "context.matches.metadata", defaultValue: "%1$lld chars · v%2$lld"),
            match.excerpt.count,
            match.version
        )
    }
}

private struct FamiliarContextMatchesDetailView: View {
    let context: FamiliarToolPresentationPayload.ContextMatches
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(context.matches, id: \.versionID) { match in
                FamiliarContextChunk(match: match)
                    .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
            }
            .listStyle(.plain)
            .navigationTitle(String(localized: "context.matches.title", defaultValue: "Context matches"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
    }
}

private struct FamiliarRecordCollectionSurface: View {
    let surface: FamiliarSurfaceDescriptor
    @State private var selectedFilter: String?
    @State private var showsAllRecords = false

    init(surface: FamiliarSurfaceDescriptor) {
        self.surface = surface
        _selectedFilter = State(initialValue: nil)
    }

    var body: some View {
        if case .recordCollection(let collection) = surface.resultEnvelope?.presentation.content {
            let filter = FamiliarRecordPresentation.filter(for: collection)
            let records = FamiliarRecordPresentation.filtered(collection.records, by: filter, value: selectedFilter)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                HStack(alignment: .firstTextBaseline, spacing: FamiliarAISurfaceMetric.spaceS) {
                    Label(collection.summary, systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FamiliarAISurfaceColor.ink)
                    Spacer(minLength: 0)
                    Text(collection.records.count, format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                }

                if let filter {
                    FamiliarRecordFilterChips(filter: filter, selected: $selectedFilter)
                }

                if records.isEmpty {
                    Text(String(localized: "records.empty", defaultValue: "No records"))
                        .font(.caption)
                        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(records.prefix(3).enumerated()), id: \.element.id) { index, record in
                            FamiliarRecordRow(record: record)
                            if index < min(records.count, 3) - 1 {
                                Rectangle()
                                    .fill(FamiliarAISurfaceColor.line)
                                    .frame(height: FamiliarAISurfaceMetric.hairline)
                            }
                        }
                    }
                }

                if collection.records.count > 3 {
                    Button {
                        showsAllRecords = true
                    } label: {
                        Label(String(localized: "records.view_all", defaultValue: "Search all records"), systemImage: "magnifyingglass")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FamiliarAISurfaceColor.accentInk)
                    .accessibilityIdentifier("surface.records.details")
                }
            }
            .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
            .fullScreenCover(isPresented: $showsAllRecords) {
                FamiliarRecordCollectionDetailView(collection: collection, initialFilter: selectedFilter)
            }
        }
    }
}

private struct FamiliarRecordFilter: Equatable {
    let fieldName: String
    let values: [String]
}

private enum FamiliarRecordPresentation {
    static func filter(for collection: FamiliarToolPresentationPayload.RecordCollection) -> FamiliarRecordFilter? {
        let preferredNames = ["status", "completed", "type", "mimeType"]
        for name in preferredNames {
            let values = collection.records.compactMap { record in
                record.fields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
            }
            let unique = Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            if unique.count > 1 { return .init(fieldName: name, values: unique) }
        }
        return nil
    }

    static func filtered(
        _ records: [FamiliarToolPresentationPayload.Record],
        by filter: FamiliarRecordFilter?,
        value: String?
    ) -> [FamiliarToolPresentationPayload.Record] {
        guard let filter, let value else { return records }
        return records.filter { record in
            record.fields.contains { $0.name.caseInsensitiveCompare(filter.fieldName) == .orderedSame && $0.value == value }
        }
    }

    static func matches(_ record: FamiliarToolPresentationPayload.Record, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return record.id.localizedCaseInsensitiveContains(query) || record.fields.contains {
            $0.name.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query)
        }
    }

    static func displayValue(_ value: String, fieldName: String) -> String {
        if fieldName.caseInsensitiveCompare("completed") == .orderedSame {
            if value.caseInsensitiveCompare("true") == .orderedSame { return String(localized: "task.status.completed", defaultValue: "Completed") }
            if value.caseInsensitiveCompare("false") == .orderedSame { return String(localized: "task.status.pending", defaultValue: "Pending") }
        }
        return value
    }
}

private struct FamiliarRecordFilterChips: View {
    let filter: FamiliarRecordFilter
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: FamiliarAISurfaceMetric.spaceXS) {
                chip(title: String(localized: "records.filter.all", defaultValue: "All"), value: nil)
                ForEach(filter.values, id: \.self) { value in
                    chip(title: FamiliarRecordPresentation.displayValue(value, fieldName: filter.fieldName), value: value)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(String(localized: "records.filter", defaultValue: "Record filter"))
    }

    private func chip(title: String, value: String?) -> some View {
        Button {
            selected = value
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(selected == value ? FamiliarAISurfaceColor.accentInk : FamiliarAISurfaceColor.inkSecondary)
                .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
                .frame(minHeight: 30)
                .background(selected == value ? FamiliarAISurfaceColor.accentTint : FamiliarAISurfaceColor.inset, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct FamiliarRecordRow: View {
    let record: FamiliarToolPresentationPayload.Record

    private var primary: FamiliarToolPresentationPayload.RecordField? {
        let preferred = ["title", "name", "filename"]
        for name in preferred {
            if let field = record.fields.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return field }
        }
        return record.fields.first
    }

    private var secondary: [FamiliarToolPresentationPayload.RecordField] {
        let preferred = ["status", "completed", "start", "due", "end", "type", "mimeType", "calendar", "list"]
        return preferred.compactMap { name in
            record.fields.first { field in
                field.name.caseInsensitiveCompare(name) == .orderedSame && field.name != primary?.name
            }
        }.prefix(3).map { $0 }
    }

    var body: some View {
        HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceM) {
            Image(systemName: statusSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FamiliarAISurfaceColor.accent)
                .frame(width: FamiliarAISurfaceMetric.icon, height: FamiliarAISurfaceMetric.icon)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                Text(primary?.value ?? record.id)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FamiliarAISurfaceColor.ink)
                    .lineLimit(2)
                ForEach(secondary, id: \.name) { field in
                    Text("\(fieldTitle(field.name)): \(formatted(field))")
                        .font(.caption)
                        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        guard let completed = record.fields.first(where: { $0.name.caseInsensitiveCompare("completed") == .orderedSame })?.value else {
            return "doc.text"
        }
        return completed.caseInsensitiveCompare("true") == .orderedSame ? "checkmark.circle.fill" : "circle"
    }

    private func formatted(_ field: FamiliarToolPresentationPayload.RecordField) -> String {
        let dateFields = ["start", "end", "due"]
        if dateFields.contains(where: { field.name.caseInsensitiveCompare($0) == .orderedSame }) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var date = formatter.date(from: field.value)
            if date == nil {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: field.value)
            }
            if let date { return date.formatted(date: .abbreviated, time: .shortened) }
        }
        return FamiliarRecordPresentation.displayValue(field.value, fieldName: field.name)
    }

    private func fieldTitle(_ name: String) -> String {
        switch name.lowercased() {
        case "status": String(localized: "records.field.status", defaultValue: "Status")
        case "completed": String(localized: "records.field.status", defaultValue: "Status")
        case "start": String(localized: "records.field.start", defaultValue: "Starts")
        case "end": String(localized: "records.field.end", defaultValue: "Ends")
        case "due": String(localized: "records.field.due", defaultValue: "Due")
        case "type", "mimetype": String(localized: "records.field.type", defaultValue: "Type")
        case "calendar": String(localized: "records.field.calendar", defaultValue: "Calendar")
        case "list": String(localized: "records.field.list", defaultValue: "List")
        default: name
        }
    }
}

private struct FamiliarRecordCollectionDetailView: View {
    let collection: FamiliarToolPresentationPayload.RecordCollection
    @State private var selectedFilter: String?
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    init(collection: FamiliarToolPresentationPayload.RecordCollection, initialFilter: String?) {
        self.collection = collection
        _selectedFilter = State(initialValue: initialFilter)
    }

    var body: some View {
        let filter = FamiliarRecordPresentation.filter(for: collection)
        let filtered = FamiliarRecordPresentation.filtered(collection.records, by: filter, value: selectedFilter)
            .filter { FamiliarRecordPresentation.matches($0, query: searchText) }
        NavigationStack {
            List {
                if let filter {
                    Section {
                        FamiliarRecordFilterChips(filter: filter, selected: $selectedFilter)
                    }
                }
                ForEach(filtered, id: \.id) { record in
                    FamiliarRecordRow(record: record)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: String(localized: "records.search", defaultValue: "Search records"))
            .navigationTitle(collection.summary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
    }
}

private struct FamiliarDiffSurface: View {
    let surface: FamiliarSurfaceDescriptor
    @State private var showsDiff = false

    var body: some View {
        if case .diff(let diff) = surface.resultEnvelope?.presentation.content {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
                Label(diff.summary, systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FamiliarAISurfaceColor.ink)
                Text(changeSummary(diff))
                    .font(.caption)
                    .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                Button {
                    showsDiff = true
                } label: {
                    Label(String(localized: "diff.view_full", defaultValue: "Review full change"), systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FamiliarAISurfaceColor.accentInk)
                .accessibilityIdentifier("surface.diff.details")
            }
            .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
            .fullScreenCover(isPresented: $showsDiff) {
                FamiliarDiffDetailView(diff: diff)
            }
        }
    }

    private func changeSummary(_ diff: FamiliarToolPresentationPayload.Diff) -> String {
        let before = diff.before.split(separator: "\n", omittingEmptySubsequences: false).count
        let after = diff.after.split(separator: "\n", omittingEmptySubsequences: false).count
        return String(format: String(localized: "diff.line_summary", defaultValue: "%1$lld lines before · %2$lld lines after"), before, after)
    }
}

private struct FamiliarDiffDetailView: View {
    let diff: FamiliarToolPresentationPayload.Diff
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceL) {
                    FamiliarDiffBlock(
                        title: String(localized: "common.before", defaultValue: "Before"),
                        symbol: "minus",
                        text: diff.before,
                        tint: FamiliarAISurfaceColor.failureTint
                    )
                    FamiliarDiffBlock(
                        title: String(localized: "common.after", defaultValue: "After"),
                        symbol: "plus",
                        text: diff.after,
                        tint: FamiliarAISurfaceColor.successTint
                    )
                }
                .padding(FamiliarAISurfaceMetric.spaceL)
            }
            .navigationTitle(diff.summary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
    }
}

private struct FamiliarDiffBlock: View {
    let title: String
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
            Label(title, systemImage: symbol)
                .font(.headline)
            ScrollView(.horizontal) {
                Text(text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .padding(FamiliarAISurfaceMetric.spaceM)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.control, style: .continuous))
        }
    }
}

private struct FamiliarCompactToolSummary: View {
    let surface: FamiliarSurfaceDescriptor
    let canUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceS) {
            Image(systemName: symbol)
                .font(.system(size: FamiliarAISurfaceMetric.compactIcon, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: FamiliarAISurfaceMetric.icon)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                Text(surface.title).font(.subheadline.weight(.semibold)).foregroundStyle(FamiliarAISurfaceColor.ink)
                if let detail = surface.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(FamiliarAISurfaceColor.inkSecondary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if canUndo {
                Button(String(localized: "common.undo"), action: onUndo)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(FamiliarAISurfaceColor.accentInk)
            }
        }
        .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
    }

    private var symbol: String {
        switch surface.phase {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .undone: "arrow.uturn.backward.circle.fill"
        case .queued, .planning, .running, .awaitingApproval, .awaitingClarification: "circle.dotted"
        }
    }

    private var tone: Color {
        switch surface.phase {
        case .succeeded: FamiliarAISurfaceColor.success
        case .failed: FamiliarAISurfaceColor.failure
        case .cancelled, .undone: FamiliarAISurfaceColor.inkTertiary
        case .queued, .planning, .running, .awaitingApproval, .awaitingClarification: FamiliarAISurfaceColor.accent
        }
    }
}

private struct FamiliarApprovalIntervention: View {
    let surface: FamiliarSurfaceDescriptor
    let onResolve: (UUID, FamiliarToolConfirmationDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
            HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceS) {
                Image(systemName: "checklist.checked")
                    .foregroundStyle(FamiliarAISurfaceColor.warning)
                    .frame(width: FamiliarAISurfaceMetric.icon)
                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                    Text(surface.title).font(.headline).foregroundStyle(FamiliarAISurfaceColor.ink)
                    if let target = surface.approvalTarget {
                        Text(target).font(.caption).foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                    }
                }
            }

            VStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                ForEach(surface.approvalFields) { field in
                    HStack(alignment: .firstTextBaseline, spacing: FamiliarAISurfaceMetric.spaceM) {
                        Text(field.label)
                            .font(.caption)
                            .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                            .frame(width: 86, alignment: .leading)
                        Text(field.formattedValue)
                            .font(.subheadline)
                            .foregroundStyle(FamiliarAISurfaceColor.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }

            if let consequence = surface.approvalConsequence, !consequence.isEmpty {
                Text(consequence).font(.caption).foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
            }

            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                Button(String(localized: "common.cancel")) { resolve(.cancelled) }
                    .buttonStyle(.bordered)
                Menu {
                    Button(String(localized: "authorization.once", defaultValue: "Only Once")) { resolve(.confirmedOnce) }
                    Button(String(localized: "authorization.always", defaultValue: "Always Allow")) { resolve(.confirmedAlways) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(.bordered)
                Button(String(localized: "authorization.session", defaultValue: "Allow This Session")) { resolve(.confirmed) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(FamiliarAISurfaceMetric.spaceL)
        .background(FamiliarAISurfaceColor.warningTint, in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.window, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.window, style: .continuous)
                .stroke(FamiliarAISurfaceColor.warning.opacity(0.3), lineWidth: FamiliarAISurfaceMetric.hairline)
        }
        .accessibilityElement(children: .contain)
    }

    private func resolve(_ decision: FamiliarToolConfirmationDecision) {
        if let id = surface.approvalRequestID { onResolve(id, decision) }
    }
}

private struct FamiliarWriteReceipt: View {
    let surface: FamiliarSurfaceDescriptor
    let canUndo: Bool
    let onUndo: () -> Void
    @State private var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
            HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceS) {
                Image(systemName: surface.phase == .undone ? "arrow.uturn.backward.circle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(surface.phase == .undone ? FamiliarAISurfaceColor.inkTertiary : FamiliarAISurfaceColor.success)
                    .frame(width: FamiliarAISurfaceMetric.icon)
                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                    Text(surface.title).font(.subheadline.weight(.semibold)).foregroundStyle(FamiliarAISurfaceColor.ink)
                    if let detail = receiptDetail {
                        Text(detail).font(.caption).foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let artifact = surface.artifact {
                HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                    Button {
                        previewURL = FamiliarArtifactStore().url(relativePath: artifact.relativePath)
                    } label: {
                        Label(artifact.title, systemImage: "doc.richtext")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FamiliarAISurfaceColor.accentInk)
                    Spacer()
                    if let url = FamiliarArtifactStore().url(relativePath: artifact.relativePath) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel(String(localized: "common.share"))
                    }
                }
            }

            if canUndo {
                Button(String(localized: "common.undo"), action: onUndo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FamiliarAISurfaceColor.accentInk)
            }
        }
        .padding(FamiliarAISurfaceMetric.spaceM)
        .background(FamiliarAISurfaceColor.successTint, in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.card, style: .continuous))
        .sheet(isPresented: Binding(get: { previewURL != nil }, set: { if !$0 { previewURL = nil } })) {
            if let previewURL { FamiliarAttachmentQuickLookView(url: previewURL).ignoresSafeArea() }
        }
    }

    private var receiptDetail: String? {
        guard let content = surface.resultEnvelope?.presentation.content else { return surface.detail }
        switch content {
        case .mutationReceipt(let receipt): return receipt.operation
        case .artifactMutation(let artifact): return "\(artifact.operation) · \(ByteCountFormatter.string(fromByteCount: artifact.byteSize, countStyle: .file))"
        case .scalar, .searchResults, .document, .contextMatches, .recordCollection, .diff, .taskList, .recommendation, .insight, .code: return surface.detail
        }
    }
}

private struct FamiliarFailureRecovery: View {
    let surface: FamiliarSurfaceDescriptor
    let onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceM) {
            Image(systemName: surface.phase == .cancelled ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(surface.phase == .cancelled ? FamiliarAISurfaceColor.inkTertiary : FamiliarAISurfaceColor.failure)
                .frame(width: FamiliarAISurfaceMetric.icon)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
                Text(surface.title).font(.subheadline.weight(.semibold)).foregroundStyle(FamiliarAISurfaceColor.ink)
                if let detail = surface.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(FamiliarAISurfaceColor.inkSecondary).textSelection(.enabled)
                }
                if let onRetry {
                    Button(String(localized: "message.retry"), action: onRetry)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FamiliarAISurfaceColor.failure)
                }
            }
        }
        .padding(FamiliarAISurfaceMetric.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FamiliarAISurfaceColor.failureTint, in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.card, style: .continuous))
    }
}

private struct FamiliarActivityTrace: View {
    let surface: FamiliarSurfaceDescriptor
    let items: [FamiliarSurfaceDescriptor]
    let finishedAt: Date?
    let metrics: FamiliarReplyMetrics?
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var readURLs: Set<String> {
        Set(items.compactMap { item in
            guard case .document(let document) = item.resultEnvelope?.presentation.content else { return nil }
            return document.url
        })
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                if let context = surface.context { FamiliarContextTrace(context: context, metrics: metrics) }
                ForEach(items) { item in FamiliarTypedResult(surface: item, readURLs: readURLs) }
            }
            .padding(.top, FamiliarAISurfaceMetric.spaceS)
            .padding(.leading, FamiliarAISurfaceMetric.traceIndent)
        } label: {
            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                Image(systemName: "waveform.path.ecg")
                Text(String(localized: "message.operation_trace", defaultValue: "Activity"))
                if let startedAt = surface.startedAt, let end = finishedAt ?? surface.finishedAt {
                    Text(duration(startedAt, end)).font(.caption2.monospacedDigit()).foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
        }
        .tint(FamiliarAISurfaceColor.inkSecondary)
        .transaction { if reduceMotion { $0.animation = nil } }
    }

    private func duration(_ start: Date, _ end: Date) -> String {
        let value = max(0, end.timeIntervalSince(start))
        return value < 60 ? String(format: "%.1fs", value) : String(format: "%dm %.1fs", Int(value / 60), value.truncatingRemainder(dividingBy: 60))
    }
}

private struct FamiliarContextTrace: View {
    let context: FamiliarRunContextSummary
    let metrics: FamiliarReplyMetrics?

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
            traceRow("cpu", String(localized: "run.context.model", defaultValue: "Model"), "\(context.providerID) · \(context.modelID)")
            if let project = context.projectName { traceRow("folder", String(localized: "run.context.project", defaultValue: "Project"), project) }
            ForEach(context.resources) { traceRow("doc.text", String(localized: "run.context.resource", defaultValue: "Resource"), "\($0.filename) · v\($0.version)") }
            ForEach(context.skills) { traceRow("wand.and.stars", String(localized: "run.context.skill", defaultValue: "Skill"), "\($0.name) · \($0.version)") }
            if let metrics {
                if let duration = metrics.duration {
                    traceRow("clock", String(localized: "run.context.reply_time", defaultValue: "Reply time"), format(duration))
                }
                traceRow("bolt.horizontal", String(localized: "run.context.first_token", defaultValue: "First token"), metrics.timeToFirstToken.map(format) ?? "—")
            }
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        interval < 60 ? String(format: "%.1fs", interval) : String(format: "%dm %.1fs", Int(interval / 60), interval.truncatingRemainder(dividingBy: 60))
    }

    private func traceRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceS) {
            Image(systemName: symbol).frame(width: FamiliarAISurfaceMetric.icon).foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(FamiliarAISurfaceColor.ink)
                Text(detail).font(.caption2).foregroundStyle(FamiliarAISurfaceColor.inkSecondary).textSelection(.enabled)
            }
        }
    }
}

private struct FamiliarTypedResult: View {
    let surface: FamiliarSurfaceDescriptor
    var readURLs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                Image(systemName: symbol).frame(width: FamiliarAISurfaceMetric.icon)
                Text(surface.title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
            if let content = surface.resultEnvelope?.presentation.content { contentView(content) }
            else if let detail = surface.detail { Text(detail).font(.caption).foregroundStyle(FamiliarAISurfaceColor.inkSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func contentView(_ content: FamiliarToolPresentationPayload.Content) -> some View {
        switch content {
        case .scalar(let scalar):
            traceValue(label: scalar.label, value: scalar.value)
        case .searchResults(let search):
            let readCount = search.results.filter { readURLs.contains($0.url) }.count
            traceValue(label: String(localized: "search.activity.query", defaultValue: "Query"), value: search.query)
            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                FamiliarSourceStatusLabel(
                    title: String(format: String(localized: "search.activity.read_count", defaultValue: "%lld read"), readCount),
                    isRead: true
                )
                FamiliarSourceStatusLabel(
                    title: String(format: String(localized: "search.activity.discovered_count", defaultValue: "%lld discovered only"), search.results.count - readCount),
                    isRead: false
                )
            }
            .accessibilityElement(children: .combine)
            Text(String(format: String(localized: "search.activity.result_count", defaultValue: "%lld results"), search.results.count))
                .font(.caption2)
                .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
        case .document(let document):
            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                if let title = document.title { Text(title).font(.caption.weight(.medium)).foregroundStyle(FamiliarAISurfaceColor.ink) }
                Spacer(minLength: 0)
                FamiliarSourceStatusLabel(title: String(localized: "source.status.read", defaultValue: "Read"), isRead: true)
            }
            Text(document.text).font(.caption2).foregroundStyle(FamiliarAISurfaceColor.inkSecondary).lineLimit(8).textSelection(.enabled)
        case .mutationReceipt(let receipt):
            traceValue(label: receipt.operation, value: receipt.targetIdentifier ?? receipt.summary)
        case .artifactMutation(let artifact):
            traceValue(label: artifact.operation, value: artifact.title)
        case .contextMatches, .recordCollection, .diff, .taskList, .recommendation, .insight, .code:
            EmptyView()
        }
    }

    private func traceValue(label: String?, value: String) -> some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
            if let label { Text(label).font(.caption2.weight(.semibold)).foregroundStyle(FamiliarAISurfaceColor.inkTertiary) }
            Text(value).font(.caption).foregroundStyle(FamiliarAISurfaceColor.ink).textSelection(.enabled)
        }
    }

    private var symbol: String {
        switch surface.kind {
        case .search: "magnifyingglass"
        case .context: "text.magnifyingglass"
        case .records: "list.bullet.rectangle"
        case .diff: "arrow.left.arrow.right"
        case .mutationReceipt: "checkmark.seal"
        case .artifact: "doc.richtext"
        case .failure: "exclamationmark.triangle"
        case .toolSummary: "wrench.and.screwdriver"
        case .approval: "checklist.checked"
        case .runStatus: "sparkles"
        case .activityTrace: "waveform.path.ecg"
        case .taskList: "checklist"
        case .recommendation: "sparkles"
        case .insight: "chart.xyaxis.line"
        case .clarification: "bubble.left.and.bubble.right"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
}

private struct FamiliarInlineSources: View {
    @Environment(\.openURL) private var openURL
    let sources: [FamiliarSource]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    if index > 0 {
                        Rectangle()
                            .fill(FamiliarAISurfaceColor.line)
                            .frame(height: FamiliarAISurfaceMetric.hairline)
                            .padding(.leading, 30)
                    }
                    sourceRow(source)
                }
            }
            .padding(.top, FamiliarAISurfaceMetric.spaceS)
        } label: {
            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                FamiliarSourceCluster(sources: sources)
                Text(String(format: String(localized: "message.sources.count", defaultValue: "%lld sources"), sources.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
            }
        }
        .tint(FamiliarAISurfaceColor.inkSecondary)
        .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
        .accessibilityIdentifier("message.sources.disclosure")
        .accessibilityLabel(String(format: String(localized: "message.sources.count", defaultValue: "%lld sources"), sources.count))
    }

    private func sourceRow(_ source: FamiliarSource) -> some View {
        Button { openURL(source.url) } label: {
            HStack(alignment: .center, spacing: FamiliarAISurfaceMetric.spaceS) {
                FamiliarSourceGlyph(source: source)
                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                    Text(source.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FamiliarAISurfaceColor.ink)
                        .lineLimit(2)
                    Text(source.siteName ?? source.url.host ?? source.url.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                FamiliarSourceStatusLabel(title: statusTitle(source), isRead: source.kind == .fetchedPage)
            }
            .frame(minHeight: FamiliarAISurfaceMetric.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("message.source.row.\(source.id)")
        .accessibilityLabel("\(source.title), \(source.siteName ?? source.url.host ?? source.url.absoluteString), \(statusTitle(source))")
        .accessibilityHint(String(localized: "source.open_hint", defaultValue: "Opens in Familiar's browser"))
    }

    private func statusTitle(_ source: FamiliarSource) -> String {
        source.kind == .fetchedPage
            ? String(localized: "source.status.read", defaultValue: "Read")
            : String(localized: "source.status.discovered", defaultValue: "Discovered")
    }
}

private struct FamiliarSourceCluster: View {
    let sources: [FamiliarSource]

    var body: some View {
        HStack(spacing: -5) {
            ForEach(Array(sources.prefix(3))) { source in
                FamiliarSourceGlyph(source: source)
                    .overlay { Circle().stroke(FamiliarAISurfaceColor.page, lineWidth: 1.5) }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FamiliarSourceGlyph: View {
    let source: FamiliarSource

    var body: some View {
        Circle()
            .fill(source.kind == .fetchedPage ? FamiliarAISurfaceColor.successTint : FamiliarAISurfaceColor.accentTint)
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: source.kind == .fetchedPage ? "doc.text.fill" : "globe")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(source.kind == .fetchedPage ? FamiliarAISurfaceColor.success : FamiliarAISurfaceColor.accentInk)
            }
            .accessibilityHidden(true)
    }
}

private struct FamiliarSourceStatusLabel: View {
    let title: String
    let isRead: Bool

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isRead ? FamiliarAISurfaceColor.success : FamiliarAISurfaceColor.inkTertiary)
            .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
            .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
            .background(isRead ? FamiliarAISurfaceColor.successTint : FamiliarAISurfaceColor.inset, in: Capsule())
    }
}

nonisolated enum FamiliarSelectionAction: String, CaseIterable, Identifiable, Sendable {
    case explain
    case improve
    case shorten
    case tone
    case grammar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain: String(localized: "selection.action.explain", defaultValue: "Explain")
        case .improve: String(localized: "selection.action.improve", defaultValue: "Improve")
        case .shorten: String(localized: "selection.action.shorten", defaultValue: "Shorten")
        case .tone: String(localized: "selection.action.tone", defaultValue: "Tone")
        case .grammar: String(localized: "selection.action.grammar", defaultValue: "Grammar")
        }
    }

    var symbol: String {
        switch self {
        case .explain: "questionmark.bubble"
        case .improve: "sparkles"
        case .shorten: "scissors"
        case .tone: "face.smiling"
        case .grammar: "textformat"
        }
    }

    func prompt(for selection: String) -> String {
        let quote = String(selection.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))
        let format = switch self {
        case .explain: String(localized: "selection.action.explain.prompt", defaultValue: "Explain this passage in plain language. Keep the explanation grounded in the quoted text:\n\n\u{201c}%@\u{201d}")
        case .improve: String(localized: "selection.action.improve.prompt", defaultValue: "Improve this passage for clarity and flow while preserving its meaning:\n\n\u{201c}%@\u{201d}")
        case .shorten: String(localized: "selection.action.shorten.prompt", defaultValue: "Shorten this passage while preserving its key meaning:\n\n\u{201c}%@\u{201d}")
        case .tone: String(localized: "selection.action.tone.prompt", defaultValue: "Rewrite this passage in a natural, appropriate tone while preserving its meaning:\n\n\u{201c}%@\u{201d}")
        case .grammar: String(localized: "selection.action.grammar.prompt", defaultValue: "Correct the grammar and punctuation in this passage without changing its meaning:\n\n\u{201c}%@\u{201d}")
        }
        return String(format: format, quote)
    }
}

private struct FamiliarSelectionActions: View {
    let selection: String
    let onInsertPrompt: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: FamiliarAISurfaceMetric.spaceXS) {
                ForEach(FamiliarSelectionAction.allCases) { action in
                    Button {
                        onInsertPrompt(action.prompt(for: selection))
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FamiliarAISurfaceColor.ink)
                            .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
                            .frame(minHeight: 32)
                            .background(FamiliarAISurfaceColor.surface, in: Capsule())
                            .overlay { Capsule().stroke(FamiliarAISurfaceColor.line, lineWidth: FamiliarAISurfaceMetric.hairline) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("selection.action.\(action.rawValue)")
                    .accessibilityLabel(action.title)
                    .accessibilityHint(String(localized: "selection.action.hint", defaultValue: "Fills the composer with the selected passage without sending"))
                }
            }
            .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "selection.actions", defaultValue: "Actions for selected text"))
    }
}

private struct FamiliarMessageAction: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: FamiliarAISurfaceMetric.rowHeight, height: FamiliarAISurfaceMetric.rowHeight, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct FamiliarImageAttachmentView: View {
    let relativePath: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.window, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.window, style: .continuous)
                    .fill(FamiliarAISurfaceColor.inset)
                    .frame(width: 200, height: 140)
                    .overlay { ProgressView() }
            }
        }
        .task(id: relativePath) {
            if let url = FamiliarAttachmentStore.url(for: relativePath) { image = UIImage(contentsOfFile: url.path) }
        }
    }
}

private struct FamiliarModelSwitchRow: View {
    let marker: FamiliarModelSwitchSnapshot

    var body: some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
            Rectangle().fill(FamiliarAISurfaceColor.line).frame(height: FamiliarAISurfaceMetric.hairline)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(FamiliarAISurfaceColor.inkSecondary).lineLimit(1)
            Rectangle().fill(FamiliarAISurfaceColor.line).frame(height: FamiliarAISurfaceMetric.hairline)
        }
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        let provider = FamiliarProviderCatalog.descriptor(for: marker.currentProviderID)
        return String(format: String(localized: "model.switched_marker"), provider?.displayName ?? marker.currentProviderID, provider?.model(for: marker.currentModelID).displayName ?? marker.currentModelID)
    }
}

struct FamiliarAssistantTurnVisualFixture: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var sendCount = 0

    private var loadingThinkingContent: FamiliarThinkingContent {
        FamiliarThinkingContent(
            variant: .steps,
            isWorking: true,
            header: Self.loadingSurface.title,
            settledHeader: Self.loadingSurface.title,
            query: nil,
            rows: [],
            truncatedCount: 0
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXL) {
                fixtureSection(String(localized: "visual.fixture.loading", defaultValue: "Loading"), id: "loading") {
                    FamiliarThinkingState(
                        content: loadingThinkingContent,
                        onSettled: nil,
                        reduceMotion: reduceMotion
                    )
                }
                fixtureSection(String(localized: "visual.fixture.reasoning", defaultValue: "Reasoning"), id: "reasoning") {
                    DisclosureGroup {
                        Text(String(localized: "visual.fixture.reasoning.detail", defaultValue: "Compared the request with the available context and checked the important constraints."))
                            .font(.callout)
                            .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                    } label: {
                        Label(String(localized: "response.reasoning_summary", defaultValue: "Reasoning summary"), systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                    }
                }
                fixtureSection(String(localized: "visual.fixture.search", defaultValue: "Search"), id: "search") {
                    FamiliarTypedResult(surface: Self.searchSurface, readURLs: ["https://example.com/read"])
                }
                fixtureSection(String(localized: "visual.fixture.approval", defaultValue: "Approval"), id: "approval") {
                    turnSurface(Self.approvalSurface)
                }
                fixtureSection(String(localized: "visual.fixture.clarification", defaultValue: "Clarification"), id: "clarification") {
                    turnSurface(Self.clarificationSurface)
                }
                fixtureSection(String(localized: "visual.fixture.task", defaultValue: "Task"), id: "task") {
                    turnSurface(Self.taskSurface)
                }
                fixtureSection(String(localized: "visual.fixture.recommendation", defaultValue: "Recommendation"), id: "recommendation") {
                    turnSurface(Self.recommendationSurface)
                }
                fixtureSection(String(localized: "visual.fixture.insight", defaultValue: "Insight"), id: "insight") {
                    turnSurface(Self.insightSurface)
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
                        .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                        .accessibilityIdentifier("visual-fixture.send-count")
                        .accessibilityLabel(String(localized: "visual.fixture.send_count", defaultValue: "Send count"))
                        .accessibilityValue(Text(sendCount, format: .number))
                }
                fixtureSection(String(localized: "visual.fixture.sources", defaultValue: "Sources"), id: "sources") {
                    FamiliarInlineSources(sources: Self.sources)
                }
            }
            .padding(FamiliarAISurfaceMetric.spaceL)
            .frame(maxWidth: FamiliarAISurfaceMetric.timelineWidth)
            .frame(maxWidth: .infinity)
        }
        .background(FamiliarAISurfaceColor.page)
        .navigationTitle(String(localized: "visual.fixture.title", defaultValue: "Assistant Turn Fixture"))
    }

    private func fixtureSection<Content: View>(_ title: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("visual-fixture.\(id)")
    }

    private func turnSurface(_ surface: FamiliarSurfaceDescriptor) -> some View {
        FamiliarTurnSurface(
            surface: surface,
            canUndo: surface.kind == .mutationReceipt,
            onResolveApproval: { _, _ in },
            onResolveClarification: { _, _ in },
            onInsertPrompt: { draft = $0 },
            onUndo: {},
            onRetry: {}
        )
    }

    private static let loadingSurface = FamiliarSurfaceDescriptor(
        id: "fixture-loading",
        runID: "fixture",
        kind: .runStatus,
        placement: .topLevel,
        phase: .running,
        title: String(localized: "agent.status.thinking"),
        startedAt: Date()
    )

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

    private static let taskSurface = resultSurface(
        id: "fixture-task",
        kind: .taskList,
        payload: .taskList(.init(planID: "fixture", title: String(localized: "visual.fixture.task.title", defaultValue: "Release checklist"), tasks: [
            .init(id: "build", title: String(localized: "visual.fixture.task.build", defaultValue: "Build"), status: .completed),
            .init(id: "verify", title: String(localized: "visual.fixture.task.verify", defaultValue: "Verify"), status: .running, progress: 0.62),
            .init(id: "ship", title: String(localized: "visual.fixture.task.ship", defaultValue: "Ship"), status: .pending)
        ]))
    )

    private static let recommendationSurface = resultSurface(
        id: "fixture-recommendation",
        kind: .recommendation,
        payload: .recommendation(.init(
            title: String(localized: "visual.fixture.recommendation.title", defaultValue: "Verify on device next"),
            explanation: String(localized: "visual.fixture.recommendation.detail", defaultValue: "The build is ready for physical-device visual acceptance."),
            nextPrompt: String(localized: "visual.fixture.recommendation.prompt", defaultValue: "Create a focused device verification checklist"),
            alternatives: [.init(id: "a", title: String(localized: "visual.fixture.recommendation.alternative", defaultValue: "Review accessibility"), prompt: String(localized: "visual.fixture.recommendation.alternative_prompt", defaultValue: "Review the accessibility checklist"))],
            confidenceLevel: .high
        ))
    )

    private static let insightSurface = resultSurface(
        id: "fixture-insight",
        kind: .insight,
        payload: .insight(.init(
            title: String(localized: "visual.fixture.insight.title", defaultValue: "Response quality"),
            explanation: String(localized: "visual.fixture.insight.detail", defaultValue: "Clarity improved while the response became shorter."),
            metrics: [
                .init(label: String(localized: "visual.fixture.insight.clarity", defaultValue: "Clarity"), value: 92, unit: "%", change: 8),
                .init(label: String(localized: "visual.fixture.insight.length", defaultValue: "Length"), value: 68, unit: "%", change: -12)
            ]
        ))
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
        FamiliarSource(id: "fixture-read", kind: .fetchedPage, title: String(localized: "visual.fixture.source.read", defaultValue: "Read source fixture"), url: URL(string: "https://example.com/read")!, siteName: "example.com", snippet: nil, retrievedAt: Date()),
        FamiliarSource(id: "fixture-found", kind: .searchResult, title: String(localized: "visual.fixture.source.discovered", defaultValue: "Discovered source fixture"), url: URL(string: "https://example.org/found")!, siteName: "example.org", snippet: nil, retrievedAt: Date())
    ]

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

private struct FamiliarBottomPositionPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
