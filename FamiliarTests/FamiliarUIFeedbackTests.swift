import Foundation
import Testing
@testable import Familiar

@Suite("Focused UI feedback contracts")
struct FamiliarUIFeedbackTests {
    @Test("Launch enters Chat directly and missing API keys fail before attachment work")
    func directLaunchAndKeyGuard() throws {
        let root = try source("Familiar/Presentation/FamiliarRootView.swift")
        let controller = try source("Familiar/Presentation/FamiliarChatController.swift")

        #expect(root.contains("FamiliarChatView("))
        #expect(!root.contains("FamiliarOnboardingView"))
        #expect(!root.contains("hasCompletedOnboarding"))

        let keyGuard = try #require(controller.range(of: "FamiliarKeychainStore.load(for: requestSettings.providerID)"))
        let imageImport = try #require(controller.range(of: "FamiliarAttachmentStore.importImage"))
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
        #expect(messages.contains("FamiliarAttachmentPreviewView(url: url)"))
        #expect(composer.contains(".fullScreenCover(item: $previewImage)"))
        #expect(composer.contains("Button(role: .destructive)"))
        #expect(preview.contains("@Environment(\\.dismiss)"))
        #expect(preview.contains("Button(String(localized: \"common.done\""))
    }

    @Test("Thinking, Activity, drawer, and Skills retain the requested native contracts")
    func activityDrawerAndSkills() throws {
        let messages = try source("Familiar/Presentation/FamiliarChatMessageViews.swift")
        let chat = try source("Familiar/Presentation/FamiliarChatView.swift")
        let settings = try source("Familiar/Presentation/FamiliarSettingsHubView.swift")
        let thinking = try section(named: "private struct FamiliarThinkingState", endingAt: "private struct FamiliarThinkingRowView", in: messages)
        let activity = try section(named: "private struct FamiliarActivityTrace", endingAt: "private struct FamiliarContextTrace", in: messages)

        #expect(!thinking.contains("Image(systemName: \"chevron.down\")"))
        #expect(!activity.contains("traceIndent"))
        #expect(activity.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(chat.contains(".sensoryFeedback(.selection, trigger: isDrawerOpen)"))
        #expect(settings.contains("NavigationLink {"))
        #expect(settings.contains("FamiliarSkillEditorView(skill: skill)"))
        #expect(settings.contains("if let skill { return skill.stableID }"))
    }

    @Test("Tool calls render as ordered stable blocks with anchored disclosure")
    func toolBlockPresentation() throws {
        let messages = try source("Familiar/Presentation/FamiliarChatMessageViews.swift")
        let chips = try source("Familiar/Presentation/FamiliarToolChips.swift")

        #expect(!messages.contains("surfaces: toolChipSurfaces"))
        #expect(messages.contains("private var contentBlocks: [FamiliarAssistantContentBlock]"))
        #expect(messages.contains("private struct FamiliarExecutionBlock"))
        #expect(messages.contains("FamiliarMotion.expansion"))
        #expect(messages.contains(".transition(.opacity)"))
        #expect(!messages.contains("variant: .coding"))
        #expect(chips.contains("@State private var isOpen = true"))
        #expect(chips.contains("@State private var openRows: Set<String>"))
        #expect(chips.contains(".onHover { isHovered = $0 }"))
        #expect(chips.contains("FamiliarToolChipFlowLayout"))
        #expect(chips.contains("afterLines.difference(from: beforeLines)"))
        #expect(chips.contains("FamiliarToolDiffPreview"))
        #expect(chips.contains("scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)"))
        #expect(!chips.contains(".move(edge:"))
        #expect(chips.contains("Dictionary(grouping: eligible)"))
        #expect(chips.contains("static func thinkingItem("))
    }

    @Test("Artifact lists group versions by lineage instead of listing each version flatly")
    func artifactVersionGrouping() throws {
        let projects = try source("Familiar/Presentation/FamiliarProjectsView.swift")

        // Both the full list and the project home summary must collapse a lineage, or
        // successive revisions of one file appear as unrelated Artifacts.
        #expect(projects.contains("Dictionary(grouping: artifacts, by: \\.lineageID)"))
        #expect(projects.contains("Dictionary(grouping: projectArtifacts, by: \\.lineageID)"))
        #expect(projects.contains("FamiliarArtifactVersionHistoryView"))
        // Superseded versions stay previewable and shareable rather than being hidden.
        #expect(projects.contains("artifact.versions.count"))
        // No force unwrap of a possibly-empty lineage group in a production list.
        #expect(!projects.contains("id: \\.first!.id"))
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

    @Test("The whole artifact receipt card opens the deliverable")
    func artifactReceiptCardIsTappable() throws {
        let messages = try source("Familiar/Presentation/FamiliarChatMessageViews.swift")
        let receipt = try section(
            named: "private struct FamiliarWriteReceipt: View {",
            endingAt: "private var authorizationSummary: String? {",
            in: messages
        )

        // contentShape is required: the background shape alone does not make the padding
        // tappable, which would leave most of the card visually inviting a dead tap.
        #expect(receipt.contains(".contentShape(RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.card"))
        #expect(receipt.contains(".onTapGesture {"))
        // The title is plain content now: a second overlapping target doing the same thing
        // only shrinks the one the user actually aims at.
        #expect(!receipt.contains("Button {"))
        // Announced as a button only when a file exists, so the card never claims to be
        // openable with nothing to open.
        #expect(receipt.contains("accessibilityAddTraits(artifactURL == nil ? [] : .isButton)"))
        // Share stays a separate element rather than being swallowed by the card gesture.
        #expect(receipt.contains("ShareLink(item: artifactURL)"))
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
