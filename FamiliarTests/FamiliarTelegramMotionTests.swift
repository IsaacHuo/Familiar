import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Telegram motion and file operation contracts", .serialized)
@MainActor struct FamiliarTelegramMotionTests {
    @Test("Batch delete preserves failed items and rejects scope changes")
    func batchDeleteScopeAndFailure() async throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let scope = FamiliarWorkScope.conversation(UUID())
        let first = FamiliarFileRecord(scope: scope, displayName: "First", origin: .generated)
        let failed = FamiliarFileRecord(scope: scope, displayName: "Failed", origin: .upload)
        let moved = FamiliarFileRecord(scope: .project(UUID()), displayName: "Moved", origin: .upload)
        for file in [first, failed, moved] { context.insert(file) }; try context.save()
        let firstID = first.id, failedID = failed.id, movedID = moved.id
        let targets = [first, failed, moved].map { FamiliarFileDeletionTarget(id: $0.id, scope: scope, name: $0.displayName) }
        let result = await FamiliarFileBatchDeletion.execute(targets, in: context) { file, context in
            if file.id == failedID { throw CocoaError(.fileWriteNoPermission) }
            try FamiliarFileCatalogService().delete(file, in: context)
        }
        #expect(result.succeeded == [firstID])
        #expect(Set(result.failures.keys) == [failedID, movedID])
        #expect(Set(try context.fetch(FetchDescriptor<FamiliarFileRecord>()).map(\.id)) == [failedID, movedID])
    }

    @Test("Selection appends without losing attachments or skills, and stale conversations cannot apply")
    func selectedTextDraftContract() {
        let controller = FamiliarChatController(dependencies: .init())
        controller.draft = "Original 😀"; let skill = UUID(); controller.selectedSkillID = skill
        let attachment = FamiliarAttachmentDraft(id: UUID(), kind: .document, filename: "keep.txt", mimeType: "text/plain", relativePath: "keep.txt", extractedText: "Evidence", byteSize: 8, extractionEngine: "test", extractionVersion: "1", detectedFormat: "txt", usedOCR: false)
        controller.draftAttachments = [attachment]
        #expect(!controller.appendSelectedText(.explain, text: "Passage", sourceID: UUID()))
        #expect(controller.draft == "Original 😀")
        #expect(controller.appendSelectedText(.shorten, text: "Passage 👩🏽‍💻", sourceID: controller.draftConversationID))
        #expect(controller.draft == "Original 😀\n\n" + FamiliarSelectionAction.shorten.prompt(for: "Passage 👩🏽‍💻"))
        #expect(controller.draftAttachments == [attachment] && controller.selectedSkillID == skill)
        #expect(controller.draftSelection == .caretAtEnd(of: controller.draft))
        #expect(!controller.isSending)
    }

    @Test("Only one message selection owns a timeline, including navigation teardown")
    func oneSelectionOwner() {
        let session = FamiliarChatScrollSession(), first = UUID(), second = UUID()
        var ended: [Int] = []
        session.beginMessageSelection(first) { ended.append(1) }
        session.beginMessageSelection(second) { ended.append(2) }
        #expect(ended == [1])
        session.endMessageSelection(first)
        session.setPresented(false)
        #expect(ended == [1, 2])
    }

    @Test("Gallery uses Telegram fade distances and its distance/velocity completion thresholds")
    func galleryDrag() {
        let halfway = FamiliarGalleryDrag(distance: 40, velocity: 0, height: 800)
        #expect(abs(halfway.controlsAlpha - 0.2) < 0.001 && halfway.backdropAlpha == 0.5)
        #expect(!halfway.shouldDismiss)
        #expect(!FamiliarGalleryDrag(distance: 200, velocity: 1_000, height: 800).shouldDismiss)
        #expect(FamiliarGalleryDrag(distance: -201, velocity: 0, height: 800).shouldDismiss)
        #expect(FamiliarGalleryDrag(distance: 0, velocity: -1_001, height: 800).shouldDismiss)
    }

    @Test("Profile mask progress clamps and blur/fade share the same source progress")
    func profileProgress() {
        #expect(FamiliarProfileCollapse(offset: -100).mask == 0)
        let middle = FamiliarProfileCollapse(offset: 60)
        #expect(middle.mask == 0.5)
        #expect(abs(middle.fade - 0.525) < 0.001 && abs(middle.blur - 0.45) < 0.001)
        #expect(FamiliarProfileCollapse(offset: 1_000).fade == 1)
        #expect(FamiliarProfileCollapse(offset: 1_000).blur == 1)
    }
}
