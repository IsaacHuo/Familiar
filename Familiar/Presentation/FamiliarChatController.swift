import Combine
import Foundation
import SwiftData

@MainActor
final class FamiliarChatController: ObservableObject {
    @Published var selectedConversationID: UUID?
    @Published private(set) var messages: [FamiliarMessageSnapshot] = []
    @Published var draft = ""
    @Published private(set) var streamingText = ""
    @Published private(set) var streamingMessageID: UUID?
    @Published private(set) var agentStatus: FamiliarAgentStatus?
    @Published private(set) var toolActivities: [FamiliarToolActivity] = []
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    @Published private(set) var settings = FamiliarSettingsStore.load()

    private let toolRegistry: FamiliarToolRegistry
    private var runningTask: Task<Void, Never>?

    init() {
        do {
            toolRegistry = try FamiliarToolRegistry(tools: [
                AnyFamiliarTool(FamiliarCurrentDateTimeTool()),
                AnyFamiliarTool(FamiliarAppInformationTool())
            ])
        } catch {
            preconditionFailure("无法创建工具注册表：\(error.localizedDescription)")
        }
    }

    deinit {
        runningTask?.cancel()
    }

    func select(_ id: UUID?, in context: ModelContext) {
        guard !isSending else { return }
        selectedConversationID = id
        resetTransientRunState()
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
            resetTransientRunState()
            return conversation
        } catch {
            context.rollback()
            errorMessage = String(format: String(localized: "error.create_conversation"), error.localizedDescription)
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
                resetTransientRunState()
            }
        } catch {
            context.rollback()
            errorMessage = String(format: String(localized: "error.delete_conversation"), error.localizedDescription)
        }
    }

    func rename(_ conversation: FamiliarConversation, to proposedTitle: String, in context: ModelContext) {
        guard !isSending else { return }
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        conversation.title = String(title.prefix(80))
        conversation.updatedAt = Date()
        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = String(
                format: String(localized: "error.rename_conversation"),
                error.localizedDescription
            )
        }
    }

    func startSending(in context: ModelContext) {
        guard !isSending else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let requestSettings = settings
        guard let apiKey = FamiliarKeychainStore.load(for: requestSettings.provider) else {
            errorMessage = String(format: String(localized: "error.api_key_missing"), requestSettings.provider.title)
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
        if conversation.messages.count == 1 {
            conversation.title = String(prompt.prefix(28))
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = String(format: String(localized: "error.save_prompt"), error.localizedDescription)
            return
        }

        draft = ""
        reloadMessages(in: context)
        let requestMessages = messages
        let responseID = UUID()
        isSending = true
        resetTransientRunState()
        streamingMessageID = responseID

        runningTask = Task { [weak self] in
            guard let self else { return }
            await self.performSend(
                requestMessages: requestMessages,
                conversationID: conversation.id,
                apiKey: apiKey,
                settings: requestSettings,
                responseID: responseID,
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
            errorMessage = String(format: String(localized: "error.save_settings"), error.localizedDescription)
        }
    }

    func selectModel(provider: FamiliarProvider, modelID: String) {
        var value = settings
        value.provider = provider
        value.modelID = modelID
        updateSettings(value)
    }

    func prepareToEdit(_ message: FamiliarMessageSnapshot, in context: ModelContext) {
        guard !isSending,
              message.role == .user,
              let conversation = selectedConversation(in: context)
        else { return }

        let removed = conversation.messages.filter { $0.sequence >= message.sequence }
        removed.forEach(context.delete)
        conversation.updatedAt = Date()
        do {
            try context.save()
            draft = message.content
            reloadMessages(in: context)
        } catch {
            context.rollback()
            errorMessage = String(
                format: String(localized: "error.edit_message"),
                error.localizedDescription
            )
        }
    }

    func retry(_ message: FamiliarMessageSnapshot, in context: ModelContext) {
        guard !isSending,
              message.role == .assistant,
              let conversation = selectedConversation(in: context)
        else { return }

        let sortedMessages = conversation.messages.sorted {
            $0.sequence == $1.sequence ? $0.createdAt < $1.createdAt : $0.sequence < $1.sequence
        }
        guard let assistantIndex = sortedMessages.firstIndex(where: { $0.id == message.id }),
              let userMessage = sortedMessages[..<assistantIndex].last(where: { $0.role == .user })
        else { return }

        let prompt = userMessage.content
        let removed = conversation.messages.filter { $0.sequence >= userMessage.sequence }
        removed.forEach(context.delete)
        conversation.updatedAt = Date()
        do {
            try context.save()
            draft = prompt
            reloadMessages(in: context)
            startSending(in: context)
        } catch {
            context.rollback()
            errorMessage = String(
                format: String(localized: "error.retry_message"),
                error.localizedDescription
            )
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
        settings: FamiliarSettings,
        responseID: UUID,
        context: ModelContext
    ) async {
        defer {
            isSending = false
            runningTask = nil
        }

        do {
            let agentLoop = FamiliarAgentLoop(
                provider: FamiliarProviderFactory.makeProvider(for: settings.provider),
                registry: toolRegistry
            )
            var completedAnswer: String?
            for try await event in agentLoop.stream(
                messages: requestMessages,
                settings: settings,
                apiKey: apiKey
            ) {
                try Task.checkCancellation()
                switch event {
                case .status(let status):
                    agentStatus = status
                case .textDelta(let delta):
                    streamingText += delta
                case .toolActivity(let activity):
                    updateToolActivity(activity)
                case .completed(let answer):
                    completedAnswer = answer
                }
            }
            try Task.checkCancellation()

            let answer = (completedAnswer ?? streamingText).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { throw FamiliarAgentError.emptyResponse }
            guard let conversation = fetchConversation(id: conversationID, in: context) else {
                throw CocoaError(.fileNoSuchFile)
            }

            let nextSequence = (conversation.messages.map(\.sequence).max() ?? -1) + 1
            let assistantMessage = FamiliarMessage(
                id: responseID,
                role: .assistant,
                content: answer,
                sequence: nextSequence,
                conversation: conversation
            )
            context.insert(assistantMessage)
            conversation.updatedAt = Date()
            try context.save()
            reloadMessages(in: context)
            resetTransientRunState()
        } catch is CancellationError {
            resetTransientRunState()
        } catch {
            context.rollback()
            resetTransientRunState()
            errorMessage = error.localizedDescription
            reloadMessages(in: context)
        }
    }

    private func updateToolActivity(_ activity: FamiliarToolActivity) {
        if let index = toolActivities.firstIndex(where: { $0.id == activity.id }) {
            toolActivities[index] = activity
        } else {
            toolActivities.append(activity)
        }
    }

    private func resetTransientRunState() {
        streamingText = ""
        streamingMessageID = nil
        agentStatus = nil
        toolActivities = []
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
