import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Familiar

@Suite("Chat navigation state", .serialized)
struct FamiliarChatNavigationTests {
    @Test("A branch from an old page copies the complete conversation")
    @MainActor func branchUsesCompleteHistory() throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let original = FamiliarConversation(title: "Original"); context.insert(original)
        for index in 0..<205 {
            context.insert(FamiliarMessage(role: .user, content: "Message \(index)",
                createdAt: Date(timeIntervalSince1970: Double(index)), sequence: index, conversation: original))
        }
        try context.save()
        let controller = FamiliarChatController(dependencies: .init()); controller.select(original.id, in: context)
        #expect(controller.messages.count == 80)
        controller.forkCurrentConversation(in: context)
        #expect(controller.errorMessage == nil)
        let forkID = try #require(controller.selectedConversationID)
        #expect(forkID != original.id)
        let all = try FamiliarChatHistoryStore.messages(conversationID: forkID, in: context)
        #expect(all.count == 205)
        #expect(all.first?.content == "Message 0")
        #expect(all.last?.content == "Message 204")
        #expect(controller.messages.count == 80)
    }

    @Test("Spotlight checks stored existence while fetching only conversation headers")
    @MainActor func spotlightHeaderProjection() throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let empty = FamiliarConversation(title: "Empty"), withMessages = FamiliarConversation(title: "Messages"), withRun = FamiliarConversation(title: "Run")
        context.insert(empty); context.insert(withMessages); context.insert(withRun)
        context.insert(FamiliarMessage(role: .user, content: "Body", sequence: 0, conversation: withMessages))
        context.insert(FamiliarAgentRun(runtimeID: "only-run", status: .failed, conversation: withRun))
        try context.save()
        let summaries = try FamiliarSpotlightIndexer.storedConversations(in: context)
        #expect(Set(summaries.map(\.id)) == [withMessages.id, withRun.id])
    }

    @Test("Stored history reads only a rich page; business snapshots remain complete")
    @MainActor func durableHistoryPagesAndCompleteInput() throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let chat = FamiliarConversation(title: "Paged"), other = FamiliarConversation(title: "Other")
        context.insert(chat); context.insert(other)
        var records: [FamiliarMessage] = []
        for index in 0..<246 {
            let message = FamiliarMessage(role: index.isMultiple(of: 2) ? .user : .assistant,
                content: "Body \(index)", createdAt: Date(timeIntervalSince1970: Double(index / 3)),
                sequence: index, conversation: chat)
            context.insert(message); records.append(message)
        }
        let attachment = FamiliarAttachment(kind: .document, filename: "early.txt", mimeType: "text/plain",
            relativePath: "early.txt", extractedText: "Early context evidence", byteSize: 22,
            extractionEngine: "test", extractionVersion: "1", detectedFormat: "txt", usedOCR: false, message: records[0])
        context.insert(attachment)
        let run = FamiliarAgentRun(runtimeID: "paged-run", status: .completed,
            startedAt: records[1].createdAt, conversation: chat)
        run.responseMessageID = records[1].id; context.insert(run)
        let block = FamiliarResponseBlockRecord(runtimeID: run.runtimeID, assistantTurnID: "turn:0",
            messageID: records[1].id, kind: .markdown, order: 0, state: .completed,
            content: "Canonical answer", startedAt: records[1].createdAt, endedAt: records[1].createdAt, contentHash: "hash")
        context.insert(block); records[1].responseBlockID = block.id
        context.insert(FamiliarSourceRecord(sourceID: "source-early", kind: .fetchedPage, title: "Early source",
            urlString: "https://example.com/early", siteName: nil, sequence: 0, retrievedAt: records[1].createdAt, message: records[1]))
        context.insert(FamiliarMessage(role: .user, content: "Other scope", sequence: 0, conversation: other))
        try context.save()
        let controller = FamiliarChatController(dependencies: .init())
        controller.select(chat.id, in: context)
        let metadata = try #require(controller.historyIndex)
        #expect(metadata.messageCount == 246)
        #expect(metadata.entries.count == 246)
        #expect(controller.messages.count == 80)
        #expect(!controller.messages.contains { $0.id == records[0].id })
        #expect(controller.agentRuns.isEmpty)
        let early = try #require(metadata.messageEntries[records[1].id])
        #expect(early == "run:paged-run")
        #expect(controller.loadHistory(anchor: early, in: context))
        #expect(controller.messages.count == 80)
        #expect(controller.messages.first?.id == records[0].id)
        #expect(controller.messages.first?.attachments.first?.extractedText == "Early context evidence")
        #expect(controller.messages.first(where: { $0.id == records[1].id })?.finalAnswerText == "Canonical answer")
        #expect(controller.messages.first(where: { $0.id == records[1].id })?.sources.first?.id == "source-early")
        #expect(controller.agentRuns.map(\.id) == ["paged-run"])
        let visible = controller.messages.map(\.id)
        let complete = try FamiliarChatHistoryStore.messages(conversationID: chat.id, in: context)
        #expect(complete.count == 246)
        #expect(complete.map(\.sequence) == Array(0..<246))
        #expect(complete.first?.attachments.first?.id == attachment.id)
        #expect(controller.messages.map(\.id) == visible)
        let prefix = try FamiliarChatHistoryStore.messages(conversationID: chat.id, beforeSequence: 120, in: context)
        #expect(prefix.map(\.sequence) == Array(0..<120))
        let latest = try FamiliarChatHistoryStore.latestAssistantMessage(conversationID: chat.id, in: context)
        #expect(latest?.id == records[245].id)
        #expect(controller.historyIndex?.latestReplyID == records[245].id)
    }

    @Test("Marker and failed-run pages preserve stable identities and reject other conversations")
    @MainActor func historyMarkersAndScope() throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let chat = FamiliarConversation(title: "Runs"), other = FamiliarConversation(title: "Private")
        context.insert(chat); context.insert(other)
        for index in 0..<170 {
            context.insert(FamiliarAgentRun(runtimeID: "failed-\(index)", status: .failed,
                startedAt: Date(timeIntervalSince1970: Double(index)), conversation: chat))
        }
        let marker = FamiliarModelSwitchRecord(previousProviderID: "before", previousModelID: "before",
            sequence: 0, createdAt: Date(timeIntervalSince1970: 100), conversation: chat)
        context.insert(marker)
        let hidden = FamiliarAgentRun(runtimeID: "private-run", status: .failed, conversation: other)
        context.insert(hidden)
        let privateMessage = FamiliarMessage(role: .assistant, content: "Hidden", sequence: 0, conversation: other)
        context.insert(privateMessage); try context.save()
        let index = try FamiliarChatHistoryStore.index(conversationID: chat.id, in: context)
        #expect(index.entries.count == 171 && index.messageCount == 0)
        let range = index.range(anchor: nil)
        let page = try FamiliarChatHistoryStore.page(conversation: chat, references: Array(index.entries[range]), activeRunID: nil, in: context)
        #expect(page.runs.count + page.modelSwitches.count == 80)
        #expect(page.modelSwitches.first?.id == marker.id)
        #expect(!page.runs.contains { $0.id == hidden.runtimeID })
        let mixed = [FamiliarHistoryReference(kind: .orphanRun(hidden.runtimeID), date: hidden.startedAt),
                     .init(kind: .message(privateMessage.id, runID: nil), date: privateMessage.createdAt)]
        let scoped = try FamiliarChatHistoryStore.page(conversation: chat, references: mixed, activeRunID: nil, in: context)
        #expect(scoped.messages.isEmpty && scoped.runs.isEmpty)
    }

    @Test("A pinned old page survives terminal writes without moving the model's full history")
    @MainActor func historyReloadKeepsPage() throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let chat = FamiliarConversation(title: "Anchor"); context.insert(chat)
        var records: [FamiliarMessage] = []
        for index in 0..<200 {
            let message = FamiliarMessage(role: .user, content: "Old \(index)",
                createdAt: Date(timeIntervalSince1970: Double(index)), sequence: index, conversation: chat)
            context.insert(message); records.append(message)
        }
        try context.save()
        let controller = FamiliarChatController(dependencies: .init()); controller.select(chat.id, in: context)
        let index = try #require(controller.historyIndex)
        let anchor = try #require(index.messageEntries[records[10].id])
        #expect(controller.loadHistory(anchor: anchor, in: context))
        let visible = controller.messages.map(\.id)
        let reply = FamiliarMessage(role: .assistant, content: "New reply", createdAt: Date(timeIntervalSince1970: 201), sequence: 200, conversation: chat)
        context.insert(reply); try context.save()
        controller.reloadMessages(in: context)
        #expect(controller.loadedHistoryAnchorID == anchor)
        #expect(controller.messages.map(\.id) == visible)
        #expect(controller.historyIndex?.latestReplyID == reply.id)
        #expect(controller.durableMessageCount == 201)
        #expect(controller.locateHistoryMessage(reply.id, in: context))
        #expect(controller.messages.contains { $0.id == reply.id })
        #expect(controller.loadHistory(anchor: nil, in: context))
        #expect(controller.messages.last?.id == reply.id)
    }

    @Test("Presentation windows stay bounded, cover old targets, and never alter durable messages")
    func historyWindows() {
        #expect(FamiliarHistoryWindow.range(total: 0, center: nil).isEmpty)
        #expect(FamiliarHistoryWindow.range(total: 5, center: 99) == 0..<5)
        #expect(FamiliarHistoryWindow.range(total: 1_000, center: nil) == 920..<1_000)
        for target in 0..<1_000 {
            let range = FamiliarHistoryWindow.range(total: 1_000, center: target)
            #expect(range.count == 80 && range.contains(target))
        }
    }

    @Test("Run queries batch SQL parameters and exclude other scopes")
    @MainActor func boundedHistoryQueries() throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let ids = (0..<405).map { "runtime-\($0)" }
        for id in ids { context.insert(FamiliarConversation(title: id)) }
        context.insert(FamiliarConversation(title: "Other scope")); try context.save()
        var sizes: [Int] = []
        let values = try FamiliarRunHistoryQuery.fetch(ids + [ids[0]], in: context) { batch in
            sizes.append(batch.count)
            return FetchDescriptor<FamiliarConversation>(predicate: #Predicate { batch.contains($0.title) })
        }
        #expect(values.count == 405)
        #expect(sizes == [200, 200, 5])
        let empty = try FamiliarRunHistoryQuery.fetch([], in: context) { _ in FetchDescriptor<FamiliarConversation>() }
        #expect(empty.isEmpty)
    }

    @Test("Idle sessions save drafts before eviction and retain real work owners")
    @MainActor func idleSessionEviction() async throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let coordinator = FamiliarChatSessionCoordinator(dependencies: .init())
        let ids = (0..<5).map { _ in coordinator.newDraft(projectID: nil, in: context) }
        for id in ids { coordinator.sessions[id]?.draft = "Draft \(id)" }
        let imported = try #require(coordinator.sessions[ids[1]])
        imported.pendingAttachmentImports = 1
        let run = try #require(coordinator.sessions[ids[2]])
        #expect(coordinator.dependencies.foregroundExecution.claim(run.executionID))
        let original = try #require(coordinator.sessions[ids[0]])
        original.scrollSession.prepareForNavigation()
        original.scrollSession.offset = 120
        original.scrollSession.historyAnchorID = "message:old"
        await coordinator.trim(retaining: [ids[4]], idleLimit: 0, in: context)
        #expect(coordinator.sessions[ids[0]] == nil)
        #expect(coordinator.sessions[ids[1]] === imported)
        #expect(coordinator.sessions[ids[2]] === run)
        #expect(coordinator.sessions[ids[4]] != nil)
        #expect(try FamiliarChatListStore.draft(ids[0], in: context)?.text == "Draft \(ids[0])")
        let loaded = try coordinator.existingSession(id: ids[0], in: context)
        let restored = try #require(loaded)
        #expect(restored.draft == "Draft \(ids[0])")
        #expect(restored.scrollSession.historyAnchorID == "message:old")
        #expect(restored.scrollSession.offset == 120)
        coordinator.dependencies.foregroundExecution.release(run.executionID)
    }


    @Test("Settings search covers every route exactly once with bilingual aliases and real paths")
    @MainActor func settingsSearchCatalog() {
        let entries = FamiliarSettingsCatalog.entries
        #expect(Set(entries.map(\.route)) == Set(FamiliarSettingsRoute.allCases))
        #expect(entries.count == Set(entries.map(\.id)).count)
        #expect(entries.contains { $0.route == .modelService && $0.matches("密钥") })
        #expect(entries.contains { $0.route == .profile && $0.matches("avatar") })
        #expect(entries.contains { $0.route == .storage && $0.matches("workspace") })
        #expect(entries.allSatisfy { !$0.matches("   ") && !$0.path.contains("settings.hub.") })
    }

    @Test("Provider verification identity changes with model, credential and configuration")
    @MainActor func providerVerificationScope() throws {
        let provider = FamiliarProviderCatalog.deepSeek
        let first = try FamiliarProviderVerificationIdentity(descriptor: provider, modelID: "first-model", credential: "test-value-one")
        #expect(first == (try FamiliarProviderVerificationIdentity(descriptor: provider, modelID: "first-model", credential: "test-value-one")))
        #expect(first != (try FamiliarProviderVerificationIdentity(descriptor: provider, modelID: "second-model", credential: "test-value-one")))
        #expect(first != (try FamiliarProviderVerificationIdentity(descriptor: provider, modelID: "first-model", credential: "test-value-two")))
        let changed = provider.instance(id: provider.id, url: URL(string: "https://example.invalid")!)
        #expect(first != (try FamiliarProviderVerificationIdentity(descriptor: changed, modelID: "first-model", credential: "test-value-one")))
    }

    @Test("Storage scan counts physical files once and never follows an outside symlink")
    func localStorageMeasurement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Storage-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for directory in ["Files", "Attachments", "Workspaces", "ShellRuntime"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        let file = root.appendingPathComponent("Files/original.txt")
        try Data(repeating: 1, count: 10).write(to: file)
        try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("Attachments/reference.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Files/outside-link"), withDestinationURL: FileManager.default.temporaryDirectory)
        try Data(repeating: 2, count: 5).write(to: root.appendingPathComponent("Workspaces/work.txt"))
        try Data(repeating: 3, count: 12).write(to: root.appendingPathComponent("ShellRuntime/runtime.bin"))
        let usage = try FamiliarStorageInventory.scan(root: root)
        #expect(usage.total == 27)
        #expect(usage.bytes["settings.storage.workspaces"] == 5)
        #expect(usage.bytes["settings.storage.runtime"] == 12)
    }

    @Test("Local search is paged, scoped, archive-aware and empty queries match nothing")
    @MainActor func localSearchScopeAndPaging() async throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let first = FamiliarConversation(title: "Needle project")
        let second = FamiliarConversation(title: "Other")
        context.insert(first); context.insert(second)
        let archive = try FamiliarChatListStore.state(for: first, in: context)
        archive.isArchived = true
        for index in 0..<63 {
            context.insert(FamiliarMessage(role: .user, content: "Needle \(index)", createdAt: Date(timeIntervalSince1970: Double(index + 100)), sequence: index, conversation: first))
        }
        context.insert(FamiliarMessage(role: .user, content: "Private Needle", sequence: 0, conversation: second))
        try context.save()
        let store = FamiliarLocalSearchStore(modelContainer: container)
        let empty = try await store.search(.init(query: "  ", conversationIDs: nil), offset: 0)
        #expect(empty.messageCount == 0 && empty.messages.isEmpty)
        let noIDs = try await store.search(.init(query: "needle", conversationIDs: []), offset: 0)
        #expect(noIDs.messageCount == 0)
        let scoped = FamiliarLocalSearchRequest(query: "needle", conversationIDs: [first.id])
        let firstPage = try await store.search(scoped, offset: 0)
        let secondPage = try await store.search(scoped, offset: FamiliarLocalSearchPage.size)
        #expect(firstPage.messageCount == 63)
        #expect(firstPage.messages.count == 50 && secondPage.messages.count == 13)
        #expect(Set(firstPage.messages.map(\.id)).isDisjoint(with: Set(secondPage.messages.map(\.id))))
        #expect(firstPage.messages.allSatisfy { $0.conversationID == first.id && $0.isArchived })
        #expect(firstPage.conversations.map(\.id) == [first.id])
        let all = try await store.search(.init(query: "needle", conversationIDs: nil), offset: 0)
        #expect(all.messageCount == 64)
        #expect(try context.fetch(FetchDescriptor<FamiliarMessage>()).count == 64)
        #expect(archive.isUnread == false)
    }

    @Test("Search excerpts retain a late Unicode hit rather than the start of a long message")
    func localSearchExcerpt() {
        let text = String(repeating: "前文🙂", count: 400) + "CAFÉ 命中" + String(repeating: "后文", count: 400)
        let excerpt = FamiliarSearchText.excerpt(text, query: "cafe")
        #expect(excerpt.contains("CAFÉ"))
        #expect(excerpt.hasPrefix("…") && excerpt.hasSuffix("…"))
        #expect(excerpt.count < 250)
    }

    @Test("Attachment-only drafts expose the managed file name in list summaries")
    @MainActor func attachmentOnlyDraftSummary() throws {
        let draft = FamiliarComposerDraftRecord(id: UUID(), conversationID: nil, projectID: nil)
        let attachment = FamiliarAttachmentDraft(id: UUID(), kind: .document, filename: "report.pdf", mimeType: "application/pdf",
            relativePath: "Drafts/report.pdf", extractedText: "", byteSize: 42, extractionEngine: "test", extractionVersion: "1", detectedFormat: "pdf", usedOCR: false)
        draft.attachmentsData = try JSONEncoder().encode([attachment])
        #expect(FamiliarChatListStore.draftSummary(draft).contains("report.pdf"))
        draft.text = "Questions"
        let summary = FamiliarChatListStore.draftSummary(draft)
        #expect(summary.contains("report.pdf") && summary.contains("Questions"))
    }

    @Test("The owner-authorized cutover removes only pre-summary history and is idempotent")
    @MainActor func summaryTitleCutover() throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let project = FamiliarProject(name: "Preserve project")
        context.insert(project)
        let legacy = FamiliarConversation(title: "Old prefix", project: project)
        legacy.titleOrigin = nil
        let current = FamiliarConversation()
        let manual = FamiliarConversation(title: "My own title")
        for chat in [legacy, current, manual] { context.insert(chat) }
        try context.save()
        let coordinator = FamiliarChatSessionCoordinator(dependencies: .init())
        #expect(coordinator.removePreSummaryHistory(in: context) == nil)
        #expect(coordinator.removePreSummaryHistory(in: context) == nil)
        #expect(Set(try context.fetch(FetchDescriptor<FamiliarConversation>()).map(\.id)) == [current.id, manual.id])
        #expect(try context.fetch(FetchDescriptor<FamiliarProject>()).map(\.id) == [project.id])
        #expect(current.titleOrigin == "pending")
        #expect(manual.titleOrigin == "manual")
    }

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
            controller.draftSelection = FamiliarComposerSelection(start: 1, end: 3)
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
        #expect(selection.start == 1)
        #expect(selection.end == 3)
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
    @Test("Composer selection clamps UTF-16 offsets to complete characters")
    func selectionBoundaries() {
        let text = "A🙂中B"
        #expect(FamiliarComposerSelection(start: 2, end: 2).normalized(in: text) == .init(start: 1, end: 1))
        #expect(FamiliarComposerSelection(start: 2, end: 3).normalized(in: text) == .init(start: 1, end: 3))
        #expect(FamiliarComposerSelection(start: 999, end: 999).normalized(in: text) == .caretAtEnd(of: text))
        let family = "A👨‍👩‍👧‍👦B"
        #expect(FamiliarComposerSelection(start: 2, end: 3).normalized(in: family).nsRange == (family as NSString).range(of: "👨‍👩‍👧‍👦"))
    }

    @Test("Opening, saving, reopening and cancelling an edit preserves history and the previous draft")
    @MainActor func editDraftLifecycle() async throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let chat = FamiliarConversation(title: "History")
        context.insert(chat)
        let original = FamiliarMessage(role: .user, content: "Original", sequence: 0, conversation: chat)
        let reply = FamiliarMessage(role: .assistant, content: "Old reply", sequence: 1, conversation: chat)
        context.insert(original); context.insert(reply); try context.save()
        let controller = FamiliarChatController(dependencies: .init())
        controller.select(chat.id, in: context)
        controller.draft = "Unsent draft"
        controller.draftSelection = .init(start: 1, end: 3)
        let skill = UUID()
        controller.selectedSkillID = skill
        let attachment = FamiliarAttachmentDraft(id: UUID(), kind: .document, filename: "keep.txt", mimeType: "text/plain",
            relativePath: "Drafts/" + UUID().uuidString + "/keep.txt", extractedText: "keep", byteSize: 4, extractionEngine: "text", extractionVersion: "1", detectedFormat: "txt", usedOCR: false)
        controller.draftAttachments = [attachment]
        let snapshot = try #require(controller.messages.first { $0.id == original.id })
        #expect(controller.prepareToEdit(snapshot, in: context))
        controller.draft = "Edited text"
        await controller.checkpointDraft(in: context)
        #expect(Set(chat.messages.map(\.id)) == [original.id, reply.id])
        #expect(try FamiliarChatListStore.retainedDraftPaths(in: context).contains(attachment.relativePath))
        let restored = FamiliarChatController(dependencies: .init())
        restored.select(chat.id, in: context)
        try restored.restoreDraft(id: chat.id, in: context)
        #expect(restored.messageEdit?.messageID == original.id)
        #expect(restored.draft == "Edited text")
        restored.cancelMessageEdit(in: context)
        await restored.checkpointDraft(in: context)
        #expect(restored.draft == "Unsent draft")
        #expect(restored.selectedSkillID == skill)
        #expect(restored.draftSelection == .init(start: 1, end: 3))
        #expect(restored.draftAttachments == [attachment])
        #expect(Set(chat.messages.map(\.id)) == [original.id, reply.id])
        #expect(try FamiliarChatListStore.draft(chat.id, in: context)?.editState() == nil)
    }

    @Test("An edited submission keeps original history until the completed reply transaction succeeds")
    @MainActor func editCommitAndRollback() async throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let chat = FamiliarConversation(title: "History")
        context.insert(chat)
        let original = FamiliarMessage(role: .user, content: "Original", sequence: 0, conversation: chat)
        let reply = FamiliarMessage(role: .assistant, content: "Old reply", sequence: 1, conversation: chat)
        context.insert(original); context.insert(reply); try context.save()
        let originalIDs = Set([original.id, reply.id])
        let controller = FamiliarChatController(dependencies: .init())
        controller.select(chat.id, in: context)
        controller.draft = "Prior draft"
        let snapshot = try #require(controller.messages.first { $0.id == original.id })
        #expect(controller.prepareToEdit(snapshot, in: context))
        controller.draft = "Edited"
        let edit = try #require(controller.messageEdit)
        let submitted = FamiliarMessage(role: .user, content: "Edited", sequence: 2, conversation: chat)
        let working = FamiliarComposerDraftSnapshot(text: "Edited", selection: nil, skillID: nil, attachments: [])
        let transaction = try controller.makeMessageEditSubmission(edit, userMessageID: submitted.id, workingDraft: working, in: context)
        context.insert(submitted)
        try controller.stageSubmittedMessageEditDraft(transaction, conversationID: chat.id, in: context)
        try context.save()
        controller.submittedMessageEdit = transaction
        #expect(originalIDs.isSubset(of: Set(chat.messages.map(\.id))))
        _ = try controller.stageSuccessfulMessageEdit(in: context)
        context.rollback()
        #expect(originalIDs.isSubset(of: Set(chat.messages.map(\.id))))
        await controller.restoreUncommittedMessageEdit(in: context)
        #expect(controller.draft == "Edited")
        #expect(controller.messageEdit?.messageID == original.id)

        controller.submittedMessageEdit = transaction
        let retired = try controller.stageSuccessfulMessageEdit(in: context)
        let newReply = FamiliarMessage(role: .assistant, content: "New reply", sequence: 1, conversation: chat)
        context.insert(newReply); try context.save()
        controller.finishSuccessfulMessageEdit(retiredPaths: retired, in: context)
        #expect(Set(chat.messages.map(\.id)) == [submitted.id, newReply.id])
        #expect(submitted.sequence == 0)
        #expect(controller.draft == "Prior draft")
        #expect(controller.messageEdit == nil)
        #expect(try FamiliarChatListStore.draft(chat.id, in: context)?.editState() == nil)
    }
}

private enum BeforeChatNavigation: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        FamiliarReleaseSchema.models.filter { $0 != FamiliarComposerDraftRecord.self && $0 != FamiliarConversationListStateRecord.self }
    }
}
