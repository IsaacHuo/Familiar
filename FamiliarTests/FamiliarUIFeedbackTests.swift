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
