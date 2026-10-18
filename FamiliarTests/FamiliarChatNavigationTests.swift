import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Familiar

@Suite("Chat navigation state", .serialized)
struct FamiliarChatNavigationTests {
    @Test("Current store adds presentation records without deleting existing conversation data")
    @MainActor func additiveStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ChatStore-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.store"), id = UUID()
        do {
            let schema = Schema(versionedSchema: BeforeChatNavigation.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Test", schema: schema, url: url)])
            container.mainContext.insert(FamiliarConversation(id: id, title: "Keep this conversation"))
            try container.mainContext.save()
        }
        let container = try FamiliarModelContainer.make(at: url, configurationName: "Test")
        let conversation = try #require(container.mainContext.fetch(FetchDescriptor<FamiliarConversation>()).first)
        #expect(conversation.id == id)
        #expect(conversation.title == "Keep this conversation")
        let state = try FamiliarChatListStore.state(for: conversation, in: container.mainContext)
        #expect(!state.isUnread)
        #expect(!state.isArchived)
        try container.mainContext.save()
    }

    @Test("New drafts persist independently without creating Conversations and retain attachment paths")
    @MainActor func independentDrafts() async throws {
        let container = try FamiliarModelContainer.makeInMemory()
        let context = container.mainContext, dependencies = FamiliarAppDependencies()
        let first = FamiliarChatController(dependencies: dependencies)
        first.draft = "First draft"
        first.selectedSkillID = UUID()
        let second = FamiliarChatController(dependencies: dependencies)
        second.draft = "Second draft"
        await first.checkpointDraft(in: context)
        await second.checkpointDraft(in: context)
        #expect(try context.fetch(FetchDescriptor<FamiliarConversation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarComposerDraftRecord>()).count == 2)
        let restored = FamiliarChatController(dependencies: dependencies)
        try restored.restoreDraft(id: first.draftConversationID, in: context)
        #expect(restored.draft == "First draft")
        #expect(restored.selectedSkillID == first.selectedSkillID)
        #expect(restored.draftConversationID == first.draftConversationID)
    }

    @Test("New replies stay archived and an old visibility callback cannot clear new unread state")
    @MainActor func unreadIdentity() throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let conversation = FamiliarConversation()
        context.insert(conversation)
        let state = try FamiliarChatListStore.state(for: conversation, in: context)
        state.isArchived = true
        let first = FamiliarMessage(role: .assistant, content: "One", sequence: 1, conversation: conversation)
        let second = FamiliarMessage(role: .assistant, content: "Two", sequence: 2, conversation: conversation)
        context.insert(first); context.insert(second)
        try FamiliarChatListStore.stageMessage(first, in: context)
        try FamiliarChatListStore.stageMessage(second, in: context)
        FamiliarChatListStore.markRead(state, replyID: first.id)
        #expect(state.isUnread)
        #expect(state.isArchived)
        FamiliarChatListStore.markRead(state, replyID: second.id)
        #expect(!state.isUnread)
        state.manuallyUnread = true
        #expect(state.isUnread)
        FamiliarChatListStore.markRead(state)
        #expect(!state.isUnread)
    }

    @Test("Draft text and UTF-16 selection reopen from a file-backed store without a Conversation")
    @MainActor func diskDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Draft-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.store"), id = UUID(), skill = UUID()
        do {
            let container = try FamiliarModelContainer.make(at: url, configurationName: "DraftTest")
            let controller = FamiliarChatController(dependencies: .init())
            controller.draftConversationID = id
            controller.draft = "A🙂中B"
            controller.selectedSkillID = skill
            controller.draftSelection = TextSelection(range: String.Index(utf16Offset: 1, in: controller.draft)..<String.Index(utf16Offset: 3, in: controller.draft))
            await controller.checkpointDraft(in: container.mainContext)
            #expect(controller.errorMessage == nil)
        }
        let container = try FamiliarModelContainer.make(at: url, configurationName: "DraftTest")
        let controller = FamiliarChatController(dependencies: .init())
        try controller.restoreDraft(id: id, in: container.mainContext)
        #expect(controller.draft == "A🙂中B")
        #expect(controller.selectedSkillID == skill)
        #expect(try container.mainContext.fetch(FetchDescriptor<FamiliarConversation>()).isEmpty)
        let selection = try #require(controller.draftSelection)
        if case .selection(let range) = selection.indices {
            #expect(range.lowerBound.utf16Offset(in: controller.draft) == 1)
            #expect(range.upperBound.utf16Offset(in: controller.draft) == 3)
        } else { Issue.record("Expected a single restored selection") }
    }

    @Test("Cleanup retains every saved draft and deleting a session prevents a late checkpoint")
    @MainActor func retentionAndDeletion() async throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let coordinator = FamiliarChatSessionCoordinator(dependencies: .init())
        let first = coordinator.newDraft(projectID: nil, in: context)
        let second = coordinator.newDraft(projectID: nil, in: context)
        for id in [first, second] {
            let session = coordinator.session(id: id, in: context)
            session.draft = id.uuidString
            await session.checkpointDraft(in: context)
            let record = try #require(try FamiliarChatListStore.draft(id, in: context))
            record.attachmentsData = try JSONEncoder().encode([FamiliarAttachmentDraft(id: UUID(), kind: .document,
                filename: "test.txt", mimeType: "text/plain", relativePath: "Drafts/" + id.uuidString + "/test.txt",
                extractedText: "text", byteSize: 4, extractionEngine: "text", extractionVersion: "1", detectedFormat: "txt", usedOCR: false)])
        }
        try context.save()
        #expect(try FamiliarChatListStore.retainedDraftPaths(in: context).count == 2)
        let session = coordinator.session(id: first, in: context)
        let record = try #require(try FamiliarChatListStore.draft(first, in: context))
        context.delete(record); try context.save()
        coordinator.invalidate([first])
        await session.checkpointDraft(in: context)
        #expect(try FamiliarChatListStore.draft(first, in: context) == nil)
        #expect(try FamiliarChatListStore.retainedDraftPaths(in: context) == ["Drafts/" + second.uuidString + "/test.txt"])
    }

    @Test("Foreground execution is exclusive and can only be released by its owner")
    @MainActor func executionLease() {
        let lease = FamiliarForegroundExecution(), first = UUID(), second = UUID()
        #expect(lease.claim(first))
        #expect(!lease.claim(second))
        lease.release(second)
        #expect(lease.ownerID == first)
        lease.release(first)
        #expect(lease.claim(second))
    }
}

private enum BeforeChatNavigation: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        FamiliarReleaseSchema.models.filter { $0 != FamiliarComposerDraftRecord.self && $0 != FamiliarConversationListStateRecord.self }
    }
}
