import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class FamiliarChatController {
    var selectedConversationID: UUID?
    var messages: [FamiliarMessageSnapshot] = []
    var modelSwitches: [FamiliarModelSwitchSnapshot] = []
    var toolRunRecords: [FamiliarToolRunSnapshot] = []
    var agentRuns: [FamiliarAgentRunSnapshot] = []
    var pendingConfirmations: [FamiliarToolConfirmationRequest] = []
    var draft = ""
    var draftImages: [FamiliarDraftImage] = []
    var draftAttachments: [FamiliarAttachmentDraft] = []
    var streamingText = ""
    var streamingMessageID: UUID?
    var agentStatus: FamiliarRuntimeState?
    var activeRunStartedAt: Date?
    var toolActivities: [FamiliarToolProgress] = []
    var availableUndoKeys: Set<String> = []
    var isSending = false
    var errorMessage: String?
    var settings = FamiliarSettingsStore.load()

    private let dependencies: FamiliarAppDependencies
    private let confirmationCoordinator: FamiliarToolConfirmationCoordinator
    private let runRecorder: FamiliarRunPersistenceRecorder
    private let runRecovery: FamiliarRunRecoveryService
    private var runningTask: Task<Void, Never>?

    init(dependencies: FamiliarAppDependencies) {
        self.dependencies = dependencies
        confirmationCoordinator = dependencies.confirmationCoordinator
        runRecorder = FamiliarRunPersistenceRecorder()
        runRecovery = FamiliarRunRecoveryService()
    }

    func select(_ id: UUID?, in context: ModelContext) {
        guard !isSending else { return }
        discardDraftAttachments()
        draft = ""
        selectedConversationID = id
        availableUndoKeys = []
        resetTransientRunState()
        reloadMessages(in: context)
        guard let conversation = selectedConversation(in: context) else { return }
        var value = settings
        value.providerID = conversation.currentProviderID
        value.modelID = conversation.currentModelID
        settings = value
    }

    @discardableResult
    func openDeepLink(
        _ deepLink: FamiliarDeepLink,
        conversations: [FamiliarConversation],
        in context: ModelContext
    ) -> Bool {
        guard !isSending else {
            errorMessage = String(localized: "error.deep_link.busy")
            return false
        }

        switch deepLink {
        case .newDraft(let text):
            select(nil, in: context)
            draft = text
        case .conversation(let id):
            guard conversations.contains(where: { $0.id == id }) else {
                errorMessage = String(localized: "error.deep_link.conversation_not_found")
                return true
            }
            select(id, in: context)
        case .run(let id):
            let runtimeID = id.uuidString
            guard let conversation = conversations.first(where: {
                $0.agentRuns.contains(where: { $0.runtimeID == runtimeID })
            }) else {
                errorMessage = String(localized: "error.deep_link.run_not_found")
                return true
            }
            select(conversation.id, in: context)
        }
        return true
    }

    @discardableResult
    func createConversation(project: FamiliarProject? = nil, in context: ModelContext) -> FamiliarConversation? {
        discardDraftAttachments()
        draft = ""
        let conversation = FamiliarConversation(
            currentProviderID: settings.providerID,
            currentModelID: settings.modelID,
            project: project
        )
        context.insert(conversation)
        do {
            try context.save()
            selectedConversationID = conversation.id
            messages = []
            modelSwitches = []
            toolRunRecords = []
            agentRuns = []
            availableUndoKeys = []
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
        let attachmentPaths = conversations.flatMap { conversation in
            conversation.messages.flatMap { $0.attachments.map(\.relativePath) }
        }
        conversations.forEach(context.delete)
        do {
            try context.save()
            FamiliarAttachmentStore.remove(relativePaths: attachmentPaths)
            if let selectedConversationID, deletedIDs.contains(selectedConversationID) {
                self.selectedConversationID = nil
                messages = []
                modelSwitches = []
                toolRunRecords = []
                agentRuns = []
                availableUndoKeys = []
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

        var importedImageDrafts: [FamiliarAttachmentDraft] = []
        defer {
            if !importedImageDrafts.isEmpty {
                FamiliarAttachmentStore.remove(relativePaths: importedImageDrafts.map(\.relativePath))
            }
        }
        do {
            importedImageDrafts = try draftImages.enumerated().map { index, draftImage in
                try FamiliarAttachmentStore.importImage(draftImage.image, filename: "photo-\(index + 1).jpg")
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let combinedAttachments = draftAttachments + importedImageDrafts

        guard !prompt.isEmpty || !combinedAttachments.isEmpty else { return }
        let requestSettings = settings
        guard let descriptor = requestSettings.resolvedProvider else {
            errorMessage = String(localized: "error.provider.invalid_custom_configuration")
            return
        }
        guard draftImages.isEmpty || requestSettings.selectedModel.capabilities.supportsImages else {
            errorMessage = String(localized: "attachment.error.model_images_unsupported")
            return
        }
        let selectedProject = selectedConversation(in: context)?.project
        let hasProjectResources = selectedProject?.resources.isEmpty == false
        guard (draftAttachments.isEmpty && !hasProjectResources) || requestSettings.selectedModel.capabilities.supportsDocuments else {
            errorMessage = String(localized: "attachment.error.model_unsupported")
            return
        }
        let priorCharacterCount = messages.reduce(into: 0) { count, message in
            count += message.content.count
            count += message.attachments.reduce(0) { $0 + $1.extractedText.count }
        }
        let requestCharacterCount = priorCharacterCount
            + prompt.count
            + combinedAttachments.reduce(0) { $0 + $1.extractedText.count }
        guard requestCharacterCount <= requestSettings.selectedModel.capabilities.maximumInputCharacters else {
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
        let createdConversation: Bool
        if let existing = selectedConversation(in: context) {
            conversation = existing
            createdConversation = false
        } else {
            let created = FamiliarConversation(
                currentProviderID: requestSettings.providerID,
                currentModelID: requestSettings.modelID
            )
            context.insert(created)
            conversation = created
            createdConversation = true
            selectedConversationID = created.id
        }
        conversation.currentProviderID = requestSettings.providerID
        conversation.currentModelID = requestSettings.modelID

        let nextSequence = nextTimelineSequence(in: conversation)
        let messageID = UUID()
        var committedPaths: [String] = []
        do {
            committedPaths = try committedAttachmentPaths(for: combinedAttachments, messageID: messageID)
        } catch {
            context.rollback()
            if createdConversation { selectedConversationID = nil }
            FamiliarAttachmentStore.remove(relativePaths: committedPaths)
            errorMessage = error.localizedDescription
            return
        }
        let userMessage = FamiliarMessage(
            id: messageID,
            role: .user,
            content: prompt,
            sequence: nextSequence,
            conversation: conversation
        )
        context.insert(userMessage)
        for (draftAttachment, relativePath) in zip(combinedAttachments, committedPaths) {
            let attachment = FamiliarAttachment(
                id: draftAttachment.id,
                kind: draftAttachment.kind,
                filename: draftAttachment.filename,
                mimeType: draftAttachment.mimeType,
                relativePath: relativePath,
                extractedText: draftAttachment.extractedText,
                byteSize: draftAttachment.byteSize,
                extractionEngine: draftAttachment.extractionEngine,
                extractionVersion: draftAttachment.extractionVersion,
                detectedFormat: draftAttachment.detectedFormat,
                usedOCR: draftAttachment.usedOCR,
                message: userMessage
            )
            context.insert(attachment)
        }
        conversation.updatedAt = Date()
        if conversation.messages.count == 1 {
            let titleSource = prompt.isEmpty ? (combinedAttachments.first?.filename ?? String(localized: "conversation.new")) : prompt
            conversation.title = String(titleSource.prefix(28))
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            if createdConversation { selectedConversationID = nil }
            FamiliarAttachmentStore.remove(relativePaths: committedPaths)
            errorMessage = String(format: String(localized: "error.save_prompt"), error.localizedDescription)
            return
        }

        FamiliarAttachmentStore.remove(relativePaths: combinedAttachments.map(\.relativePath))
        draft = ""
        draftAttachments = []
        draftImages = []
        reloadMessages(in: context)
        let requestMessages = messages
        let contextSeed = makeContextSeed(conversation: conversation)
        let responseID = UUID()
        isSending = true
        availableUndoKeys = []
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
                contextSeed: contextSeed,
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
                eventSequence: Int.max,
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

        let stagedAttachments: [FamiliarAttachmentDraft]
        do {
            stagedAttachments = try stagedCopies(of: message.attachments)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let messagesToDelete = conversation.messages.filter { $0.sequence >= message.sequence }
        let attachmentPaths = messagesToDelete.flatMap { $0.attachments.map(\.relativePath) }
        messagesToDelete.forEach(context.delete)
        conversation.modelSwitchRecords
            .filter { $0.sequence >= message.sequence }
            .forEach(context.delete)
        conversation.agentRuns
            .filter { run in run.steps.contains { $0.timelineSequence >= message.sequence } }
            .forEach(context.delete)
        conversation.updatedAt = Date()
        do {
            try context.save()
            FamiliarAttachmentStore.remove(relativePaths: attachmentPaths)
            discardDraftAttachments()
            draft = message.content
            draftAttachments = stagedAttachments
            reloadMessages(in: context)
        } catch {
            context.rollback()
            FamiliarAttachmentStore.remove(relativePaths: stagedAttachments.map(\.relativePath))
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
        let userSnapshotAttachments = userMessage.attachments.map {
            FamiliarAttachmentSnapshot(
                id: $0.id,
                kind: $0.kind,
                filename: $0.filename,
                mimeType: $0.mimeType,
                relativePath: $0.relativePath,
                extractedText: $0.extractedText,
                byteSize: $0.byteSize,
                extractionEngine: $0.extractionEngine,
                extractionVersion: $0.extractionVersion,
                detectedFormat: $0.detectedFormat,
                usedOCR: $0.usedOCR
            )
        }
        let stagedAttachments: [FamiliarAttachmentDraft]
        do {
            stagedAttachments = try stagedCopies(of: userSnapshotAttachments)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let messagesToDelete = conversation.messages.filter { $0.sequence >= userMessage.sequence }
        let attachmentPaths = messagesToDelete.flatMap { $0.attachments.map(\.relativePath) }
        messagesToDelete.forEach(context.delete)
        conversation.modelSwitchRecords
            .filter { $0.sequence >= userMessage.sequence }
            .forEach(context.delete)
        conversation.agentRuns
            .filter { run in run.steps.contains { $0.timelineSequence >= userMessage.sequence } }
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
            FamiliarAttachmentStore.remove(relativePaths: attachmentPaths)
            discardDraftAttachments()
            draft = prompt
            draftAttachments = stagedAttachments
            reloadMessages(in: context)
            startSending(in: context)
        } catch {
            context.rollback()
            FamiliarAttachmentStore.remove(relativePaths: stagedAttachments.map(\.relativePath))
            errorMessage = String(format: String(localized: "error.retry_message"), error.localizedDescription)
        }
    }

    func reloadMessages(in context: ModelContext) {
        guard let conversation = selectedConversation(in: context) else {
            messages = []
            modelSwitches = []
            toolRunRecords = []
            agentRuns = []
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
                    modelID: $0.modelID,
                    attachments: $0.attachments
                        .sorted { $0.createdAt < $1.createdAt }
                        .map {
                            FamiliarAttachmentSnapshot(
                                id: $0.id,
                                kind: $0.kind,
                                filename: $0.filename,
                                mimeType: $0.mimeType,
                                relativePath: $0.relativePath,
                                extractedText: $0.extractedText,
                                byteSize: $0.byteSize,
                                extractionEngine: $0.extractionEngine,
                                extractionVersion: $0.extractionVersion,
                                detectedFormat: $0.detectedFormat,
                                usedOCR: $0.usedOCR
                            )
                        },
                    sources: $0.sources
                        .sorted { $0.sequence < $1.sequence }
                        .compactMap { record in
                            guard let url = URL(string: record.urlString) else { return nil }
                            return FamiliarSource(
                                id: record.sourceID,
                                kind: record.kind,
                                title: record.title,
                                url: url,
                                siteName: record.siteName,
                                snippet: record.snippet,
                                retrievedAt: record.retrievedAt
                            )
                        }
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
        toolRunRecords = conversation.agentRuns.flatMap(\.steps)
            .filter { $0.type == .tool }
            .sorted { lhs, rhs in
                lhs.timelineSequence == rhs.timelineSequence ? lhs.finishedAt < rhs.finishedAt : lhs.timelineSequence < rhs.timelineSequence
            }
            .map {
                FamiliarToolRunSnapshot(
                    id: $0.id,
                    runID: $0.run?.runtimeID ?? "",
                    toolCallID: $0.toolCallID,
                    toolName: $0.toolName,
                    summary: $0.summary,
                    detail: $0.detail,
                    confirmation: $0.confirmation,
                    status: $0.status,
                    sequence: $0.timelineSequence,
                    startedAt: $0.startedAt,
                    finishedAt: $0.finishedAt
                )
            }
        agentRuns = conversation.agentRuns
            .sorted { $0.startedAt < $1.startedAt }
            .map { run in
                FamiliarAgentRunSnapshot(
                    id: run.runtimeID,
                    responseMessageID: run.responseMessageID,
                    status: run.status,
                    startedAt: run.startedAt,
                    finishedAt: run.finishedAt,
                    steps: run.steps
                        .filter { $0.type != .result }
                        .sorted { $0.eventSequence < $1.eventSequence }
                        .map {
                            FamiliarAgentStepSnapshot(
                                id: $0.id,
                                type: $0.type,
                                toolName: $0.toolName,
                                summary: $0.summary,
                                detail: $0.detail,
                                status: $0.status,
                                eventSequence: $0.eventSequence,
                                startedAt: $0.startedAt,
                                finishedAt: $0.finishedAt
                            )
                        }
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
                let nextSequence = nextTimelineSequence(in: conversation)
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
        contextSeed: FamiliarProjectContextSeed,
        responseID: UUID,
        context: ModelContext
    ) async {
        defer {
            isSending = false
            runningTask = nil
        }

        var activeRunID: UUID?
        do {
            let manifests = settings.selectedModel.capabilities.supportsTools
                ? await dependencies.registry.manifests()
                : []
            let contextSnapshot = try FamiliarProjectContextAssembler.assemble(
                seed: contextSeed,
                settings: settings,
                messages: requestMessages,
                toolManifests: manifests
            )
            let agentLoop = dependencies.makeRuntime(for: descriptor)
            var completedResponse: FamiliarCompletedResponse?
            for try await event in agentLoop.stream(
                contextSnapshot: contextSnapshot,
                apiKey: apiKey
            ) {
                switch event.payload {
                case .runStarted:
                    activeRunID = UUID(uuidString: event.runID)
                    activeRunStartedAt = event.timestamp
                    runRecorder.ensureRun(runtimeID: event.runID, snapshot: contextSnapshot, startedAt: event.timestamp, context: context)
                    do {
                        let capabilitySnapshot = FamiliarCapabilitySnapshot(
                            id: UUID(),
                            createdAt: contextSnapshot.createdAt,
                            projectID: contextSnapshot.projectID,
                            manifests: contextSnapshot.toolManifests
                        )
                        try runRecovery.persistCapabilitySnapshot(
                            capabilitySnapshot,
                            contextSnapshotID: contextSnapshot.id,
                            conversationID: conversationID,
                            in: context
                        )
                        _ = try runRecovery.beginCursor(
                            runtimeID: event.runID,
                            runID: activeRunID,
                            contextSnapshotID: contextSnapshot.id,
                            in: context
                        )
                    } catch {
                        errorMessage = String(format: String(localized: "error.save_tool_record"), error.localizedDescription)
                    }
                case .state(let status):
                    agentStatus = status
                case .textDelta(let delta):
                    streamingText += delta
                case .toolRequested:
                    break
                case .toolInvocationRequested(let toolCallID, let toolName, let arguments):
                    beginToolInvocation(
                        runtimeID: event.runID,
                        toolCallID: toolCallID,
                        toolName: toolName,
                        arguments: arguments,
                        eventSequence: event.sequence,
                        context: context
                    )
                case .toolProgress(let activity):
                    updateToolActivity(activity)
                case .approvalRequested(let request):
                    updateRunCursor(runtimeID: event.runID, phase: .awaitingApproval, eventSequence: event.sequence, context: context)
                    if !pendingConfirmations.contains(where: { $0.id == request.id }) {
                        pendingConfirmations.append(request)
                    }
                case .approvalResolved(let requestID, _):
                    if let request = pendingConfirmations.first(where: { $0.id == requestID }) {
                        runRecorder.recordCheckpoint(type: .approval, runtimeID: event.runID, eventSequence: event.sequence, summary: request.title, detail: "审批已完成", context: context)
                    }
                    updateRunCursor(runtimeID: event.runID, phase: .committingTool, eventSequence: event.sequence, context: context)
                    pendingConfirmations.removeAll { $0.id == requestID }
                case .toolFinished(let record):
                    finishToolInvocation(record, eventSequence: event.sequence, context: context)
                    persistToolRecord(record, eventSequence: event.sequence, conversationID: conversationID, context: context)
                    persistToolOutputs(record, conversationID: conversationID, context: context)
                    if record.undoAvailable {
                        availableUndoKeys.insert(record.runID + ":" + record.toolCallID)
                    }
                case .responseCompleted(let response):
                    completedResponse = response
                    updateRunCursor(runtimeID: event.runID, phase: .model, eventSequence: event.sequence, context: context)
                    runRecorder.recordCheckpoint(type: .model, runtimeID: event.runID, eventSequence: event.sequence, summary: "模型回复", detail: String(response.text.prefix(2_000)), context: context)
                case .runCompleted:
                    updateRunCursor(runtimeID: event.runID, phase: .terminal, eventSequence: event.sequence, context: context)
                    runRecorder.finishRun(runtimeID: event.runID, status: .completed, reason: "completed", eventSequence: event.sequence, at: event.timestamp, context: context)
                case .runCancelled:
                    updateRunCursor(runtimeID: event.runID, phase: .terminal, eventSequence: event.sequence, context: context)
                    runRecorder.finishRun(runtimeID: event.runID, status: .cancelled, reason: "cancelled", eventSequence: event.sequence, at: event.timestamp, context: context)
                case .runFailed(let message):
                    updateRunCursor(runtimeID: event.runID, phase: .terminal, eventSequence: event.sequence, context: context)
                    runRecorder.finishRun(runtimeID: event.runID, status: .failed, reason: message, eventSequence: event.sequence, at: event.timestamp, context: context)
                    errorMessage = message
                }
            }
            try Task.checkCancellation()

            let answer = (completedResponse?.text ?? streamingText).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { throw FamiliarAgentError.emptyResponse }
            guard let conversation = fetchConversation(id: conversationID, in: context) else {
                throw CocoaError(.fileNoSuchFile)
            }

            let nextSequence = nextTimelineSequence(in: conversation)
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
            for (sequence, source) in (completedResponse?.sources ?? []).enumerated() {
                context.insert(FamiliarSourceRecord(
                    sourceID: source.id,
                    kind: source.kind,
                    title: source.title,
                    urlString: source.url.absoluteString,
                    siteName: source.siteName,
                    snippet: source.snippet,
                    sequence: sequence,
                    retrievedAt: source.retrievedAt,
                    message: assistantMessage
                ))
            }
            if let activeRunID,
               let run = conversation.agentRuns.first(where: { $0.id == activeRunID }) {
                run.responseMessageID = responseID
            }
            conversation.updatedAt = Date()
            try context.save()
            reloadMessages(in: context)
            resetTransientRunState()
            await FamiliarNotificationService.scheduleCompletedRun(
                conversationID: conversationID,
                runID: activeRunID
            )
        } catch is CancellationError {
            runRecorder.finishActiveRuns(conversationID: conversationID, status: .cancelled, reason: "cancelled", context: context)
            resetTransientRunState()
        } catch {
            context.rollback()
            runRecorder.finishActiveRuns(conversationID: conversationID, status: .failed, reason: error.localizedDescription, context: context)
            resetTransientRunState()
            errorMessage = error.localizedDescription
            reloadMessages(in: context)
            await FamiliarNotificationService.scheduleFailedRun(
                conversationID: conversationID,
                runID: activeRunID
            )
        }
    }

    private func updateToolActivity(_ activity: FamiliarToolProgress) {
        if let index = toolActivities.firstIndex(where: { $0.id == activity.id }) {
            toolActivities[index] = activity
        } else {
            toolActivities.append(activity)
        }
    }

    func undo(_ record: FamiliarToolRunSnapshot, in context: ModelContext) {
        let key = record.runID + ":" + record.toolCallID
        let runtimeID = record.runID
        let toolCallID = record.toolCallID
        guard availableUndoKeys.contains(key) else { return }
        Task {
            do {
                let result = try await dependencies.undoStore.execute(key: key)
                availableUndoKeys.remove(key)
                let descriptor = FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.runtimeID == runtimeID })
                if let run = try? context.fetch(descriptor).first,
                   let step = run.steps.first(where: { $0.toolCallID == toolCallID }) {
                    step.detail = result.displayContent
                    try? context.save()
                    reloadMessages(in: context)
                }
            } catch {
                availableUndoKeys.remove(key)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetTransientRunState() {
        streamingText = ""
        streamingMessageID = nil
        agentStatus = nil
        activeRunStartedAt = nil
        toolActivities = []
        pendingConfirmations = []
    }

    private func persistToolRecord(
        _ event: FamiliarToolRunTerminalEvent,
        eventSequence: Int,
        conversationID: UUID?,
        context: ModelContext
    ) {
        do {
            if try runRecorder.recordTool(event, eventSequence: eventSequence, conversationID: conversationID, context: context) {
                reloadMessages(in: context)
            }
        } catch {
            errorMessage = String(format: String(localized: "error.save_tool_record"), error.localizedDescription)
        }
    }

    private func beginToolInvocation(
        runtimeID: String,
        toolCallID: String,
        toolName: String,
        arguments: String,
        eventSequence: Int,
        context: ModelContext
    ) {
        do {
            _ = try runRecovery.beginInvocation(
                idempotencyKey: runtimeID + ":" + toolCallID,
                runtimeID: runtimeID,
                toolName: toolName,
                arguments: arguments,
                in: context
            )
            updateRunCursor(runtimeID: runtimeID, phase: .committingTool, eventSequence: eventSequence, context: context)
        } catch FamiliarRunRecoveryService.Error.invocationAlreadyCommitted {
            errorMessage = String(localized: "error.tool.duplicate_call")
        } catch {
            errorMessage = String(format: String(localized: "error.save_tool_record"), error.localizedDescription)
        }
    }

    private func finishToolInvocation(
        _ event: FamiliarToolRunTerminalEvent,
        eventSequence: Int,
        context: ModelContext
    ) {
        let idempotencyKey = event.runID + ":" + event.toolCallID
        let descriptor = FetchDescriptor<FamiliarToolInvocationRecord>(
            predicate: #Predicate { $0.idempotencyKey == idempotencyKey }
        )
        guard let invocation = try? context.fetch(descriptor).first else { return }
        let state: FamiliarToolInvocationState
        switch event.status {
        case .succeeded: state = .committed
        case .cancelled: state = .cancelled
        case .failed: state = .failed
        }
        do {
            try runRecovery.setInvocationState(
                invocation,
                state: state,
                resultReference: event.artifactIdentifier,
                in: context
            )
            updateRunCursor(runtimeID: event.runID, phase: .model, eventSequence: eventSequence, context: context)
        } catch {
            errorMessage = String(format: String(localized: "error.save_tool_record"), error.localizedDescription)
        }
    }

    private func persistToolOutputs(_ event: FamiliarToolRunTerminalEvent, conversationID: UUID, context: ModelContext) {
        guard event.status == .succeeded else { return }
        do {
            if let descriptor = event.artifact {
                try FamiliarArtifactService().persist(descriptor, in: context)
            }
            if let project = fetchConversation(id: conversationID, in: context)?.project {
                let service = FamiliarProjectResourceService()
                for capture in event.sources.contains(where: { $0.kind == .fetchedPage }) ? event.webCaptures : [] {
                    _ = try service.importFetchedWebText(capture, into: project, in: context)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateRunCursor(
        runtimeID: String,
        phase: FamiliarRunRecoveryPhase,
        eventSequence: Int,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<FamiliarRunResumeCursorRecord>(predicate: #Predicate { $0.runtimeID == runtimeID })
        guard let cursor = try? context.fetch(descriptor).first else { return }
        try? runRecovery.updateCursor(
            cursor,
            iteration: cursor.nextIteration,
            phase: phase,
            eventSequence: eventSequence,
            in: context
        )
    }

    private func nextTimelineSequence(in conversation: FamiliarConversation?) -> Int {
        guard let conversation else { return 0 }
        let values = conversation.messages.map(\.sequence)
            + conversation.modelSwitchRecords.map(\.sequence)
            + conversation.agentRuns.flatMap(\.steps).map(\.timelineSequence)
        return (values.max() ?? -1) + 1
    }

    private func committedAttachmentPaths(
        for attachments: [FamiliarAttachmentDraft],
        messageID: UUID
    ) throws -> [String] {
        var paths: [String] = []
        do {
            for attachment in attachments {
                paths.append(try FamiliarAttachmentStore.committedCopy(of: attachment, messageID: messageID))
            }
            return paths
        } catch {
            FamiliarAttachmentStore.remove(relativePaths: paths)
            throw error
        }
    }

    private func stagedCopies(
        of attachments: [FamiliarAttachmentSnapshot]
    ) throws -> [FamiliarAttachmentDraft] {
        var drafts: [FamiliarAttachmentDraft] = []
        do {
            for attachment in attachments {
                drafts.append(try FamiliarAttachmentStore.stageCopy(of: attachment))
            }
            return drafts
        } catch {
            FamiliarAttachmentStore.remove(relativePaths: drafts.map(\.relativePath))
            throw error
        }
    }

    private func discardDraftAttachments() {
        FamiliarAttachmentStore.remove(relativePaths: draftAttachments.map(\.relativePath))
        draftAttachments = []
        draftImages = []
    }

    private func selectedConversation(in context: ModelContext) -> FamiliarConversation? {
        guard let selectedConversationID else { return nil }
        return fetchConversation(id: selectedConversationID, in: context)
    }

    private func makeContextSeed(conversation: FamiliarConversation) -> FamiliarProjectContextSeed {
        let project = conversation.project
        let resources = (project?.resources ?? []).compactMap { resource -> FamiliarContextResource? in
            guard let version = resource.versions.max(by: {
                $0.version == $1.version ? $0.createdAt < $1.createdAt : $0.version < $1.version
            }) else { return nil }
            return FamiliarContextResource(
                resourceID: resource.id,
                resourceVersionID: version.id,
                version: version.version,
                displayName: resource.displayName,
                filename: version.filename,
                mimeType: version.mimeType,
                contentHash: version.contentHash,
                extractedText: version.extractedText,
                extractedTextHash: version.extractedTextHash
            )
        }
        return FamiliarProjectContextSeed(
            projectID: project?.id,
            projectName: project?.name,
            conversationID: conversation.id,
            projectInstruction: project?.instruction?.text,
            resources: resources
        )
    }

    private func fetchConversation(id: UUID, in context: ModelContext) -> FamiliarConversation? {
        var descriptor = FetchDescriptor<FamiliarConversation>(
            predicate: #Predicate { conversation in conversation.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
