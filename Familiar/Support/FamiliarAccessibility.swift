import UIKit

/// Short semantic events only. Never announce tokens or move accessibility focus
/// as a side effect of a response, a list diff, or a background task.
@MainActor enum FamiliarAccessibility {
    static func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning, UIApplication.shared.applicationState == .active else { return }
        UIAccessibility.post(notification: .announcement, argument: NSAttributedString(
            string: text, attributes: [.accessibilitySpeechQueueAnnouncement: true]
        ))
    }

    static func runAnnouncement(for phase: FamiliarSurfacePhase) -> String? {
        switch phase {
        case .awaitingApproval: String(localized: "agent.status.awaiting_confirmation")
        case .awaitingClarification: String(localized: "clarification.awaiting")
        case .succeeded: String(localized: "notification.run.completed.body")
        case .failed: String(localized: "accessibility.reply_failed")
        case .cancelled: String(localized: "accessibility.reply_stopped")
        default: nil
        }
    }
}
