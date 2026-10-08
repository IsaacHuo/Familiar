import SwiftUI
import UIKit
import Observation

/// Centralized motion tokens. Views must not invent their own durations or
/// springs; state-driven animation should reference these constants.
nonisolated enum FamiliarMotion {
    static let micro = Animation.easeOut(duration: 0.12)
    static let standard = Animation.smooth(duration: 0.22)
    static let emphasized = Animation.smooth(duration: 0.34)
    static let interactiveSpring = Animation.interactiveSpring(
        response: 0.36, dampingFraction: 0.88, blendDuration: 0.08
    )
    static let contentAppearDuration = 0.15
    static let contentAppearOffset: CGFloat = 2.5
    static let contentAppear = Animation.easeOut(duration: contentAppearDuration)
    static let collapse = Animation.smooth(duration: 0.20)
    static var softRise: AnyTransition {
        .opacity.combined(with: .offset(y: contentAppearOffset))
    }

}

/// Haptics mark semantic boundaries, never individual tokens or read results.
@MainActor
final class FamiliarHaptics {
    nonisolated enum Kind: Equatable { case selection, send, approval, success, warning, destructive }
    static let shared = FamiliarHaptics()
    private var gate = FamiliarHapticGate()

    func perform(_ kind: Kind, event: String? = nil) {
        guard gate.accept(kind, event: event, at: ProcessInfo.processInfo.systemUptime) else { return }
        switch kind {
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .send: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .approval: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .destructive: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }

    nonisolated static func boundary(from old: FamiliarSurfacePhase, to new: FamiliarSurfacePhase) -> Kind? {
        guard old != new else { return nil }
        switch new {
        case .awaitingApproval, .failed: return .warning
        case .succeeded: return .success
        default: return nil
        }
    }
}

/// Bounded duplicate suppression; simultaneous completion receipts share one pulse.
nonisolated struct FamiliarHapticGate {
    private var events: [String: Double] = [:]
    private var lastSuccess: Double?
    mutating func accept(_ kind: FamiliarHaptics.Kind, event: String?, at time: Double) -> Bool {
        if let event {
            guard events[event] == nil else { return false }
            if events.count >= 128, let oldest = events.min(by: { $0.value < $1.value })?.key { events[oldest] = nil }
            events[event] = time
        }
        if kind == .success {
            if let lastSuccess, time - lastSuccess < 0.3 { return false }
            lastSuccess = time
        }
        return true
    }
}

/// Shared short acknowledgement for successful Copy/Save actions.
@MainActor @Observable
final class FamiliarActionConfirmation {
    private(set) var isConfirmed = false
    @ObservationIgnored private var task: Task<Void, Never>?

    @discardableResult func confirm() -> Bool {
        guard !isConfirmed else { return false }
        isConfirmed = true
        task = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.isConfirmed = false
            self.task = nil
        }
        return true
    }

    func reset() {
        task?.cancel()
        task = nil
        isConfirmed = false
    }
}

/// One restrained entrance for newly arriving native Activity/File surfaces.
struct FamiliarSoftRise: ViewModifier {
    let enabled: Bool
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @State private var appeared = false
    func body(content: Content) -> some View {
        let waiting = enabled && !reduceMotion && !appeared
        content.opacity(waiting ? 0 : 1)
            .offset(y: waiting ? FamiliarMotion.contentAppearOffset : 0)
            .task(id: enabled) {
                guard enabled, !reduceMotion, !appeared else { return }
                withAnimation(FamiliarMotion.contentAppear) { appeared = true }
            }
    }
}

extension EnvironmentValues {
    /// System preference in production; deterministic custom-motion acceptance in Debug Simulator.
    var familiarReduceMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        accessibilityReduceMotion || FamiliarChatTestScenario.accessibilityEnabled
        #else
        accessibilityReduceMotion
        #endif
    }
}
