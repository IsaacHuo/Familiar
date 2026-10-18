import Foundation
import SwiftData
import SwiftUI
import UIKit

extension FamiliarChatController {
    func scheduleDraftCheckpoint(in context: ModelContext) {
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await self?.checkpointDraft(in: context)
        }
    }

    func checkpointDraft(in context: ModelContext) async {
        guard !isDiscarded else { return }
        let checkpointID = UUID()
        draftCheckpointID = checkpointID
        let id = selectedConversationID ?? draftConversationID
        let text = draft, documents = draftAttachments, images = draftImages, skill = selectedSkillID
        let projectID = selectedProjectID, conversationID = selectedConversationID
        var imported: [FamiliarAttachmentDraft] = []
        do {
            if let conversationID {
                var descriptor = FetchDescriptor<FamiliarConversation>(predicate: #Predicate { $0.id == conversationID })
                descriptor.fetchLimit = 1
                guard try context.fetch(descriptor).first != nil else { return }
            }
            var savedImages: [FamiliarDraftImage] = []
            for item in images {
                let attachment: FamiliarAttachmentDraft
                if let existing = item.attachment { attachment = existing }
                else {
                    attachment = try await FamiliarAttachmentStore.importImage(item.image)
                    imported.append(attachment)
                }
                savedImages.append(.init(id: item.id, image: item.image, attachment: attachment))
            }
            guard !isDiscarded, draftCheckpointID == checkpointID, !Task.isCancelled, id == (selectedConversationID ?? draftConversationID),
                  text == draft, documents == draftAttachments, images.map(\.id) == draftImages.map(\.id), skill == selectedSkillID else {
                FamiliarAttachmentStore.remove(relativePaths: imported.map(\.relativePath)); return
            }
            let attachments = documents + savedImages.compactMap(\.attachment)
            if text.isEmpty && attachments.isEmpty && skill == nil {
                if let record = try FamiliarChatListStore.draft(id, in: context) {
                    let removedPaths = try record.attachments().map(\.relativePath)
                    context.delete(record); try context.save()
                    removeRetiredDraftFiles(removedPaths, in: context)
                }
                return
            }
            let record = try FamiliarChatListStore.draft(id, in: context)
                ?? FamiliarComposerDraftRecord(id: id, conversationID: conversationID, projectID: projectID)
            let previousPaths = try record.attachments().map(\.relativePath)
            context.insert(record)
            let encoded = try JSONEncoder().encode(attachments)
            let contentChanged = record.text != text || record.skillID != skill || record.attachmentsData != encoded
            record.conversationID = conversationID
            record.projectID = projectID
            record.text = text
            record.skillID = skill
            record.attachmentsData = encoded
            if let selection = draftSelection, case .selection(let range) = selection.indices {
                record.selectionStart = range.lowerBound.utf16Offset(in: text)
                record.selectionEnd = range.upperBound.utf16Offset(in: text)
            } else {
                record.selectionStart = text.utf16.count; record.selectionEnd = text.utf16.count
            }
            if contentChanged { record.updatedAt = Date() }
            try context.save()
            let currentPaths = Set(attachments.map(\.relativePath))
            removeRetiredDraftFiles(previousPaths.filter { !currentPaths.contains($0) }, in: context)
            draftImages = savedImages
        } catch is CancellationError {
            FamiliarAttachmentStore.remove(relativePaths: imported.map(\.relativePath))
        } catch {
            context.rollback()
            FamiliarAttachmentStore.remove(relativePaths: imported.map(\.relativePath))
            errorMessage = error.localizedDescription
        }
    }

    private func removeRetiredDraftFiles(_ paths: [String], in context: ModelContext) {
        guard !paths.isEmpty else { return }
        // Cleanup failure keeps old bytes; it must never roll back a completed save or remove new bytes.
        guard let retained = try? FamiliarChatListStore.retainedDraftPaths(in: context) else { return }
        FamiliarAttachmentStore.remove(relativePaths: paths.filter { !retained.contains($0) })
    }

    func restoreDraft(id: UUID, in context: ModelContext) throws {
        guard let record = try FamiliarChatListStore.draft(id, in: context) else { return }
        let attachments = try record.attachments()
        draftConversationID = id
        selectedProjectID = record.projectID
        draft = record.text
        selectedSkillID = record.skillID
        draftAttachments = attachments.filter { $0.kind != .image }
        draftImages = attachments.filter { $0.kind == .image }.compactMap { attachment in
            guard let url = FamiliarAttachmentStore.url(for: attachment.relativePath),
                  let image = UIImage(contentsOfFile: url.path) else {
                draftAttachments.append(attachment)
                return nil
            }
            return .init(id: attachment.id, image: image, attachment: attachment)
        }
        if draftImages.count != attachments.filter({ $0.kind == .image }).count {
            errorMessage = String(localized: "chat.draft.missing_attachment")
        }
        let start = min(max(0, record.selectionStart), draft.utf16.count)
        let end = min(max(start, record.selectionEnd), draft.utf16.count)
        let lower = String.Index(utf16Offset: start, in: draft), upper = String.Index(utf16Offset: end, in: draft)
        draftSelection = TextSelection(range: lower..<upper)
    }
}
