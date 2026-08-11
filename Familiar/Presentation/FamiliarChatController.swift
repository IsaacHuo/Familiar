import Combine
import Foundation
import SwiftData

@MainActor
final class FamiliarChatController: ObservableObject {
    @Published var selectedConversationID: UUID?
    @Published private(set) var messages: [FamiliarMessageSnapshot] = []
    @Published private(set) var modelSwitches: [FamiliarModelSwitchSnapshot] = []
    @Published private(set) var toolRunRecords: [FamiliarToolRunSnapshot] = []
    @Published private(set) var pendingConfirmations: [FamiliarToolConfirmationRequest] = []
    @Published var draft = ""
    @Published private(set) var streamingText = ""
    @Published private(set) var streamingMessageID: UUID?
    @Published private(set) var agentStatus: FamiliarAgentStatus?
    @Published private(set) var toolActivities: [FamiliarToolActivity] = []
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    @Published private(set) var settings = FamiliarSettingsStore.load()

    private let toolRegistry: FamiliarToolRegistry
    private let eventKitService: FamiliarEventKitService
    private let confirmationCoordinator: FamiliarToolConfirmationCoordinator
    private var runningTask: Task<Void, Never>?

    init() {
        let eventKitService = FamiliarEventKitService()
        self.eventKitService = eventKitService
        confirmationCoordinator = FamiliarToolConfirmationCoordinator()
        do {
            toolRegistry = try FamiliarToolRegistry(tools: [
                AnyFamiliarTool(FamiliarCurrentDateTimeTool()),
                AnyFamiliarTool(FamiliarAppInformationTool()),
                AnyFamiliarTool(FamiliarCalendarEventsTool(service: eventKitService)),
                AnyFamiliarTool(FamiliarCreateCalendarEventTool()),
                AnyFamiliarTool(FamiliarRemindersTool(service: eventKitService)),
                AnyFamiliarTool(FamiliarCreateReminderTool())
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
        guard let conversation = selectedConversation(in: context) else { return }
        var value = settings
        value.providerID = conversation.currentProviderID
        value.modelID = conversation.currentModelID
        settings = value
    }

    @discardableResult
    func createConversation(in context: ModelContext) -> FamiliarConversation? {
        let conversation = FamiliarConversation(
            currentProviderID: settings.providerID,
            currentModelID: settings.modelID
        )
        context.insert(conversation)
        do {
            try context.save()
            selectedConversationID = conversation.id
            messages = []
            modelSwitches = []
            toolRunRecords = []
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
                modelSwitches = []
                toolRunRecords = []
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
            errorMessage = String(format: String(localized: "error.rename_conversation"), error.localizedDescription)
        }
    }

    func startSending(in context: ModelContext) {
        guard !isSending else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let requestSettings = settings
        guard let descriptor = requestSettings.resolvedProvider else {
            errorMessage = String(localized: "error.provider.invalid_custom_configuration")
            return
        }
        guard prompt.count <= requestSettings.selectedModel.capabilities.maximumInputCharacters else {
            errorMessage = String(localized: "error.message.context_too_large")
            return
        }
        guard let apiKey = FamiliarKeychainStore.load(for: requestSettings.providerID) else {
            errorMessage = String(
                format: String(localized: "error.api_key_missing"),
                descriptor.displayName
            )
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
        conversation.currentProviderID = requestSettings.providerID
        conversation.currentModelID = requestSettings.modelID

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
                descriptor: descriptor,
                settings: requestSettings,
                responseID: responseID,
                context: context
            )
        }
    }

    func cancelSending(in context: ModelContext) {
        for request in pendingConfirmations {
            persistToolRecord(
                FamiliarToolRunTerminalEvent(
                    runID: request.runID,
                    toolCallID: request.toolCallID,
                    toolName: request.toolName,
                    summary: request.title,
                    detail: String(localized: "tool.cancelled_by_user"),
                    confirmation: .cancelled,
                    status: .cancelled,
                    startedAt: Date(),
                    finishedAt: Date()
                ),
                conversationID: selectedConversationID,
                context: context
            )
        }
        pendingConfirmations = []
        runningTask?.cancel()
        Task { await confirmationCoordinator.cancelAll() }
    }

    func resolveConfirmation(
        _ request: FamiliarToolConfirmationRequest,
        decision: FamiliarToolConfirmationDecision
    ) {
        Task {
            _ = await confirmationCoordinator.resolve(requestID: request.id, decision: decision)
        }
    }

    func updateSettings(_ value: FamiliarSettings, in context: ModelContext) {
        guard !isSending else { return }
        applySettings(value, recordingSwitchIn: context)
    }

    func selectModel(providerID: String, modelID: String, in context: ModelContext) {
        guard !isSending else { return }
        var value = settings
        value.providerID = providerID
        value.modelID = modelID
        applySettings(value, recordingSwitchIn: context)
    }

    func prepareToEdit(_ message: FamiliarMessageSnapshot, in context: ModelContext) {
        guard !isSending,
              message.role == .user,
              let conversation = selectedConversation(in: context)
        else { return }

        conversation.messages
            .filter { $0.sequence >= message.sequence }
            .forEach(context.delete)
        conversation.modelSwitchRecords
            .filter { $0.sequence >= message.sequence }
            .forEach(context.delete)
        conversation.updatedAt = Date()
        do {
            try context.save()
            draft = message.content
            reloadMessages(in: context)
        } catch {
            context.rollback()
            errorMessage = String(format: String(localized: "error.edit_message"), error.localizedDescription)
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
        conversation.messages
            .filter { $0.sequence >= userMessage.sequence }
            .forEach(context.delete)
        conversation.modelSwitchRecords
            .filter { $0.sequence >= userMessage.sequence }
            .forEach(context.delete)
        if let providerID = message.providerID, let modelID = message.modelID {
            settings.providerID = providerID
            settings.modelID = modelID
            conversation.currentProviderID = providerID
            conversation.currentModelID = modelID
        }
        conversation.updatedAt = Date()
        do {
            try context.save()
            try FamiliarSettingsStore.save(settings)
            draft = prompt
            reloadMessages(in: context)
            startSending(in: context)
        } catch {
            context.rollback()
            errorMessage = String(format: String(localized: "error.retry_message"), error.localizedDescription)
        }
    }

    func reloadMessages(in context: ModelContext) {
        guard let conversation = selectedConversation(in: context) else {
            messages = []
            modelSwitches = []
            toolRunRecords = []
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
                    sequence: $0.sequence,
                    providerID: $0.providerID,
                    modelID: $0.modelID
                )
            }
        modelSwitches = conversation.modelSwitchRecords
            .sorted { lhs, rhs in
                lhs.sequence == rhs.sequence ? lhs.createdAt < rhs.createdAt : lhs.sequence < rhs.sequence
            }
            .map {
                FamiliarModelSwitchSnapshot(
                    id: $0.id,
                    previousProviderID: $0.previousProviderID,
                    previousModelID: $0.previousModelID,
                    currentProviderID: $0.currentProviderID,
                    currentModelID: $0.currentModelID,
                    sequence: $0.sequence,
                    createdAt: $0.createdAt
                )
            }
        toolRunRecords = conversation.toolRunRecords
            .sorted { lhs, rhs in
                lhs.sequence == rhs.sequence ? lhs.finishedAt < rhs.finishedAt : lhs.sequence < rhs.sequence
            }
            .map {
                FamiliarToolRunSnapshot(
                    id: $0.id,
                    runID: $0.runID,
                    toolCallID: $0.toolCallID,
                    toolName: $0.toolName,
                    summary: $0.summary,
                    detail: $0.detail,
                    confirmation: $0.confirmation,
                    status: $0.status,
                    sequence: $0.sequence,
                    startedAt: $0.startedAt,
                    finishedAt: $0.finishedAt
                )
            }
    }

    private func applySettings(_ value: FamiliarSettings, recordingSwitchIn context: ModelContext) {
        guard value.resolvedProvider != nil else {
            errorMessage = String(localized: "error.provider.invalid_custom_configuration")
            return
        }
        let oldValue = settings
        do {
            try FamiliarSettingsStore.save(value)
            settings = value
            guard let conversation = selectedConversation(in: context) else { return }
            if oldValue.providerID != value.providerID || oldValue.modelID != value.modelID {
                let nextSequence = (conversation.messages.map(\.sequence).max() ?? -1) + 1
                let record = FamiliarModelSwitchRecord(
                    previousProviderID: conversation.currentProviderID,
                    previousModelID: conversation.currentModelID,
                    currentProviderID: value.providerID,
                    currentModelID: value.modelID,
                    sequence: nextSequence,
                    conversation: conversation
                )
                context.insert(record)
                conversation.currentProviderID = value.providerID
                conversation.currentModelID = value.modelID
                conversation.updatedAt = Date()
                try context.save()
                reloadMessages(in: context)
            }
        } catch {
            context.rollback()
            settings = oldValue
            errorMessage = String(format: String(localized: "error.save_settings"), error.localizedDescription)
        }
    }

    private func performSend(
        requestMessages: [FamiliarMessageSnapshot],
        conversationID: UUID,
        apiKey: String,
        descriptor: FamiliarProviderDescriptor,
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
                provider: FamiliarProviderFactory.makeProvider(for: descriptor),
                registry: toolRegistry,
                confirmationCoordinator: confirmationCoordinator,
                eventKitService: eventKitService
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
                case .confirmationRequested(let request):
                    if !pendingConfirmations.contains(where: { $0.id == request.id }) {
                        pendingConfirmations.append(request)
                    }
                case .confirmationResolved(let requestID, _):
                    pendingConfirmations.removeAll { $0.id == requestID }
                case .toolRecord(let record):
                    persistToolRecord(record, conversationID: conversationID, context: context)
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
                providerID: settings.providerID,
                modelID: settings.modelID,
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
        pendingConfirmations = []
    }

    private func persistToolRecord(
        _ event: FamiliarToolRunTerminalEvent,
        conversationID: UUID?,
        context: ModelContext
    ) {
        guard let conversationID,
              let conversation = fetchConversation(id: conversationID, in: context),
              !conversation.toolRunRecords.contains(where: {
                  $0.runID == event.runID && $0.toolCallID == event.toolCallID
              })
        else { return }
        let sequence = (conversation.messages.map(\.sequence).max() ?? -1) + 1
        let record = FamiliarToolRunRecord(
            runID: event.runID,
            toolCallID: event.toolCallID,
            toolName: event.toolName,
            summary: event.summary,
            detail: event.detail,
            confirmation: event.confirmation,
            status: event.status,
            sequence: sequence,
            startedAt: event.startedAt,
            finishedAt: event.finishedAt,
            conversation: conversation
        )
        context.insert(record)
        conversation.updatedAt = event.finishedAt
        do {
            try context.save()
            reloadMessages(in: context)
        } catch {
            context.rollback()
            errorMessage = String(format: String(localized: "error.save_tool_record"), error.localizedDescription)
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
