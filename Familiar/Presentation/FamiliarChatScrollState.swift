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
}

/// Frequent geometry belongs to the session, not observable Timeline inputs.
@MainActor @Observable
final class FamiliarChatScrollSession {
    private(set) var mode = FamiliarChatScrollState.Mode.following
    private(set) var showsReturnToLatest = false
    private(set) var readingRevision = 0
    @ObservationIgnored private var state = FamiliarChatScrollState()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var anchor: (id: String, y: CGFloat, priority: Int)?
    @ObservationIgnored var offset: CGFloat = 0
    @ObservationIgnored var latestOffset: CGFloat = 0
    @ObservationIgnored var viewportHeight: CGFloat = 0

    var isInteracting: Bool { state.isInteracting }

    func contentShifted(_ delta: CGFloat) {
        if let anchor { self.anchor = (anchor.id, anchor.y - delta, anchor.priority) }
        offset += delta
    }

    func userBegan() { cancel(); anchor = nil; state.userBegan(); publish() }
    func userEnded() { guard state.isInteracting else { return }; state.userEnded(); readingRevision += 1; publish() }
    func contentAdded() { state.contentAdded(); publish() }
    func requestReturn() { cancel(); state.requestReturn(); publish() }
    func geometryChanged(offset: CGFloat, latest: CGFloat, viewport: CGFloat) {
        self.offset = offset
        latestOffset = max(0, latest)
        viewportHeight = viewport
        state.geometryChanged(distance: Double(latestOffset - offset))
        publish()
    }

    func rowChanged(id: String, frame: CGRect, priority: Int = 0, compensate: (CGFloat) -> Void) {
        guard mode == .userReading else { return }
        let visible = frame.minY <= 0 && frame.maxY > 0
        if state.isInteracting || anchor == nil || (visible && priority > (anchor?.priority ?? -1)) {
            if visible {
                if anchor == nil || priority >= (anchor?.priority ?? -1) { anchor = (id, frame.minY, priority) }
            } else if anchor?.id == id { anchor = nil }
        } else if let anchor, anchor.id == id {
            let delta = frame.minY - anchor.y
            if abs(delta) > 0.5 { compensate(delta) }
        }
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        guard mode != .userReading, task == nil else { return }
        task = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self else { return }
            self.task = nil
            guard self.mode != .userReading else { return }
            action()
        }
    }

    func cancel() { task?.cancel(); task = nil }
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
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.session === rhs.session }
    @MainActor func record(id: String, frame: CGRect, priority: Int) {
        session.rowChanged(id: id, frame: frame, priority: priority) { delta in
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { position.wrappedValue.scrollTo(y: max(0, session.offset + delta)) }
        }
    }
}
