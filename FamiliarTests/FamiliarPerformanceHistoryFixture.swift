import Foundation
import SwiftData
@testable import Familiar

/// The container must outlive the hosted views. No user store or network is used.
@MainActor final class FamiliarPerformanceHistoryFixture {
    let container: ModelContainer
    let conversation: FamiliarConversation
    let index: FamiliarConversationHistoryIndex
    let page: FamiliarConversationHistoryPage

    init(count: Int) async throws {
        container = try FamiliarTestStore.make(name: "Performance-" + UUID().uuidString)
        let context = container.mainContext
        conversation = FamiliarConversation(title: "Performance fixture")
        context.insert(conversation)
        for index in 0..<count {
            context.insert(FamiliarMessage(role: .assistant,
                content: "# Reply \(index)\n\nA paragraph in the conversation.\n\n~~~swift\nlet value = \(index)\n~~~",
                createdAt: Date(timeIntervalSince1970: Double(index)), sequence: index, conversation: conversation))
        }
        try context.save()
        let result = try await FamiliarChatHistoryReader.read(container: container, conversationID: conversation.id)
        index = result.index
        page = result.page
    }
}
