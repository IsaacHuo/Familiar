import SwiftUI

/// An immutable source identity travels with the native edit menu, not a row index.
struct FamiliarSelectedTextSink: Equatable {
    let controller: FamiliarChatController
    let sourceID: UUID
    let focus: Binding<Bool>
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.controller === rhs.controller && lhs.sourceID == rhs.sourceID }
    @MainActor var isAvailable: Bool {
        controller.scrollSession.isPresented && !controller.isDiscarded &&
            sourceID == (controller.selectedConversationID ?? controller.draftConversationID) &&
            controller.pendingConfirmations.isEmpty && controller.pendingClarifications.isEmpty &&
            !(controller.messageEdit != nil && controller.isSending)
    }
    @MainActor func perform(_ action: FamiliarSelectionAction, text: String) {
        guard isAvailable, controller.appendSelectedText(action, text: text, sourceID: sourceID) else { return }
        focus.wrappedValue = true
    }
}
extension EnvironmentValues { @Entry var familiarSelectedTextSink: FamiliarSelectedTextSink? = nil }

extension FamiliarChatController {
    @discardableResult func appendSelectedText(_ action: FamiliarSelectionAction, text: String, sourceID: UUID) -> Bool {
        guard !isDiscarded, sourceID == (selectedConversationID ?? draftConversationID),
              !(messageEdit != nil && isSending) else { return false }
        let selection = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))
        guard !selection.isEmpty else { return false }
        let addition = action.prompt(for: selection)
        draft += draft.isEmpty ? addition : "\n\n" + addition
        draftSelection = .caretAtEnd(of: draft)
        if let presentationContext { scheduleDraftCheckpoint(in: presentationContext) }
        return true
    }
}
