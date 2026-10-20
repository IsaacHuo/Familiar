import Foundation
import SwiftData
import SwiftUI
import UIKit

extension FamiliarChatController {
    func scheduleDraftCheckpoint(in context: ModelContext, immediately: Bool = false) {
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor [weak self] in
            if !immediately { do { try await Task.sleep(for: .milliseconds(350)) } catch { return } }
            await self?.checkpointDraft(in: context)
        }
    }

    @discardableResult func checkpointDraft(in context: ModelContext) async -> Bool {
        guard !isDiscarded, submittedMessageEdit == nil else { return false }
        let checkpointID = UUID()
        draftCheckpointID = checkpointID
        let id = selectedConversationID ?? draftConversationID
        let text = draft, documents = draftAttachments, images = draftImages, skill = selectedSkillID
        let projectID = selectedProjectID, conversationID = selectedConversationID, edit = messageEdit
        var imported: [FamiliarAttachmentDraft] = []
        do {
            if let conversationID {
                var descriptor = FetchDescriptor<FamiliarConversation>(predicate: #Predicate { $0.id == conversationID })
                descriptor.fetchLimit = 1
                guard try context.fetch(descriptor).first != nil else { return false }
            }
            var savedImages: [FamiliarDraftImage] = []
            for item in images {
                let attachment: FamiliarAttachmentDraft
                if let existing = item.attachment { attachment = existing }
                else {
                    guard let image = item.image else { throw FamiliarAttachmentStoreError.sourceUnavailable }
                    attachment = try await FamiliarAttachmentStore.importImage(image)
                    imported.append(attachment)
                }
                savedImages.append(.init(id: item.id, image: item.image, attachment: attachment))
            }
            guard !isDiscarded, draftCheckpointID == checkpointID, !Task.isCancelled, id == (selectedConversationID ?? draftConversationID),
                  text == draft, documents == draftAttachments, images.map(\.id) == draftImages.map(\.id), skill == selectedSkillID, edit == messageEdit else {
                FamiliarAttachmentStore.remove(relativePaths: imported.map(\.relativePath)); return false
            }
            let attachments = documents + savedImages.compactMap(\.attachment)
            if text.isEmpty && attachments.isEmpty && skill == nil && edit == nil {
                if let record = try FamiliarChatListStore.draft(id, in: context) {
                    let removedPaths = try record.retainedAttachments().map(\.relativePath)
                    context.delete(record); try context.save()
                    removeRetiredDraftFiles(removedPaths, in: context)
                }
                return true
            }
            let record = try FamiliarChatListStore.draft(id, in: context)
                ?? FamiliarComposerDraftRecord(id: id, conversationID: conversationID, projectID: projectID)
            let previousPaths = try record.retainedAttachments().map(\.relativePath)
            context.insert(record)
            let encoded = try JSONEncoder().encode(attachments)
            let encodedEdit = try edit.map { try JSONEncoder().encode($0) }
            let contentChanged = record.text != text || record.skillID != skill || record.attachmentsData != encoded || record.editStateData != encodedEdit
            record.conversationID = conversationID
            record.projectID = projectID
            record.text = text
            record.skillID = skill
            record.attachmentsData = encoded
            record.editStateData = encodedEdit
            let selection = (draftSelection ?? .caretAtEnd(of: text)).normalized(in: text)
            record.selectionStart = selection.start
            record.selectionEnd = selection.end
            if contentChanged { record.updatedAt = Date() }
            try context.save()
            let currentPaths = Set((attachments + (edit?.previousDraft.attachments ?? [])).map(\.relativePath))
            removeRetiredDraftFiles(previousPaths.filter { !currentPaths.contains($0) }, in: context)
            draftImages = savedImages
            return true
        } catch is CancellationError {
            FamiliarAttachmentStore.remove(relativePaths: imported.map(\.relativePath))
        } catch {
            context.rollback()
            FamiliarAttachmentStore.remove(relativePaths: imported.map(\.relativePath))
            errorMessage = error.localizedDescription
        }
        return false
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
        messageEdit = try record.editState()
        restoreComposerDraft(.init(text: record.text,
            selection: FamiliarComposerSelection(start: record.selectionStart, end: record.selectionEnd),
            skillID: record.skillID, attachments: attachments))
    }

    func restoreComposerDraft(_ snapshot: FamiliarComposerDraftSnapshot) {
        draftAttachmentIdentity = UUID()
        draft = snapshot.text
        draftSelection = (snapshot.selection ?? .caretAtEnd(of: draft)).normalized(in: draft)
        selectedSkillID = snapshot.skillID
        draftAttachments = snapshot.attachments.filter { $0.kind != .image }
        draftImages = snapshot.attachments.filter { $0.kind == .image }.compactMap { attachment in
            guard FamiliarAttachmentStore.url(for: attachment.relativePath) != nil else {
                draftAttachments.append(attachment)
                return nil
            }
            return .init(id: attachment.id, attachment: attachment)
        }
        if draftImages.count != snapshot.attachments.filter({ $0.kind == .image }).count {
            errorMessage = String(localized: "chat.draft.missing_attachment")
        }
    }
}
