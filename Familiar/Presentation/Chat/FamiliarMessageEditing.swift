import Foundation
import SwiftData

nonisolated enum FamiliarMessageEditError: LocalizedError {
    case changed, preparing, blocked
    var errorDescription: String? {
        switch self {
        case .changed: String(localized: "message.edit.changed")
        case .preparing: String(localized: "attachment.processing")
        case .blocked: String(localized: "tool.commit.retry_blocked")
        }
    }
}

struct FamiliarSubmittedMessageEdit {
    let state: FamiliarMessageEditState
    let userMessageID: UUID
    let workingDraft: FamiliarComposerDraftSnapshot
    let originalMessageIDs: Set<UUID>
    let originalRunIDs: Set<UUID>
    let originalSwitchIDs: Set<UUID>
}

extension FamiliarChatController {
    @discardableResult
    func prepareToEdit(_ message: FamiliarMessageSnapshot, in context: ModelContext) -> Bool {
        guard !execution.isBusy, !isSending, !isCompacting, message.role == .user,
              let conversation = selectedConversation(in: context),
              conversation.messages.contains(where: { $0.id == message.id }) else { return false }
        if messageEdit?.messageID == message.id { return true }
        guard permitsRegeneration(conversation.agentRuns.filter { $0.startedAt >= message.createdAt }, in: context) else { return false }
        if messageEdit != nil { cancelMessageEdit(in: context) }
        guard draftImages.allSatisfy({ $0.attachment != nil }) else {
            errorMessage = FamiliarMessageEditError.preparing.localizedDescription
            return false
        }
        do {
            let staged = try stagedCopies(of: message.attachments)
            let previous = FamiliarComposerDraftSnapshot(text: draft, selection: draftSelection,
                skillID: selectedSkillID, attachments: draftAttachments + draftImages.compactMap(\.attachment))
            messageEdit = .init(messageID: message.id, sequence: message.sequence,
                sourceContent: message.content, sourceAttachmentIDs: Set(message.attachments.map(\.id)), previousDraft: previous)
            restoreComposerDraft(.init(text: message.content, selection: .caretAtEnd(of: message.content), skillID: nil, attachments: staged))
            scheduleDraftCheckpoint(in: context)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func cancelMessageEdit(in context: ModelContext) {
        guard !isSending, !isCompacting, let edit = messageEdit else { return }
        messageEdit = nil
        restoreComposerDraft(edit.previousDraft)
        scheduleDraftCheckpoint(in: context)
    }

    func makeMessageEditSubmission(_ edit: FamiliarMessageEditState, userMessageID: UUID,
                                   workingDraft: FamiliarComposerDraftSnapshot, in context: ModelContext) throws -> FamiliarSubmittedMessageEdit {
        guard let conversation = selectedConversation(in: context),
              let original = conversation.messages.first(where: { $0.id == edit.messageID }),
              original.role == .user, original.sequence == edit.sequence, original.content == edit.sourceContent,
              Set(original.attachments.map(\.id)) == edit.sourceAttachmentIDs else { throw FamiliarMessageEditError.changed }
        let runs = conversation.agentRuns.filter { $0.startedAt >= original.createdAt }
        guard permitsRegeneration(runs, in: context) else { throw FamiliarMessageEditError.blocked }
        return .init(state: edit, userMessageID: userMessageID, workingDraft: workingDraft,
            originalMessageIDs: Set(conversation.messages.filter { $0.sequence >= edit.sequence }.map(\.id)),
            originalRunIDs: Set(runs.map(\.id)),
            originalSwitchIDs: Set(conversation.modelSwitchRecords.filter { $0.sequence >= edit.sequence }.map(\.id)))
    }

    /// Part of the user-submission save. The original history and edit bytes stay intact until a complete reply commits.
    func stageSubmittedMessageEditDraft(_ edit: FamiliarSubmittedMessageEdit, conversationID: UUID, in context: ModelContext) throws {
        let record = try FamiliarChatListStore.draft(conversationID, in: context)
            ?? FamiliarComposerDraftRecord(id: conversationID, conversationID: conversationID, projectID: selectedProjectID)
        context.insert(record)
        record.conversationID = conversationID
        record.projectID = selectedProjectID
        try writeDraft(edit.workingDraft, editState: edit.state, to: record)
    }

    /// Stages replacement in the same transaction as the new completed assistant reply.
    func stageSuccessfulMessageEdit(in context: ModelContext) throws -> [String] {
        guard let edit = submittedMessageEdit, let conversation = selectedConversation(in: context) else { return [] }
        guard let original = conversation.messages.first(where: { $0.id == edit.state.messageID }),
              original.sequence == edit.state.sequence, original.content == edit.state.sourceContent,
              Set(original.attachments.map(\.id)) == edit.state.sourceAttachmentIDs,
              let submitted = conversation.messages.first(where: { $0.id == edit.userMessageID }),
              edit.originalMessageIDs.isSubset(of: Set(conversation.messages.map(\.id))) else { throw FamiliarMessageEditError.changed }
        let removed = conversation.messages.filter { edit.originalMessageIDs.contains($0.id) }
        let paths = removed.flatMap { $0.attachments.map(\.relativePath) } + edit.workingDraft.attachments.map(\.relativePath)
        let runs = conversation.agentRuns.filter { edit.originalRunIDs.contains($0.id) }
        deleteSkillSnapshots(for: runs, in: context)
        runs.forEach(context.delete)
        conversation.modelSwitchRecords.filter { edit.originalSwitchIDs.contains($0.id) }.forEach(context.delete)
        removed.forEach(context.delete)
        submitted.sequence = edit.state.sequence
        conversation.contextSummary = nil
        conversation.summaryThroughSequence = nil
        if let record = try FamiliarChatListStore.draft(conversation.id, in: context) {
            let previous = edit.state.previousDraft
            if previous.text.isEmpty && previous.attachments.isEmpty && previous.skillID == nil { context.delete(record) }
            else { try writeDraft(previous, editState: nil, to: record) }
        }
        return paths
    }

    func finishSuccessfulMessageEdit(retiredPaths: [String], in context: ModelContext) {
        guard let edit = submittedMessageEdit else { return }
        submittedMessageEdit = nil
        messageEdit = nil
        restoreComposerDraft(edit.state.previousDraft)
        // Cleanup is after the successful transaction; failure retains bytes, never rolls back history.
        if let retained = try? FamiliarChatListStore.retainedDraftPaths(in: context) {
            let unowned = FamiliarFileCatalogService().unownedAttachmentPaths(retiredPaths, in: context)
            FamiliarAttachmentStore.remove(relativePaths: unowned.filter { !retained.contains($0) })
        }
    }

    func restoreUncommittedMessageEdit(in context: ModelContext) async {
        guard let edit = submittedMessageEdit else { return }
        submittedMessageEdit = nil
        messageEdit = edit.state
        restoreComposerDraft(edit.workingDraft)
        // Failed attempts and their real receipts remain inspectable; the original history was never removed.
        await checkpointDraft(in: context)
    }

    private func writeDraft(_ snapshot: FamiliarComposerDraftSnapshot, editState: FamiliarMessageEditState?, to record: FamiliarComposerDraftRecord) throws {
        record.text = snapshot.text
        let selection = (snapshot.selection ?? .caretAtEnd(of: snapshot.text)).normalized(in: snapshot.text)
        record.selectionStart = selection.start
        record.selectionEnd = selection.end
        record.skillID = snapshot.skillID
        record.attachmentsData = try JSONEncoder().encode(snapshot.attachments)
        record.editStateData = try editState.map { try JSONEncoder().encode($0) }
        record.updatedAt = Date()
    }
}
