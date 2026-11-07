import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Background history ownership")
struct FamiliarAsyncHistoryTests {
    @Test("A superseded conversation cannot publish its page into the new selection")
    @MainActor func selectionAndFailureKeepTheValidPage() async throws {
        let fixture = try await FamiliarPerformanceHistoryFixture(count: 300)
        let context = fixture.container.mainContext
        let other = FamiliarConversation(title: "Other")
        context.insert(other)
        let message = FamiliarMessage(role: .user, content: "Other scope", sequence: 0, conversation: other)
        context.insert(message); try context.save()
        let controller = FamiliarChatController(dependencies: .init())
        controller.select(fixture.conversation.id, in: context)
        await Task.yield()
        controller.select(other.id, in: context)
        #expect(await controller.waitForHistory())
        #expect(controller.historyIndex?.conversationID == other.id)
        #expect(controller.messages.map(\.id) == [message.id])
        #expect(!(await controller.loadHistory(anchor: "message:missing", in: context)))
        #expect(controller.messages.map(\.id) == [message.id])
        #expect(controller.loadedHistoryAnchorID == nil)
    }

    @Test("Read contexts observe new checkpoints while business input stays complete")
    @MainActor func freshReadsAndCompleteBusinessHistory() async throws {
        let fixture = try await FamiliarPerformanceHistoryFixture(count: 100)
        let container = fixture.container, id = fixture.conversation.id
        let reader = await Task.detached { FamiliarChatHistoryReader(modelContainer: container) }.value
        let first = try await reader.load(conversationID: id, cachedIndex: nil, anchor: nil, messageID: nil, activeRunID: nil)
        #expect(first.page.messages.count == 80)
        let context = container.mainContext
        let messages = try context.fetch(FetchDescriptor<FamiliarMessage>())
        let last = try #require(messages.max { $0.sequence < $1.sequence })
        last.content = "A new checkpoint"; try context.save()
        let next = try await reader.load(conversationID: id, cachedIndex: first.index, anchor: nil, messageID: nil, activeRunID: nil)
        #expect(next.page.messages.last?.content == "A new checkpoint")
        let all = try await reader.messages(conversationID: id, beforeSequence: nil)
        #expect(all.count == 100)
        #expect(all.first?.sequence == 0 && all.last?.sequence == 99)
    }
    @Test("Cached search counts cannot offer empty pages after concurrent deletions")
    @MainActor func deletedSearchResultsEndPagination() async throws {
        let container = try FamiliarTestStore.make(), context = container.mainContext
        let chat = FamiliarConversation(title: "Query fixture"); context.insert(chat)
        var records: [FamiliarMessage] = []
        for index in 0..<120 {
            let message = FamiliarMessage(role: .user, content: "match \(index)", sequence: index, conversation: chat)
            context.insert(message); records.append(message)
        }
        try context.save()
        let store = await Task.detached { FamiliarLocalSearchStore(modelContainer: container) }.value
        let request = FamiliarLocalSearchRequest(query: "match", conversationIDs: [chat.id], includeTitles: false)
        let first = try await store.search(request, offset: 0)
        #expect(first.hasMore && first.messages.count == 50)
        for record in records { context.delete(record) }
        try context.save()
        let next = try await store.search(request, offset: 50)
        #expect(next.messages.isEmpty && !next.hasMore)
        let refreshed = try await store.search(request, offset: 0)
        #expect(refreshed.messageCount == 0 && !refreshed.hasMore)
    }

    @Test("A retired presenter cannot replace the active reader's window")
    @MainActor func retiredPresenterCannotPublishPage() async throws {
        let fixture = try await FamiliarPerformanceHistoryFixture(count: 100)
        let controller = FamiliarChatController(dependencies: .init())
        controller.select(fixture.conversation.id, in: fixture.container.mainContext)
        #expect(await controller.waitForHistory())
        let old = UUID(), current = UUID()
        controller.scrollSession.beginPresentation(old)
        controller.scrollSession.endPresentation(old)
        controller.scrollSession.beginPresentation(current)
        let before = controller.messages.map(\.id)
        let anchor = try #require(controller.historyIndex?.entries.first?.id)
        #expect(!(await controller.loadHistory(anchor: anchor, in: fixture.container.mainContext,
            updateBookmark: false, presenterID: old)))
        #expect(controller.messages.map(\.id) == before)
        #expect(controller.loadedHistoryAnchorID == nil)
        #expect(controller.scrollSession.acceptsPresenter(current))
    }

    @Test("Button tracking does not cancel an explicit page request")
    @MainActor func trackingCanLoadPage() async throws {
        let fixture = try await FamiliarPerformanceHistoryFixture(count: 100)
        let controller = FamiliarChatController(dependencies: .init())
        controller.select(fixture.conversation.id, in: fixture.container.mainContext)
        #expect(await controller.waitForHistory())
        let presenter = UUID()
        controller.scrollSession.beginPresentation(presenter)
        controller.scrollSession.userBegan()
        let anchor = try #require(controller.historyIndex?.entries.first?.id)
        #expect(await controller.loadHistory(anchor: anchor, in: fixture.container.mainContext,
            updateBookmark: false, presenterID: presenter))
        #expect(controller.loadedHistoryAnchorID == anchor)
        #expect(controller.scrollSession.historyAnchorID == anchor)
        controller.scrollSession.userEnded()
    }

}
