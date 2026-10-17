import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Familiar

@Suite("Input dock waiting identity and independent drafts")
struct FamiliarChatInputDockTests {
    private struct Host: View {
        let controller: FamiliarChatController
        @FocusState private var focused: Bool
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
