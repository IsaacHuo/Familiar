import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Familiar

@Suite("Input dock waiting identity and independent drafts")
struct FamiliarChatInputDockTests {
    @Test("Production text views use initialized Swift subclasses and a retained TextKit 1 stack")
    @MainActor func nativeTextViewInitialization() throws {
        let composer = FamiliarComposerNativeTextView.makeTextKit1View()
        #expect(composer.centersSingleLine)
        #expect(composer.extraTrailingInset == 0)
        #expect(composer.placeholderLabel.superview === composer)
        #expect(!composer.placeholderLabel.isUserInteractionEnabled)
        #expect(!composer.placeholderLabel.isAccessibilityElement)
        let message = FamiliarMessageNativeTextView.makeTextKit1View()
        for view in [composer as UITextView, message] {
            #expect(view.textLayoutManager == nil)
            #expect(view.textContainer.layoutManager === view.layoutManager)
            #expect(view.layoutManager.textStorage === view.textStorage)
            view.text = "中文 👩🏽‍💻\nSecond line\n"
            view.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
            view.layoutIfNeeded()
            #expect(view.textStorage.string == view.text)
        }
        var escaped = false
        message.onEscape = { escaped = true; return true }
        #expect(message.accessibilityPerformEscape())
        #expect(escaped)
    }

    @Test("Opening and focusing the production composer repeatedly handles empty and multiline drafts")
    @MainActor func newChatComposerLifecycle() async throws {
        let window = familiarTestWindow(width: 390, height: 844)
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<3 {
            let controller = FamiliarChatController(dependencies: .init())
            let host = UIHostingController(rootView: Host(controller: controller))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            let editor = try #require(textViews(host.view).first as? FamiliarComposerNativeTextView)
            #expect(editor.centersSingleLine)
            #expect(editor.placeholderLabel.superview === editor)
            #expect(editor.textLayoutManager == nil)
            #expect(editor.becomeFirstResponder())
            for text in ["", "中文 👩🏽‍💻", "Line\n" + String(repeating: "\n", count: 12), ""] {
                editor.text = text
                editor.selectedRange = NSRange(location: text.utf16.count, length: 0)
                editor.delegate?.textViewDidChange?(editor)
                editor.setNeedsLayout()
                editor.layoutIfNeeded()
                #expect(editor.placeholderLabel.isHidden == !text.isEmpty)
                #expect(controller.draft == text)
            }
            editor.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0))
            editor.layoutIfNeeded()
            #expect(editor.markedTextRange != nil)
            editor.unmarkText()
            editor.resignFirstResponder()
            window.rootViewController = nil
        }
    }

    @Test("An interactive pop suspends reading before disappear; cancelling resumes the same presenter")
    @MainActor func interactivePopReadingLifecycle() {
        let session = FamiliarChatScrollSession(), id = UUID()
        session.beginPresentation(id)
        session.geometryChanged(offset: 160, latest: 500, viewport: 400, presenter: id)
        let lifecycle = FamiliarChatReadingLifecycle.Controller(session: session, presenterID: id)
        lifecycle.viewWillDisappear(true)
        session.geometryChanged(offset: 0, latest: 0, viewport: 0, presenter: id)
        #expect(!session.isPresented && session.offset == 160)
        lifecycle.viewDidAppear(true)
        #expect(session.acceptsPresenter(id))
        session.geometryChanged(offset: 180, latest: 500, viewport: 400, presenter: id)
        #expect(session.offset == 180)
    }

    @Test("An outgoing presentation cannot replace the active page's reading geometry")
    @MainActor func readingPresentationOwnership() {
        let session = FamiliarChatScrollSession(), previous = UUID(), current = UUID()
        session.beginPresentation(previous)
        session.geometryChanged(offset: 120, latest: 300, viewport: 500, presenter: previous)
        session.beginPresentation(current)
        session.endPresentation(previous)
        session.geometryChanged(offset: 0, latest: 0, viewport: 0, presenter: previous)
        #expect(session.isPresented && session.offset == 120)
        session.geometryChanged(offset: 250, latest: 500, viewport: 500, presenter: current)
        #expect(session.offset == 250)
        session.endPresentation(current)
        #expect(!session.isPresented)
    }

    @Test("A dismissed timeline ignores teardown geometry and cancels pending follow")
    @MainActor func dismissedScrollGeometry() {
        let session = FamiliarChatScrollSession()
        session.geometryChanged(offset: 120, latest: 500, viewport: 400)
        session.setPresented(false)
        session.geometryChanged(offset: 0, latest: 0, viewport: 0)
        #expect(session.offset == 120)
        #expect(session.latestOffset == 500)
        var moved = false
        session.rowChanged(id: "old", frame: .zero) { _ in moved = true }
        #expect(!moved)
    }

    @Test("Trailing blank paragraphs contribute full height, including beyond the compact cap")
    @MainActor func trailingBlankLineMeasurement() {
        let font = UIFont.systemFont(ofSize: 18)
        let short = FamiliarComposerNativeTextView.contentHeight(text: "Line", font: font, width: 180)
        let blank = FamiliarComposerNativeTextView.contentHeight(text: "Line" + String(repeating: "\n", count: 12), font: font, width: 180)
        #expect(blank >= short + 11 * font.lineHeight)
        let empty = FamiliarComposerNativeTextView.contentHeight(text: "", font: font, width: 180)
        #expect(empty >= font.lineHeight)
    }

    @Test("Plain prose stays native across length and paragraph boundaries; rich content retains WebKit")
    func nativeTextClassification() {
        for text in ["你好，世界。", "Line\nBreak", "Line\n\nBreak", "Line\r\nBreak", "中文 👩🏽‍💻\nمرحبا", String(repeating: "普通长回答。", count: 100)] {
            #expect(FamiliarMessageReadingStyle.canUseNativeText(text))
        }
        for text in ["", "**Bold**", "1. List", "- List", "[source]", "https://example.com", "`code`", "a_b", "Paragraph\n- List", "Paragraph\n  2. List", "Paragraph\n+ List", "---", "+", "Title\n--", "Paragraph\n---\r\n", "Paragraph\n    code", "\tcode", "Paragraph\nperson@example.com", "$$x$$", "| Column |", "\\(x\\)"] {
            #expect(!FamiliarMessageReadingStyle.canUseNativeText(text))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = Date(timeIntervalSince1970: 86_400)
        #expect(FamiliarMessageReadingStyle.startsDay(midnight, after: midnight.addingTimeInterval(-1), calendar: calendar))
        #expect(!FamiliarMessageReadingStyle.startsDay(midnight.addingTimeInterval(20), after: midnight, calendar: calendar))
    }

    private struct Host: View {
        let controller: FamiliarChatController
        @State private var focused = false
        var body: some View {
            FamiliarChatInputDock(controller: controller, skills: [], isListening: false,
                focus: $focused, availableHeight: 700, onSpeech: {}, onSend: {}, onStop: {})
        }
    }

    @Test("The real editor routes an answer separately and restores message draft and attachments")
    @MainActor func editorRestoresDraft() async throws {
        let controller = FamiliarChatController(dependencies: .init())
        controller.draft = "Original message draft"
        controller.selectedSkillID = UUID()
        let skill = controller.selectedSkillID
        let image = FamiliarDraftImage(image: UIImage())
        controller.draftImages = [image]
        let request = FamiliarClarificationRequest(runID: "run", toolCallID: "ask", question: "Which?", options: [], allowCustom: true)
        controller.pendingClarifications = [request]
        controller.surfaces.apply(.init(runID: "run", sequence: 1, timestamp: Date(), assistantTurnID: "run:turn:0",
            payload: .clarificationRequested(request)))
        let host = UIHostingController(rootView: Host(controller: controller))
        let window = familiarTestWindow(width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(100))
        let editor = try #require(textViews(host.view).first)
        #expect(editor.text.isEmpty)
        editor.text = "Separate answer"
        editor.delegate?.textViewDidChange?(editor)
        try await Task.sleep(for: .milliseconds(80))
        #expect(controller.draft == "Original message draft")
        #expect(controller.draftImages.map(\.id) == [image.id])
        #expect(controller.selectedSkillID == skill)
        controller.pendingClarifications = []
        controller.surfaces.apply(.init(runID: "run", sequence: 2, timestamp: Date(), assistantTurnID: "run:turn:0",
            payload: .clarificationResolved(requestID: request.id, resolution: .custom("Separate answer"))))
        try await Task.sleep(for: .milliseconds(100))
        #expect(textViews(host.view).first?.text == "Original message draft")
        #expect(controller.draftImages.map(\.id) == [image.id])
        #expect(controller.selectedSkillID == skill)
    }

    @MainActor private func textViews(_ view: UIView) -> [UITextView] {
        (view as? UITextView).map { [$0] } ?? view.subviews.flatMap { textViews($0) }
    }
    @Test("Only registered waiting requests appear, ordered by Runtime sequence")
    func projection() {
        let question = FamiliarClarificationRequest(runID: "run", toolCallID: "question", question: "Which?", options: [], allowCustom: true)
        let questionSurface = FamiliarSurfaceDescriptor(id: "question", runID: "run", sequence: 5,
            kind: .clarification, placement: .topLevel, phase: .awaitingClarification, title: question.question,
            toolCallID: question.toolCallID,
            clarificationRequestID: question.id, clarificationAllowsCustom: true)
        var stale = questionSurface
        stale.phase = .succeeded
        #expect(FamiliarPendingInteraction.project(surfaces: [questionSurface], approvals: [], questions: []).isEmpty)
        #expect(FamiliarPendingInteraction.project(surfaces: [stale], approvals: [], questions: [question]).isEmpty)
        let projected = FamiliarPendingInteraction.project(surfaces: [questionSurface], approvals: [], questions: [question])
        #expect(projected.map(\.id) == [question.id])
        #expect(projected.first?.surface == questionSurface)
        var wrongCall = questionSurface
        wrongCall.toolCallID = "another-call"
        #expect(FamiliarPendingInteraction.project(surfaces: [wrongCall], approvals: [], questions: [question]).isEmpty)
        let approval = FamiliarToolConfirmationRequest(runID: "run", toolCallID: "write", toolName: "file_write", title: "Write file")
        let approvalSurface = FamiliarSurfaceDescriptor(id: "approval", runID: "run", sequence: 2,
            kind: .approval, placement: .topLevel, phase: .awaitingApproval, title: approval.title,
            toolCallID: approval.toolCallID, approvalRequestID: approval.id)
        #expect(FamiliarPendingInteraction.project(surfaces: [questionSurface, approvalSurface],
            approvals: [approval], questions: [question]).map(\.id) == [approval.id, question.id])
    }

    @Test("Answers are isolated per request, removed on resolution, and submit once")
    func answerLifecycle() {
        let first = UUID(), second = UUID()
        var drafts = FamiliarInteractionDrafts()
        drafts.setAnswer("First answer", for: first)
        drafts.setAnswer("Second answer", for: second)
        let accepted = drafts.beginSubmission(first)
        let duplicate = drafts.beginSubmission(first)
        #expect(accepted)
        #expect(!duplicate)
        drafts.reconcile([second])
        #expect(drafts.answer(for: first).isEmpty)
        #expect(drafts.answer(for: second) == "Second answer")
        #expect(drafts.submitting.isEmpty)
        drafts.reconcile([])
        #expect(drafts.answer(for: second).isEmpty)
    }

    @Test("Inspection cancels follow work and keeps reading ownership after dismiss")
    @MainActor func inspectionOwnership() async throws {
        let session = FamiliarChatScrollSession()
        session.geometryChanged(offset: 100, latest: 100, viewport: 600)
        var followed = false
        session.schedule { followed = true }
        session.beginInspection()
        session.contentAdded()
        session.geometryChanged(offset: 100, latest: 500, viewport: 600)
        session.schedule { followed = true }
        try await Task.sleep(for: .milliseconds(80))
        #expect(!followed)
        #expect(session.offset == 100)
        #expect(session.mode == .userReading)
        session.endInspection()
        session.schedule { followed = true }
        try await Task.sleep(for: .milliseconds(80))
        #expect(!followed)
        #expect(session.showsReturnToLatest)
        session.requestReturn()
        session.schedule { followed = true }
        try await Task.sleep(for: .milliseconds(80))
        #expect(followed)
    }
}
