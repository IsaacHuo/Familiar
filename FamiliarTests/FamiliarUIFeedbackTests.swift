import Foundation
import Testing
@testable import Familiar

@Suite("Focused UI feedback contracts")
struct FamiliarUIFeedbackTests {
    @Test("Copy and Save acknowledge once, expire and cancel on departure")
    @MainActor func confirmationLifetime() async throws {
        let confirmation = FamiliarActionConfirmation()
        #expect(!confirmation.isConfirmed)
        let first = confirmation.confirm()
        let duplicate = confirmation.confirm()
        #expect(first && !duplicate)
        #expect(confirmation.isConfirmed)
        try await Task.sleep(for: .milliseconds(1300))
        #expect(!confirmation.isConfirmed)
        confirmation.confirm()
        confirmation.reset()
        #expect(!confirmation.isConfirmed)
        confirmation.confirm()
        try await Task.sleep(for: .milliseconds(100))
        #expect(confirmation.isConfirmed)
        confirmation.reset()
    }

    @Test("Haptics suppress duplicate boundaries and combine concurrent successes")
    func semanticHaptics() {
        var gate = FamiliarHapticGate()
        let accepted1 = gate.accept(.success, event: "a", at: 1)
        #expect(accepted1)
        let accepted2 = !gate.accept(.success, event: "a", at: 2)
        #expect(accepted2)
        let accepted3 = !gate.accept(.success, event: "b", at: 1.1)
        #expect(accepted3)
        let accepted4 = gate.accept(.success, event: "c", at: 1.4)
        #expect(accepted4)
        let accepted5 = gate.accept(.warning, event: "error", at: 1.41)
        #expect(accepted5)
        let accepted6 = !gate.accept(.warning, event: "error", at: 2)
        #expect(accepted6)
        #expect(FamiliarHaptics.boundary(from: .running, to: .succeeded) == .success)
        #expect(FamiliarHaptics.boundary(from: .running, to: .failed) == .warning)
        #expect(FamiliarHaptics.boundary(from: .succeeded, to: .succeeded) == nil)
        #expect(FamiliarHaptics.boundary(from: .running, to: .cancelled) == nil)
    }

    @Test("Launch enters Chat directly and missing API keys fail before attachment work")
    func directLaunchAndKeyGuard() throws {
        let root = try source("Familiar/Presentation/FamiliarRootView.swift")
        let controller = try source("Familiar/Presentation/FamiliarChatController.swift")

        #expect(root.contains("FamiliarChatView("))
        #expect(!root.contains("FamiliarOnboardingView"))
        #expect(!root.contains("hasCompletedOnboarding"))

        let sending = try #require(controller.range(of: "func startSending(in context: ModelContext)"))
        let submission = controller[sending.lowerBound...]
        let keyGuard = try #require(submission.range(of: "FamiliarProviderFactory.credential(for: descriptor)"))
        let imageImport = try #require(submission.range(of: "FamiliarAttachmentStore.importImage"))
        #expect(keyGuard.lowerBound < imageImport.lowerBound)
        #expect(controller.contains("errorMessage = String(localized: \"error.api_key_missing\")"))
    }

    @Test("Images use independent chat presentation with native preview dismissal and deletion")
    func imagePresentation() throws {
        let messages = try source("Familiar/Presentation/FamiliarChatMessageViews.swift")
        let composer = try source("Familiar/Presentation/FamiliarComposerView.swift")
        let preview = try source("Familiar/Presentation/FamiliarAttachmentQuickLookView.swift")

        #expect(messages.contains("ForEach(imageAttachments)"))
        #expect(messages.contains("VStack(alignment: .trailing"))
        #expect(messages.contains(".navigationDestination(item: $previewAttachment)"))
        #expect(composer.contains(".fullScreenCover(item: $previewImage)"))
        #expect(composer.contains("Button(role: .destructive)"))
        #expect(preview.contains("@Environment(\\.dismiss)"))
        #expect(preview.contains("FamiliarDismissButton()"))
    }

    @Test("Runtime Activity, drawer, and Skills retain the requested native contracts")
    func activityDrawerAndSkills() throws {
        let messages = try source("Familiar/Presentation/FamiliarChatMessageViews.swift")
        let chat = try source("Familiar/Presentation/FamiliarChatView.swift")
        let settings = try source("Familiar/Presentation/FamiliarSettingsHubView.swift")
        let activity = try section(named: "private struct FamiliarRuntimeCard", endingAt: "private struct FamiliarRuntimeStageView", in: messages)
        #expect(!messages.contains("FamiliarThinkingState"))
        #expect(activity.contains("disclosure.binding(for: activity.id).wrappedValue.toggle()"))
        #expect(activity.contains("runtime.ui.technical_details"))
        #expect(chat.contains("FamiliarHaptics.shared.perform(.selection)"))
        #expect(settings.contains("NavigationLink {"))
        #expect(settings.contains("FamiliarSkillEditorView(skill: skill)"))
        #expect(settings.contains("if let skill { return skill.stableID }"))
    }

    @Test("Production timeline and visual fixtures share stable execution blocks")
    func toolBlockPresentation() throws {
        let messages = try source("Familiar/Presentation/FamiliarChatMessageViews.swift")
        #expect(messages.contains("private var contentBlocks: [FamiliarAssistantContentBlock]"))
        #expect(messages.contains("private struct FamiliarRuntimeCard"))
        #expect(messages.contains("FamiliarAssistantResponseProjection.blocks(text: [], surfaces: Self.executionSurfaces)"))
        #expect(!messages.contains("FamiliarToolChips("))
    }

    @Test("Canonical file identity owns versions and the catalog defaults to the latest")
    @MainActor
    func fileVersionGrouping() {
        let file = FamiliarFileRecord(projectID: UUID(), displayName: "Report", origin: .generated)
        let first = FamiliarFileVersionRecord(version: 1, filename: "Report.md", mimeType: "text/markdown",
            byteSize: 1, contentHash: "first", extractedText: "First", extractedTextHash: "first",
            storage: .init(kind: .managed, relativePath: "first.md"), file: file)
        let second = FamiliarFileVersionRecord(version: 2, filename: "Report.md", mimeType: "text/markdown",
            byteSize: 2, contentHash: "second", extractedText: "Second", extractedTextHash: "second",
            storage: .init(kind: .managed, relativePath: "second.md"), file: file)
        file.versions = [second, first]
        #expect(first.fileID == second.fileID)
        #expect(file.versions.count == 2)
        #expect(file.latestVersion?.id == second.id)
        #expect(file.snapshot?.reference.fileID == file.id)
        #expect(file.snapshot?.reference.versionID == second.id)
        #expect(first.extractedText == "First")
    }

    @Test("Diagnostics surfaces the real unavailability reason from the registry report")
    func diagnosticsSurfacesReasons() throws {
        let hub = try source("Familiar/Presentation/FamiliarSettingsHubView.swift")

        #expect(hub.contains("case diagnostics"))
        #expect(hub.contains("FamiliarDiagnosticsSettingsView"))
        // Must read the same report the model is told about, not a parallel query that
        // could drift from the runtime's own view of availability.
        #expect(hub.contains("await registry.availabilityReport()"))
        // The concrete reason has to be rendered; showing only "Unavailable" would repeat
        // the defect that made a missing capability indistinguishable from a working one.
        #expect(hub.contains("Text(tool.reason)"))

        let en = try source("Familiar/Resources/en.lproj/Localizable.strings")
        #expect(en.contains("\"settings.diagnostics.title\""))
    }

    @Test("Composer text and its height math scale together with Dynamic Type")
    func dynamicTypeScaling() throws {
        let composer = try source("Familiar/Presentation/FamiliarComposerView.swift")
        let hub = try source("Familiar/Presentation/FamiliarSettingsHubView.swift")

        #expect(composer.contains("@ScaledMetric(relativeTo: .body) private var editorFontSize"))
        // The height math must derive from the same scaled value. Measuring against a
        // fixed 20pt while rendering a scaled font would clip the user's own text.
        #expect(composer.contains("private var lineHeight: CGFloat { UIFont.systemFont(ofSize: editorFontSize).lineHeight }"))
        #expect(!composer.contains("Self.editorFontSize"))
        #expect(!composer.contains("Self.lineHeight"))

        // A fixed icon container beside a label that scales would leave the glyph
        // visually detached at larger sizes.
        #expect(hub.contains("@ScaledMetric(relativeTo: .body) private var rowIconContainer"))
    }

    @Test("File presentation retains the frozen version and does not open missing bytes")
    @MainActor
    func fileReceiptCardIsTappable() {
        let projectID = UUID(), versionID = UUID()
        let snapshot = FamiliarFileSnapshot(reference: .init(fileID: UUID(), versionID: versionID, projectID: projectID),
            name: "Report", origin: .generated, version: 3, filename: "Report.md", mimeType: "text/markdown",
            byteSize: 200, contentHash: "hash",
            storage: .init(kind: .managed, relativePath: "Projects/\(projectID.uuidString)/missing.md"),
            isProjectContext: false, updatedAt: Date())
        let presentation = FamiliarFilePresentation(snapshot: snapshot)
        #expect(presentation.id == versionID.uuidString)
        #expect(presentation.title == "Report")
        #expect(presentation.metadata.contains("v3"))
        #expect(presentation.url == nil)
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func section(named start: String, endingAt end: String, in source: String) throws -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
        else { throw CocoaError(.fileReadCorruptFile) }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}
