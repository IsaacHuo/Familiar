import SwiftUI
import UIKit

struct FamiliarMessageTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let messages: [FamiliarMessageSnapshot]
    let modelSwitches: [FamiliarModelSwitchSnapshot]
    let toolRunRecords: [FamiliarToolRunSnapshot]
    let agentRuns: [FamiliarAgentRunSnapshot]
    let pendingConfirmations: [FamiliarToolConfirmationRequest]
    let streamingMessageID: UUID?
    let streamingText: String
    let agentStatus: FamiliarRuntimeState?
    let activeRunStartedAt: Date?
    let toolActivities: [FamiliarToolProgress]
    let availableUndoKeys: Set<String>
    let onResolveConfirmation: (FamiliarToolConfirmationRequest, FamiliarToolConfirmationDecision) -> Void
    let onUndo: (FamiliarToolRunSnapshot) -> Void
    let onEdit: (FamiliarMessageSnapshot) -> Void
    let onRetry: (FamiliarMessageSnapshot) -> Void

    @State private var isFollowingLatest = true
    @AccessibilityFocusState private var focusedConfirmationID: UUID?

    private var timelineItems: [FamiliarTimelineItem] {
        var items = messages.map { FamiliarTimelineItem.message(.init(snapshot: $0)) }
        items += modelSwitches.map(FamiliarTimelineItem.modelSwitch)
        let associatedRunIDs = Set(agentRuns.filter { $0.responseMessageID != nil }.map(\.id))
        items += toolRunRecords.filter {
            !associatedRunIDs.contains($0.runID) || availableUndoKeys.contains($0.runID + ":" + $0.toolCallID)
        }.map(FamiliarTimelineItem.toolRecord)
        items.sort {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            return $0.createdAt < $1.createdAt
        }
        for request in pendingConfirmations {
            items.append(.confirmation(request))
        }
        if agentStatus != nil || !toolActivities.isEmpty {
            items.append(.agent(status: agentStatus, activities: toolActivities))
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
                            case .toolRecord(let record):
                                FamiliarPersistedToolRunRow(
                                    record: record,
                                    canUndo: availableUndoKeys.contains(record.runID + ":" + record.toolCallID),
                                    onUndo: { onUndo(record) }
                                )
                                    .id(item.id)
                            case .confirmation(let request):
                                FamiliarToolConfirmationCard(
                                    request: request,
                                    onDecision: { onResolveConfirmation(request, $0) }
                                )
                                .id(item.id)
                                .accessibilityFocused($focusedConfirmationID, equals: request.id)
                            case .agent(let status, let activities):
                                FamiliarAgentRunRow(status: status, startedAt: activeRunStartedAt, activities: activities)
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
                .onChange(of: toolActivities) { _, _ in
                    scrollToLatestIfNeeded(proxy)
                }
                .onChange(of: pendingConfirmations.map(\.id)) { previousIDs, currentIDs in
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
    case toolRecord(FamiliarToolRunSnapshot)
    case confirmation(FamiliarToolConfirmationRequest)
    case agent(status: FamiliarRuntimeState?, activities: [FamiliarToolProgress])

    var id: String {
        switch self {
        case .message(let message): message.id.uuidString
        case .modelSwitch(let marker): "model-switch-\(marker.id.uuidString)"
        case .toolRecord(let record): "tool-record-\(record.id.uuidString)"
        case .confirmation(let request): "confirmation-\(request.id.uuidString)"
        case .agent: "agent-run"
        }
    }

    var sequence: Int {
        switch self {
        case .message(let message): message.sequence
        case .modelSwitch(let marker): marker.sequence
        case .toolRecord(let record): record.sequence
        case .confirmation: Int.max - 1
        case .agent: Int.max
        }
    }

    var createdAt: Date {
        switch self {
        case .message(let message): message.createdAt
        case .modelSwitch(let marker): marker.createdAt
        case .toolRecord(let record): record.finishedAt
        case .confirmation: Date()
        case .agent: .distantFuture
        }
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

private struct FamiliarToolConfirmationCard: View {
    let request: FamiliarToolConfirmationRequest
    let onDecision: (FamiliarToolConfirmationDecision) -> Void

    private var isWrite: Bool {
        request.effect != .read
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: isWrite ? "checklist.checked" : "hand.raised.fill")
                        .font(.title3)
                        .foregroundStyle(FamiliarTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.title)
                            .font(.headline)
                        if let target = request.target {
                            Text(String(format: String(localized: "eventkit.target"), target))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(spacing: 8) {
                    ForEach(request.fields.keys.sorted(), id: \.self) { key in
                        HStack(alignment: .top, spacing: 12) {
                            Text(key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 82, alignment: .leading)
                            Text(request.fields[key] ?? "")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(request.title)
            .accessibilityValue(confirmationAccessibilityValue)

            HStack(spacing: 10) {
                Button(String(localized: "common.cancel")) {
                    onDecision(.cancelled)
                }
                .buttonStyle(.bordered)

                Button(isWrite ? String(localized: "eventkit.confirm_add") : String(localized: "common.continue")) {
                    onDecision(.confirmed)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(FamiliarTheme.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var confirmationAccessibilityValue: String {
        var components = [String(localized: "accessibility.confirmation.required")]
        if let target = request.target {
            components.append(String(format: String(localized: "eventkit.target"), target))
        }
        components += request.fields.keys.sorted().compactMap { key in
            guard let value = request.fields[key], !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        return components.joined(separator: ", ")
    }
}

private struct FamiliarPersistedToolRunRow: View {
    let record: FamiliarToolRunSnapshot
    let canUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                statusIcon
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.summary)
                        .font(.subheadline.weight(.semibold))
                    if !record.detail.isEmpty {
                        Text(record.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                    }
                    Text(record.finishedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(record.summary)
            .accessibilityValue(toolRecordAccessibilityValue)

            if canUndo {
                Button(String(localized: "common.undo"), action: onUndo)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint(String(localized: "tool.undo.hint"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var toolRecordAccessibilityValue: String {
        [record.status.accessibilityDescription, record.detail]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch record.status {
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .cancelled:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
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

private struct FamiliarAgentRunRow: View {
    let status: FamiliarRuntimeState?
    let startedAt: Date?
    let activities: [FamiliarToolProgress]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let status {
                HStack(spacing: 9) {
                    FamiliarOrbitLoadingView(reduceMotion: reduceMotion)
                        .accessibilityHidden(true)
                    Text(status.title)
                        .font(.subheadline.weight(.semibold))
                    if let startedAt {
                        TimelineView(.periodic(from: startedAt, by: 0.1)) { context in
                            Text(Self.elapsed(from: startedAt, to: context.date))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(status.title)
                .accessibilityAddTraits(.updatesFrequently)
            }

            ForEach(activities) { activity in
                HStack(alignment: .top, spacing: 10) {
                    if activity.state != .running {
                        activityIcon(activity.state)
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(activity.title)
                            .font(.subheadline.weight(.semibold))
                        if let detail = activity.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(activity.title)
                .accessibilityValue(
                    [activity.state.accessibilityDescription, activity.detail ?? ""]
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private static func elapsed(from start: Date, to end: Date) -> String {
        let interval = max(0, end.timeIntervalSince(start))
        if interval < 60 { return String(format: "%.1fs", interval) }
        return String(format: "%dm %.1fs", Int(interval / 60), interval.truncatingRemainder(dividingBy: 60))
    }

    @ViewBuilder
    private func activityIcon(_ state: FamiliarToolProgressState) -> some View {
        switch state {
        case .running:
            EmptyView()
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .cancelled:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
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

private extension FamiliarToolProgressState {
    var accessibilityDescription: String {
        switch self {
        case .running: String(localized: "accessibility.tool.status.running")
        case .succeeded: String(localized: "accessibility.tool.status.succeeded")
        case .cancelled: String(localized: "accessibility.tool.status.cancelled")
        case .failed: String(localized: "accessibility.tool.status.failed")
        }
    }
}

private extension FamiliarToolRunTerminalStatus {
    var accessibilityDescription: String {
        switch self {
        case .succeeded: String(localized: "accessibility.tool.status.succeeded")
        case .cancelled: String(localized: "accessibility.tool.status.cancelled")
        case .failed: String(localized: "accessibility.tool.status.failed")
        }
    }
}

private struct FamiliarBottomPositionPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
