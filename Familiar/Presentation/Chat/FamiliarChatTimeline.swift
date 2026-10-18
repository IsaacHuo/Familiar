import Observation
import SwiftData
import SwiftUI
import UIKit

struct FamiliarReplyMetrics: Equatable {
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
    @Environment(\.familiarReduceMotion) private var reduceMotion
    let messages: [FamiliarMessageSnapshot]
    let modelSwitches: [FamiliarModelSwitchSnapshot]
    let agentRuns: [FamiliarAgentRunSnapshot]
    let liveController: FamiliarChatController
    let availableUndoKeys: Set<String>
    let completedUndoKeys: Set<String>
    let onInsertPrompt: (String) -> Void
    let onUndo: (String, String) -> Void
    let onEdit: (FamiliarMessageSnapshot) -> Void
    let onRetry: (FamiliarMessageSnapshot) -> Void
    let onRetryRecovery: (String) -> Void

    @State private var scroll: FamiliarChatScrollSession
    @State private var position = ScrollPosition(idType: String.self)
    @State private var runtimeDisclosure = FamiliarRuntimeDisclosureState()

    private let historyItems: [FamiliarTimelineItem]

    init(
        messages: [FamiliarMessageSnapshot], modelSwitches: [FamiliarModelSwitchSnapshot],
        agentRuns: [FamiliarAgentRunSnapshot], liveController: FamiliarChatController,
        availableUndoKeys: Set<String>, completedUndoKeys: Set<String>,
        onInsertPrompt: @escaping (String) -> Void, onUndo: @escaping (String, String) -> Void,
        onEdit: @escaping (FamiliarMessageSnapshot) -> Void, onRetry: @escaping (FamiliarMessageSnapshot) -> Void,
        onRetryRecovery: @escaping (String) -> Void,
        scrollSession: FamiliarChatScrollSession = .init()
    ) {
        _scroll = State(initialValue: scrollSession)
        self.messages = messages; self.modelSwitches = modelSwitches; self.agentRuns = agentRuns
        self.liveController = liveController
        self.availableUndoKeys = availableUndoKeys; self.completedUndoKeys = completedUndoKeys
        self.onInsertPrompt = onInsertPrompt; self.onUndo = onUndo
        self.onEdit = onEdit; self.onRetry = onRetry; self.onRetryRecovery = onRetryRecovery
        historyItems = Self.history(messages, modelSwitches, agentRuns)
    }

    private static func history(_ messages: [FamiliarMessageSnapshot], _ modelSwitches: [FamiliarModelSwitchSnapshot],
                                _ agentRuns: [FamiliarAgentRunSnapshot]) -> [FamiliarTimelineItem] {
        let runsByMessage = agentRuns.reduce(into: [UUID: FamiliarAgentRunSnapshot]()) { index, run in
            if let id = run.responseMessageID, index[id] == nil { index[id] = run }
        }
        var items = messages.map { message in
            if message.role == .assistant {
                return FamiliarTimelineItem.assistant(
                    id: runsByMessage[message.id].map { "run:\($0.id)" } ?? "message:\(message.id)",
                    message: message, run: runsByMessage[message.id],
                    live: false, date: message.createdAt
                )
            }
            return FamiliarTimelineItem.message(message)
        }
        items += modelSwitches.map(FamiliarTimelineItem.modelSwitch)
        items += agentRuns
            .filter { $0.responseMessageID == nil && $0.status != .running }
            .map { FamiliarTimelineItem.assistant(id: "run:\($0.id)", message: nil, run: $0, live: false, date: $0.startedAt) }
        return items.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    private var timelineItems: [FamiliarTimelineItem] {
        var items = historyItems
        if let surface = liveController.surfaces.orderedSurfaces.first,
           !items.contains(where: { $0.id == "run:\(surface.runID)" }) {
            items.append(.assistant(id: "run:\(surface.runID)", message: nil, run: nil,
                live: true, date: surface.startedAt ?? Date()))
        }
        return items
    }


    var body: some View {
        GeometryReader { viewport in
            Group {
                ScrollView {
                    LazyVStack(spacing: FamiliarAISurfaceMetric.spaceXL) {
                        ForEach(timelineItems) { item in
                            Group {
                            switch item {
                            case .message(let message):
                                FamiliarMessageRow(
                                    message: message,
                                    run: nil,
                                    disclosure: runtimeDisclosure,
                                    availableUndoKeys: availableUndoKeys,
                                    completedUndoKeys: completedUndoKeys,
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
                            case .assistant(_, let message, let run, let live, _):
                                FamiliarAssistantTurn(
                                    message: message,
                                    run: run,
                                    surfaces: live ? liveController.surfaces.orderedSurfaces : run.map(FamiliarSurfaceStore.projectedSurfaces) ?? [],
                                    disclosure: runtimeDisclosure,
                                    liveController: live ? liveController : nil,
                                    onLiveContentChange: { _ in contentAdded() },
                                    availableUndoKeys: availableUndoKeys,
                                    completedUndoKeys: completedUndoKeys,
                                    onInsertPrompt: onInsertPrompt,
                                    onUndo: onUndo,
                                    onRetryRecovery: onRetryRecovery,
                                    onRetryMessage: message.map { value in { onRetry(value) } }
                                )
                                .id(item.id)
                            }
                            }
                            .onGeometryChange(for: CGRect.self) { geometry in
                                geometry.frame(in: .named("conversation-scroll"))
                            } action: { frame in
                                scroll.rowChanged(id: item.id, frame: frame) { delta in
                                    var transaction = Transaction(animation: nil)
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        position.scrollTo(y: max(0, scroll.offset + delta))
                                    }
                                }
                            }
                        }

                        Color.clear.frame(height: FamiliarAISurfaceMetric.hairline)
                            .id("conversation-bottom")
                    }
                    .environment(\.familiarChatScrollSession, scroll)
                    .environment(\.familiarReadingGeometry, FamiliarReadingGeometry(session: scroll, position: $position))
                    .scrollTargetLayout()
                    .padding(.horizontal, FamiliarAISurfaceMetric.spaceL)
                    .padding(.top, FamiliarAISurfaceMetric.spaceL)
                    .padding(.bottom, FamiliarAISurfaceMetric.spaceM)
                    .frame(maxWidth: FamiliarAISurfaceMetric.timelineWidth)
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "conversation-scroll")
                .scrollDismissesKeyboard(.interactively)
                .scrollPosition($position)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.top, for: .sizeChanges)
                .onScrollPhaseChange { _, phase in
                    switch phase {
                    case .tracking, .interacting: scroll.userBegan()
                    case .idle: scroll.userEnded()
                    default: break
                    }
                }
                .onScrollGeometryChange(for: FamiliarTimelineGeometry.self) { geometry in
                    .init(offset: geometry.contentOffset.y,
                          latest: geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height,
                          viewport: geometry.containerSize.height, contentHeight: geometry.contentSize.height)
                } action: { old, new in
                    scroll.geometryChanged(offset: new.offset, latest: new.latest, viewport: new.viewport)
                    if old.contentHeight != new.contentHeight || old.viewport != new.viewport {
                        scheduleFollow()
                    }
                }
                .onAppear { scheduleFollow() }
                .onDisappear { scroll.cancel() }
                .onChange(of: messages.count) { _, _ in contentAdded() }
                .onChange(of: modelSwitches.count) { _, _ in contentAdded() }
                .accessibilityIdentifier("chat.timeline")
                .overlay(alignment: .bottomTrailing) {
                    if scroll.showsReturnToLatest {
                        Button {
                            returnToLatest()
                        } label: {
                            Image(systemName: "arrow.down")
                                .frame(width: FamiliarAISurfaceMetric.rowHeight, height: FamiliarAISurfaceMetric.rowHeight)
                        }
                        .buttonStyle(.plain)
                        .familiarGlassCircle(interactive: true)
                        .padding(FamiliarAISurfaceMetric.spaceL)
                        .accessibilityIdentifier("chat.returnToLatest")
                        .accessibilityLabel(String(localized: "conversation.scroll_latest"))
                        .transition(reduceMotion ? .opacity : FamiliarMotion.softRise)
                    }
                }
            }
        }
    }

    private func contentAdded() {
        scroll.contentAdded()
        scheduleFollow()
    }

    private func scheduleFollow() {
        scroll.schedule {
            withAnimation(reduceMotion ? nil : FamiliarMotion.micro) {
                position.scrollTo(edge: .bottom)
            }
        }
    }

    private func returnToLatest() {
        scroll.requestReturn()
        if scroll.latestOffset - scroll.offset > scroll.viewportHeight {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                position.scrollTo(y: max(0, scroll.latestOffset - scroll.viewportHeight * 0.6))
            }
        }
        scroll.schedule {
            withAnimation(reduceMotion ? nil : FamiliarMotion.collapse) {
                position.scrollTo(edge: .bottom)
            }
        }
    }
}

struct FamiliarTimelineGeometry: Equatable {
    let offset: CGFloat
    let latest: CGFloat
    let viewport: CGFloat
    let contentHeight: CGFloat
}

enum FamiliarTimelineItem: Identifiable {
    case message(FamiliarMessageSnapshot)
    case modelSwitch(FamiliarModelSwitchSnapshot)
    case assistant(id: String, message: FamiliarMessageSnapshot?, run: FamiliarAgentRunSnapshot?, live: Bool, date: Date)

    var id: String {
        switch self {
        case .message(let message): "message:\(message.id.uuidString)"
        case .modelSwitch(let marker): "model-switch:\(marker.id.uuidString)"
        case .assistant(let id, _, _, _, _): id
        }
    }

    var createdAt: Date {
        switch self {
        case .message(let message): message.createdAt
        case .modelSwitch(let marker): marker.createdAt
        case .assistant(_, _, _, _, let date): date
        }
    }
}
