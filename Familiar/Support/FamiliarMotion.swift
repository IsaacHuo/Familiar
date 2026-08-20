import SwiftUI
import UIKit

/// Centralized motion tokens. Views must not invent their own durations or
/// springs; state-driven animation should reference these constants.
nonisolated enum FamiliarMotion {
    /// Micro adjustments: icons, button state, opacity, text swaps.
    static let micro = Animation.easeOut(duration: 0.16)
    /// Discrete state transitions: queued -> running -> succeeded -> failed.
    static let state = Animation.smooth(duration: 0.28)
    /// Spatial movement: card expansion, detail presentation, position change.
    static let spatial = Animation.spring(duration: 0.42, bounce: 0.12)
    /// Drawer and composer snap-to-detent.
    static let drawer = Animation.interactiveSpring(
        response: 0.38, dampingFraction: 0.86, blendDuration: 0.08
    )
}

/// Maps a surface phase transition to a single sensory feedback, or nil.
/// Haptics mark only meaningful user-perceivable boundaries, never per-token
/// or per-search-result activity.
nonisolated enum FamiliarHapticPolicy {
    static func feedback(
        from old: FamiliarSurfacePhase,
        to new: FamiliarSurfacePhase
    ) -> SensoryFeedback? {
        guard old != new else { return nil }
        switch (old, new) {
        case (_, .awaitingApproval):
            return .warning
        case (_, .succeeded):
            return .success
        case (_, .failed):
            return .error
        case (_, .cancelled):
            return nil
        default:
            return nil
        }
    }
}
