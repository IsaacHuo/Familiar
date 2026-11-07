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
    @State private var saveTask: Task<Void, Never>?
    @State private var saveID: UUID?
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
                guard !confirmation.isConfirmed, saveID == nil else { return }
                let id = UUID()
                saveID = id
                saveTask = Task {
                    defer { if saveID == id { saveID = nil; saveTask = nil } }
                do {
                    let file = try await FamiliarFileImportService().saveFetchedWebResult(
                        runtimeID: runtimeID, toolCallID: toolCallID, in: modelContext)
                    guard !Task.isCancelled, saveID == id else { return }
                    if let projectID = file.scope.projectID {
                        savedProjectName = (try? modelContext.fetch(FetchDescriptor<FamiliarProject>(predicate: #Predicate { $0.id == projectID })))?.first?.displayName
                    } else { savedProjectName = String(localized: "conversation.ordinary") }
                    errorMessage = nil
                    confirmation.confirm()
                    FamiliarHaptics.shared.perform(.success)
                } catch is CancellationError {
                } catch {
                    guard !Task.isCancelled, saveID == id else { return }
                    savedProjectName = nil
                    errorMessage = error.localizedDescription
                    FamiliarHaptics.shared.perform(.warning)
                }
                }
            } label: {
                if saveID != nil {
                    HStack(spacing: FamiliarSpacing.small) {
                        ProgressView().controlSize(.small).accessibilityHidden(true)
                        Text(String(localized: "common.saving"))
                    }
                } else {
                    Label(String(localized: confirmation.isConfirmed ? "common.saved" : "resource.web.save_to_files"), systemImage: confirmation.isConfirmed ? "checkmark" : "folder.badge.plus")
                        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                }
            }
            .buttonStyle(FamiliarPillButtonStyle(prominence: .secondary))
            .disabled(saveID != nil)
            .accessibilityIdentifier("web.capture.save_to_project")
            .animation(reduceMotion ? nil : FamiliarMotion.micro, value: confirmation.isConfirmed)
            .onDisappear { cancelSave() }
            .onChange(of: runtimeID + ":" + toolCallID) { _, _ in cancelSave(); savedProjectName = nil; errorMessage = nil }

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

    private func cancelSave() {
        saveID = nil
        saveTask?.cancel()
        saveTask = nil
        confirmation.reset()
    }

}
