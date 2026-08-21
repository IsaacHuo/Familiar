import Foundation
import Testing
@testable import Familiar

@Suite("Selection and source presentation contracts")
struct FamiliarSelectionPresentationTests {
    @Test("Markdown renderer uses the bounded terminal-only selection bridge")
    func selectionBridgeContract() throws {
        let renderer = try source("Familiar/Resources/FamiliarMarkdownRenderer/renderer.js")
        let bridge = try source("Familiar/Presentation/FamiliarMarkdownWebView.swift")

        #expect(renderer.contains("post(\"selectionChanged\", text)"))
        #expect(renderer.contains("Array.from(text).slice(0, 4000)"))
        #expect(renderer.contains("setSelectionEnabled(!(options && options.streaming))"))
        #expect(renderer.contains("selection.removeAllRanges()"))
        #expect(bridge.contains("selectionMessageName = \"selectionChanged\""))
        #expect(bridge.contains("String(selection.prefix(4_000))"))
    }

    @Test("Selection actions only produce localized quoted composer prompts")
    func selectionActionsDoNotSend() throws {
        let selected = String(repeating: "a", count: 4_200)
        let prompt = FamiliarSelectionAction.improve.prompt(for: selected)
        let presentation = try source("Familiar/Presentation/FamiliarChatMessageViews.swift")
        let actions = try section(
            named: "private struct FamiliarSelectionActions",
            endingAt: "private struct FamiliarMessageAction",
            in: presentation
        )

        #expect(prompt.contains(String(repeating: "a", count: 4_000)))
        #expect(!prompt.contains(String(repeating: "a", count: 4_001)))
        #expect(actions.contains("onInsertPrompt(action.prompt(for: selection))"))
        #expect(!actions.contains("onSend"))
    }

    @Test("Sources default collapsed and search results are semantic summaries")
    func compactSourceAndSearchContracts() throws {
        let presentation = try source("Familiar/Presentation/FamiliarChatMessageViews.swift")
        let sources = try section(
            named: "private struct FamiliarInlineSources",
            endingAt: "nonisolated enum FamiliarSelectionAction",
            in: presentation
        )
        let typedResult = try section(
            named: "private struct FamiliarTypedResult",
            endingAt: "private struct FamiliarInlineSources",
            in: presentation
        )
        let english = try source("Familiar/Resources/en.lproj/Localizable.strings")
        let chinese = try source("Familiar/Resources/zh-Hans.lproj/Localizable.strings")

        #expect(sources.contains("@State private var expanded = false"))
        #expect(sources.contains("DisclosureGroup(isExpanded: $expanded)"))
        #expect(!sources.contains("arrow.up.right"))
        #expect(typedResult.contains("search.activity.query"))
        #expect(typedResult.contains("search.activity.read_count"))
        #expect(!typedResult.contains("ForEach(search.results"))
        #expect(!english.contains("tool.cards.position"))
        #expect(!chinese.contains("tool.cards.position"))
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
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}
