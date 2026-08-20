import SwiftUI
import UIKit

struct FamiliarMessageTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let messages: [FamiliarMessageSnapshot]
    let modelSwitches: [FamiliarModelSwitchSnapshot]
    let toolRunRecords: [FamiliarToolRunSnapshot]
    let agentRuns: [FamiliarAgentRunSnapshot]
    let surfaces: [FamiliarSurfaceDescriptor]
    let streamingMessageID: UUID?
    let streamingText: String
    let availableUndoKeys: Set<String>
    let completedUndoKeys: Set<String>
    let onResolveConfirmation: (UUID, FamiliarToolConfirmationDecision) -> Void
    let onUndo: (String, String) -> Void
    let onEdit: (FamiliarMessageSnapshot) -> Void
    let onRetry: (FamiliarMessageSnapshot) -> Void

    @State private var isFollowingLatest = true
    @AccessibilityFocusState private var focusedConfirmationID: UUID?

    private var activeRunID: String? {
        surfaces.first(where: { $0.kind == .agentStatus })?.runID
    }

    private var pendingApprovalIDs: [UUID] {
        surfaces.filter { $0.phase == .awaitingApproval }.compactMap(\.approvalRequestID)
    }

    private var timelineItems: [FamiliarTimelineItem] {
        var items = messages.map { FamiliarTimelineItem.message(.init(snapshot: $0)) }
        items += modelSwitches.map(FamiliarTimelineItem.modelSwitch)
        let associatedRunIDs = Set(agentRuns.filter { $0.responseMessageID != nil }.map(\.id))
        items += toolRunRecords.filter { record in
            guard record.runID != activeRunID else { return false }
            return !associatedRunIDs.contains(record.runID)
                || availableUndoKeys.contains(record.runID + ":" + record.toolCallID)
                || completedUndoKeys.contains(record.runID + ":" + record.toolCallID)
        }.map {
            FamiliarTimelineItem.surface(.init(
                snapshot: $0,
                isUndone: completedUndoKeys.contains($0.runID + ":" + $0.toolCallID)
            ))
        }
        items.sort {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.createdAt < $1.createdAt
        }
        if let agent = surfaces.first(where: { $0.kind == .agentStatus }) {
            items.append(.surface(agent))
        }
        let actions = surfaces.filter { $0.kind == .toolActivity }
        var groupedIDs: [String] = []
        var groups: [String: [FamiliarSurfaceDescriptor]] = [:]
        for surface in actions {
            let key = surface.assistantTurnID ?? surface.id
            if groups[key] == nil { groupedIDs.append(key) }
            groups[key, default: []].append(surface)
        }
        for key in groupedIDs {
            guard let group = groups[key] else { continue }
            if group.count == 1, let surface = group.first {
                items.append(.surface(surface))
            } else {
                items.append(.actionGroup(.init(id: key, surfaces: group)))
            }
        }
        if let streamingMessageID,
           !streamingText.isEmpty,
           !messages.contains(where: { $0.id == streamingMessageID }) {
            items.append(.message(.init(
                id: streamingMessageID,
                role: .assistant,
                content: streamingText,
                createdAt: Date(),
                sequence: Int.max,
                providerID: nil,
                modelID: nil,
                attachments: [],
                sources: [],
                isStreaming: true,
                source: nil
            )))
        }
        return items
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        ForEach(timelineItems) { item in
                            switch item {
                            case .message(let message):
                                FamiliarMessageRow(
                                    message: message,
                                    run: agentRuns.first(where: { $0.responseMessageID == message.id }),
                                    onEdit: onEdit,
                                    onRetry: onRetry
                                )
                                .id(item.id)
                            case .modelSwitch(let marker):
                                FamiliarModelSwitchRow(marker: marker)
                                    .id(item.id)
                            case .surface(let surface):
                                surfaceView(surface)
                                    .id(item.id)
                            case .actionGroup(let group):
                                FamiliarActionPager(
                                    group: group,
                                    availableUndoKeys: availableUndoKeys,
                                    onResolveApproval: onResolveConfirmation,
                                    onUndo: onUndo
                                )
                                .id(item.id)
                            }
                        }

                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: FamiliarBottomPositionPreferenceKey.self,
                                value: geometry.frame(in: .named("conversation-scroll")).maxY
                            )
                        }
                        .frame(height: 1)
                        .id("conversation-bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "conversation-scroll")
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(FamiliarBottomPositionPreferenceKey.self) { bottomY in
                    isFollowingLatest = bottomY <= viewport.size.height + 120
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToLatestIfNeeded(proxy)
                }
                .onChange(of: streamingText) { _, _ in
                    scrollToLatestIfNeeded(proxy, animated: false)
                }
                .onChange(of: surfaces) { _, _ in
                    scrollToLatestIfNeeded(proxy)
                }
                .onChange(of: pendingApprovalIDs) { previousIDs, currentIDs in
                    guard let newID = currentIDs.first(where: { !previousIDs.contains($0) }) else {
                        if currentIDs.isEmpty {
                            focusedConfirmationID = nil
                        }
                        return
                    }
                    focusedConfirmationID = newID
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isFollowingLatest {
                        Button {
                            isFollowingLatest = true
                            if reduceMotion {
                                proxy.scrollTo("conversation-bottom", anchor: .bottom)
                            } else {
                                withAnimation(.smooth) {
                                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .familiarGlassCircle(interactive: true)
                        .padding(.trailing, 16)
                        .padding(.bottom, 10)
                        .accessibilityLabel(String(localized: "conversation.scroll_latest"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func surfaceView(_ surface: FamiliarSurfaceDescriptor) -> some View {
        if surface.kind == .agentStatus {
            FamiliarAgentStatusRow(surface: surface)
        } else {
            FamiliarToolActivityCard(
                surface: surface,
                canUndo: availableUndoKeys.contains(surface.runID + ":" + (surface.toolCallID ?? "")),
                onResolveApproval: onResolveConfirmation,
                onUndo: { onUndo(surface.runID, surface.toolCallID ?? "") }
            )
            .accessibilityFocused($focusedConfirmationID, equals: surface.approvalRequestID)
        }
    }

    private func scrollToLatestIfNeeded(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard isFollowingLatest else { return }
        if animated && !reduceMotion {
            withAnimation(.smooth) {
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("conversation-bottom", anchor: .bottom)
        }
    }
}

private enum FamiliarTimelineItem: Identifiable {
    case message(FamiliarRenderedMessage)
    case modelSwitch(FamiliarModelSwitchSnapshot)
    case surface(FamiliarSurfaceDescriptor)
    case actionGroup(FamiliarActionGroup)

    var id: String {
        switch self {
        case .message(let message): message.id.uuidString
        case .modelSwitch(let marker): "model-switch-\(marker.id.uuidString)"
        case .surface(let surface): surface.id
        case .actionGroup(let group): "action-group-\(group.id)"
        }
    }

    var sequence: Int {
        switch self {
        case .message(let message): message.sequence
        case .modelSwitch(let marker): marker.sequence
        case .surface, .actionGroup: Int.max
        }
    }

    var createdAt: Date {
        switch self {
        case .message(let message): message.createdAt
        case .modelSwitch(let marker): marker.createdAt
        case .surface, .actionGroup: .distantFuture
        }
    }
}

private struct FamiliarActionGroup {
    let id: String
    let surfaces: [FamiliarSurfaceDescriptor]
}

private struct FamiliarActionPager: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let group: FamiliarActionGroup
    let availableUndoKeys: Set<String>
    let onResolveApproval: (UUID, FamiliarToolConfirmationDecision) -> Void
    let onUndo: (String, String) -> Void

    @State private var selectedID: String?

    private var selectedIndex: Int {
        guard let selectedID, let index = group.surfaces.firstIndex(where: { $0.id == selectedID }) else { return 0 }
        return index
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(group.surfaces) { surface in
                    FamiliarToolActivityCard(
                        surface: surface,
                        canUndo: availableUndoKeys.contains(surface.runID + ":" + (surface.toolCallID ?? "")),
                        onResolveApproval: onResolveApproval,
                        onUndo: { onUndo(surface.runID, surface.toolCallID ?? "") }
                    )
                    .containerRelativeFrame(.horizontal) { length, _ in max(0, length - 24) }
                    .id(surface.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $selectedID)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .overlay(alignment: .leading) {
            if selectedIndex > 0 { edgeFade(isLeading: true) }
        }
        .overlay(alignment: .trailing) {
            if selectedIndex < group.surfaces.count - 1 { edgeFade(isLeading: false) }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear { selectedID = selectedID ?? group.surfaces.first?.id }
        .accessibilityElement(children: .contain)
        .accessibilityValue(String(format: String(localized: "tool.cards.position", defaultValue: "%lld of %lld"), selectedIndex + 1, group.surfaces.count))
    }

    private func edgeFade(isLeading: Bool) -> some View {
        LinearGradient(
            colors: [Color(.systemBackground).opacity(0.82), Color(.systemBackground).opacity(0)],
            startPoint: isLeading ? .leading : .trailing,
            endPoint: isLeading ? .trailing : .leading
        )
        .frame(width: 18)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FamiliarRenderedMessage {
    let id: UUID
    let role: FamiliarMessageRole
    let content: String
    let createdAt: Date
    let sequence: Int
    let providerID: String?
    let modelID: String?
    let attachments: [FamiliarAttachmentSnapshot]
    let sources: [FamiliarSource]
    let isStreaming: Bool
    let source: FamiliarMessageSnapshot?

    init(snapshot: FamiliarMessageSnapshot) {
        id = snapshot.id
        role = snapshot.role
        content = snapshot.content
        createdAt = snapshot.createdAt
        sequence = snapshot.sequence
        providerID = snapshot.providerID
        modelID = snapshot.modelID
        attachments = snapshot.attachments
        sources = snapshot.sources
        isStreaming = false
        source = snapshot
    }

    init(
        id: UUID,
        role: FamiliarMessageRole,
        content: String,
        createdAt: Date,
        sequence: Int,
        providerID: String?,
        modelID: String?,
        attachments: [FamiliarAttachmentSnapshot],
        sources: [FamiliarSource],
        isStreaming: Bool,
        source: FamiliarMessageSnapshot?
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.sequence = sequence
        self.providerID = providerID
        self.modelID = modelID
        self.attachments = attachments
        self.sources = sources
        self.isStreaming = isStreaming
        self.source = source
    }
}

private struct FamiliarMessageRow: View {
    let message: FamiliarRenderedMessage
    let run: FamiliarAgentRunSnapshot?
    let onEdit: (FamiliarMessageSnapshot) -> Void
    let onRetry: (FamiliarMessageSnapshot) -> Void

    @State private var previewAttachment: FamiliarAttachmentSnapshot?

    var body: some View {
        Group {
            if message.role == .user {
                userMessage
            } else {
                assistantMessage
            }
        }
        .sheet(item: $previewAttachment) { attachment in
            if let url = FamiliarAttachmentStore.url(for: attachment.relativePath) {
                FamiliarAttachmentQuickLookView(url: url)
                    .ignoresSafeArea()
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
            Spacer(minLength: 48)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(message.attachments) { attachment in
                    if attachment.kind == .image {
                        Button {
                            previewAttachment = attachment
                        } label: {
                            FamiliarImageAttachmentView(relativePath: attachment.relativePath)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(format: String(localized: "attachment.preview"), attachment.filename))
                    } else {
                        Button {
                            previewAttachment = attachment
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: attachment.mimeType == "application/pdf" ? "doc.richtext" : "doc.text")
                                    .font(.title3)
                                    .foregroundStyle(FamiliarTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attachment.filename)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                    Text(
                                        "\(attachment.extractionEngine)\(attachment.usedOCR ? " + Vision OCR" : "") · "
                                        + "\(attachment.detectedFormat.uppercased()) · "
                                        + ByteCountFormatter.string(fromByteCount: attachment.byteSize, countStyle: .file)
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(format: String(localized: "attachment.preview"), attachment.filename))
                    }
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(FamiliarTheme.userFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contextMenu {
                if !message.content.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: {
                        Label(String(localized: "common.copy"), systemImage: "doc.on.doc")
                    }
                }
                if let source = message.source {
                    Button {
                        onEdit(source)
                    } label: {
                        Label(String(localized: "common.edit"), systemImage: "pencil")
                    }
                }
            }
        }
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 10) {
            if message.isStreaming {
                FamiliarMarkdownFallbackText(markdown: message.content)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FamiliarMarkdownWebView(markdown: message.content, sources: message.sources)
            }

            if !message.isStreaming, let run, !run.steps.isEmpty {
                FamiliarOperationTrace(run: run)
            }

            if !message.isStreaming, !message.sources.isEmpty {
                FamiliarSourcesDisclosure(sources: message.sources)
            }

            if !message.isStreaming, let source = message.source {
                if let sourceLabel {
                    Text(sourceLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(String(format: String(localized: "message.generated_by"), sourceLabel))
                }

                HStack(spacing: 4) {
                    MessageActionButton(symbol: "doc.on.doc", label: String(localized: "common.copy")) {
                        UIPasteboard.general.string = message.content
                    }

                    ShareLink(item: message.content) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "common.share"))

                    MessageActionButton(symbol: "arrow.clockwise", label: String(localized: "message.retry")) {
                        onRetry(source)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceLabel: String? {
        guard let providerID = message.providerID, let modelID = message.modelID else { return nil }
        let provider = FamiliarProviderCatalog.descriptor(for: providerID)
        let providerName = provider?.displayName ?? providerID
        let modelName = provider?.model(for: modelID).displayName ?? modelID
        return "\(providerName) · \(modelName)"
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
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FamiliarTheme.elevatedFill)
                    .frame(width: 200, height: 140)
                    .overlay { ProgressView() }
            }
        }
        .task(id: relativePath) {
            if let url = FamiliarAttachmentStore.url(for: relativePath) {
                image = UIImage(contentsOfFile: url.path)
            }
        }
    }
}

private struct FamiliarModelSwitchRow: View {
    let marker: FamiliarModelSwitchSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(FamiliarTheme.separator)
                .frame(height: 0.5)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Rectangle()
                .fill(FamiliarTheme.separator)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        let provider = FamiliarProviderCatalog.descriptor(for: marker.currentProviderID)
        let providerName = provider?.displayName ?? marker.currentProviderID
        let modelName = provider?.model(for: marker.currentModelID).displayName ?? marker.currentModelID
        return String(format: String(localized: "model.switched_marker"), providerName, modelName)
    }
}

private struct FamiliarToolActivityCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let surface: FamiliarSurfaceDescriptor
    let canUndo: Bool
    let onResolveApproval: (UUID, FamiliarToolConfirmationDecision) -> Void
    let onUndo: () -> Void

    var body: some View {
        Group {
            if surface.phase == .awaitingApproval {
                approvalContent
            } else {
                statusContent
            }
        }
        .padding(surface.phase == .awaitingApproval ? 16 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: surface.phase == .awaitingApproval ? 20 : 16, style: .continuous))
        .overlay {
            if surface.phase == .awaitingApproval {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(FamiliarTheme.separator, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .sensoryFeedback(trigger: surface.phase) { old, new in
            FamiliarHapticPolicy.feedback(from: old, to: new)
        }
    }

    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                statusIcon
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(surface.title)
                        .font(.subheadline.weight(.semibold))
                    if let detail = surface.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                    }
                    if surface.phase.isTerminal, let finishedAt = surface.finishedAt {
                        Text(finishedAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(surface.title)
            .accessibilityValue(statusAccessibilityValue)

            if canUndo {
                Button(String(localized: "common.undo"), action: onUndo)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint(String(localized: "tool.undo.hint"))
            }

            if let artifact = surface.artifact {
                FamiliarArtifactCard(artifact: artifact)
            }
        }
    }

    private var approvalContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: surface.symbol)
                        .font(.title3)
                        .foregroundStyle(FamiliarTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(surface.title)
                            .font(.headline)
                        if let target = surface.target {
                            Text(String(format: String(localized: "eventkit.target"), target))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(spacing: 8) {
                    ForEach(surface.fields) { field in
                        HStack(alignment: .top, spacing: 12) {
                            Text(field.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 82, alignment: .leading)
                            Text(field.value)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(surface.title)
            .accessibilityValue(approvalAccessibilityValue)

            HStack(spacing: 10) {
                Button(String(localized: "common.cancel")) {
                    if let id = surface.approvalRequestID { onResolveApproval(id, .cancelled) }
                }
                .buttonStyle(.bordered)

                if surface.isWrite {
                    Menu {
                        Button(String(localized: "authorization.once", defaultValue: "Only Once")) {
                            if let id = surface.approvalRequestID { onResolveApproval(id, .confirmedOnce) }
                        }
                        Button(String(localized: "authorization.always", defaultValue: "Always Allow")) {
                            if let id = surface.approvalRequestID { onResolveApproval(id, .confirmedAlways) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(String(localized: "authorization.options", defaultValue: "Authorization options"))
                }

                Button(surface.isWrite ? String(localized: "authorization.session", defaultValue: "Allow This Session") : String(localized: "common.continue")) {
                    if let id = surface.approvalRequestID { onResolveApproval(id, .confirmed) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var statusAccessibilityValue: String {
        var components = [surface.phase.accessibilityDescription]
        if let detail = surface.detail, !detail.isEmpty {
            components.append(detail)
        }
        return components.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var approvalAccessibilityValue: String {
        var components = [String(localized: "accessibility.confirmation.required")]
        if let target = surface.target {
            components.append(String(format: String(localized: "eventkit.target"), target))
        }
        components += surface.fields.compactMap { field in
            field.value.isEmpty ? nil : "\(field.label): \(field.value)"
        }
        return components.joined(separator: ", ")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch surface.phase {
        case .running:
            FamiliarOrbitLoadingView(reduceMotion: reduceMotion)
        case .queued, .planning:
            ProgressView().controlSize(.small)
        case .awaitingApproval:
            EmptyView()
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .cancelled:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .undone:
            Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary)
        }
    }
}

private struct FamiliarArtifactCard: View {
    let artifact: FamiliarArtifactDescriptor
    @State private var previewURL: URL?

    private var fileURL: URL? {
        FamiliarArtifactStore().url(relativePath: artifact.relativePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                previewURL = fileURL
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: artifact.format == .markdown ? "doc.richtext" : "doc.text")
                        .font(.title3)
                        .foregroundStyle(FamiliarTheme.accent)
                        .frame(width: 40, height: 40)
                        .background(FamiliarTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(artifact.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount: artifact.byteSize, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "eye")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(artifact.title)
            .accessibilityHint(String(localized: "artifact.preview.hint", defaultValue: "轻点以预览"))

            if let fileURL {
                ShareLink(item: fileURL) {
                    Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FamiliarTheme.separator, lineWidth: 0.5)
        }
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let previewURL {
                FamiliarAttachmentQuickLookView(url: previewURL)
                    .ignoresSafeArea()
            }
        }
    }
}

private struct MessageActionButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct FamiliarAgentStatusRow: View {
    let surface: FamiliarSurfaceDescriptor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 9) {
            if !surface.phase.isTerminal {
                FamiliarOrbitLoadingView(reduceMotion: reduceMotion)
                    .accessibilityHidden(true)
            }
            Text(surface.title)
                .font(.subheadline.weight(.semibold))
            if !surface.phase.isTerminal, let startedAt = surface.startedAt {
                TimelineView(.periodic(from: startedAt, by: 0.1)) { context in
                    Text(Self.elapsed(from: startedAt, to: context.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(surface.title)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private static func elapsed(from start: Date, to end: Date) -> String {
        let interval = max(0, end.timeIntervalSince(start))
        if interval < 60 { return String(format: "%.1fs", interval) }
        return String(format: "%dm %.1fs", Int(interval / 60), interval.truncatingRemainder(dividingBy: 60))
    }
}

private struct FamiliarOrbitLoadingView: View {
    let reduceMotion: Bool
    private let orbitOrder = [0, 1, 2, 5, 8, 7, 6, 3]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.11) % orbitOrder.count
            Grid(horizontalSpacing: 1.5, verticalSpacing: 1.5) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            RoundedRectangle(cornerRadius: 1)
                                .fill(.secondary)
                                .frame(width: 4, height: 4)
                                .opacity(opacity(for: index, phase: phase))
                        }
                    }
                }
            }
        }
        .frame(width: 16, height: 16)
    }

    private func opacity(for index: Int, phase: Int) -> Double {
        guard !reduceMotion, let position = orbitOrder.firstIndex(of: index) else {
            return index == 4 ? 0.07 : 0.15
        }
        let distance = (phase - position + orbitOrder.count) % orbitOrder.count
        if distance == 0 { return 1 }
        if distance == 1 { return 0.45 }
        return 0.15
    }
}

private struct FamiliarOperationTrace: View {
    let run: FamiliarAgentRunSnapshot
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let context = run.context {
                    contextDetails(context)
                    if !run.steps.isEmpty {
                        Divider()
                            .padding(.vertical, 2)
                    }
                }
                ForEach(run.steps) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: symbol(for: step))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tone(for: step))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.summary)
                                .font(.caption.weight(.medium))
                            if step.type == .tool, !step.detail.isEmpty {
                                Text(step.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
            .padding(.top, 7)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                Text(traceLabel)
                Text(Self.duration(run))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
    }

    @ViewBuilder
    private func contextDetails(_ context: FamiliarRunContextSummary) -> some View {
        traceDetailRow(
            symbol: "cpu",
            title: String(localized: "run.context.model", defaultValue: "Model"),
            detail: context.providerID + " · " + context.modelID
        )
        if let projectName = context.projectName {
            traceDetailRow(
                symbol: "folder",
                title: String(localized: "run.context.project", defaultValue: "Project"),
                detail: projectName
            )
        }
        ForEach(context.resources) { resource in
            traceDetailRow(
                symbol: "doc.text",
                title: String(localized: "run.context.resource", defaultValue: "Resource"),
                detail: "\(resource.filename) · v\(resource.version)"
            )
        }
        ForEach(context.skills) { skill in
            traceDetailRow(
                symbol: "wand.and.stars",
                title: String(localized: "run.context.skill", defaultValue: "Skill"),
                detail: "\(skill.name) · \(skill.version)"
            )
        }
        if !context.toolNames.isEmpty {
            traceDetailRow(
                symbol: "wrench.and.screwdriver",
                title: String(localized: "run.context.tools", defaultValue: "Available Tools"),
                detail: context.toolNames.joined(separator: ", ")
            )
        }
    }

    private func traceDetailRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var traceLabel: String {
        let toolCount = run.steps.filter { $0.type == .tool }.count
        return toolCount == 0
            ? String(localized: "message.operation_trace", defaultValue: "运行轨迹")
            : String(format: String(localized: "message.operation_trace.tools", defaultValue: "%lld 个工具步骤"), toolCount)
    }

    private static func duration(_ run: FamiliarAgentRunSnapshot) -> String {
        let value = max(0, (run.finishedAt ?? run.startedAt).timeIntervalSince(run.startedAt))
        return value < 60 ? String(format: "%.1fs", value) : String(format: "%dm %.1fs", Int(value / 60), value.truncatingRemainder(dividingBy: 60))
    }

    private func symbol(for step: FamiliarAgentStepSnapshot) -> String {
        switch step.status {
        case .succeeded: step.type == .approval ? "checkmark.shield" : "checkmark.circle"
        case .cancelled: "xmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func tone(for step: FamiliarAgentStepSnapshot) -> Color {
        switch step.status {
        case .succeeded: .secondary
        case .cancelled: .secondary
        case .failed: .orange
        }
    }
}

private struct FamiliarSourcesDisclosure: View {
    let sources: [FamiliarSource]
    @Environment(\.openURL) private var openURL

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sources) { source in
                    Button {
                        openURL(source.url)
                    } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: source.kind.symbol)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(FamiliarTheme.accent)
                                    .frame(width: 28, height: 28)
                                    .background(FamiliarTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(source.kind.label)
                                        Text("·")
                                        Text(source.siteName ?? source.url.host ?? source.url.absoluteString)
                                            .lineLimit(1)
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            if let snippet = source.snippet?.trimmingCharacters(in: .whitespacesAndNewlines), !snippet.isEmpty {
                                Text(snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(FamiliarTheme.separator, lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 5)
        } label: {
            Label(
                String(format: String(localized: "message.sources.count", defaultValue: "%lld 个来源"), sources.count),
                systemImage: "link"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }
}

private extension FamiliarSourceKind {
    var symbol: String {
        switch self {
        case .searchResult: "magnifyingglass"
        case .fetchedPage: "doc.text"
        case .providerNative: "sparkles"
        }
    }

    var label: String {
        switch self {
        case .searchResult: String(localized: "source.kind.search", defaultValue: "搜索结果")
        case .fetchedPage: String(localized: "source.kind.page", defaultValue: "已读取网页")
        case .providerNative: String(localized: "source.kind.provider", defaultValue: "模型来源")
        }
    }
}

private extension FamiliarSurfacePhase {
    var accessibilityDescription: String {
        switch self {
        case .queued, .planning, .running:
            String(localized: "accessibility.tool.status.running")
        case .awaitingApproval:
            String(localized: "accessibility.confirmation.required")
        case .succeeded:
            String(localized: "accessibility.tool.status.succeeded")
        case .cancelled:
            String(localized: "accessibility.tool.status.cancelled")
        case .failed:
            String(localized: "accessibility.tool.status.failed")
        case .undone:
            String(localized: "tool.undone", defaultValue: "Undone")
        }
    }
}

private struct FamiliarBottomPositionPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Previews

#Preview("Tool card lifecycle") {
    let samples = FamiliarSurfacePreviewSamples.allToolPhases
    return ScrollView {
        VStack(spacing: 14) {
            ForEach(samples) { sample in
                FamiliarToolActivityCard(
                    surface: sample.surface,
                    canUndo: sample.surface.phase == .succeeded,
                    onResolveApproval: { _, _ in },
                    onUndo: {}
                )
            }
        }
        .padding(18)
    }
}

#Preview("Agent status") {
    VStack(spacing: 14) {
        FamiliarAgentStatusRow(
            surface: FamiliarSurfaceDescriptor(
                id: "run:preview",
                runID: "preview",
                kind: .agentStatus,
                phase: .planning,
                title: String(localized: "agent.status.thinking"),
                startedAt: Date(),
                eventSequence: 0
            )
        )
        FamiliarAgentStatusRow(
            surface: FamiliarSurfaceDescriptor(
                id: "run:preview-failed",
                runID: "preview-failed",
                kind: .agentStatus,
                phase: .failed,
                title: String(localized: "agent.status.responding"),
                detail: "Network unreachable",
                startedAt: Date(),
                eventSequence: 1
            )
        )
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(uiColor: .systemBackground))
}

#Preview("Artifact card") {
    FamiliarArtifactCard(
        artifact: FamiliarArtifactDescriptor(
            id: UUID(),
            identifier: "artifact_preview",
            projectID: UUID(),
            title: "复习总结",
            format: .markdown,
            relativePath: "Projects/preview/Artifacts/preview/summary.md",
            byteSize: 2048,
            contentHash: "preview",
            source: .generated,
            sourceURLString: nil,
            sourceResourceID: nil,
            sourceResourceVersionID: nil,
            sourceCaptureID: nil,
            createdByRunID: "preview"
        )
    )
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(uiColor: .systemBackground))
}

private enum FamiliarSurfacePreviewSamples {
    static let allToolPhases: [FamiliarToolActivityCardSample] = [
        .init("Running", phase: .running, title: "Web 搜索", detail: "正在检索结果…"),
        .init("Awaiting approval", phase: .awaitingApproval, title: "创建日历事件", detail: nil,
              effect: .reversibleWrite,
              fields: [.init(id: "title", label: "标题", value: "明天下午复习")],
              target: "日历"),
        .init("Succeeded", phase: .succeeded, title: "Web 搜索", detail: "找到 3 条结果"),
        .init("Failed", phase: .failed, title: "读取网页", detail: "连接超时"),
        .init("Cancelled", phase: .cancelled, title: "创建提醒", detail: "已由用户取消")
    ]
}

private struct FamiliarToolActivityCardSample: Identifiable {
    let id: String
    let surface: FamiliarSurfaceDescriptor

    init(
        _ id: String,
        phase: FamiliarSurfacePhase,
        title: String,
        detail: String?,
        effect: FamiliarToolEffect? = nil,
        fields: [FamiliarSurfaceField] = [],
        target: String? = nil
    ) {
        self.id = id
        surface = FamiliarSurfaceDescriptor(
            id: "tool:preview:\(id)",
            runID: "preview",
            toolCallID: id,
            kind: .toolActivity,
            phase: phase,
            title: title,
            detail: detail,
            effect: effect,
            fields: fields,
            target: target,
            approvalRequestID: phase == .awaitingApproval ? UUID() : nil,
            startedAt: Date(),
            finishedAt: phase.isTerminal ? Date() : nil,
            eventSequence: 0
        )
    }
}
