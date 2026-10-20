import Foundation
import CoreGraphics
import Observation
import SwiftUI

nonisolated struct FamiliarChatScrollState {
    enum Mode { case following, userReading, returnToLatest }
    private(set) var mode: Mode = .following
    private(set) var hasUnreadContent = false
    private(set) var isInteracting = false
    private var distance: Double = 0

    var showsReturnToLatest: Bool {
        mode == .userReading && (hasUnreadContent || distance > 24)
    }

    mutating func userBegan() {
        isInteracting = true
        mode = .userReading
    }

    mutating func userEnded() {
        isInteracting = false
        if distance <= 1 { mode = .following; hasUnreadContent = false }
    }

    mutating func geometryChanged(distance: Double) {
        self.distance = max(0, distance)
        if mode == .returnToLatest, !isInteracting, distance <= 24 {
            mode = .following
            hasUnreadContent = false
        }
    }

    mutating func contentAdded() {
        if mode == .userReading { hasUnreadContent = true }
    }

    mutating func requestReturn() { mode = .returnToLatest }
    mutating func beginInspection() { isInteracting = false; mode = .userReading }
}

/// Frequent geometry belongs to the session, not observable Timeline inputs.
nonisolated struct FamiliarChatReadingBookmark {
    let offset: CGFloat
    let historyAnchorID: String?
    let wasReading: Bool
}

@MainActor @Observable
final class FamiliarChatScrollSession {
    private(set) var mode = FamiliarChatScrollState.Mode.following
    private(set) var showsReturnToLatest = false
    private(set) var readingRevision = 0
    @ObservationIgnored private var state = FamiliarChatScrollState()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var rowTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRow: (id: String, frame: CGRect, compensate: @MainActor (CGFloat) -> Void)?
    @ObservationIgnored private var inspectionCount = 0
    @ObservationIgnored private var selectionOwner: UUID?
    @ObservationIgnored private var selectionEnd: (() -> Void)?
    @ObservationIgnored private var anchor: (id: String, y: CGFloat, priority: Int)?
    @ObservationIgnored var offset: CGFloat = 0
    @ObservationIgnored var latestOffset: CGFloat = 0
    @ObservationIgnored var viewportHeight: CGFloat = 0
    @ObservationIgnored var historyAnchorID: String?
    @ObservationIgnored private(set) var isPresented = true
    @ObservationIgnored private var presenterID: UUID?

    func beginPresentation(_ id: UUID) {
        guard presenterID != id || !isPresented else { return }
        cancel(); presenterID = id; isPresented = true
    }
    func endPresentation(_ id: UUID) {
        guard presenterID == id else { return }
        setPresented(false)
    }
    func acceptsPresenter(_ id: UUID?) -> Bool { isPresented && (id == nil || presenterID == id) }

    func setPresented(_ value: Bool) {
        isPresented = value
        if !value {
            cancel(); anchor = nil
            let end = selectionEnd; selectionEnd = nil; selectionOwner = nil; end?()
        }
    }

    func beginMessageSelection(_ id: UUID, end: @escaping () -> Void) {
        if selectionOwner != id { let previous = selectionEnd; selectionEnd = nil; selectionOwner = nil; previous?() }
        selectionOwner = id; selectionEnd = end
    }
    func endMessageSelection(_ id: UUID) { if selectionOwner == id { selectionOwner = nil; selectionEnd = nil } }

    var isInteracting: Bool { state.isInteracting }
    var isInspecting: Bool { inspectionCount > 0 }

    var bookmark: FamiliarChatReadingBookmark {
        .init(offset: offset, historyAnchorID: historyAnchorID, wasReading: mode == .userReading)
    }

    func restore(_ bookmark: FamiliarChatReadingBookmark) {
        if bookmark.wasReading { prepareForNavigation() }
        offset = bookmark.offset
        historyAnchorID = bookmark.historyAnchorID
        setPresented(false)
    }

    func contentShifted(_ delta: CGFloat) {
        guard isPresented else { return }
        pendingRow = nil
        if let anchor { self.anchor = (anchor.id, anchor.y - delta, anchor.priority) }
        offset += delta
    }

    func userBegan() { guard isPresented else { return }; cancel(); anchor = nil; state.userBegan(); publish() }
    /// Explicit search/navigation replaces the reading anchor; it is not content growth.
    func prepareForNavigation() {
        cancel(); anchor = nil; state.beginInspection(); readingRevision += 1; publish()
    }
    func userEnded() { guard isPresented, state.isInteracting else { return }; state.userEnded(); readingRevision += 1; publish() }
    func contentAdded() { state.contentAdded(); publish() }
    func requestReturn() { cancel(); state.requestReturn(); publish() }
    func geometryChanged(offset: CGFloat, latest: CGFloat, viewport: CGFloat, presenter: UUID? = nil) {
        guard acceptsPresenter(presenter) else { return }
        let movement = offset - self.offset
        if movement != 0 {
            // The same row moves in viewport coordinates when the viewport scrolls.
            // That movement is not content growth and must not trigger a counter-scroll.
            if let anchor { self.anchor = (anchor.id, anchor.y - movement, anchor.priority) }
            // A row sampled before this scroll geometry belongs to the old viewport.
            pendingRow = nil
        }
        self.offset = offset
        latestOffset = max(0, latest)
        viewportHeight = viewport
        state.geometryChanged(distance: Double(latestOffset - offset))
        publish()
    }

    func rowChanged(id: String, frame: CGRect, priority: Int = 0, presenter: UUID? = nil, compensate: @escaping @MainActor (CGFloat) -> Void) {
        guard acceptsPresenter(presenter), mode == .userReading else { return }
        let visible = frame.minY <= 0 && frame.maxY > 0
        if state.isInteracting || anchor == nil || (visible && priority > (anchor?.priority ?? -1)) {
            if visible {
                if anchor == nil || priority >= (anchor?.priority ?? -1) { anchor = (id, frame.minY, priority) }
            } else if anchor?.id == id { anchor = nil }
        } else if let anchor, anchor.id == id {
            pendingRow = (id, frame, compensate)
            guard rowTask == nil else { return }
            // Geometry callbacks only collect observations. Coalesce the latest
            // sample after layout; never write ScrollPosition during its geometry pass.
            rowTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                self.rowTask = nil
                guard let row = self.pendingRow else { return }
                self.pendingRow = nil
                guard self.isPresented, self.mode == .userReading, !self.state.isInteracting,
                      let anchor = self.anchor, anchor.id == row.id else { return }
                let delta = row.frame.minY - anchor.y
                // Consume this sample before scrolling, including a clamped scroll.
                // The subsequent offset report moves this baseline with the viewport.
                self.anchor = (anchor.id, row.frame.minY, anchor.priority)
                if abs(delta) > 0.5 { row.compensate(delta) }
            }
        }
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        guard isPresented, mode != .userReading, inspectionCount == 0, task == nil else { return }
        task = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self else { return }
            self.task = nil
            guard self.isPresented, self.mode != .userReading, self.inspectionCount == 0 else { return }
            action()
        }
    }

    /// Detail presentation is not a request to follow the newest text.
    func beginInspection() {
        inspectionCount += 1
        cancel()
        if mode != .userReading {
            state.beginInspection()
            readingRevision += 1
            publish()
        }
    }
    func endInspection() { inspectionCount = max(0, inspectionCount - 1); readingRevision += 1 }

    func cancel() {
        task?.cancel(); task = nil
        rowTask?.cancel(); rowTask = nil; pendingRow = nil
    }
    private func publish() {
        if mode != state.mode { mode = state.mode }
        if showsReturnToLatest != state.showsReturnToLatest { showsReturnToLatest = state.showsReturnToLatest }
    }
}

extension EnvironmentValues {
    @Entry var familiarReadingGeometry: FamiliarReadingGeometry? = nil
    @Entry var familiarChatScrollSession: FamiliarChatScrollSession? = nil
}

/// Comparable geometry action: token updates do not replace an environment closure.
nonisolated struct FamiliarReadingGeometry: Equatable {
    let session: FamiliarChatScrollSession
    let position: Binding<ScrollPosition>
    var presenterID: UUID? = nil
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.session === rhs.session && lhs.presenterID == rhs.presenterID }
    @MainActor func record(id: String, frame: CGRect, priority: Int) {
        session.rowChanged(id: id, frame: frame, priority: priority, presenter: presenterID) { delta in
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { position.wrappedValue.scrollTo(y: max(0, session.offset + delta)) }
        }
    }
}
