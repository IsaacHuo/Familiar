import Charts
import Observation
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
    let liveController: FamiliarChatController
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
    @State private var runtimeDisclosure = FamiliarRuntimeDisclosureState()

    private var timelineItems: [FamiliarTimelineItem] {
        var items = messages.map(FamiliarTimelineItem.message)
        items += modelSwitches.map(FamiliarTimelineItem.modelSwitch)
        items += agentRuns
            .filter { $0.responseMessageID == nil && $0.status != .running }
            .map(FamiliarTimelineItem.recovery)
        return items.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    var body: some View {
        // Rebuild only with history inputs; preserve the first matching Run.
        let runsByMessage = agentRuns.reduce(into: [UUID: FamiliarAgentRunSnapshot]()) { index, run in
            if let id = run.responseMessageID, index[id] == nil { index[id] = run }
        }
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: FamiliarAISurfaceMetric.spaceXL) {
                        ForEach(timelineItems) { item in
                            switch item {
                            case .message(let message):
                                FamiliarMessageRow(
                                    message: message,
                                    run: runsByMessage[message.id],
                                    disclosure: runtimeDisclosure,
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
                                    disclosure: runtimeDisclosure,
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

                        FamiliarLiveAssistantTurn(controller: liveController, disclosure: runtimeDisclosure,
                            onResolveConfirmation: onResolveConfirmation, onResolveClarification: onResolveClarification,
                            onInsertPrompt: onInsertPrompt, onUndo: onUndo, onRetryRecovery: onRetryRecovery,
                            onContentChange: { animated in scrollToLatest(proxy, animated: animated) })

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

/// Only this subtree observes token deltas. History/order and Chat controls
/// receive no streaming strings and retain their existing input lifetimes.
private struct FamiliarLiveAssistantTurn: View {
    let controller: FamiliarChatController
    let disclosure: FamiliarRuntimeDisclosureState
    let onResolveConfirmation: (UUID, FamiliarToolConfirmationDecision) -> Void
    let onResolveClarification: (UUID, FamiliarClarificationResolution) -> Void
    let onInsertPrompt: (String) -> Void
    let onUndo: (String, String) -> Void
    let onRetryRecovery: (String) -> Void
    let onContentChange: (Bool) -> Void

    var body: some View {
        let surfaces = controller.surfaces.orderedSurfaces
        Group {
            if !surfaces.isEmpty || !controller.runtimeContentBlocks.isEmpty {
                FamiliarAssistantTurn(message: nil, run: nil, surfaces: surfaces,
                    disclosure: disclosure, liveController: controller,
                    onLiveContentChange: onContentChange,
                    availableUndoKeys: controller.availableUndoKeys, completedUndoKeys: controller.completedUndoKeys,
                    onResolveApproval: onResolveConfirmation, onResolveClarification: onResolveClarification,
                    onInsertPrompt: onInsertPrompt, onUndo: onUndo, onRetryRecovery: onRetryRecovery)
                    .id(controller.streamingMessageID?.uuidString ?? "active-assistant-turn")
            }
        }
        .onChange(of: surfaces) { _, _ in onContentChange(true) }
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
    let disclosure: FamiliarRuntimeDisclosureState
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
                    disclosure: disclosure,
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
                FamiliarAttachmentPreviewView(url: url)
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
            VStack(alignment: .trailing, spacing: FamiliarAISurfaceMetric.spaceS) {
                ForEach(imageAttachments) { attachment in
                    Button { previewAttachment = attachment } label: {
                        FamiliarImageAttachmentView(relativePath: attachment.relativePath)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: String(localized: "attachment.preview"), attachment.filename))
                }

                ForEach(documentAttachments) { attachment in
                    Button { previewAttachment = attachment } label: {
                        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                            Image(systemName: attachment.mimeType == "application/pdf" ? "doc.richtext" : "doc.text")
                                .foregroundStyle(FamiliarTheme.accent)
                            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                                Text(attachment.filename).font(FamiliarTypography.secondary.weight(.medium)).lineLimit(2)
                                Text("\(attachment.detectedFormat.uppercased()) · \(ByteCountFormatter.string(fromByteCount: attachment.byteSize, countStyle: .file))")
                                    .font(FamiliarTypography.caption)
                                    .foregroundStyle(FamiliarTheme.inkSecondary)
                            }
                        }
                        .padding(FamiliarAISurfaceMetric.spaceM)
                        .frame(maxWidth: 280, alignment: .leading)
                        .background(FamiliarTheme.userFill, in: RoundedRectangle(cornerRadius: FamiliarRadius.overlay, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: String(localized: "attachment.preview"), attachment.filename))
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(FamiliarTypography.body)
                        .textSelection(.enabled)
                        .padding(FamiliarAISurfaceMetric.spaceM)
                        .background(FamiliarTheme.userFill, in: RoundedRectangle(cornerRadius: FamiliarRadius.overlay, style: .continuous))
                }
            }
            .frame(maxWidth: 300, alignment: .trailing)
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

    private var imageAttachments: [FamiliarAttachmentSnapshot] {
        message.attachments.filter { $0.kind == .image }
    }

    private var documentAttachments: [FamiliarAttachmentSnapshot] {
        message.attachments.filter { $0.kind != .image }
    }
}

private struct FamiliarAssistantTurn: View {
    let message: FamiliarMessageSnapshot?
    let run: FamiliarAgentRunSnapshot?
    let surfaces: [FamiliarSurfaceDescriptor]
    let disclosure: FamiliarRuntimeDisclosureState
    var liveController: FamiliarChatController? = nil
    var onLiveContentChange: ((Bool) -> Void)? = nil
    let availableUndoKeys: Set<String>
    let completedUndoKeys: Set<String>
    let onResolveApproval: (UUID, FamiliarToolConfirmationDecision) -> Void
    let onResolveClarification: (UUID, FamiliarClarificationResolution) -> Void
    let onInsertPrompt: (String) -> Void
    let onUndo: (String, String) -> Void
    let onRetryRecovery: (String) -> Void
    var onRetryMessage: (() -> Void)? = nil

    private var status: FamiliarSurfaceDescriptor? { surfaces.first { $0.kind == .runStatus } }
    private var contentBlocks: [FamiliarAssistantContentBlock] {
        if let liveController { return liveController.runtimeContentBlocks }
        let markdown = (message?.responseBlocks ?? run?.responseBlocks ?? []).filter { $0.kind == .markdown || $0.kind == .text }
        let text: [FamiliarAssistantTextBlock]
        if markdown.isEmpty, let message, !message.content.isEmpty {
            text = [.init(message: message, order: (surfaces.map(\.sequence).max() ?? -1) + 1)]
        } else {
            text = markdown.map(FamiliarAssistantTextBlock.init)
        }
        return FamiliarAssistantResponseProjection.blocks(text: text, surfaces: surfaces)
    }

    private var canRetry: Bool {
        guard run?.regenerationRequiresInspection != true, liveController == nil else { return false }
        return !surfaces.contains { surface in
            surface.effect != nil && surface.effect != .read &&
                (surface.phase == .succeeded || ["tool_commit_unconfirmed", "tool_persistence_failed", "tool_rollback_failed"].contains(surface.failureCode ?? ""))
        }
    }

    var body: some View {
        let blocks = contentBlocks
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
            ForEach(blocks) { block in
                switch block {
                case .text(let text):
                    if let liveController {
                        FamiliarLiveMarkdownBlock(controller: liveController, blockID: text.id,
                            onContentChange: { onLiveContentChange?(false) })
                    } else {
                        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
                            FamiliarMarkdownWebView(markdown: text.content, sources: message?.sources ?? [], isStreaming: false)
                            if text.state != .completed {
                                Label(String(localized: "runtime.ui.incomplete_text"), systemImage: "pause.circle")
                                    .font(FamiliarTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                case .runtime(let activity):
                    FamiliarRuntimeCard(activity: activity, disclosure: disclosure, context: run?.context,
                        metrics: replyMetrics)
                case .surface(let surface):
                    if surface.kind == .activityTrace {
                        Label(surface.title, systemImage: "exclamationmark.circle")
                            .font(FamiliarTypography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        FamiliarTurnSurface(surface: adjustedUndoPhase(surface), canUndo: canUndo(surface),
                            onResolveApproval: onResolveApproval, onResolveClarification: onResolveClarification,
                            onInsertPrompt: onInsertPrompt, onUndo: { onUndo(surface.runID, surface.toolCallID ?? "") },
                            onRetry: surface.kind == .failure && surface.toolCallID == nil && canRetry ? retryAction : nil)
                    }
                }
            }
            if let liveController {
                FamiliarLiveReplyStatus(controller: liveController)
            }
            if let message {
                FamiliarAssistantFooter(message: message, onRetryMessage: canRetry ? onRetryMessage : nil, onInsertPrompt: onInsertPrompt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var replyMetrics: FamiliarReplyMetrics? {
        guard let startedAt = run?.startedAt ?? status?.startedAt else { return nil }
        return .init(startedAt: startedAt, finishedAt: run?.finishedAt ?? status?.finishedAt, firstTokenAt: run?.firstTokenAt)
    }
    private func adjustedUndoPhase(_ surface: FamiliarSurfaceDescriptor) -> FamiliarSurfaceDescriptor {
        guard let toolCallID = surface.toolCallID, completedUndoKeys.contains(surface.runID + ":" + toolCallID) else { return surface }
        var value = surface
        value.phase = .undone
        return value
    }
    private func canUndo(_ surface: FamiliarSurfaceDescriptor) -> Bool {
        guard let toolCallID = surface.toolCallID else { return false }
        return availableUndoKeys.contains(surface.runID + ":" + toolCallID)
    }
    private var retryAction: (() -> Void)? {
        guard let id = run?.id ?? surfaces.first?.runID else { return nil }
        return { onRetryRecovery(id) }
    }
}

/// Token observation is confined to text/status; Runtime aggregation is updated
/// by the Controller only for activity events and nonempty text boundaries.
private struct FamiliarLiveMarkdownBlock: View {
    let controller: FamiliarChatController
    let blockID: String
    let onContentChange: () -> Void
    var body: some View {
        if let block = controller.streamingResponseBlocks.first(where: { "text:\($0.id.uuidString)" == blockID }) {
            FamiliarMarkdownWebView(markdown: block.content, isStreaming: block.isStreaming)
                .onChange(of: block.content) { _, _ in onContentChange() }
        }
    }
}

private struct FamiliarLiveReplyStatus: View {
    let controller: FamiliarChatController
    var body: some View {
        let status = controller.surfaces.orderedSurfaces.first { $0.kind == .runStatus }
        let hasActiveCard = controller.runtimeContentBlocks.contains { block in
            if case .runtime(let activity) = block { return activity.status.isActive }
            return false
        }
        let hasInteraction = !controller.pendingConfirmations.isEmpty || !controller.pendingClarifications.isEmpty
        let isWriting = controller.streamingResponseBlocks.last.map { $0.isStreaming && !$0.content.isEmpty } ?? false
        if let status, !status.phase.isTerminal, !hasActiveCard, !hasInteraction, !isWriting {
            HStack(spacing: FamiliarSpacing.small) {
                ProgressView().controlSize(.small)
                Text(status.title).font(FamiliarTypography.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

@MainActor
@Observable
private final class FamiliarRuntimeDisclosureState {
    var expanded: Set<String> = []
    func binding(for id: String) -> Binding<Bool> {
        Binding(get: { self.expanded.contains(id) }, set: { value in
            if value { self.expanded.insert(id) } else { self.expanded.remove(id) }
        })
    }
}

private struct FamiliarRuntimeCard: View {
    let activity: FamiliarRuntimeActivityGroup
    let disclosure: FamiliarRuntimeDisclosureState
    var context: FamiliarRunContextSummary? = nil
    var metrics: FamiliarReplyMetrics? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DisclosureGroup(isExpanded: disclosure.binding(for: activity.id)) {
            VStack(alignment: .leading, spacing: FamiliarSpacing.medium) {
                ForEach(activity.stages) { stage in
                    FamiliarRuntimeStageView(stage: stage, disclosure: disclosure)
                }
                DisclosureGroup(isExpanded: disclosure.binding(for: "technical:\(activity.id)")) {
                    VStack(alignment: .leading, spacing: FamiliarSpacing.large) {
                        if let context { FamiliarContextTrace(context: context, metrics: metrics) }
                        ForEach(activity.activities) { surface in
                            FamiliarRuntimeTechnicalDetails(surface: surface)
                        }
                        ForEach(activity.notices) { notice in
                            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                                Text(notice.title).font(FamiliarTypography.caption.weight(.medium))
                                if let call = notice.toolCallID { Text(call).font(FamiliarTypography.caption.monospaced()) }
                                if let detail = notice.detail { Text(FamiliarRuntimeTechnicalText.redacted(detail)).textSelection(.enabled) }
                            }
                        }
                    }
                    .font(FamiliarTypography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, FamiliarSpacing.small)
                } label: {
                    Text(String(localized: "runtime.ui.technical_details"))
                        .font(FamiliarTypography.caption)
                        .frame(minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
                }
            }
            .padding(.top, FamiliarSpacing.small)
        } label: {
            HStack(alignment: .center, spacing: FamiliarSpacing.small) {
                FamiliarRuntimeStatusIcon(status: activity.status)
                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                    if activity.status.isActive {
                        Text(activity.activeTitle).font(FamiliarTypography.secondary.weight(.medium))
                    }
                    Text(activity.summary).font(FamiliarTypography.caption)
                }
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .tint(.secondary)
        .padding(.horizontal, activity.status.isActive ? FamiliarSpacing.medium : 0)
        .padding(.vertical, activity.status.isActive ? FamiliarSpacing.xSmall : 0)
        .background(activity.status.isActive ? FamiliarTheme.inset : Color.clear,
                    in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
        .transaction { if reduceMotion { $0.animation = nil } }
        .accessibilityIdentifier("runtime.card.\(activity.id)")
    }
}

private struct FamiliarRuntimeStageView: View {
    let stage: FamiliarRuntimeStage
    let disclosure: FamiliarRuntimeDisclosureState

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
            HStack(spacing: FamiliarSpacing.small) {
                FamiliarRuntimeStatusIcon(status: stage.status)
                Text(stage.kind.title).font(FamiliarTypography.secondary)
                Spacer(minLength: FamiliarSpacing.small)
                Text(statusTitle).font(FamiliarTypography.caption)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            Text(String(format: String(localized: "runtime.ui.call_count"), stage.activities.count))
                .font(FamiliarTypography.caption)
                .foregroundStyle(.tertiary)
            DisclosureGroup(isExpanded: disclosure.binding(for: "results:\(stage.id)")) {
                VStack(alignment: .leading, spacing: FamiliarSpacing.medium) {
                    if stage.kind == .search {
                        FamiliarRuntimeSourceResults(results: stage.searchResults)
                    } else {
                        ForEach(stage.activities) { surface in FamiliarRuntimeResult(surface: surface) }
                    }
                }
                .padding(.top, FamiliarSpacing.small)
            } label: {
                Text(String(localized: "runtime.ui.results"))
                    .font(FamiliarTypography.caption)
                    .frame(minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
            }
            .tint(.secondary)
        }
    }

    private var statusTitle: String {
        switch stage.status {
        case .running: String(localized: "runtime.ui.running")
        case .completed: String(localized: "runtime.ui.completed")
        case .warning: String(localized: "runtime.ui.partial_failure")
        case .failed: String(localized: "settings.runs.failed")
        case .waiting: String(localized: "runtime.ui.waiting")
        case .cancelled:
            String(localized: stage.activities.allSatisfy { $0.phase == .cancelled && $0.approvalDecision == .cancelled }
                ? "runtime.ui.skipped" : "runtime.ui.stopped")
        case .undone: String(localized: "common.undone")
        }
    }
}

private struct FamiliarRuntimeStatusIcon: View {
    let status: FamiliarRuntimeDisplayStatus
    var body: some View {
        Group {
            if status == .running {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .font(FamiliarTypography.caption)
                    .foregroundStyle(status == .failed ? FamiliarTheme.failure : status == .warning ? FamiliarTheme.warning : FamiliarTheme.inkSecondary)
            }
        }
        .frame(width: FamiliarIconSize.standard, height: FamiliarIconSize.standard)
        .accessibilityHidden(true)
    }
    private var symbol: String {
        switch status {
        case .running: "circle.dotted"
        case .completed: "checkmark.circle"
        case .warning: "exclamationmark.circle"
        case .failed: "exclamationmark.triangle"
        case .waiting: "clock"
        case .cancelled: "pause.circle"
        case .undone: "arrow.uturn.backward.circle"
        }
    }
}

private struct FamiliarRuntimeResult: View {
    let surface: FamiliarSurfaceDescriptor
    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
            if surface.phase == .failed || surface.phase == .cancelled {
                Label(surface.title, systemImage: surface.phase == .cancelled ? "pause.circle" : "exclamationmark.circle")
                    .font(FamiliarTypography.caption).foregroundStyle(.secondary)
            } else if case .searchResults(let search)? = surface.resultEnvelope?.presentation.content {
                Text(search.query).font(FamiliarTypography.caption).foregroundStyle(.secondary)
                FamiliarRuntimeSourceResults(results: search.results)
            } else {
                switch surface.resultEnvelope?.presentation.content {
                case .contextMatches: FamiliarContextMatchesSurface(surface: surface)
                case .recordCollection: FamiliarRecordCollectionSurface(surface: surface)
                case .shellExecution:
                    Text(surface.title).font(FamiliarTypography.caption).foregroundStyle(.secondary)
                default: FamiliarTypedResult(surface: surface)
                }
                if surface.toolName == "web_fetch", surface.phase == .succeeded,
                   let call = surface.toolCallID, let envelope = surface.resultEnvelope,
                   let output = try? JSONDecoder().decode(FamiliarWebFetchOutput.self, from: Data(envelope.modelContent.utf8)) {
                    FamiliarWebCaptureSaveButton(runtimeID: surface.runID, toolCallID: call, truncated: output.truncated)
                }
            }
        }
    }
}

private struct FamiliarRuntimeSourceResults: View {
    let results: [FamiliarToolPresentationPayload.SearchResult]
    var body: some View {
        ForEach(results, id: \.url) { result in
            if let url = URL(string: result.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                        Text(result.title).font(FamiliarTypography.caption)
                        Text(url.host ?? result.url).font(FamiliarTypography.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FamiliarRuntimeTechnicalDetails: View {
    let surface: FamiliarSurfaceDescriptor
    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
            LabeledContent(String(localized: "runtime.ui.tool_name"), value: surface.toolName ?? surface.title)
            if let arguments = surface.argumentsJSON {
                Text(FamiliarRuntimeTechnicalText.redacted(arguments)).font(FamiliarTypography.caption.monospaced()).textSelection(.enabled)
            } else {
                Text(String(localized: "runtime.ui.parameters_unavailable")).foregroundStyle(.tertiary)
            }
            if case .document(let document)? = surface.resultEnvelope?.presentation.content, let url = document.url {
                Text(FamiliarRuntimeTechnicalText.redacted(url)).textSelection(.enabled)
            }
            if let code = surface.failureCode { Text(code).font(FamiliarTypography.caption.monospaced()).textSelection(.enabled) }
            if let detail = surface.detail, !detail.isEmpty {
                Text(FamiliarRuntimeTechnicalText.redacted(detail)).textSelection(.enabled)
            }
            if case .shellExecution = surface.resultEnvelope?.presentation.content {
                FamiliarShellExecutionSurface(surface: surface)
            }
        }
        .font(FamiliarTypography.caption)
        .foregroundStyle(.secondary)
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
                FamiliarApprovalCard(surface: surface, onResolve: onResolveApproval)
            case .mutationReceipt, .artifact:
                FamiliarWriteReceipt(surface: surface, canUndo: canUndo, onUndo: onUndo)
            case .failure:
                FamiliarFailureRecovery(surface: surface, onRetry: onRetry, canUndo: canUndo, onUndo: onUndo)
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
            case .share:
                FamiliarShareDraftSurface(surface: surface)
            case .shell:
                FamiliarShellExecutionSurface(surface: surface)
            case .diff:
                FamiliarDiffSurface(surface: surface)
            case .toolSummary:
                HStack(spacing: FamiliarSpacing.small) {
                    FamiliarRuntimeStatusIcon(status: FamiliarRuntimeActivityGroup.displayStatus(surface))
                    Text(surface.title).font(FamiliarTypography.caption).foregroundStyle(.secondary)
                }
            case .context:
                if case .contextMatches = surface.resultEnvelope?.presentation.content {
                    FamiliarContextMatchesSurface(surface: surface)
                } else {
                    FamiliarTypedResult(surface: surface)
                }
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

private struct FamiliarShareDraftSurface: View {
    let surface: FamiliarSurfaceDescriptor
    @State private var preview: FamiliarPreparedFilePreview?

    var body: some View {
        Group {
            if case .shareDraft(let draft) = surface.resultEnvelope?.presentation.content {
                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                    HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceS) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(FamiliarTheme.accentInk)
                            .frame(width: FamiliarAISurfaceMetric.icon)
                        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                            Text(draft.title ?? String(localized: "common.share"))
                                .font(FamiliarTypography.secondary.weight(.semibold))
                                .foregroundStyle(FamiliarTheme.ink)
                            Text(draft.text)
                                .font(FamiliarTypography.caption)
                                .foregroundStyle(FamiliarTheme.inkSecondary)
                                .lineLimit(6)
                                .textSelection(.enabled)
                        }
                    }
                    ShareLink(item: draft.text) {
                        Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                            .font(FamiliarTypography.secondary.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint(String(localized: "share.draft.accessibility_hint", defaultValue: "Opens the system share sheet. Familiar does not send this automatically."))
                }
                .padding(FamiliarAISurfaceMetric.spaceM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FamiliarTheme.accentTint, in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
            } else if case .document(let document) = surface.resultEnvelope?.presentation.content,
                      let value = document.url,
                      let url = URL(string: value),
                      url.isFileURL {
                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                    Label(document.title ?? document.summary, systemImage: "doc")
                        .font(FamiliarTypography.secondary.weight(.semibold))
                        .foregroundStyle(FamiliarTheme.ink)
                    HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                        Button {
                            preview = FamiliarPreparedFilePreview(url: url)
                        } label: {
                            Label(String(localized: "common.preview", defaultValue: "Preview"), systemImage: "eye")
                                .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                        }
                        .buttonStyle(.bordered)
                        ShareLink(item: url) {
                            Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                                .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(FamiliarAISurfaceMetric.spaceM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FamiliarTheme.accentTint, in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
            }
        }
        .sheet(item: $preview) { item in
            FamiliarAttachmentPreviewView(url: item.url)
        }
    }
}

private struct FamiliarPreparedFilePreview: Identifiable {
    let url: URL
    var format: FamiliarArtifactFormat? = nil
    var id: String { url.absoluteString }
}

private struct FamiliarTaskListSurface: View {
    let surface: FamiliarSurfaceDescriptor

    var body: some View {
        if case .taskList(let plan) = surface.resultEnvelope?.presentation.content {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                    Image(systemName: "checklist")
                        .foregroundStyle(FamiliarTheme.accent)
                    Text(String(format: String(localized: "runtime.ui.model_plan"), plan.title))
                        .font(FamiliarTypography.sectionTitle)
                        .foregroundStyle(FamiliarTheme.ink)
                    Spacer(minLength: 0)
                    Text("\(plan.tasks.filter { $0.status == .completed }.count)/\(plan.tasks.count)")
                        .font(FamiliarTypography.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(FamiliarTheme.inkSecondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(plan.tasks.enumerated()), id: \.element.id) { index, task in
                        FamiliarTaskRow(task: task)
                        if index < plan.tasks.count - 1 {
                            Rectangle()
                                .fill(FamiliarTheme.line)
                                .frame(height: FamiliarAISurfaceMetric.hairline)
                                .padding(.leading, FamiliarAISurfaceMetric.icon + FamiliarAISurfaceMetric.spaceM)
                        }
                    }
                }
            }
            .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(FamiliarTheme.accent)
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
                    .font(FamiliarTypography.secondary.weight(.medium))
                    .foregroundStyle(FamiliarTheme.ink)
                if let detail = task.detail, !detail.isEmpty {
                    Text(detail)
                        .font(FamiliarTypography.caption)
                        .foregroundStyle(FamiliarTheme.inkSecondary)
                }
                if let progress = task.progress, progress.isFinite {
                    HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                        ProgressView(value: progress)
                            .tint(tone)
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(FamiliarTheme.inkTertiary)
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
        case .pending: FamiliarTheme.inkTertiary
        case .running: FamiliarTheme.accent
        case .completed: FamiliarTheme.success
        case .failed: FamiliarTheme.failure
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
                        .foregroundStyle(FamiliarTheme.accent)
                    Text(recommendation.title)
                        .font(FamiliarTypography.sectionTitle)
                        .foregroundStyle(FamiliarTheme.ink)
                    Spacer(minLength: 0)
                    if let confidence = recommendation.confidenceLevel {
                        Text(confidenceTitle(confidence))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(FamiliarTheme.accentInk)
                            .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
                            .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
                            .background(FamiliarTheme.accentTint, in: Capsule())
                    }
                }
                Text(recommendation.explanation)
                    .font(FamiliarTypography.secondary)
                    .foregroundStyle(FamiliarTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onInsertPrompt(recommendation.nextPrompt)
                } label: {
                    HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                        Text(recommendation.nextPrompt)
                            .font(FamiliarTypography.secondary.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left")
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
                    .frame(minHeight: FamiliarAISurfaceMetric.rowHeight)
                    .background(FamiliarTheme.accent, in: RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "recommendation.fill_hint", defaultValue: "Fills the composer without sending"))

                ForEach(recommendation.alternatives) { alternative in
                    Button {
                        onInsertPrompt(alternative.prompt)
                    } label: {
                        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                            Text(alternative.title)
                                .font(FamiliarTypography.secondary.weight(.medium))
                            Spacer(minLength: 0)
                            Image(systemName: "plus")
                                .font(FamiliarTypography.caption.weight(.semibold))
                        }
                        .foregroundStyle(FamiliarTheme.ink)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(String(localized: "recommendation.fill_hint", defaultValue: "Fills the composer without sending"))
                }
            }
            .padding(FamiliarAISurfaceMetric.spaceL)
            .background(FamiliarTheme.accentTint.opacity(0.55), in: RoundedRectangle(cornerRadius: FamiliarRadius.overlay, style: .continuous))
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
                    .font(FamiliarTypography.sectionTitle)
                    .foregroundStyle(FamiliarTheme.ink)
                Text(insight.explanation)
                    .font(FamiliarTypography.secondary)
                    .foregroundStyle(FamiliarTheme.inkSecondary)

                if !insight.metrics.isEmpty {
                    Chart(Array(insight.metrics.enumerated()), id: \.offset) { _, metric in
                        BarMark(
                            x: .value(String(localized: "insight.metric.value", defaultValue: "Value"), metric.value),
                            y: .value(String(localized: "insight.metric.name", defaultValue: "Metric"), metric.label)
                        )
                        .foregroundStyle(metric.value < 0 ? FamiliarTheme.warning : FamiliarTheme.accent)
                        .annotation(position: metric.value < 0 ? .leading : .trailing, alignment: .center) {
                            VStack(alignment: metric.value < 0 ? .trailing : .leading, spacing: 1) {
                                Text(metricValue(metric))
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                if let change = metric.change {
                                    Text(change, format: .number.sign(strategy: .always()))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(change < 0 ? FamiliarTheme.failure : FamiliarTheme.success)
                                }
                            }
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisValueLabel()
                                .font(FamiliarTypography.caption)
                                .foregroundStyle(FamiliarTheme.inkSecondary)
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
                    .foregroundStyle(surface.phase == .failed ? FamiliarTheme.inkTertiary : FamiliarTheme.accent)
                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                    Text(String(localized: "clarification.title", defaultValue: "One question"))
                        .font(FamiliarTypography.caption.weight(.semibold))
                        .foregroundStyle(FamiliarTheme.inkSecondary)
                    Text(surface.title)
                        .font(FamiliarTypography.sectionTitle)
                        .foregroundStyle(FamiliarTheme.ink)
                }
            }

            if surface.phase == .awaitingClarification, let requestID = surface.clarificationRequestID {
                ForEach(surface.clarificationOptions) { option in
                    Button {
                        onResolve(requestID, .selectedOption(id: option.id, label: option.label))
                    } label: {
                        HStack {
                            Text(option.label)
                                .font(FamiliarTypography.secondary.weight(.medium))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(FamiliarTypography.caption.weight(.semibold))
                                .foregroundStyle(FamiliarTheme.inkTertiary)
                        }
                        .foregroundStyle(FamiliarTheme.ink)
                        .padding(.horizontal, FamiliarAISurfaceMetric.spaceXS)
                        .frame(minHeight: FamiliarAISurfaceMetric.rowHeight)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(FamiliarTheme.line).frame(height: FamiliarAISurfaceMetric.hairline)
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
                                .frame(width: FamiliarControlSize.minimumHitTarget, height: FamiliarControlSize.minimumHitTarget)
                                .contentShape(Rectangle())
                                .foregroundStyle(customResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FamiliarTheme.inkTertiary : FamiliarTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(customResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel(String(localized: "clarification.submit", defaultValue: "Submit answer"))
                    }
                    .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
                    .frame(minHeight: FamiliarAISurfaceMetric.rowHeight)
                    .background(FamiliarTheme.field, in: RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous))
                }
            } else if let answer = surface.clarificationResolution?.answer {
                Label(answer, systemImage: "checkmark.circle.fill")
                    .font(FamiliarTypography.secondary)
                    .foregroundStyle(FamiliarTheme.success)
            } else if let detail = surface.detail {
                Text(detail)
                    .font(FamiliarTypography.caption)
                    .foregroundStyle(FamiliarTheme.inkSecondary)
            }
        }
        .padding(FamiliarAISurfaceMetric.spaceL)
        .background(FamiliarTheme.inset, in: RoundedRectangle(cornerRadius: FamiliarRadius.overlay, style: .continuous))
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
                        .font(FamiliarTypography.secondary.weight(.semibold))
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
                .foregroundStyle(FamiliarTheme.inkSecondary)

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
                    .foregroundStyle(FamiliarTheme.inkTertiary)
                }

                ScrollView(.horizontal) {
                    Text(codePreview(code.code))
                        .font(FamiliarTypography.caption.monospaced())
                        .foregroundStyle(FamiliarTheme.ink)
                        .textSelection(.enabled)
                        .padding(FamiliarAISurfaceMetric.spaceM)
                }
                .background(FamiliarTheme.inset, in: RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous))

                if isLong(code.code) {
                    Button {
                        showsFullCode = true
                    } label: {
                        Label(String(localized: "code.view_full", defaultValue: "View full code"), systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(FamiliarTypography.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FamiliarTheme.accentInk)
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
                    .font(FamiliarTypography.body.monospaced())
                    .textSelection(.enabled)
                    .padding(FamiliarAISurfaceMetric.spaceL)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(FamiliarTheme.inset)
            .navigationTitle(code.filename ?? code.summary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    FamiliarDismissButton()
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
                        .font(FamiliarTypography.secondary.weight(.semibold))
                        .foregroundStyle(FamiliarTheme.ink)
                    Spacer(minLength: 0)
                    Text(context.query)
                        .font(FamiliarTypography.caption)
                        .foregroundStyle(FamiliarTheme.inkTertiary)
                        .lineLimit(1)
                }

                if context.matches.isEmpty {
                    Text(String(localized: "context.matches.empty", defaultValue: "No matching context"))
                        .font(FamiliarTypography.caption)
                        .foregroundStyle(FamiliarTheme.inkSecondary)
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
                        .font(FamiliarTypography.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FamiliarTheme.accentInk)
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
                    .font(FamiliarTypography.caption.weight(.semibold))
                    .foregroundStyle(FamiliarTheme.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(metadata)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(FamiliarTheme.inkTertiary)
            }
            Text(match.excerpt)
                .font(FamiliarTypography.caption)
                .foregroundStyle(FamiliarTheme.inkSecondary)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(.leading, FamiliarAISurfaceMetric.spaceM)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(FamiliarTheme.accentTint)
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
                ToolbarItem(placement: .confirmationAction) {
                    FamiliarDismissButton()
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
                    Label(surface.title, systemImage: "list.bullet.rectangle")
                        .font(FamiliarTypography.secondary.weight(.semibold))
                        .foregroundStyle(FamiliarTheme.ink)
                    Spacer(minLength: 0)
                    Text(collection.records.count, format: .number)
                        .font(FamiliarTypography.caption.monospacedDigit())
                        .foregroundStyle(FamiliarTheme.inkTertiary)
                }

                if let filter {
                    FamiliarRecordFilterChips(filter: filter, selected: $selectedFilter)
                }

                if records.isEmpty {
                    Text(String(localized: "records.empty", defaultValue: "No records"))
                        .font(FamiliarTypography.caption)
                        .foregroundStyle(FamiliarTheme.inkSecondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(records.prefix(3).enumerated()), id: \.element.id) { index, record in
                            FamiliarRecordRow(record: record)
                            if index < min(records.count, 3) - 1 {
                                Rectangle()
                                    .fill(FamiliarTheme.line)
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
                            .font(FamiliarTypography.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FamiliarTheme.accentInk)
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
                .font(FamiliarTypography.caption.weight(.medium))
                .foregroundStyle(selected == value ? FamiliarTheme.accentInk : FamiliarTheme.inkSecondary)
                .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
                .frame(minHeight: 30)
                .background(selected == value ? FamiliarTheme.accentTint : FamiliarTheme.inset, in: Capsule())
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
                .font(FamiliarTypography.caption.weight(.semibold))
                .foregroundStyle(FamiliarTheme.accent)
                .frame(width: FamiliarAISurfaceMetric.icon, height: FamiliarAISurfaceMetric.icon)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                Text(primary?.value ?? record.id)
                    .font(FamiliarTypography.secondary.weight(.medium))
                    .foregroundStyle(FamiliarTheme.ink)
                    .lineLimit(2)
                ForEach(secondary, id: \.name) { field in
                    Text("\(fieldTitle(field.name)): \(formatted(field))")
                        .font(FamiliarTypography.caption)
                        .foregroundStyle(FamiliarTheme.inkSecondary)
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
        if dateFields.contains(where: { field.name.caseInsensitiveCompare($0) == .orderedSame }),
           let date = try? FamiliarISO8601.date(field.value) {
            return date.formatted(date: .abbreviated, time: .shortened)
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
                ToolbarItem(placement: .confirmationAction) {
                    FamiliarDismissButton()
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
                    .font(FamiliarTypography.secondary.weight(.semibold))
                    .foregroundStyle(FamiliarTheme.ink)
                Text(changeSummary(diff))
                    .font(FamiliarTypography.caption)
                    .foregroundStyle(FamiliarTheme.inkSecondary)
                Button {
                    showsDiff = true
                } label: {
                    Label(String(localized: "diff.view_full", defaultValue: "Review full change"), systemImage: "doc.text.magnifyingglass")
                        .font(FamiliarTypography.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FamiliarTheme.accentInk)
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
                        tint: FamiliarTheme.failureTint
                    )
                    FamiliarDiffBlock(
                        title: String(localized: "common.after", defaultValue: "After"),
                        symbol: "plus",
                        text: diff.after,
                        tint: FamiliarTheme.successTint
                    )
                }
                .padding(FamiliarAISurfaceMetric.spaceL)
            }
            .navigationTitle(diff.summary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    FamiliarDismissButton()
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
                .font(FamiliarTypography.sectionTitle)
            ScrollView(.horizontal) {
                Text(text)
                    .font(FamiliarTypography.body.monospaced())
                    .textSelection(.enabled)
                    .padding(FamiliarAISurfaceMetric.spaceM)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous))
        }
    }
}

private struct FamiliarWriteReceipt: View {
    let surface: FamiliarSurfaceDescriptor
    let canUndo: Bool
    let onUndo: () -> Void
    @State private var previewFile: FamiliarPreparedFilePreview?

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
            HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceS) {
                Image(systemName: surface.phase == .undone ? "arrow.uturn.backward.circle" : isArtifact ? "doc.richtext" : "checkmark.circle")
                    .foregroundStyle(FamiliarTheme.inkSecondary)
                    .frame(width: FamiliarAISurfaceMetric.icon)
                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                    Text(receiptTitle).font(FamiliarTypography.secondary.weight(.semibold)).foregroundStyle(FamiliarTheme.ink)
                    if let detail = receiptDetail {
                        Text(detail).font(FamiliarTypography.caption).foregroundStyle(FamiliarTheme.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if isArtifact {
                if let artifactURL {
                    HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                        Label(String(localized: "common.preview", defaultValue: "Preview"), systemImage: "eye")
                            .font(FamiliarTypography.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        ShareLink(item: artifactURL) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel(String(localized: "common.share"))
                            .frame(minWidth: FamiliarControlSize.minimumHitTarget, minHeight: FamiliarControlSize.minimumHitTarget)
                        Image(systemName: "chevron.right").font(FamiliarTypography.caption).foregroundStyle(.tertiary)
                    }
                } else {
                    Text(String(localized: surface.phase == .undone ? "runtime.ui.file_revoked" : "runtime.ui.file_unavailable"))
                        .font(FamiliarTypography.caption).foregroundStyle(.secondary)
                }
            }

            if let authorizationSummary {
                Label(authorizationSummary, systemImage: surface.automaticAuthorization ? "checkmark.shield.fill" : "hand.raised")
                    .font(FamiliarTypography.caption)
                    .foregroundStyle(FamiliarTheme.inkSecondary)
            }

            if canUndo {
                Button(String(localized: "common.undo"), action: onUndo)
                    .font(FamiliarTypography.secondary.weight(.semibold))
                    .foregroundStyle(FamiliarTheme.accentInk)
                    .frame(minHeight: FamiliarControlSize.minimumHitTarget)
            }
        }
        .padding(FamiliarAISurfaceMetric.spaceM)
        .background(FamiliarTheme.inset, in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
        // The whole card opens the deliverable. contentShape is required because the
        // background shape alone does not make the padding tappable, which would leave
        // most of the card visually inviting a tap that does nothing.
        .contentShape(RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
        .onTapGesture {
            guard let artifactURL else { return }
            previewFile = .init(url: artifactURL, format: surface.artifact?.format)
        }
        // Only announce the card as a button when there is a file to open; Undo and Share
        // stay separate elements so VoiceOver can still reach them.
        .accessibilityAddTraits(artifactURL == nil ? [] : .isButton)
        .accessibilityAction {
            guard let url = artifactURL else { return }
            previewFile = .init(url: url, format: surface.artifact?.format)
        }
        .sheet(item: $previewFile) { file in
            FamiliarAttachmentPreviewView(url: file.url, format: file.format)
        }
    }

    /// Resolved once and reused by the row, the tap target and the accessibility traits.
    /// It is `nil` when the file is missing, which is what keeps the card from presenting
    /// itself as openable when there is nothing to open.
    private var artifactURL: URL? {
        guard surface.phase != .undone, let artifact = surface.artifact else { return nil }
        return FamiliarArtifactStore().url(relativePath: artifact.relativePath)
    }

    private var isArtifact: Bool {
        if case .artifactMutation = surface.resultEnvelope?.presentation.content { return true }
        return surface.artifact != nil
    }

    private var receiptTitle: String {
        if let artifact = surface.artifact { return artifact.title }
        if case .artifactMutation(let artifact) = surface.resultEnvelope?.presentation.content { return artifact.title }
        return surface.title
    }

    private var authorizationSummary: String? {
        if surface.automaticAuthorization {
            return String(localized: "project.run.authorization.automatic", defaultValue: "Allowed by a remembered authorization")
        }
        guard surface.approvalDecision == .approved else { return nil }
        return switch surface.approvalScope {
        case .once: String(localized: "authorization.once", defaultValue: "Only Once")
        case .session: String(localized: "authorization.session", defaultValue: "Allow This Session")
        case .always: String(localized: "authorization.always", defaultValue: "Always Allow")
        case nil: String(localized: "approval.sent", defaultValue: "Approved")
        }
    }

    private var receiptDetail: String? {
        guard let content = surface.resultEnvelope?.presentation.content else { return surface.detail }
        switch content {
        case .mutationReceipt: return nil
        case .artifactMutation(let artifact):
            let size = ByteCountFormatter.string(fromByteCount: artifact.byteSize, countStyle: .file)
            return surface.artifact.map { $0.format.filenameExtension.uppercased() + " · " + size } ?? size
        case .scalar, .searchResults, .document, .contextMatches, .recordCollection, .diff, .taskList, .recommendation, .insight, .code, .shareDraft, .shellExecution: return surface.detail
        }
    }
}

private struct FamiliarFailureRecovery: View {
    let surface: FamiliarSurfaceDescriptor
    let onRetry: (() -> Void)?
    var canUndo = false
    var onUndo: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceM) {
            Image(systemName: surface.phase == .cancelled ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(surface.phase == .cancelled ? FamiliarTheme.inkTertiary : FamiliarTheme.failure)
                .frame(width: FamiliarAISurfaceMetric.icon)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
                Text(surface.title).font(FamiliarTypography.secondary.weight(.semibold)).foregroundStyle(FamiliarTheme.ink)
                if let detail = surface.detail, !detail.isEmpty {
                    Text(detail).font(FamiliarTypography.caption).foregroundStyle(FamiliarTheme.inkSecondary).textSelection(.enabled)
                }
                if canUndo {
                    Button(String(localized: "common.undo"), action: onUndo)
                        .font(FamiliarTypography.secondary.weight(.semibold))
                        .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                }
                if let onRetry {
                    Button(String(localized: "message.retry"), action: onRetry)
                        .font(FamiliarTypography.secondary.weight(.semibold))
                        .foregroundStyle(FamiliarTheme.failure)
                        .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                }
            }
        }
        .padding(FamiliarAISurfaceMetric.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface.phase == .cancelled ? FamiliarTheme.inset : FamiliarTheme.failureTint, in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
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
            Image(systemName: symbol).frame(width: FamiliarAISurfaceMetric.icon).foregroundStyle(FamiliarTheme.inkTertiary)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                Text(title).font(FamiliarTypography.caption.weight(.semibold)).foregroundStyle(FamiliarTheme.ink)
                Text(detail).font(.caption2).foregroundStyle(FamiliarTheme.inkSecondary).textSelection(.enabled)
            }
        }
    }
}

private struct FamiliarTypedResult: View {
    let surface: FamiliarSurfaceDescriptor
    var readURLs: Set<String> = []
    var showsHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
            if showsHeader {
                HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                    Image(systemName: symbol).frame(width: FamiliarAISurfaceMetric.icon)
                    Text(surface.title).font(FamiliarTypography.caption.weight(.semibold))
                }
                .foregroundStyle(FamiliarTheme.inkSecondary)
            }
            if let content = surface.resultEnvelope?.presentation.content { contentView(content) }
            else if let detail = surface.detail { Text(detail).font(FamiliarTypography.caption).foregroundStyle(FamiliarTheme.inkSecondary) }
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
                .foregroundStyle(FamiliarTheme.inkTertiary)
        case .document(let document):
            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                if let title = document.title { Text(title).font(FamiliarTypography.caption.weight(.medium)).foregroundStyle(FamiliarTheme.ink) }
                Spacer(minLength: 0)
                FamiliarSourceStatusLabel(title: String(localized: "source.status.read", defaultValue: "Read"), isRead: true)
            }
            Text(document.text).font(.caption2).foregroundStyle(FamiliarTheme.inkSecondary).lineLimit(8).textSelection(.enabled)
        case .mutationReceipt(let receipt):
            traceValue(label: receipt.operation, value: receipt.targetIdentifier ?? receipt.summary)
        case .artifactMutation(let artifact):
            traceValue(label: artifact.operation, value: artifact.title)
        case .contextMatches, .recordCollection, .diff, .taskList, .recommendation, .insight, .code, .shareDraft, .shellExecution:
            EmptyView()
        }
    }

    private func traceValue(label: String?, value: String) -> some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
            if let label { Text(label).font(.caption2.weight(.semibold)).foregroundStyle(FamiliarTheme.inkTertiary) }
            Text(value).font(FamiliarTypography.caption).foregroundStyle(FamiliarTheme.ink).textSelection(.enabled)
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
        case .share: "square.and.arrow.up"
        case .shell: "terminal"
        }
    }
}

private struct FamiliarShellExecutionSurface: View {
    let surface: FamiliarSurfaceDescriptor

    var body: some View {
        if case .shellExecution(let shell) = surface.resultEnvelope?.presentation.content {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                    Image(systemName: "terminal")
                        .foregroundStyle(FamiliarTheme.accentInk)
                    Text(shell.summary)
                        .font(FamiliarTypography.secondary.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(shell.status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(shell.status == "succeeded" ? FamiliarTheme.success : FamiliarTheme.inkSecondary)
                }

                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                    Text(String(localized: "shell.command", defaultValue: "Command"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FamiliarTheme.inkTertiary)
                    Text(FamiliarRuntimeTechnicalText.redacted(shell.command))
                        .font(FamiliarTypography.caption.monospaced())
                        .foregroundStyle(FamiliarTheme.ink)
                        .textSelection(.enabled)
                    Text("\(shell.workingDirectory) · \(shell.networkEnabled ? String(localized: "shell.network.enabled", defaultValue: "Public Internet On") : String(localized: "shell.network.disabled", defaultValue: "Network Off"))")
                        .font(.caption2)
                        .foregroundStyle(FamiliarTheme.inkTertiary)
                }

                if !shell.standardOutput.isEmpty {
                    output(shell.standardOutput, color: FamiliarTheme.ink)
                }
                if !shell.standardError.isEmpty {
                    output(shell.standardError, color: FamiliarTheme.failure)
                }
                if shell.outputWasTruncated {
                    Label(String(localized: "shell.output.truncated", defaultValue: "Output was truncated at the safety limit."), systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(FamiliarTheme.inkSecondary)
                }

                let diffCount = shell.addedFiles.count + shell.modifiedFiles.count + shell.removedFiles.count
                if diffCount > 0 {
                    Text(String(
                        format: String(localized: "shell.diff.summary", defaultValue: "%lld added · %lld modified · %lld removed"),
                        shell.addedFiles.count,
                        shell.modifiedFiles.count,
                        shell.removedFiles.count
                    ))
                    .font(FamiliarTypography.caption)
                    .foregroundStyle(FamiliarTheme.inkSecondary)
                }
            }
            .padding(FamiliarAISurfaceMetric.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FamiliarTheme.inset, in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    private func output(_ value: String, color: Color) -> some View {
        ScrollView(.horizontal) {
            Text(FamiliarRuntimeTechnicalText.redacted(outputTail(value)))
                .font(.caption2.monospaced())
                .foregroundStyle(color)
                .textSelection(.enabled)
                .padding(FamiliarAISurfaceMetric.spaceS)
        }
        .background(FamiliarTheme.field, in: RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous))
    }

    private func outputTail(_ value: String) -> String {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(20).joined(separator: "\n")
    }
}

private struct FamiliarAssistantFooter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: FamiliarMessageSnapshot
    let onRetryMessage: (() -> Void)?
    let onInsertPrompt: (String) -> Void
    @State private var sourcesOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
            HStack(spacing: FamiliarAISurfaceMetric.spaceXS) {
                if !message.finalAnswerText.isEmpty {
                    FamiliarMessageAction(symbol: "doc.on.doc", label: String(localized: "common.copy")) {
                        UIPasteboard.general.string = message.finalAnswerText
                    }
                }
                if let onRetryMessage {
                    FamiliarMessageAction(symbol: "arrow.clockwise", label: String(localized: "message.retry"), action: onRetryMessage)
                }
                if !message.sources.isEmpty {
                    Button {
                        withAnimation(reduceMotion ? nil : FamiliarMotion.state) {
                            sourcesOpen.toggle()
                        }
                    } label: {
                        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                            FamiliarSourceCluster(sources: message.sources)
                            Text(String(format: String(localized: "message.sources.count", defaultValue: "%lld sources"), message.sources.count))
                                .font(FamiliarTypography.caption)
                                .foregroundStyle(FamiliarTheme.inkSecondary)
                        }
                        .padding(.horizontal, FamiliarAISurfaceMetric.spaceXS)
                        .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("message.sources.disclosure")
                    .accessibilityLabel(String(format: String(localized: "message.sources.count", defaultValue: "%lld sources"), message.sources.count))
                    .accessibilityValue(sourcesOpen
                                        ? String(localized: "common.expanded", defaultValue: "Expanded")
                                        : String(localized: "common.collapsed", defaultValue: "Collapsed"))
                }
            }
            .foregroundStyle(FamiliarTheme.inkSecondary)

            if sourcesOpen {
                FamiliarInlineSources(sources: message.sources)
                    .transition(.opacity)
            }

            FamiliarFollowUps(onInsertPrompt: onInsertPrompt)
                .padding(.top, FamiliarAISurfaceMetric.spaceXS)
        }
    }
}

private struct FamiliarInlineSources: View {
    @Environment(\.openURL) private var openURL
    let sources: [FamiliarSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sources) { source in
                sourceRow(source)
            }
        }
        .padding(FamiliarAISurfaceMetric.spaceXS)
        .background(FamiliarTheme.inset, in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous)
                .stroke(FamiliarTheme.line, lineWidth: FamiliarAISurfaceMetric.hairline)
        }
        .accessibilityElement(children: .contain)
    }

    private func sourceRow(_ source: FamiliarSource) -> some View {
        Button { openURL(source.url) } label: {
            HStack(alignment: .center, spacing: FamiliarAISurfaceMetric.spaceS) {
                FamiliarSourceGlyph(source: source)
                Text(source.title)
                    .font(FamiliarTypography.caption.weight(.medium))
                    .foregroundStyle(FamiliarTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(displayDomain(source))
                    .font(.caption2.monospaced())
                    .foregroundStyle(FamiliarTheme.inkTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("message.source.row.\(source.id)")
        .accessibilityLabel("\(source.title), \(displayDomain(source)), \(statusTitle(source))")
        .accessibilityHint(String(localized: "source.open_hint", defaultValue: "Opens in Familiar's browser"))
    }

    private func displayDomain(_ source: FamiliarSource) -> String {
        let host = source.url.host ?? source.url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
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
                    .overlay { Circle().stroke(FamiliarTheme.page, lineWidth: 1.5) }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FamiliarSourceGlyph: View {
    let source: FamiliarSource

    var body: some View {
        AsyncImage(url: faviconURL) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(FamiliarTheme.accentInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FamiliarTheme.accentTint)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
        .overlay { Circle().stroke(FamiliarTheme.line, lineWidth: FamiliarAISurfaceMetric.hairline) }
        .accessibilityHidden(true)
    }

    private var faviconURL: URL? {
        guard var components = URLComponents(url: source.url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host != nil
        else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

private struct FamiliarSourceStatusLabel: View {
    let title: String
    let isRead: Bool

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isRead ? FamiliarTheme.success : FamiliarTheme.inkTertiary)
            .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
            .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
            .background(isRead ? FamiliarTheme.successTint : FamiliarTheme.inset, in: Capsule())
    }
}

nonisolated enum FamiliarFollowUpPrompt: String, CaseIterable, Identifiable, Sendable {
    case goDeeper
    case nextSteps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goDeeper:
            String(localized: "message.follow_up.go_deeper", defaultValue: "Explain the most important point in more detail")
        case .nextSteps:
            String(localized: "message.follow_up.next_steps", defaultValue: "Turn this answer into clear next steps")
        }
    }
}

private struct FamiliarFollowUps: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onInsertPrompt: (String) -> Void
    @State private var visibleCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "message.follow_ups", defaultValue: "Follow-ups"))
                .font(FamiliarTypography.caption.weight(.semibold))
                .foregroundStyle(FamiliarTheme.inkSecondary)
                .padding(.bottom, FamiliarAISurfaceMetric.spaceXS)

            ForEach(Array(FamiliarFollowUpPrompt.allCases.prefix(visibleCount).enumerated()), id: \.element.id) { index, followUp in
                if index > 0 {
                    Rectangle()
                        .fill(FamiliarTheme.line)
                        .frame(height: FamiliarAISurfaceMetric.hairline)
                }

                Button {
                    onInsertPrompt(followUp.title)
                } label: {
                    HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                        Image(systemName: "arrow.turn.up.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FamiliarTheme.inkTertiary)
                        Text(followUp.title)
                            .font(FamiliarTypography.secondary)
                            .foregroundStyle(FamiliarTheme.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, FamiliarAISurfaceMetric.spaceXS)
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("message.follow_up.\(followUp.rawValue)")
                .accessibilityHint(String(localized: "message.follow_up.hint", defaultValue: "Fills the composer without sending"))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "message.follow_ups", defaultValue: "Follow-ups"))
        .task {
            let count = FamiliarFollowUpPrompt.allCases.count
            guard visibleCount < count else { return }
            if reduceMotion {
                visibleCount = count
                return
            }
            for nextCount in (visibleCount + 1)...count {
                withAnimation(FamiliarMotion.reveal) {
                    visibleCount = nextCount
                }
                if nextCount < count {
                    try? await Task.sleep(for: .milliseconds(90))
                }
            }
        }
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
                            .font(FamiliarTypography.caption.weight(.medium))
                            .foregroundStyle(FamiliarTheme.ink)
                            .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
                            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                            .background(FamiliarTheme.surface, in: Capsule())
                            .overlay { Capsule().stroke(FamiliarTheme.line, lineWidth: FamiliarAISurfaceMetric.hairline) }
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
                .font(.system(size: FamiliarIconSize.standard, weight: .regular))
                .frame(width: FamiliarControlSize.minimumHitTarget, height: FamiliarControlSize.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(FamiliarIconButtonStyle())
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
                    .scaledToFill()
                    .frame(width: displaySize(for: image).width, height: displaySize(for: image).height)
                    .clipShape(RoundedRectangle(cornerRadius: FamiliarRadius.overlay, style: .continuous))
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: FamiliarRadius.overlay, style: .continuous)
                    .fill(FamiliarTheme.inset)
                    .frame(width: 220, height: 180)
                    .overlay { ProgressView() }
            }
        }
        .task(id: relativePath) {
            if let url = FamiliarAttachmentStore.url(for: relativePath) { image = UIImage(contentsOfFile: url.path) }
        }
    }

    private func displaySize(for image: UIImage) -> CGSize {
        let maximum = CGSize(width: 240, height: 320)
        guard image.size.width > 0, image.size.height > 0 else { return CGSize(width: 220, height: 180) }
        let scale = min(maximum.width / image.size.width, maximum.height / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }
}

private struct FamiliarModelSwitchRow: View {
    let marker: FamiliarModelSwitchSnapshot

    var body: some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
            Rectangle().fill(FamiliarTheme.line).frame(height: FamiliarAISurfaceMetric.hairline)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(FamiliarTheme.inkSecondary).lineLimit(1)
            Rectangle().fill(FamiliarTheme.line).frame(height: FamiliarAISurfaceMetric.hairline)
        }
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        let provider = FamiliarProviderCatalog.descriptor(for: marker.currentProviderID)
        return String(format: String(localized: "model.switched_marker"), provider?.displayName ?? marker.currentProviderID, provider?.model(for: marker.currentModelID).displayName ?? marker.currentModelID)
    }
}

#if DEBUG
struct FamiliarAssistantTurnVisualFixture: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            onResolveApproval: { _, _ in },
            onResolveClarification: { _, _ in },
            onInsertPrompt: { draft = $0 },
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

private struct FamiliarBottomPositionPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
