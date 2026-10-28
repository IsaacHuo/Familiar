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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.displayScale) private var displayScale
    @Environment(\.familiarCanMarkRead) private var canMarkRead
    @State private var visibility = FamiliarTimelineReadVisibility()
    @State private var presenterID = UUID()
    @State private var restoredPosition = false
    @State private var highlightedID: String?
    @State private var returnOffset: CGFloat?
    @State private var returnsToLatest = false
    let initialMessageID: UUID?
    let findState: FamiliarConversationFindState?
    @State private var findReturnOffset: CGFloat?
    @State private var findWasFollowing = false
    @State private var inspectingFind = false
    @State private var historyAnchorID: String?
    @State private var returnAnchorID: String?
    @State private var findReturnAnchorID: String?
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
    @State private var entrances: FamiliarEntranceRegistry

    private let historyItems: [FamiliarTimelineItem]
    private let historyIndex: [String: Int]
    private let pageIndex: FamiliarConversationHistoryIndex?
    private let onLoadHistory: (String?) -> Bool

    init(
        messages: [FamiliarMessageSnapshot], modelSwitches: [FamiliarModelSwitchSnapshot],
        agentRuns: [FamiliarAgentRunSnapshot], liveController: FamiliarChatController,
        availableUndoKeys: Set<String>, completedUndoKeys: Set<String>,
        onInsertPrompt: @escaping (String) -> Void, onUndo: @escaping (String, String) -> Void,
        onEdit: @escaping (FamiliarMessageSnapshot) -> Void, onRetry: @escaping (FamiliarMessageSnapshot) -> Void,
        onRetryRecovery: @escaping (String) -> Void,
        scrollSession: FamiliarChatScrollSession = .init(),
        initialMessageID: UUID? = nil,
        findState: FamiliarConversationFindState? = nil,
        historyIndex: FamiliarConversationHistoryIndex? = nil,
        onLoadHistory: @escaping (String?) -> Bool = { _ in true }
    ) {
        _scroll = State(initialValue: scrollSession)
        var restoredScroll = ScrollPosition(idType: String.self)
        if scrollSession.mode == .userReading { restoredScroll.scrollTo(y: max(0, scrollSession.offset)) }
        else { restoredScroll.scrollTo(edge: .bottom) }
        _position = State(initialValue: restoredScroll)
        self.initialMessageID = initialMessageID
        self.findState = findState
        self.pageIndex = historyIndex
        self.onLoadHistory = onLoadHistory
        self.messages = messages; self.modelSwitches = modelSwitches; self.agentRuns = agentRuns
        self.liveController = liveController
        self.availableUndoKeys = availableUndoKeys; self.completedUndoKeys = completedUndoKeys
        self.onInsertPrompt = onInsertPrompt; self.onUndo = onUndo
        self.onEdit = onEdit; self.onRetry = onRetry; self.onRetryRecovery = onRetryRecovery
        let initialHistory = Self.history(messages, modelSwitches, agentRuns)
        historyItems = initialHistory
        self.historyIndex = historyIndex?.positions ?? Dictionary(uniqueKeysWithValues: initialHistory.enumerated().map { ($0.element.id, $0.offset) })
        let initialTarget = initialMessageID.flatMap { id in historyIndex?.messageEntries[id] ?? initialHistory.first { $0.messageID == id }?.id }
        if let initialTarget {
            restoredScroll.scrollTo(id: initialTarget, anchor: .center)
            _position = State(initialValue: restoredScroll)
        }
        _historyAnchorID = State(initialValue: initialTarget ?? scrollSession.historyAnchorID)
        _returnAnchorID = State(initialValue: scrollSession.historyAnchorID)
        var restored = historyItems.map(\.id)
        restored += liveController.surfaces.orderedSurfaces.map { "run:" + $0.runID }
        restored += liveController.runtimeContentBlocks.map { "block:" + $0.id }
        _entrances = State(initialValue: FamiliarEntranceRegistry(restored: restored))
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

    private var historyCount: Int { pageIndex?.entries.count ?? historyItems.count }
    private var historyRange: Range<Int> {
        FamiliarHistoryWindow.range(total: historyCount, center: historyAnchorID.flatMap { historyIndex[$0] })
    }
    private func entryID(at index: Int) -> String {
        pageIndex?.entries[index].id ?? historyItems[index].id
    }
    private func entryID(for message: UUID) -> String? {
        pageIndex?.messageEntries[message] ?? historyItems.first { $0.messageID == message }?.id
    }
    @discardableResult private func changeHistoryAnchor(_ value: String?) -> Bool {
        guard scroll.acceptsPresenter(presenterID) else { return false }
        guard onLoadHistory(value) else { return false }
        historyAnchorID = value
        return true
    }

    private var timelineItems: [FamiliarTimelineItem] {
        let selectedIDs = pageIndex.map { Set($0.entries[historyRange].map(\.id)) }
        var items = selectedIDs.map { ids in historyItems.filter { ids.contains($0.id) } } ?? Array(historyItems[historyRange])
        if let surface = liveController.surfaces.orderedSurfaces.first,
           historyRange.upperBound == historyCount,
           !items.contains(where: { $0.id == "run:\(surface.runID)" }) {
            items.append(.assistant(id: "run:\(surface.runID)", message: nil, run: nil,
                live: true, date: surface.startedAt ?? Date()))
        }
        return items
    }

    private var presentationRows: [FamiliarTimelinePresentationRow] {
        let items = timelineItems
        return items.enumerated().map { index, item in
            let previous = index > 0 ? items[index - 1] : nil
            let day = FamiliarMessageReadingStyle.startsDay(item.createdAt, after: previous?.createdAt)
            // Messages remain distinct. Only adjacency spacing is shared; AI Runs
            // are never merged based on their visible author.
            let sameUser = previous.map { item.isUser && $0.isUser &&
                item.createdAt.timeIntervalSince($0.createdAt) < 600 && !day } ?? false
            let next = index + 1 < items.count ? items[index + 1] : nil
            let joinsNext = next.map { item.isUser && $0.isUser &&
                $0.createdAt.timeIntervalSince(item.createdAt) < 600 &&
                !FamiliarMessageReadingStyle.startsDay($0.createdAt, after: item.createdAt) } ?? false
            return .init(item: item, startsDay: day,
                         gap: index == 0 ? 0 : sameUser ? 0 : 4 + 2 / max(1, displayScale),
                         neighbors: .init(top: sameUser, bottom: joinsNext))
        }
    }


    var body: some View {
        GeometryReader { viewport in
            let viewportHeight = viewport.size.height
            Group {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if historyRange.lowerBound > 0 {
                            Button(String(localized: "message.load_earlier")) { pageHistory(earlier: true) }
                                .font(.subheadline).frame(minHeight: 44).id("history-earlier")
                        }
                        ForEach(presentationRows) { row in
                            let item = row.item
                            VStack(spacing: 0) {
                            if row.startsDay { FamiliarMessageDateDivider(date: item.createdAt) }
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
                            case .modelSwitch(let marker):
                                FamiliarModelSwitchRow(marker: marker)
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
                            }
                            }
                            .background {
                                RoundedRectangle(cornerRadius: FamiliarRadius.card)
                                    .fill(FamiliarTheme.accent.opacity(highlightedID == item.id ? 0.14 : 0))
                            }
                            }
                            .environment(\.familiarMessageNeighbors, row.neighbors)
                            .padding(.top, row.gap)
                            .id(item.id)
                            .animation(reduceMotion ? nil : FamiliarMotion.standard, value: highlightedID == item.id)
                            .modifier(FamiliarSoftRise(enabled: !item.isUser && scroll.mode != .userReading && !voiceOver, identity: item.id))
                            .onGeometryChange(for: Bool.self) { geometry in
                                let frame = geometry.frame(in: .named("conversation-scroll"))
                                return frame.maxY > 0 && frame.maxY <= viewportHeight + 1
                            } action: { visible in
                                guard scroll.acceptsPresenter(presenterID) else { return }
                                if visible { visibility.rows.insert(item.id) } else { visibility.rows.remove(item.id) }
                                updateReadVisibility()
                            }
                            .onGeometryChange(for: CGRect.self) { geometry in
                                geometry.frame(in: .named("conversation-scroll"))
                            } action: { frame in
                                scroll.rowChanged(id: item.id, frame: frame, presenter: presenterID) { delta in
                                    var transaction = Transaction(animation: nil)
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        position.scrollTo(y: max(0, scroll.offset + delta))
                                    }
                                }
                            }
                        }

                        if historyRange.upperBound < historyCount {
                            Button(String(localized: "message.load_later")) { pageHistory(earlier: false) }
                                .font(.subheadline).frame(minHeight: 44)
                        }
                        Color.clear.frame(height: FamiliarAISurfaceMetric.hairline)
                            .id("conversation-bottom")
                    }
                    .environment(\.familiarMessageSearchTerm, findState?.term ?? "")
                    .environment(\.familiarEntranceRegistry, entrances)
                    .environment(\.familiarChatScrollSession, scroll)
                    .environment(\.familiarReadingGeometry, FamiliarReadingGeometry(session: scroll, position: $position, presenterID: presenterID))
                    .scrollTargetLayout()
                    .padding(.horizontal, FamiliarChatAppearance.edgeInset)
                    .padding(.top, FamiliarAISurfaceMetric.spaceM)
                    .padding(.bottom, FamiliarAISurfaceMetric.spaceM)
                    .frame(maxWidth: FamiliarAISurfaceMetric.timelineWidth)
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "conversation-scroll")
                .scrollDismissesKeyboard(.interactively)
                .scrollEdgeEffectHidden(true, for: .top)
                .scrollPosition($position)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.top, for: .sizeChanges)
                .onScrollPhaseChange { _, phase in
                    guard scroll.acceptsPresenter(presenterID) else { return }
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
                    scroll.geometryChanged(offset: new.offset, latest: new.latest, viewport: new.viewport, presenter: presenterID)
                    if old.contentHeight != new.contentHeight || old.viewport != new.viewport {
                        scheduleFollow()
                    }
                }
                .onAppear {
                    scroll.beginPresentation(presenterID)
                    _ = onLoadHistory(historyAnchorID)
                    scroll.historyAnchorID = historyAnchorID
                    if findState?.isPresented == true, !inspectingFind {
                        if findReturnOffset == nil {
                            findReturnOffset = scroll.offset
                            findWasFollowing = scroll.mode != .userReading
                        }
                        scroll.beginInspection(); inspectingFind = true
                    }
                    guard !restoredPosition else { return }
                    restoredPosition = true
                    if let initialMessageID, let target = entryID(for: initialMessageID) {
                        if scroll.mode == .userReading { returnOffset = scroll.offset }
                        else { returnsToLatest = true }
                        scroll.beginInspection()
                        scroll.prepareForNavigation()
                        position.scrollTo(id: target, anchor: .center)
                        highlightedID = target
                        scroll.endInspection()
                    } else if scroll.mode == .userReading { position.scrollTo(y: max(0, scroll.offset)) }
                    else { scheduleFollow() }
                    if voiceOver { scroll.prepareForNavigation() }
                }
                .onChange(of: voiceOver) { _, enabled in
                    if enabled && scroll.acceptsPresenter(presenterID) { scroll.prepareForNavigation() }
                }
                .task(id: highlightedID) {
                    guard highlightedID != nil else { return }
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    highlightedID = nil
                }
                .onChange(of: scroll.readingRevision) { _, _ in updateReadVisibility() }
                .onChange(of: canMarkRead) { _, _ in updateReadVisibility() }
                .onChange(of: messages.last(where: { $0.role == .assistant })?.id) { _, _ in updateReadVisibility() }
                .onChange(of: findState?.isPresented) { _, shown in
                    if shown == true {
                        findReturnOffset = scroll.offset
                        findReturnAnchorID = historyAnchorID
                        findWasFollowing = scroll.mode != .userReading
                        scroll.beginInspection(); inspectingFind = true
                    } else if inspectingFind {
                        scroll.endInspection(); inspectingFind = false
                        guard changeHistoryAnchor(findReturnAnchorID) else { return }
                        if findWasFollowing { returnToLatest() }
                        else if let offset = findReturnOffset {
                            scroll.prepareForNavigation()
                            position.scrollTo(y: max(0, offset))
                        }
                        findReturnOffset = nil; highlightedID = nil
                    }
                }
                .onChange(of: findState?.navigationID) { _, _ in
                    guard let id = findState?.selectedMessageID,
                          let target = entryID(for: id), changeHistoryAnchor(target) else { return }
                    scroll.prepareForNavigation()
                    position.scrollTo(id: target, anchor: .center)
                    highlightedID = target
                }
                .onDisappear {
                    scroll.endPresentation(presenterID)
                    if inspectingFind { scroll.endInspection(); inspectingFind = false }
                }
                .onChange(of: messages.count) { _, _ in contentAdded() }
                .onChange(of: modelSwitches.count) { _, _ in contentAdded() }
                .onChange(of: historyAnchorID) { _, id in scroll.historyAnchorID = id }
                .accessibilityIdentifier("chat.timeline")
                .overlay(alignment: .bottomLeading) {
                    if returnOffset != nil || returnsToLatest {
                        Button {
                            if let offset = returnOffset {
                                guard changeHistoryAnchor(returnAnchorID) else { return }
                                scroll.beginInspection()
                                scroll.prepareForNavigation()
                                position.scrollTo(y: max(0, offset))
                                scroll.endInspection()
                            } else { returnToLatest() }
                            returnOffset = nil; returnsToLatest = false; highlightedID = nil
                        } label: {
                            Label(String(localized: "message.return_position"), systemImage: "arrow.uturn.backward")
                                .font(.caption.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain).familiarGlassSurface(interactive: true)
                        .padding(FamiliarAISurfaceMetric.spaceL)
                        .accessibilityIdentifier("chat.returnToPosition")
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if scroll.showsReturnToLatest || historyRange.upperBound < historyCount {
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
        .background {
            FamiliarChatReadingLifecycle(session: scroll, presenterID: presenterID, sendPresentation: liveController.sendPresentation)
                .frame(width: 0, height: 0).allowsHitTesting(false)
        }
    }

    private func updateReadVisibility() {
        guard scroll.acceptsPresenter(presenterID) else { return }
        guard let latestID = pageIndex?.latestReplyID ?? messages.last(where: { $0.role == .assistant })?.id,
              let row = timelineItems.first(where: { item in
                  if case .assistant(_, let message, _, _, _) = item { return message?.id == latestID }
                  return false
              }), visibility.rows.contains(row.id) else { visibility.latestReply = nil; return }
        visibility.latestReply = latestID
        markVisibleReplyRead()
    }

    private func markVisibleReplyRead() {
        guard canMarkRead, !scroll.isInspecting, let latestVisibleReply = visibility.latestReply else { return }
        liveController.markReplyRead(latestVisibleReply)
    }

    private func contentAdded() {
        scroll.contentAdded()
        scheduleFollow()
    }

    private func scheduleFollow() {
        // Assistive reading must not chase a growing response. The explicit
        // Return to latest action still navigates without changing AX focus.
        guard scroll.acceptsPresenter(presenterID) else { return }
        guard !voiceOver, historyAnchorID == nil else { scroll.cancel(); return }
        scroll.schedule {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                position.scrollTo(edge: .bottom)
            }
        }
    }

    private func returnToLatest() {
        guard changeHistoryAnchor(nil) else { return }
        if voiceOver {
            scroll.prepareForNavigation()
            position.scrollTo(edge: .bottom)
            return
        }
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

    private func pageHistory(earlier: Bool) {
        let range = historyRange
        guard !range.isEmpty else { return }
        let oldEdge = entryID(at: earlier ? range.lowerBound : range.upperBound - 1)
        let index = earlier ? max(0, range.lowerBound - 1) : min(historyCount - 1, range.upperBound)
        scroll.prepareForNavigation()
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) {
            guard changeHistoryAnchor(entryID(at: index)) else { return }
            position.scrollTo(id: oldEdge, anchor: earlier ? .top : .bottom)
        }
    }
}

/// Read bookkeeping never drives layout. Publishing it as SwiftUI State from a
/// geometry callback invalidates the very tree whose visibility is being measured.
@MainActor private final class FamiliarTimelineReadVisibility {
    var rows: Set<String> = []
    var latestReply: UUID?
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

    var isUser: Bool {
        if case .message(let message) = self { return message.role == .user }
        return false
    }

    var messageID: UUID? {
        switch self {
        case .message(let message): message.id
        case .assistant(_, let message, _, _, _): message?.id
        case .modelSwitch: nil
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

private struct FamiliarTimelinePresentationRow: Identifiable {
    let item: FamiliarTimelineItem
    let startsDay: Bool
    let gap: CGFloat
    let neighbors: FamiliarMessageNeighbors
    var id: String { item.id }
}
