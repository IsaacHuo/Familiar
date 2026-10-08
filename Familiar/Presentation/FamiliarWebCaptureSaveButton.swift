import SwiftData
import SwiftUI

/// A user action on the existing result, independent of Agent tool authorization.
struct FamiliarWebCaptureSaveButton: View {
    let runtimeID: String
    let toolCallID: String
    let truncated: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var savedProjectName: String?
    @State private var errorMessage: String?
    @State private var confirmation = FamiliarActionConfirmation()
    @Environment(\.familiarReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
            if truncated {
                Text(String(localized: "resource.web.partial", defaultValue: "Only the captured portion of this page will be saved."))
                    .font(FamiliarTypography.caption)
                    .foregroundStyle(FamiliarTheme.inkSecondary)
            }
            Button {
                guard !confirmation.isConfirmed else { return }
                do {
                    let file = try FamiliarFileImportService().saveFetchedWebResult(
                        runtimeID: runtimeID, toolCallID: toolCallID, in: modelContext)
                    let projectID = file.projectID
                    savedProjectName = (try? modelContext.fetch(FetchDescriptor<FamiliarProject>(predicate: #Predicate { $0.id == projectID })))?.first?.displayName
                    errorMessage = nil
                    confirmation.confirm()
                    FamiliarHaptics.shared.perform(.success)
                } catch {
                    savedProjectName = nil
                    errorMessage = error.localizedDescription
                    FamiliarHaptics.shared.perform(.warning)
                }
            } label: {
                Label(String(localized: confirmation.isConfirmed ? "common.saved" : "resource.web.save_to_project"), systemImage: confirmation.isConfirmed ? "checkmark" : "folder.badge.plus")
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            }
            .buttonStyle(FamiliarPillButtonStyle(prominence: .secondary))
            .accessibilityIdentifier("web.capture.save_to_project")
            .animation(reduceMotion ? nil : FamiliarMotion.micro, value: confirmation.isConfirmed)
            .onDisappear { confirmation.reset() }

            if let savedProjectName {
                Text(String(format: String(localized: "resource.web.saved_to_project", defaultValue: "Saved to %@"), savedProjectName))
                    .font(FamiliarTypography.caption)
                    .foregroundStyle(FamiliarTheme.inkSecondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(FamiliarTypography.caption)
                    .foregroundStyle(FamiliarTheme.failure)
            }
        }
    }
}
