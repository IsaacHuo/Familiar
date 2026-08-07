import Combine
import Foundation
import SwiftData

@MainActor
final class FamiliarChatController: ObservableObject {
    @Published var selectedConversationID: UUID?
    @Published private(set) var messages: [FamiliarMessageSnapshot] = []
    @Published var draft = ""
    @Published private(set) var streamingText = ""
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    @Published private(set) var settings = FamiliarSettingsStore.load()

    private let client = DeepSeekClient()
    private var runningTask: Task<Void, Never>?

    deinit {
        runningTask?.cancel()
    }

    func select(_ id: UUID?, in context: ModelContext) {
        guard !isSending else { return }
        selectedConversationID = id
        reloadMessages(in: context)
    }

    @discardableResult
    func createConversation(in context: ModelContext) -> FamiliarConversation? {
        let conversation = FamiliarConversation()
        context.insert(conversation)
        do {
            try context.save()
            selectedConversationID = conversation.id
            messages = []
            return conversation
        } catch {
            context.rollback()
            errorMessage = "新建对话失败：\(error.localizedDescription)"
            return nil
        }
    }

    func delete(_ conversations: [FamiliarConversation], in context: ModelContext) {
        guard !isSending else { return }
        let deletedIDs = Set(conversations.map(\.id))
        conversations.forEach(context.delete)
        do {
            try context.save()
            if let selectedConversationID, deletedIDs.contains(selectedConversationID) {
                self.selectedConversationID = nil
                messages = []
            }
        } catch {
            context.rollback()
            errorMessage = "删除对话失败：\(error.localizedDescription)"
        }
    }

    func startSending(in context: ModelContext) {
        guard !isSending else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard let apiKey = FamiliarKeychainStore.load() else {
            errorMessage = DeepSeekClientError.missingAPIKey.localizedDescription
            return
        }

        let conversation: FamiliarConversation
        if let existing = selectedConversation(in: context) {
            conversation = existing
        } else if let created = createConversation(in: context) {
            conversation = created
        } else {
            return
        }

        let nextSequence = (conversation.messages.map(\.sequence).max() ?? -1) + 1
        let userMessage = FamiliarMessage(
            role: .user,
            content: prompt,
            sequence: nextSequence,
            conversation: conversation
        )
        context.insert(userMessage)
        conversation.updatedAt = Date()
        if conversation.title == "新对话" {
            conversation.title = String(prompt.prefix(28))
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "保存问题失败：\(error.localizedDescription)"
            return
        }

        draft = ""
        reloadMessages(in: context)
        let requestMessages = messages
        isSending = true
        streamingText = ""

        runningTask = Task { [weak self] in
            guard let self else { return }
            await self.performSend(
                requestMessages: requestMessages,
                conversationID: conversation.id,
                apiKey: apiKey,
                context: context
            )
        }
    }

    func cancelSending() {
        runningTask?.cancel()
    }

    func updateSettings(_ value: FamiliarSettings) {
        do {
            try FamiliarSettingsStore.save(value)
            settings = value
        } catch {
            errorMessage = "保存设置失败：\(error.localizedDescription)"
        }
    }

    func reloadMessages(in context: ModelContext) {
        guard let conversation = selectedConversation(in: context) else {
            messages = []
            return
        }
        messages = conversation.messages
            .sorted { lhs, rhs in
                lhs.sequence == rhs.sequence ? lhs.createdAt < rhs.createdAt : lhs.sequence < rhs.sequence
            }
            .map {
                FamiliarMessageSnapshot(
                    id: $0.id,
                    role: $0.role,
                    content: $0.content,
                    createdAt: $0.createdAt,
                    sequence: $0.sequence
                )
            }
    }

    private func performSend(
        requestMessages: [FamiliarMessageSnapshot],
        conversationID: UUID,
        apiKey: String,
        context: ModelContext
    ) async {
        defer {
            isSending = false
            runningTask = nil
        }

        do {
            for try await delta in client.stream(
                messages: requestMessages,
                settings: settings,
                apiKey: apiKey
            ) {
                try Task.checkCancellation()
                streamingText += delta
            }
            try Task.checkCancellation()

            let answer = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { throw DeepSeekClientError.emptyResponse }
            guard let conversation = fetchConversation(id: conversationID, in: context) else {
                throw CocoaError(.fileNoSuchFile)
            }

            let nextSequence = (conversation.messages.map(\.sequence).max() ?? -1) + 1
            let assistantMessage = FamiliarMessage(
                role: .assistant,
                content: answer,
                sequence: nextSequence,
                conversation: conversation
            )
            context.insert(assistantMessage)
            conversation.updatedAt = Date()
            try context.save()
            streamingText = ""
            reloadMessages(in: context)
        } catch is CancellationError {
            streamingText = ""
        } catch {
            context.rollback()
            streamingText = ""
            errorMessage = error.localizedDescription
            reloadMessages(in: context)
        }
    }

    private func selectedConversation(in context: ModelContext) -> FamiliarConversation? {
        guard let selectedConversationID else { return nil }
        return fetchConversation(id: selectedConversationID, in: context)
    }

    private func fetchConversation(id: UUID, in context: ModelContext) -> FamiliarConversation? {
        var descriptor = FetchDescriptor<FamiliarConversation>(
            predicate: #Predicate { conversation in conversation.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
