import Foundation
import Testing
@testable import Familiar

@Suite("Bounded streaming presentation")
struct FamiliarStreamingPresentationTests {
    @Test("First-frame fallback preserves Markdown paragraph boundaries")
    @MainActor
    func fallbackParagraphs() throws {
        let value = try FamiliarMarkdownFallbackText.attributed("# Title\n\nFirst **paragraph**.\n\nSecond 👋🏽.")
        #expect(String(value.characters) == "Title\n\nFirst paragraph.\n\nSecond 👋🏽.")
    }

    @Test("Initial buffering, Unicode chunks, and terminal flush preserve all received text")
    func unicodeAndFlush() {
        var buffer = FamiliarStreamingBuffer()
        let text = "你好 👨‍👩‍👧‍👦 café，正文连续出现。\n\n第二段。"
        buffer.receive(text, streaming: true, at: 0)
        buffer.advance(at: 0.04)
        #expect(buffer.visible.isEmpty)
        buffer.advance(at: 0.08)
        #expect(!buffer.visible.isEmpty)
        #expect(text.hasPrefix(buffer.visible))
        #expect(buffer.visible.count < text.count)
        buffer.receive(text, streaming: false, at: 0.09)
        #expect(buffer.visible == text)
        #expect(!buffer.hasPending)
    }

    @Test("A burst catches up within the additional presentation delay bound")
    func burstBound() {
        var buffer = FamiliarStreamingBuffer()
        let text = String(repeating: "长回复 👋🏽 ", count: 2_000)
        buffer.receive(text, streaming: true, at: 1)
        for tick in 1...13 {
            buffer.advance(at: 1 + Double(tick) * 0.04)
            #expect(text.hasPrefix(buffer.visible))
        }
        #expect(buffer.visible == text)
    }

    @Test("Replacement, cancellation flush, and a new stream cannot leak old queued text")
    func replacement() {
        var buffer = FamiliarStreamingBuffer()
        buffer.receive("Old pending response", streaming: true, at: 0)
        buffer.receive("New response", streaming: false, at: 0.02)
        buffer.advance(at: 1)
        #expect(buffer.visible == "New response")
        buffer.receive("New response continued", streaming: true, at: 2)
        buffer.flush()
        #expect(buffer.visible == "New response continued")
        #expect(!buffer.hasPending)
    }

    @Test("Paced output does not invalidate raw recording and a stopped scheduler stays stopped")
    @MainActor
    func stoppedScheduler() async throws {
        let presentation = FamiliarStreamingPresentation()
        presentation.receive("Pending text", streaming: true)
        presentation.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(presentation.text.isEmpty)
        presentation.receive("Pending text", streaming: false)
        #expect(presentation.text == "Pending text")
    }
}
