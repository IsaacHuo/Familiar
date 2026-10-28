import Observation
import SwiftData
import SwiftUI
import UIKit

struct FamiliarAssistantTurn: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.familiarExecutionBlocked) private var executionBlocked
    @Environment(\.familiarReadingGeometry) private var readingGeometry
    @Environment(\.familiarChatScrollSession) private var scroll
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let message: FamiliarMessageSnapshot?
    let run: FamiliarAgentRunSnapshot?
    let surfaces: [FamiliarSurfaceDescriptor]
    let disclosure: FamiliarRuntimeDisclosureState
    var liveController: FamiliarChatController? = nil
    var onLiveContentChange: ((Bool) -> Void)? = nil
    let availableUndoKeys: Set<String>
    let completedUndoKeys: Set<String>
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
        guard !executionBlocked, run?.regenerationRequiresInspection != true, liveController == nil else { return false }
        return !surfaces.contains { surface in
            surface.effect != nil && surface.effect != .read &&
                (surface.phase == .succeeded || ["tool_commit_unconfirmed", "tool_persistence_failed", "tool_rollback_failed"].contains(surface.failureCode ?? ""))
        }
    }

    var body: some View {
        let blocks = contentBlocks
        let fileTimestampBlockID = blocks.last.flatMap { block -> String? in
            guard case let .surface(surface) = block, surface.kind == .file, surface.file != nil else { return nil }
            return block.id
        }
        FamiliarMessageGroupLayout(accessibilityWide: dynamicType.isAccessibilitySize, trailing: false) {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
            ForEach(blocks) { block in
                Group {
                switch block {
                case .text(let text):
                    FamiliarMarkdownBlock(controller: liveController, text: text,
                        sources: message?.sources ?? [],
                        citationSources: message?.citedSources ?? [],
                        onContentChange: { onLiveContentChange?(false) },
                        messageActions: message.map { .init(text: $0.finalAnswerText, messageID: $0.id, blockID: text.id, retry: canRetry ? onRetryMessage : nil) },
                        timestamp: block.id == blocks.last?.id ? message?.createdAt : nil)
                case .runtime(let activity):
                    FamiliarRuntimeCard(activity: activity, disclosure: disclosure, context: run?.context,
                        metrics: replyMetrics, undo: runtimeUndo(for: activity))
                        .modifier(FamiliarSoftRise(enabled: liveController != nil && scroll?.mode != .userReading && !voiceOver, identity: "block:" + block.id))
                case .surface(let surface):
                    if surface.kind == .activityTrace {
                        Label(surface.title, systemImage: "exclamationmark.circle")
                            .font(FamiliarTypography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        FamiliarTurnSurface(surface: adjustedUndoPhase(surface), canUndo: canUndo(surface),
                            onUndo: { onUndo(surface.runID, surface.toolCallID ?? "") },
                            onRetry: surface.kind == .failure && surface.toolCallID == nil && canRetry ? retryAction : nil,
                            timestamp: block.id == fileTimestampBlockID ? message?.createdAt : nil)
                            .modifier(FamiliarSoftRise(enabled: liveController != nil && scroll?.mode != .userReading && !voiceOver, identity: "block:" + block.id))
                    }
                }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("conversation-scroll")) } action: { frame in
                    readingGeometry?.record(id: "block:" + block.id, frame: frame, priority: 1)
                }
            }
            if let liveController {
                FamiliarLiveReplyStatus(controller: liveController)
            }
            ForEach(FamiliarWeatherAttribution.unique(in: surfaces)) { attribution in
                FamiliarWeatherAttributionView(attribution: attribution)
            }
            if let message {
                if case .text = blocks.last { } else if fileTimestampBlockID == nil {
                    FamiliarMessageTimestamp(date: message.createdAt, onMedia: true).accessibilityIdentifier("message.completed")
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(FamiliarChatAppearance.serviceFill, in: Capsule())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if !message.citedSources.isEmpty || !message.followUpQuestions.isEmpty {
                    FamiliarAssistantFooter(message: message, onInsertPrompt: onInsertPrompt)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: surfaces) { _, _ in onLiveContentChange?(true) }
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
    /// Receipts fold into the activity row, so the row carries the Undo affordance
    /// for the latest activity in the group that still has an executable Undo.
    private func runtimeUndo(for group: FamiliarRuntimeActivityGroup) -> (() -> Void)? {
        guard liveController == nil else { return nil }
        guard let surface = group.activities.last(where: canUndo), let toolCallID = surface.toolCallID else { return nil }
        return { onUndo(surface.runID, toolCallID) }
    }
    private var retryAction: (() -> Void)? {
        guard let id = run?.id ?? surfaces.first?.runID else { return nil }
        return { onRetryRecovery(id) }
    }
}

/// Token observation is confined to text/status; Runtime aggregation is updated
/// by the Controller only for activity events and nonempty text boundaries.
struct FamiliarMarkdownBlock: View {
    let controller: FamiliarChatController?
    let text: FamiliarAssistantTextBlock
    let sources: [FamiliarSource]
    let citationSources: [FamiliarSource]
    let onContentChange: () -> Void
    var messageActions: FamiliarMessageActions? = nil
    var timestamp: Date? = nil
    @ScaledMetric(relativeTo: .body) private var textSize: CGFloat = 17

    var body: some View {
        let live = controller?.streamingResponseBlocks.first { "text:\($0.id.uuidString)" == text.id }
        let content = live?.content ?? text.content
        let streaming = live?.isStreaming ?? false
        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
            Group {
                if controller == nil, sources.isEmpty, citationSources.isEmpty,
                   FamiliarMessageReadingStyle.canUseNativeText(content), let messageActions {
                    if let timestamp {
                        FamiliarTextAndTimeLayout(fontSize: textSize, text: content) {
                            FamiliarMessageText(text: content, actions: messageActions)
                            FamiliarMessageTimestamp(date: timestamp).accessibilityIdentifier("message.completed")
                        }
                    } else { FamiliarMessageText(text: content, actions: messageActions) }
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        FamiliarMarkdownWebView(markdown: FamiliarCitation.canonicalized(content, sources: sources).text,
                                                sources: citationSources, isStreaming: streaming, messageActions: messageActions)
                        if let timestamp { FamiliarMessageTimestamp(date: timestamp).accessibilityIdentifier("message.completed") }
                    }
                }
            }
            .familiarMessageBubble(isUser: false)
            if live == nil, text.state != .completed {
                Label(String(localized: "runtime.ui.incomplete_text"), systemImage: "pause.circle")
                    .font(FamiliarTypography.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: content) { _, _ in onContentChange() }
    }
}

struct FamiliarLiveReplyStatus: View {
    let controller: FamiliarChatController
    var body: some View {
        let status = controller.surfaces.orderedSurfaces.first { $0.kind == .runStatus }
        let hasActiveCard = controller.runtimeContentBlocks.contains { block in
            if case .runtime(let activity) = block { return activity.status.isActive }
            return false
        }
        let hasInteraction = !controller.pendingConfirmations.isEmpty || !controller.pendingClarifications.isEmpty
        let isWriting = controller.streamingResponseBlocks.last.map { $0.isStreaming && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
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
final class FamiliarRuntimeDisclosureState {
    var expanded: Set<String> = []
    func binding(for id: String) -> Binding<Bool> {
        Binding(get: { self.expanded.contains(id) }, set: { value in
            withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : FamiliarTelegramMotion.panel) {
                if value { self.expanded.insert(id) } else { self.expanded.remove(id) }
            }
        })
    }
}

struct FamiliarTurnSurface: View {
    @Environment(\.familiarReduceMotion) private var reduceMotion
    let surface: FamiliarSurfaceDescriptor
    let canUndo: Bool
    let onUndo: () -> Void
    let onRetry: (() -> Void)?
    var timestamp: Date? = nil

    var body: some View {
        Group {
            switch surface.kind {
            case .approval:
                FamiliarInteractionReceipt(surface: surface)
            case .file:
                FamiliarWriteReceipt(surface: surface, canUndo: canUndo, onUndo: onUndo, timestamp: timestamp)
            case .failure:
                FamiliarFailureRecovery(surface: surface, onRetry: onRetry, canUndo: canUndo, onUndo: onUndo)
            case .clarification:
                FamiliarInteractionReceipt(surface: surface)
            case .shell:
                FamiliarShellExecutionSurface(surface: surface)
            case .toolSummary:
                HStack(spacing: FamiliarSpacing.small) {
                    FamiliarRuntimeStatusIcon(status: FamiliarRuntimeActivityGroup.displayStatus(surface))
                    Text(surface.title).font(FamiliarTypography.caption).foregroundStyle(.secondary)
                }
            case .records:
                FamiliarRecordCollectionSurface(surface: surface)
            case .context, .search, .mutationReceipt:
                FamiliarTypedResult(surface: surface)
            case .runStatus, .activityTrace:
                EmptyView()
            }
        }
        .onChange(of: surface.phase) { old, new in
            if let feedback = FamiliarHaptics.boundary(from: old, to: new) {
                FamiliarHaptics.shared.perform(feedback, event: "\(surface.id):\(new)")
            }
        }
        .animation(reduceMotion ? nil : FamiliarMotion.collapse, value: surface.kind)
        .animation(reduceMotion ? nil : FamiliarMotion.standard, value: surface.phase)
    }
}

struct FamiliarPreparedFilePreview: Identifiable, Hashable {
    let url: URL
    var format: FamiliarFileFormat? = nil
    var id: String { url.absoluteString }
}

struct FamiliarWriteReceipt: View {
    @Environment(\.modelContext) private var context
    @Environment(\.familiarOpenMessageFile) private var openMessageFile
    let surface: FamiliarSurfaceDescriptor
    let canUndo: Bool
    let onUndo: () -> Void
    var timestamp: Date? = nil
    @State private var previewError: String?

    var body: some View {
        Group {
            if let file = surface.file {
                VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
                    let presentation = FamiliarFilePresentation(file: file, revoked: surface.phase == .undone)
                        .resolved(in: context, scope: file.scope)
                    FamiliarFileTile(file: presentation, date: timestamp) {
                        do { openMessageFile?.open(.init(url: try presentation.validatedURL(), format: file.format)) }
                        catch { previewError = error.localizedDescription }
                    }
                    if let authorizationSummary {
                        Label(authorizationSummary, systemImage: surface.automaticAuthorization ? "checkmark.shield.fill" : "hand.raised")
                            .font(FamiliarTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    if canUndo {
                        Button(String(localized: "common.undo"), action: onUndo)
                            .font(FamiliarTypography.caption)
                            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                    }
                }
            } else {
                preparedExportCard
            }
        }
        .alert(String(localized: "app.name"), isPresented: Binding(
            get: { previewError != nil }, set: { if !$0 { previewError = nil } }
        )) { Button(String(localized: "common.ok"), role: .cancel) {} }
        message: { Text(previewError ?? "") }
    }

    /// A File record whose bytes are gone (revoked or deleted) and the
    /// prepare_file_export document URL both land here.
    private var preparedExportCard: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
            HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceS) {
                Image(systemName: surface.phase == .undone ? "arrow.uturn.backward.circle" : "doc")
                    .foregroundStyle(FamiliarTheme.inkSecondary)
                    .frame(width: FamiliarAISurfaceMetric.icon)
                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                    Text(title).font(FamiliarTypography.secondary.weight(.semibold)).foregroundStyle(FamiliarTheme.ink)
                    if let detail {
                        Text(detail).font(FamiliarTypography.caption).foregroundStyle(FamiliarTheme.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let exportURL {
                HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                    Button {
                        openMessageFile?.open(.init(url: exportURL))
                    } label: {
                        Label(String(localized: "common.preview", defaultValue: "Preview"), systemImage: "eye")
                            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                    }
                    .buttonStyle(.bordered)
                    ShareLink(item: exportURL) {
                        Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text(String(localized: surface.phase == .undone ? "runtime.ui.file_revoked" : "runtime.ui.file_unavailable"))
                    .font(FamiliarTypography.caption).foregroundStyle(.secondary)
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
        .background(FamiliarTheme.surface, in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous)
                .stroke(FamiliarTheme.line, lineWidth: FamiliarAISurfaceMetric.hairline)
        }
    }

    private var exportURL: URL? {
        guard surface.phase != .undone,
              case .document(let document) = surface.resultEnvelope?.presentation.content,
              let value = document.url,
              let url = URL(string: value),
              url.isFileURL else { return nil }
        return url
    }

    private var title: String {
        if let file = surface.file { return file.title }
        if case .fileMutation(let file) = surface.resultEnvelope?.presentation.content { return file.title }
        if case .document(let document) = surface.resultEnvelope?.presentation.content {
            return document.title ?? document.summary
        }
        return surface.title
    }

    private var detail: String? {
        guard case .fileMutation(let file) = surface.resultEnvelope?.presentation.content else { return surface.detail }
        let size = ByteCountFormatter.string(fromByteCount: file.byteSize, countStyle: .file)
        return surface.file.map { $0.format.filenameExtension.uppercased() + " · " + size } ?? size
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
}

struct FamiliarFailureRecovery: View {
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

struct FamiliarContextTrace: View {
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

struct FamiliarAssistantFooter: View {
    @Environment(\.familiarChatScrollSession) private var scroll
    let message: FamiliarMessageSnapshot
    let onInsertPrompt: (String) -> Void
    @State private var sourcesOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
            if !message.citedSources.isEmpty {
                HStack(spacing: FamiliarAISurfaceMetric.spaceXS) {
                    Button {
                        scroll?.beginInspection()
                        sourcesOpen = true
                    } label: {
                        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                            FamiliarSourceCluster(sources: message.citedSources)
                            Text(String(format: String(localized: "message.sources.count", defaultValue: "%lld sources"), message.citedSources.count))
                                .font(FamiliarTypography.caption)
                                .foregroundStyle(FamiliarTheme.inkSecondary)
                        }
                        .padding(.horizontal, FamiliarAISurfaceMetric.spaceXS)
                        .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("message.sources.disclosure")
                    .accessibilityLabel(String(format: String(localized: "message.sources.count", defaultValue: "%lld sources"), message.citedSources.count))
                }
                .foregroundStyle(FamiliarTheme.inkSecondary)
            }

            if !message.followUpQuestions.isEmpty {
                FamiliarFollowUps(questions: message.followUpQuestions, onInsertPrompt: onInsertPrompt)
                    .padding(.top, FamiliarAISurfaceMetric.spaceXS)
            }
        }
        .sheet(isPresented: $sourcesOpen, onDismiss: { scroll?.endInspection() }) {
            NavigationStack {
                ScrollView { FamiliarInlineSources(sources: message.citedSources).padding(FamiliarSpacing.large) }
                    .navigationTitle(String(localized: "message.sources.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { FamiliarDismissButton() } }
            }
            .modifier(FamiliarSheetBrowser())
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct FamiliarInlineSources: View {
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

struct FamiliarSourceCluster: View {
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

struct FamiliarSourceGlyph: View {
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

struct FamiliarSourceStatusLabel: View {
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

struct FamiliarFollowUps: View {
    let questions: [String]
    let onInsertPrompt: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "message.follow_ups", defaultValue: "Follow-ups"))
                .font(FamiliarTypography.caption.weight(.semibold))
                .foregroundStyle(FamiliarTheme.inkSecondary)
                .padding(.bottom, FamiliarAISurfaceMetric.spaceXS)

            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                if index > 0 {
                    Rectangle()
                        .fill(FamiliarTheme.line)
                        .frame(height: FamiliarAISurfaceMetric.hairline)
                }

                Button {
                    onInsertPrompt(question)
                } label: {
                    HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                        Image(systemName: "arrow.turn.up.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FamiliarTheme.inkTertiary)
                        Text(question)
                            .font(FamiliarTypography.secondary)
                            .foregroundStyle(FamiliarTheme.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, FamiliarAISurfaceMetric.spaceXS)
                    .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("message.follow_up.\(index)")
                .accessibilityHint(String(localized: "message.follow_up.hint", defaultValue: "Fills the composer without sending"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "message.follow_ups", defaultValue: "Follow-ups"))
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

struct FamiliarSelectionActions: View {
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
