import SwiftUI
import UIKit

/// Centralized motion tokens. Views must not invent their own durations or
/// springs; state-driven animation should reference these constants.
nonisolated enum FamiliarMotion {
    /// Micro adjustments: icons, button state, opacity, text swaps.
    static let micro = Animation.easeOut(duration: 0.16)
    /// Discrete state transitions: queued -> running -> succeeded -> failed.
    static let state = Animation.smooth(duration: 0.28)
    /// Inline disclosure expands from its existing top edge without travel.
    static let expansion = Animation.smooth(duration: 0.24)
    /// Spatial movement: card expansion, detail presentation, position change.
    static let spatial = Animation.spring(duration: 0.42, bounce: 0.12)
    /// Drawer and composer snap-to-detent.
    static let drawer = Animation.interactiveSpring(
        response: 0.38, dampingFraction: 0.86, blendDuration: 0.08
    )
    /// Beautiful UI's emphasized ease-out curve for response surfaces.
    static let response = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.4)
    /// Short entrance used by result rows and intervention surfaces.
    static let reveal = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.35)
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
