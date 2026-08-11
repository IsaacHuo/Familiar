import SwiftUI
import UIKit

struct FamiliarMessageTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let messages: [FamiliarMessageSnapshot]
    let streamingMessageID: UUID?
    let streamingText: String
    let agentStatus: FamiliarAgentStatus?
    let toolActivities: [FamiliarToolActivity]
    let onEdit: (FamiliarMessageSnapshot) -> Void
    let onRetry: (FamiliarMessageSnapshot) -> Void

    @State private var isFollowingLatest = true

    private var timelineItems: [FamiliarTimelineItem] {
        var items = messages.map { FamiliarTimelineItem.message(.init(snapshot: $0)) }
        if agentStatus != nil || !toolActivities.isEmpty {
            items.append(.agent(status: agentStatus, activities: toolActivities))
        }
        if let streamingMessageID, !streamingText.isEmpty {
            items.append(.message(.init(
                id: streamingMessageID,
                role: .assistant,
                content: streamingText,
                createdAt: Date(),
                sequence: Int.max,
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
                    LazyVStack(spacing: 22) {
                        ForEach(timelineItems) { item in
                            switch item {
                            case .message(let message):
                                FamiliarMessageRow(
                                    message: message,
                                    onEdit: onEdit,
                                    onRetry: onRetry
                                )
                                .id(item.id)
                            case .agent(let status, let activities):
                                FamiliarAgentRunRow(status: status, activities: activities)
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
    case agent(status: FamiliarAgentStatus?, activities: [FamiliarToolActivity])

    var id: String {
        switch self {
        case .message(let message): message.id.uuidString
        case .agent: "agent-run"
        }
    }
}

private struct FamiliarRenderedMessage {
    let id: UUID
    let role: FamiliarMessageRole
    let content: String
    let createdAt: Date
    let sequence: Int
    let isStreaming: Bool
    let source: FamiliarMessageSnapshot?

    init(snapshot: FamiliarMessageSnapshot) {
        id = snapshot.id
        role = snapshot.role
        content = snapshot.content
        createdAt = snapshot.createdAt
        sequence = snapshot.sequence
        isStreaming = false
        source = snapshot
    }

    init(
        id: UUID,
        role: FamiliarMessageRole,
        content: String,
        createdAt: Date,
        sequence: Int,
        isStreaming: Bool,
        source: FamiliarMessageSnapshot?
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.sequence = sequence
        self.isStreaming = isStreaming
        self.source = source
    }
}

private struct FamiliarMessageRow: View {
    let message: FamiliarRenderedMessage
    let onEdit: (FamiliarMessageSnapshot) -> Void
    let onRetry: (FamiliarMessageSnapshot) -> Void

    var body: some View {
        if message.role == .user {
            userMessage
        } else {
            assistantMessage
        }
    }

    private var userMessage: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 48)
            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(FamiliarTheme.userFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: {
                        Label(String(localized: "common.copy"), systemImage: "doc.on.doc")
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
            FamiliarMarkdownWebView(markdown: message.content, isStreaming: message.isStreaming)

            if message.isStreaming {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text(String(localized: "message.responding"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let source = message.source {
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
    let status: FamiliarAgentStatus?
    let activities: [FamiliarToolActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let status {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(status.title)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }

            ForEach(activities) { activity in
                HStack(alignment: .top, spacing: 10) {
                    activityIcon(activity.state)
                        .frame(width: 20, height: 20)
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
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func activityIcon(_ state: FamiliarToolActivityState) -> some View {
        switch state {
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

private struct FamiliarBottomPositionPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
