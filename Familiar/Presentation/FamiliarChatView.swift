import SwiftData
import SwiftUI
import SafariServices

struct FamiliarChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FamiliarConversation.updatedAt, order: .reverse)
    private var conversations: [FamiliarConversation]
    @Query(
        filter: #Predicate<FamiliarProject> { $0.statusRawValue == "active" },
        sort: \FamiliarProject.updatedAt,
        order: .reverse
    ) private var activeProjects: [FamiliarProject]
    @Query(sort: \FamiliarProject.updatedAt, order: .reverse)
    private var allProjects: [FamiliarProject]
    @Query(sort: \FamiliarPinnedItemRecord.pinnedAt, order: .reverse)
    private var pinnedItems: [FamiliarPinnedItemRecord]
    @Query(sort: \FamiliarSkill.name)
    private var installedSkills: [FamiliarSkill]

    @State private var controller: FamiliarChatController
    @StateObject private var speechTranscriber = FamiliarSpeechTranscriber()
    @State private var isDrawerOpen = false
    @State private var drawerDrag: CGFloat = 0
    @State private var isDragging = false
    @State private var presentedSheet: FamiliarSheetDestination?
    @State private var renameRequest: FamiliarRenameRequest?
    @State private var pendingMessageOperation: FamiliarPendingMessageOperation?
    @State private var pendingDraftNavigation: FamiliarPendingDraftNavigation?
    @State private var conversationPendingDeletion: FamiliarConversation?
    @State private var speechBaseDraft = ""
    @State private var configuredProviderIDs: Set<String> = []
    @State private var isImportingSharedItem = false
    @State private var pendingSharedDraft: FamiliarPreparedSharedDraft?
    @State private var showsSharedDestination = false
    @State private var webDestination: FamiliarWebDestination?
    @FocusState private var isComposerFocused: Bool
    private let toolRegistry: FamiliarToolRegistry
    private let searchService: FamiliarWebSearchService
    private let pythonPackageSourceSettings: FamiliarPythonPackageSourceSettingsStore
    private let workspaceStore: FamiliarWorkspaceStore
    private let shellRuntimeStatus: FamiliarShellRuntimeStatus
    @Binding private var pendingSystemEntry: FamiliarSystemEntryRequest?

    init(
        dependencies: FamiliarAppDependencies,
        pendingSystemEntry: Binding<FamiliarSystemEntryRequest?>
    ) {
        _controller = State(initialValue: FamiliarChatController(dependencies: dependencies))
        toolRegistry = dependencies.registry
        searchService = dependencies.searchService
        pythonPackageSourceSettings = dependencies.pythonPackageSourceSettings
        workspaceStore = dependencies.workspaceStore
        shellRuntimeStatus = dependencies.shellRuntimeStatus
        _pendingSystemEntry = pendingSystemEntry
    }

    var body: some View {
        @Bindable var controller = controller
        GeometryReader { safeGeometry in
            let safeAreaInsets = safeGeometry.safeAreaInsets
            let keyboardHeight = max(UIScreen.main.bounds.height - safeGeometry.size.height, 0)
            let bottomInset = keyboardHeight > 0 ? 0 : safeAreaInsets.bottom

            GeometryReader { geometry in
                let drawerWidth = geometry.size.width * (2.0 / 3.0)
                let visibleDrawerWidth = drawerOffset(width: drawerWidth)
                let drawerProgress = visibleDrawerWidth / max(drawerWidth, 1)
                let cornerRadius = FamiliarTheme.displayCornerRadius * drawerProgress
                let isDrawerVisible = drawerProgress > 0.001

                ZStack(alignment: .leading) {
                    FamiliarTheme.drawerFill
                        .ignoresSafeArea()

                    FamiliarConversationDrawer(
                        conversations: conversations,
                        projects: activeProjects,
                        pinnedItems: pinnedItems,
                        selectedConversationID: controller.selectedConversationID,
                        safeAreaInsets: safeAreaInsets,
                        onSelect: { conversation in
                            requestConversationSelection(conversation)
                        },
                        onRename: { conversation in
                            renameRequest = FamiliarRenameRequest(
                                conversation: conversation,
                                title: conversation.title
                            )
                        },
                        onDelete: { conversation in
                            conversationPendingDeletion = conversation
                            closeDrawer()
                        },
                        onSelectProject: { project in
                            presentedSheet = .projects(project.id)
                            closeDrawer()
                        },
                        onAllProjects: {
                            presentedSheet = .projects(nil)
                        },
                        onToggleConversationPin: { togglePin(.conversation, targetID: $0.id) },
                        onToggleProjectPin: { togglePin(.project, targetID: $0.id) }
                    )
                    .frame(width: drawerWidth)
                    .offset(x: -(drawerWidth * 0.12) * (1 - drawerProgress))

                    ZStack {
                        UnevenRoundedRectangle(
                            topLeadingRadius: cornerRadius,
                            bottomLeadingRadius: cornerRadius,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                        .fill(Color(uiColor: .systemBackground))

                        mainSurface(availableHeight: geometry.size.height - safeAreaInsets.top - bottomInset)
                            .scrollDisabled(isDrawerVisible)
                            .scrollIndicators(isDrawerVisible ? .hidden : .automatic)
                            .padding(.top, safeAreaInsets.top)
                            .padding(.bottom, bottomInset)
                    }
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: cornerRadius,
                            bottomLeadingRadius: cornerRadius,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                    )
                    .allowsHitTesting(!isDrawerVisible)
                    .shadow(color: .black.opacity(0.13 * drawerProgress), radius: 18, x: -7, y: 0)
                    .overlay {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture { closeDrawer() }
                            .allowsHitTesting(isDrawerVisible)
                    }
                    .offset(x: visibleDrawerWidth)
                    .simultaneousGesture(drawerGesture(width: drawerWidth))

                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 30)
                        .frame(maxHeight: .infinity)
                        .onTapGesture {
                            isComposerFocused = false
                            setDrawerOpen(true)
                        }
                        .gesture(drawerGesture(width: drawerWidth))
                        .allowsHitTesting(!isDrawerOpen)
                        .zIndex(100)
                        .accessibilityLabel(String(localized: "drawer.open"))
                        .accessibilityAddTraits(.isButton)
                }
                .background(FamiliarTheme.drawerFill.ignoresSafeArea())
            }
            .ignoresSafeArea(.container)
        }
        .ignoresSafeArea(.keyboard, edges: isDrawerOpen || drawerDrag != 0 ? .all : [])
        .sensoryFeedback(.selection, trigger: isDrawerOpen)
        .sheet(item: $presentedSheet, onDismiss: refreshConfiguredProviders) { destination in
            switch destination {
            case .settings(let route):
                FamiliarSettingsView(
                    initialSettings: controller.settings,
                    initialRoute: route,
                    registry: toolRegistry,
                    searchService: searchService,
                    pythonPackageSourceSettings: pythonPackageSourceSettings,
                    workspaceStore: workspaceStore,
                    workspaceID: controller.selectedProjectID.map(FamiliarWorkspaceID.project)
                        ?? controller.selectedConversationID.map(FamiliarWorkspaceID.conversation),
                    shellRuntimeStatus: shellRuntimeStatus,
                    onSaveSettings: {
                        controller.updateSettings($0, in: modelContext)
                        refreshConfiguredProviders()
                    }
                )
            case .projects(let projectID):
                FamiliarProjectsView(
                    initialProjectID: projectID,
                    registry: toolRegistry,
                    onConversationRequest: handleProjectConversationRequest,
                    onDeleteConversations: { controller.delete($0, in: modelContext) }
                )
            }
        }
        .sheet(item: $webDestination) { destination in
            FamiliarSafariView(url: destination.url) {
                webDestination = nil
            }
            .ignoresSafeArea()
            .presentationSizing(.page)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsSharedDestination, onDismiss: discardPendingSharedDraftIfNeeded) {
            FamiliarSharedDestinationView { destination in
                importSharedDraft(to: destination)
            }
        }
        .alert(String(localized: "conversation.rename.title"), isPresented: Binding(
            get: { renameRequest != nil },
            set: { if !$0 { renameRequest = nil } }
        )) {
            TextField(String(localized: "conversation.rename.placeholder"), text: renameTitleBinding)
            Button(String(localized: "common.save")) { commitRename() }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }

        .alert(String(localized: "app.name"), isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )) {
            if !isSelectedProviderConfigured {
                Button(String(localized: "common.open_settings")) {
                    presentedSheet = .settings(nil)
                }
            }
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(controller.errorMessage ?? String(localized: "error.unknown"))
        }
        .confirmationDialog(
            "切换到 DeepSeek？",
            isPresented: Binding(
                get: { !controller.pendingModelEscalations.isEmpty },
                set: { isPresented in
                    if !isPresented,
                       let approval = controller.pendingModelEscalations.first {
                        controller.resolveModelEscalation(id: approval.id, approved: false)
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let approval = controller.pendingModelEscalations.first {
                Button("继续使用 DeepSeek") {
                    controller.resolveModelEscalation(id: approval.id, approved: true)
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    controller.resolveModelEscalation(id: approval.id, approved: false)
                }
            }
        } message: {
            if let approval = controller.pendingModelEscalations.first {
                Text(modelEscalationDescription(approval.request))
            }
        }
        .confirmationDialog(
            String(localized: "message.operation.title"),
            isPresented: Binding(
                get: { pendingMessageOperation != nil },
                set: { if !$0 { pendingMessageOperation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingMessageOperation?.actionTitle ?? "", role: .destructive) {
                performPendingMessageOperation()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "message.operation.detail"))
        }
        .confirmationDialog(
            String(localized: "draft.discard.title", defaultValue: "Discard this draft?"),
            isPresented: Binding(
                get: { pendingDraftNavigation != nil },
                set: { if !$0 { pendingDraftNavigation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "draft.discard.action", defaultValue: "Discard Draft"), role: .destructive) {
                performPendingDraftNavigation()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "draft.discard.detail", defaultValue: "Your unsent text and attachments will be removed before switching."))
        }
        .confirmationDialog(
            String(localized: "conversation.delete.title", defaultValue: "Delete this chat?"),
            isPresented: Binding(
                get: { conversationPendingDeletion != nil },
                set: { if !$0 { conversationPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                guard let conversationPendingDeletion else { return }
                controller.delete([conversationPendingDeletion], in: modelContext)
                self.conversationPendingDeletion = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "conversation.delete.detail", defaultValue: "Messages, attachments, and saved run history in this chat will be deleted from this iPhone."))
        }
        .onAppear {
            controller.recoverInterruptedRuns(in: modelContext)
            try? FamiliarSkillService().installExampleIfNeeded(in: modelContext)
            if controller.selectedConversationID == nil,
               let first = conversations.first(where: { $0.project == nil }) {
                controller.select(first.id, in: modelContext)
            }
            refreshConfiguredProviders()
            FamiliarAttachmentStore.pruneDrafts(keeping: Set(controller.draftAttachments.map(\.relativePath)))
            FamiliarAttachmentStore.pruneMessageFiles(keeping: Set(
                conversations.flatMap { $0.messages.flatMap { $0.attachments.map(\.relativePath) } }
            ))
            handlePendingSystemEntry()
            handleSharedInbox()
            updateSpotlightIndex(spotlightConversations)
        }
        .onChange(of: speechTranscriber.errorMessage) { _, message in
            if let message { controller.errorMessage = message }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshConfiguredProviders()
                handleSharedInbox()
            } else {
                Task { await speechTranscriber.stop() }
            }
        }
        .onChange(of: pendingSystemEntry) { _, _ in
            handlePendingSystemEntry()
        }
        .onChange(of: controller.isSending) { _, isSending in
            if !isSending {
                handlePendingSystemEntry()
                handleSharedInbox()
            }
        }
        .onChange(of: controller.draft) { _, _ in
            handlePendingSystemEntry()
            handleSharedInbox()
        }
        .onChange(of: controller.draftAttachments) { _, _ in
            handlePendingSystemEntry()
            handleSharedInbox()
        }
        .onChange(of: controller.draftImages.count) { _, _ in
            handlePendingSystemEntry()
            handleSharedInbox()
        }
        .onChange(of: installedSkillIDs) { _, skillIDs in
            if let selectedSkillID = controller.selectedSkillID,
               !skillIDs.contains(selectedSkillID) {
                controller.selectedSkillID = nil
            }
        }
        .onChange(of: spotlightConversations) { _, conversations in
            updateSpotlightIndex(conversations)
        }
    }

    private var spotlightConversations: [FamiliarSpotlightConversation] {
        conversations.compactMap { conversation in
            guard !conversation.messages.isEmpty || !conversation.agentRuns.isEmpty else { return nil }
            return FamiliarSpotlightConversation(
                id: conversation.id,
                title: conversation.title,
                updatedAt: conversation.updatedAt
            )
        }
    }

    private func modelEscalationDescription(
        _ request: FamiliarModelEscalationRequest
    ) -> String {
        var scopes = ["\(request.messageCount) 条消息"]
        if request.includesDocuments { scopes.append("文档内容") }
        if request.includesImages { scopes.append("图片") }
        return "本地模型当前无法完成这项任务。确认后，Familiar 会将\(scopes.joined(separator: "、"))发送给 DeepSeek；拒绝后不会静默切换。"
    }

    private var installedSkillIDs: [UUID] {
        installedSkills.map(\.id)
    }

    private var isSelectedProviderConfigured: Bool {
        configuredProviderIDs.contains(controller.settings.providerID)
    }

    private var isInNewConversation: Bool {
        controller.messages.isEmpty
            && controller.agentRuns.isEmpty
            && controller.pendingConfirmations.isEmpty
            && controller.pendingClarifications.isEmpty
            && controller.streamingText.isEmpty
            && !controller.hasTransientActivity
    }

    private func updateSpotlightIndex(_ conversations: [FamiliarSpotlightConversation]) {
        Task {
            await FamiliarSpotlightIndexer.shared.replaceConversations(conversations)
        }
    }

    private func handlePendingSystemEntry() {
        guard let request = pendingSystemEntry, !controller.isSending else { return }

        guard !hasUnsentDraft else {
            pendingSystemEntry = nil
            controller.errorMessage = String(localized: "error.system_entry.draft_pending")
            return
        }

        guard controller.openDeepLink(request.deepLink, conversations: conversations, in: modelContext) else { return }

        pendingSystemEntry = nil
        Task { await speechTranscriber.stop() }
        presentedSheet = nil
        closeDrawer()
        switch request.deepLink {
        case .newDraft:
            isComposerFocused = true
        case .conversation, .run:
            isComposerFocused = false
        }
        if request.automaticallySubmit {
            controller.startSending(in: modelContext)
        }
    }

    private func handleSharedInbox() {
        guard pendingSystemEntry == nil,
              !controller.isSending,
              !isImportingSharedItem,
              controller.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              controller.draftAttachments.isEmpty,
              controller.draftImages.isEmpty,
              controller.selectedSkillID == nil
        else { return }

        isImportingSharedItem = true
        Task { @MainActor in
            defer { isImportingSharedItem = false }
            do {
                guard let prepared = try await FamiliarSharedDraftImportService.prepareNext() else { return }

                guard !controller.isSending,
                      controller.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      controller.draftAttachments.isEmpty,
                      controller.draftImages.isEmpty,
                      controller.selectedSkillID == nil
                else {
                    FamiliarSharedDraftImportService.discardPreparedAttachments(prepared)
                    return
                }

                guard !prepared.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !prepared.attachments.isEmpty else {
                    controller.errorMessage = prepared.firstImportErrorDescription
                        ?? String(localized: "share.error.no_supported_content")
                    return
                }
                pendingSharedDraft = prepared
                showsSharedDestination = true
            } catch {
                controller.errorMessage = String(
                    format: String(localized: "share.error.import_failed"),
                    error.localizedDescription
                )
            }
        }
    }

    private func importSharedDraft(to destination: FamiliarSharedDestination) {
        guard let prepared = pendingSharedDraft else { return }
        Task { await speechTranscriber.stop() }
        switch destination {
        case .project(let project):
            pendingSharedDraft = nil
            showsSharedDestination = false
            isImportingSharedItem = true
            Task { @MainActor in
                defer { isImportingSharedItem = false }
                let service = FamiliarProjectResourceService()
                var firstError = prepared.firstImportErrorDescription
                var importedCount = 0

                for attachment in prepared.attachments {
                    guard let url = FamiliarAttachmentStore.url(for: attachment.relativePath) else {
                        firstError = firstError ?? FamiliarAttachmentStoreError.sourceUnavailable.localizedDescription
                        continue
                    }
                    do {
                        try await service.importDocument(from: url, into: project, in: modelContext)
                        importedCount += 1
                    } catch {
                        firstError = firstError ?? error.localizedDescription
                    }
                }

                let sharedText = prepared.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sharedText.isEmpty {
                    do {
                        if Self.isStandaloneHTTPSURL(sharedText) {
                            try await service.importWebPage(from: sharedText, into: project, in: modelContext)
                        } else {
                            try service.importPastedText(sharedText, into: project, in: modelContext)
                        }
                        importedCount += 1
                    } catch {
                        firstError = firstError ?? error.localizedDescription
                    }
                }

                FamiliarSharedDraftImportService.consume(prepared)
                FamiliarSharedDraftImportService.discardPreparedAttachments(prepared)
                presentedSheet = .projects(project.id)
                if let firstError {
                    controller.errorMessage = importedCount > 0
                        ? String(format: String(localized: "share.error.partial_import"), firstError)
                        : String(format: String(localized: "share.error.import_failed"), firstError)
                }
            }
            return
        case .ordinary:
            FamiliarSharedDraftImportService.consume(prepared)
            pendingSharedDraft = nil
            controller.select(nil, in: modelContext)
            controller.draft = prepared.text
            controller.draftAttachments = prepared.attachments
        }
        showsSharedDestination = false
        presentedSheet = nil
        closeDrawer()
        isComposerFocused = true
        if let importErrorDescription = prepared.firstImportErrorDescription {
            controller.errorMessage = String(format: String(localized: "share.error.partial_import"), importErrorDescription)
        }
    }

    private static func isStandaloneHTTPSURL(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false
        else { return false }
        return url.absoluteString == text
    }

    private func discardPendingSharedDraftIfNeeded() {
        guard let pendingSharedDraft else { return }
        FamiliarSharedDraftImportService.discardPreparedAttachments(pendingSharedDraft)
        self.pendingSharedDraft = nil
    }

    @ViewBuilder
    private func mainSurface(availableHeight: CGFloat) -> some View {
        NavigationStack {
            chatBody
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FamiliarComposer(
                        draft: $controller.draft,
                        images: $controller.draftImages,
                        documents: $controller.draftAttachments,
                        selectedSkillID: $controller.selectedSkillID,
                        skills: installedSkills.map {
                            FamiliarSkillMenuItem(
                                id: $0.id,
                                stableID: $0.stableID,
                                name: $0.name,
                                detail: $0.descriptionText
                            )
                        },
                        isSending: controller.isSending,
                        isListening: speechTranscriber.isListening,
                        draftScopeID: controller.selectedConversationID ?? controller.selectedProjectID,
                        focus: $isComposerFocused,
                        onSpeech: toggleSpeech,
                        onSend: {
                            Task { await speechTranscriber.stop() }
                            isComposerFocused = false
                            if controller.isSending {
                                controller.cancelSending(in: modelContext)
                            } else {
                                controller.startSending(in: modelContext)
                            }
                        },
                        availableHeight: availableHeight
                    )
                }
                .modifier(FamiliarTopBarInstaller(content: topBar))
                .toolbar(.hidden, for: .navigationBar)
        }
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private var chatBody: some View {
        if controller.messages.isEmpty,
           controller.agentRuns.isEmpty,
           controller.pendingConfirmations.isEmpty,
           controller.pendingClarifications.isEmpty,
           controller.streamingText.isEmpty,
           controller.streamingReasoningSummary.isEmpty,
           !controller.hasTransientActivity {
            FamiliarEmptyConversationView(
                isProviderConfigured: isSelectedProviderConfigured,
                onConfigure: { presentedSheet = .settings(nil) },
                onPrompt: { prompt in
                    controller.draft = prompt
                    isComposerFocused = true
                }
            )
            .id(controller.selectedConversationID)
        } else {
            FamiliarMessageTimeline(
                messages: controller.messages,
                modelSwitches: controller.modelSwitches,
                agentRuns: controller.agentRuns,
                surfaces: controller.surfaces.orderedSurfaces,
                streamingMessageID: controller.streamingMessageID,
                streamingResponseBlocks: controller.streamingResponseBlocks,
                streamingReasoningSummary: controller.streamingReasoningSummary,
                availableUndoKeys: controller.availableUndoKeys,
                completedUndoKeys: controller.completedUndoKeys,
                onResolveConfirmation: { requestID, decision in
                    controller.resolveConfirmation(requestID: requestID, decision: decision)
                },
                onResolveClarification: { requestID, resolution in
                    controller.resolveClarification(requestID: requestID, resolution: resolution)
                },
                onInsertPrompt: { prompt in
                    controller.draft = prompt
                    isComposerFocused = true
                },
                onUndo: { runID, toolCallID in
                    controller.undo(runID: runID, toolCallID: toolCallID, in: modelContext)
                },
                onEdit: { pendingMessageOperation = .edit($0) },
                onRetry: { pendingMessageOperation = .retry($0) },
                onRetryRecovery: { controller.retry(runID: $0, in: modelContext) }
            )
            .environment(\.openURL, OpenURLAction { url in
                guard FamiliarConversationURLRouter.shouldOpenInApp(url) else {
                    return .systemAction
                }
                webDestination = FamiliarWebDestination(url: url)
                return .handled
            })
        }
    }

    private var topBar: some View {
        let selectedProvider = controller.settings.selectedProvider
        let project = selectedProject
        let providers = FamiliarProviderCatalog.builtIn.filter { configuredProviderIDs.contains($0.id) }
        return FamiliarChatTopBar(
            provider: selectedProvider,
            model: controller.settings.selectedModel,
            project: project,
            projects: activeProjects,
            providerOptions: providers,
            isSending: controller.isSending,
            isNewConversation: isInNewConversation,
            onOpenSettings: { presentedSheet = .settings(nil) },
            onSelectProject: requestWorkspaceSelection,
            onManageProjects: { presentedSheet = .projects(nil) },
            onSelectModel: { providerID, modelID in
                controller.selectModel(providerID: providerID, modelID: modelID, in: modelContext)
            },
            onConfigure: { presentedSheet = .settings(nil) },
            onOpenProject: {
                guard let project else { return }
                presentedSheet = .projects(project.id)
            },
            onNewConversation: {
                guard !isInNewConversation else { return }
                requestNewConversation(project: project)
            }
        )
    }

    private var selectedProject: FamiliarProject? {
        guard let selectedProjectID = controller.selectedProjectID else { return nil }
        return allProjects.first { $0.id == selectedProjectID }
    }

    private var renameTitleBinding: Binding<String> {
        Binding(
            get: { renameRequest?.title ?? "" },
            set: { renameRequest?.title = $0 }
        )
    }

    private var hasUnsentDraft: Bool {
        !controller.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !controller.draftAttachments.isEmpty
            || !controller.draftImages.isEmpty
            || controller.selectedSkillID != nil
    }

    private func requestConversationSelection(_ conversation: FamiliarConversation) {
        guard !controller.isSending else {
            controller.errorMessage = String(localized: "error.deep_link.busy")
            return
        }
        guard conversation.id != controller.selectedConversationID else {
            closeDrawer()
            return
        }
        let navigation = FamiliarPendingDraftNavigation.select(conversation)
        if hasUnsentDraft {
            pendingDraftNavigation = navigation
            closeDrawer()
        } else {
            perform(navigation)
        }
    }

    private func requestNewConversation(project: FamiliarProject?) {
        guard !controller.isSending else {
            controller.errorMessage = String(localized: "error.deep_link.busy")
            return
        }
        let navigation = FamiliarPendingDraftNavigation.newConversation(project)
        if hasUnsentDraft {
            pendingDraftNavigation = navigation
            closeDrawer()
        } else {
            perform(navigation)
        }
    }

    private func requestWorkspaceSelection(_ project: FamiliarProject?) {
        if let latest = conversations.first(where: { $0.project?.id == project?.id }) {
            requestConversationSelection(latest)
        } else {
            requestNewConversation(project: project)
        }
    }

    private func handleProjectConversationRequest(_ request: FamiliarProjectConversationRequest) {
        guard !controller.isSending else {
            controller.errorMessage = String(localized: "error.deep_link.busy")
            return
        }
        let navigation: FamiliarPendingDraftNavigation?
        switch request {
        case .open(let conversationID):
            guard let conversation = conversations.first(where: { $0.id == conversationID }) else {
                controller.errorMessage = String(localized: "error.deep_link.conversation_not_found")
                return
            }
            navigation = .select(conversation)
        case .create(let projectID):
            guard let project = fetchProject(id: projectID) else {
                controller.errorMessage = String(localized: "project.unavailable")
                return
            }
            navigation = .newConversation(project)
        }
        guard let navigation else { return }
        if hasUnsentDraft {
            pendingDraftNavigation = navigation
        } else {
            perform(navigation)
        }
    }

    private func performPendingDraftNavigation() {
        guard let pendingDraftNavigation else { return }
        self.pendingDraftNavigation = nil
        perform(pendingDraftNavigation)
    }

    private func perform(_ navigation: FamiliarPendingDraftNavigation) {
        guard !controller.isSending else {
            controller.errorMessage = String(localized: "error.deep_link.busy")
            return
        }
        Task { await speechTranscriber.stop() }
        switch navigation {
        case .select(let conversation):
            controller.select(conversation.id, in: modelContext)
            isComposerFocused = false
        case .newConversation(let project):
            controller.startNewConversation(project: project, in: modelContext)
            isComposerFocused = true
        }
        closeDrawer()
    }

    private func fetchProject(id: UUID) -> FamiliarProject? {
        var descriptor = FetchDescriptor<FamiliarProject>(
            predicate: #Predicate { project in project.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func drawerOffset(width: CGFloat) -> CGFloat {
        let base = isDrawerOpen ? width : 0
        return min(max(base + drawerDrag, 0), width)
    }

    private func drawerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical || isDragging else { return }
                if !isDragging {
                    isComposerFocused = false
                }
                isDragging = true
                drawerDrag = value.translation.width
            }
            .onEnded { value in
                guard isDragging else { return }
                isDragging = false

                let currentOffset = drawerOffset(width: width)
                let projectedOffset = min(max(currentOffset + (value.predictedEndTranslation.width - value.translation.width), 0), width)
                let shouldOpen = projectedOffset > width * 0.5

                if reduceMotion {
                    drawerDrag = 0
                    isDrawerOpen = shouldOpen
                } else {
                    withAnimation(FamiliarMotion.drawer) {
                        drawerDrag = 0
                        isDrawerOpen = shouldOpen
                    }
                }
            }
    }

    private func closeDrawer() {
        setDrawerOpen(false)
    }

    private func setDrawerOpen(_ isOpen: Bool) {
        if reduceMotion {
            isDrawerOpen = isOpen
        } else {
            withAnimation(FamiliarMotion.drawer) {
                isDrawerOpen = isOpen
            }
        }
    }

    private func toggleSpeech() {
        if !speechTranscriber.isListening {
            speechBaseDraft = controller.draft
        }
        Task {
            await speechTranscriber.toggle { transcript in
                let separator = speechBaseDraft.isEmpty || transcript.isEmpty ? "" : " "
                controller.draft = speechBaseDraft + separator + transcript
                isComposerFocused = true
            }
        }
    }

    private func togglePin(_ targetType: FamiliarPinnedTargetType, targetID: UUID) {
        do {
            _ = try FamiliarPinService().toggle(targetType, targetID: targetID, in: modelContext)
        } catch {
            controller.errorMessage = error.localizedDescription
        }
    }

    private func refreshConfiguredProviders() {
        configuredProviderIDs = FamiliarKeychainStore.configuredProviderIDs(
            in: FamiliarProviderCatalog.allProviderIDs
        )
    }

    private func commitRename() {
        guard let request = renameRequest else { return }
        controller.rename(request.conversation, to: request.title, in: modelContext)
        renameRequest = nil
    }

    private func performPendingMessageOperation() {
        guard let operation = pendingMessageOperation else { return }
        pendingMessageOperation = nil
        switch operation {
        case .edit(let message):
            controller.prepareToEdit(message, in: modelContext)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                isComposerFocused = true
            }
        case .retry(let message):
            controller.retry(message, in: modelContext)
        }
    }
}

nonisolated enum FamiliarConversationURLRouter {
    static func shouldOpenInApp(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else { return false }
        return true
    }
}

private struct FamiliarWebDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct FamiliarSafariView: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let viewController = SFSafariViewController(url: url)
        viewController.dismissButtonStyle = .close
        viewController.delegate = context.coordinator
        return viewController
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish()
        }
    }
}

private enum FamiliarSheetDestination: Identifiable {
    case settings(FamiliarSettingsRoute?)
    case projects(UUID?)

    var id: String {
        switch self {
        case .settings(let route): "settings-\(route?.rawValue ?? "root")"
        case .projects(let projectID): "projects-\(projectID?.uuidString ?? "all")"
        }
    }
}

private struct FamiliarRenameRequest: Identifiable {
    let id: UUID
    let conversation: FamiliarConversation
    var title: String

    init(conversation: FamiliarConversation, title: String) {
        id = conversation.id
        self.conversation = conversation
        self.title = title
    }
}

private enum FamiliarPendingDraftNavigation: Identifiable {
    case select(FamiliarConversation)
    case newConversation(FamiliarProject?)

    var id: String {
        switch self {
        case .select(let conversation): "select-\(conversation.id.uuidString)"
        case .newConversation(let project): "new-\(project?.id.uuidString ?? "ordinary")"
        }
    }
}

private enum FamiliarPendingMessageOperation: Identifiable {
    case edit(FamiliarMessageSnapshot)
    case retry(FamiliarMessageSnapshot)

    var id: String {
        switch self {
        case .edit(let message): "edit-\(message.id.uuidString)"
        case .retry(let message): "retry-\(message.id.uuidString)"
        }
    }

    var actionTitle: String {
        switch self {
        case .edit: String(localized: "message.edit_and_resend")
        case .retry: String(localized: "message.retry")
        }
    }
}



private struct FamiliarTopBarInstaller<Bar: View>: ViewModifier {
    let content: Bar

    @ViewBuilder
    func body(content root: Content) -> some View {
        if #available(iOS 26.0, *) {
            root.safeAreaBar(edge: .top) {
                content
                    .padding(.horizontal, FamiliarSpacing.large)
                    .padding(.vertical, FamiliarSpacing.small)
            }
        } else {
            root.safeAreaInset(edge: .top, spacing: 0) {
                content
                    .padding(.horizontal, FamiliarSpacing.large)
                    .padding(.vertical, FamiliarSpacing.small)
                    .background(Color(uiColor: .systemBackground))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(FamiliarTheme.separator)
                            .frame(height: 0.5)
                    }
            }
        }
    }
}

private struct FamiliarChatTopBar: View {
    let provider: FamiliarProviderDescriptor
    let model: FamiliarModelDescriptor
    let project: FamiliarProject?
    let projects: [FamiliarProject]
    let providerOptions: [FamiliarProviderDescriptor]
    let isSending: Bool
    let isNewConversation: Bool
    let onOpenSettings: () -> Void
    let onSelectProject: (FamiliarProject?) -> Void
    let onManageProjects: () -> Void
    let onSelectModel: (String, String) -> Void
    let onConfigure: () -> Void
    let onOpenProject: () -> Void
    let onNewConversation: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: FamiliarSpacing.medium) { controls }
            } else {
                controls
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: FamiliarSpacing.medium) {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: FamiliarIconSize.standard, weight: .semibold))
                .frame(
                    width: FamiliarControlSize.minimumHitTarget,
                    height: FamiliarControlSize.minimumHitTarget
                )
            }
            .buttonStyle(.plain)
            .familiarGlassCircle(interactive: true)
            .accessibilityLabel(String(localized: "drawer.settings"))

            Menu {
                Button {
                    onSelectProject(nil)
                } label: {
                    if project == nil {
                        Label(String(localized: "conversation.ordinary", defaultValue: "Regular Chat"), systemImage: "checkmark")
                    } else {
                        Text(String(localized: "conversation.ordinary", defaultValue: "Regular Chat"))
                    }
                }
                ForEach(projects) { option in
                    Button {
                        onSelectProject(option)
                    } label: {
                        if option.id == project?.id {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                    }
                }
                Divider()
                if project != nil {
                    Button(action: onOpenProject) {
                        Label(String(localized: "project.details"), systemImage: "folder.badge.gearshape")
                    }
                }
                Button(action: onManageProjects) {
                    Label(String(localized: "project.all"), systemImage: "tray.full")
                }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: FamiliarIconSize.standard, weight: .semibold))
                    .frame(
                        width: FamiliarControlSize.minimumHitTarget,
                        height: FamiliarControlSize.minimumHitTarget
                    )
            }
            .buttonStyle(.plain)
            .familiarGlassCircle(interactive: true)
            .disabled(isSending)
            .accessibilityLabel(
                project?.name ?? String(localized: "conversation.ordinary", defaultValue: "Daily Chat")
            )

            Menu {
                if providerOptions.isEmpty {
                    Button(action: onConfigure) {
                        Label(String(localized: "empty.configure"), systemImage: "key")
                    }
                } else {
                    ForEach(providerOptions) { provider in
                        providerMenu(provider)
                    }
                }
            } label: {
                HStack(spacing: FamiliarSpacing.small) {
                    Text(model.displayName)
                        .font(FamiliarTypography.secondary.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .padding(.horizontal, FamiliarSpacing.large)
                .frame(height: FamiliarControlSize.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .familiarGlassSurface(interactive: true)
            .disabled(isSending)
            .accessibilityLabel(String(format: String(localized: "model.current"), provider.displayName, model.displayName))

            Spacer(minLength: 0)

            Button(action: onNewConversation) {
                Image(systemName: "plus")
                    .font(.system(size: FamiliarIconSize.standard, weight: .semibold))
                    .frame(
                        width: FamiliarControlSize.minimumHitTarget,
                        height: FamiliarControlSize.minimumHitTarget
                    )
            }
            .buttonStyle(.plain)
            .familiarGlassCircle(interactive: true)
            .disabled(isSending || isNewConversation)
            .accessibilityLabel(String(localized: "conversation.new"))
            .accessibilityIdentifier("chat.new")
        }
    }

    @ViewBuilder
    private func providerMenu(_ provider: FamiliarProviderDescriptor) -> some View {
        let models = models(for: provider)
        if models.isEmpty {
            Button(action: onConfigure) {
                Label(provider.displayName, systemImage: "gearshape")
            }
        } else {
            Menu(provider.displayName) {
                ForEach(models) { model in
                    Button {
                        onSelectModel(provider.id, model.id)
                    } label: {
                        if self.provider.id == provider.id && self.model.id == model.id {
                            Label(model.displayName, systemImage: "checkmark")
                        } else {
                            Text(model.displayName)
                        }
                    }
                }
            }
        }
    }

    private func models(for provider: FamiliarProviderDescriptor) -> [FamiliarModelDescriptor] {
        guard self.provider.id == provider.id,
              !provider.curatedModels.contains(where: { $0.id == model.id })
        else { return provider.curatedModels }
        return [model] + provider.curatedModels
    }
}



private struct FamiliarEmptyConversationView: View {
    let isProviderConfigured: Bool
    let onConfigure: () -> Void
    let onPrompt: (String) -> Void

    private static let allPrompts: [String] = (1...10).map {
        NSLocalizedString("empty.prompt.\($0)", comment: "")
    }

    @State private var suggestions: [String] = FamiliarEmptyConversationView.randomSuggestions()

    private static func randomSuggestions() -> [String] {
        Array(allPrompts.shuffled().prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: FamiliarSpacing.section) {
                Spacer(minLength: 94)

                ZStack {
                    Circle()
                        .fill(FamiliarTheme.brandGlow)
                        .frame(width: 76, height: 76)
                    Image(systemName: "sparkles")
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(FamiliarTheme.accent)
                }

                VStack(spacing: 8) {
                    Text(String(localized: "empty.title"))
                        .font(FamiliarTypography.screenTitle)
                    Text(String(localized: "empty.subtitle"))
                        .font(FamiliarTypography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if isProviderConfigured {
                    VStack(spacing: FamiliarSpacing.small) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            PromptSuggestion(title: suggestion, onSelect: onPrompt)
                        }
                    }
                    .frame(maxWidth: 420)
                } else {
                    Button {
                        onConfigure()
                    } label: {
                        Text(String(localized: "empty.configure"))
                            .font(FamiliarTypography.button)
                    }
                    .buttonStyle(FamiliarPillButtonStyle(prominence: .primary))
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, FamiliarSpacing.section)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct PromptSuggestion: View {
    let title: String
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(title)
        } label: {
            HStack {
                Text(title)
                    .font(FamiliarTypography.secondary.weight(.medium))
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, FamiliarSpacing.large)
            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            FamiliarTheme.elevatedFill,
            in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous)
        )
    }
}

private struct FamiliarConversationDrawer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let conversations: [FamiliarConversation]
    let projects: [FamiliarProject]
    let pinnedItems: [FamiliarPinnedItemRecord]
    let selectedConversationID: UUID?
    let safeAreaInsets: EdgeInsets
    let onSelect: (FamiliarConversation) -> Void
    let onRename: (FamiliarConversation) -> Void
    let onDelete: (FamiliarConversation) -> Void
    let onSelectProject: (FamiliarProject) -> Void
    let onAllProjects: () -> Void
    let onToggleConversationPin: (FamiliarConversation) -> Void
    let onToggleProjectPin: (FamiliarProject) -> Void

    @State private var isSearchPresented = false
    @State private var expandedProjectIDs: Set<UUID> = []
    @State private var projectLimits: [UUID: Int] = [:]
    @State private var recentLimit = 20

    private var pinnedConversationIDs: Set<UUID> {
        Set(pinnedItems.filter { $0.targetType == .conversation }.map(\.targetID))
    }

    private var pinnedProjectIDs: Set<UUID> {
        Set(pinnedItems.filter { $0.targetType == .project }.map(\.targetID))
    }

    private var pinnedConversations: [FamiliarConversation] {
        pinnedItems.compactMap { record in
            guard record.targetType == .conversation else { return nil }
            return conversations.first { $0.id == record.targetID }
        }
    }

    private var pinnedProjects: [FamiliarProject] {
        pinnedItems.compactMap { record in
            guard record.targetType == .project else { return nil }
            return projects.first { $0.id == record.targetID }
        }
    }

    private var unpinnedProjects: [FamiliarProject] {
        projects.filter { !pinnedProjectIDs.contains($0.id) }
    }

    private var ordinaryConversations: [FamiliarConversation] {
        conversations.filter { $0.project == nil && !pinnedConversationIDs.contains($0.id) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                    if !pinnedConversations.isEmpty || !pinnedProjects.isEmpty {
                        sectionTitle(String(localized: "drawer.pinned", defaultValue: "Pinned"))
                        ForEach(pinnedProjects) { project in
                            projectSection(project, isPinned: true)
                        }
                        ForEach(pinnedConversations) { conversation in
                            conversationRow(conversation, isPinned: true)
                        }
                    }

                    sectionTitle(String(localized: "project.projects"))
                    ForEach(unpinnedProjects) { project in
                        projectSection(project, isPinned: false)
                    }
                    Button(action: onAllProjects) {
                        HStack(spacing: 0) {
                            HStack(spacing: FamiliarSpacing.small) {
                                Image(systemName: "tray.full")
                                Text(String(localized: "project.all"))
                                Spacer(minLength: 4)
                                Text("\(projects.count)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.leading, FamiliarSpacing.large)
                            .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: FamiliarControlSize.minimumHitTarget)
                        }
                        .font(.body)
                        .frame(height: FamiliarControlSize.minimumHitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, FamiliarSpacing.small)

                    sectionTitle(String(localized: "drawer.recent"))
                        .padding(.top, FamiliarSpacing.small)
                    if ordinaryConversations.isEmpty {
                        Text(String(localized: "drawer.no_conversations"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, FamiliarSpacing.xLarge)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(ordinaryConversations.prefix(recentLimit))) { conversation in
                            conversationRow(conversation, isPinned: false)
                        }
                        if ordinaryConversations.count > recentLimit {
                            showMoreButton {
                                recentLimit += 20
                            }
                        }
                    }
                }
                .padding(.top, drawerHeaderHeight + FamiliarSpacing.small)
                .padding(.bottom, FamiliarSpacing.medium)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            drawerHeader
        }
        .background(FamiliarTheme.drawerFill)
        .onAppear {
            if let selected = conversations.first(where: { $0.id == selectedConversationID }),
               let projectID = selected.project?.id {
                expandedProjectIDs.insert(projectID)
            }
        }
        .sheet(isPresented: $isSearchPresented) {
            FamiliarConversationSearchView(
                conversations: conversations,
                projects: projects,
                selectedConversationID: selectedConversationID,
                onSelect: { conversation in
                    isSearchPresented = false
                    onSelect(conversation)
                },
                onSelectProject: { project in
                    isSearchPresented = false
                    onSelectProject(project)
                }
            )
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, FamiliarSpacing.xLarge)
            .padding(.top, FamiliarSpacing.medium)
            .padding(.bottom, FamiliarSpacing.xSmall)
    }

    @ViewBuilder
    private func projectSection(_ project: FamiliarProject, isPinned: Bool) -> some View {
        let projectConversations = conversations.filter {
            $0.project?.id == project.id && !pinnedConversationIDs.contains($0.id)
        }
        let isExpanded = expandedProjectIDs.contains(project.id)
        HStack(spacing: 0) {
            Button {
                setProjectExpanded(project.id, expanded: !isExpanded)
            } label: {
                HStack(spacing: FamiliarSpacing.small) {
                    Image(systemName: isPinned ? "folder.fill" : "folder")
                    Text(project.name)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(projectConversations.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .font(.body)
                .padding(.leading, FamiliarSpacing.large)
                .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                setProjectExpanded(project.id, expanded: !isExpanded)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: FamiliarControlSize.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(localized: isExpanded ? "project.collapse" : "project.expand", defaultValue: isExpanded ? "Collapse Project" : "Expand Project")
            )
        }
        .padding(.horizontal, FamiliarSpacing.small)
        .contextMenu {
            Button { onToggleProjectPin(project) } label: {
                Label(
                    String(localized: isPinned ? "drawer.unpin" : "drawer.pin", defaultValue: isPinned ? "Unpin" : "Pin"),
                    systemImage: isPinned ? "pin.slash" : "pin"
                )
            }
            Button { onSelectProject(project) } label: {
                Label(String(localized: "project.details"), systemImage: "folder.badge.gearshape")
            }
        }

        if isExpanded {
            let limit = projectLimits[project.id, default: 20]
            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                ForEach(Array(projectConversations.prefix(limit))) { conversation in
                    conversationRow(conversation, isPinned: false, isNested: true)
                }
                if projectConversations.count > limit {
                    showMoreButton {
                        projectLimits[project.id] = limit + 20
                    }
                    .padding(.leading, FamiliarSpacing.large)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func setProjectExpanded(_ projectID: UUID, expanded: Bool) {
        let update = {
            if expanded {
                expandedProjectIDs.insert(projectID)
            } else {
                expandedProjectIDs.remove(projectID)
            }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(FamiliarMotion.spatial, update)
        }
    }

    private func conversationRow(
        _ conversation: FamiliarConversation,
        isPinned: Bool,
        isNested: Bool = false
    ) -> some View {
        Button {
            onSelect(conversation)
        } label: {
            HStack(spacing: FamiliarSpacing.small) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(conversation.title)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.leading, isNested ? FamiliarSpacing.xLarge + FamiliarSpacing.large : FamiliarSpacing.large)
            .padding(.trailing, FamiliarSpacing.large)
            .frame(height: FamiliarControlSize.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(conversation.id == selectedConversationID ? .isSelected : [])
        .background(
            conversation.id == selectedConversationID
                ? Color.primary.opacity(0.075)
                : .clear,
            in: RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous)
        )
        .padding(.horizontal, FamiliarSpacing.small)
        .contextMenu {
            Button {
                onToggleConversationPin(conversation)
            } label: {
                Label(
                    String(localized: isPinned ? "drawer.unpin" : "drawer.pin", defaultValue: isPinned ? "Unpin" : "Pin"),
                    systemImage: isPinned ? "pin.slash" : "pin"
                )
            }
            Button {
                onRename(conversation)
            } label: {
                Label(String(localized: "conversation.rename"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete(conversation)
            } label: {
                Label(String(localized: "common.delete"), systemImage: "trash")
            }
        }
    }

    private func showMoreButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(String(localized: "drawer.show_more", defaultValue: "Show More"), systemImage: "chevron.down")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
                .padding(.horizontal, FamiliarSpacing.large)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, FamiliarSpacing.small)
    }

    private var drawerHeader: some View {
        HStack {
            Text(String(localized: "app.name"))
                .font(.title2.bold())
            Spacer()
            Button {
                isSearchPresented = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: FamiliarIconSize.standard, weight: .semibold))
                    .frame(
                        width: FamiliarControlSize.minimumHitTarget,
                        height: FamiliarControlSize.minimumHitTarget
                    )
            }
            .buttonStyle(.plain)
            .familiarGlassCircle(interactive: true)
            .accessibilityLabel(String(localized: "drawer.search"))
        }
        .padding(.horizontal, FamiliarSpacing.xLarge)
        .padding(.top, safeAreaInsets.top + FamiliarSpacing.small)
        .padding(.bottom, FamiliarSpacing.medium)
        .background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color(uiColor: .secondarySystemBackground).opacity(0.9), location: 0),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: safeAreaInsets.top + 56)
        }
    }

    private var drawerHeaderHeight: CGFloat {
        safeAreaInsets.top + 66
    }
}

private struct FamiliarConversationSearchView: View {
    @Environment(\.dismiss) private var dismiss

    let conversations: [FamiliarConversation]
    let projects: [FamiliarProject]
    let selectedConversationID: UUID?
    let onSelect: (FamiliarConversation) -> Void
    let onSelectProject: (FamiliarProject) -> Void

    @State private var searchText = ""
    @State private var scope = FamiliarSearchScope.all

    private var filteredConversations: [FamiliarConversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return conversations.filter { conversation in
            let inScope: Bool = switch scope {
            case .all: true
            case .ordinary: conversation.project == nil
            case .project(let projectID): conversation.project?.id == projectID
            }
            return inScope && (query.isEmpty || conversation.title.localizedCaseInsensitiveContains(query))
        }
    }

    private var filteredProjects: [FamiliarProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return projects.filter { project in
            let inScope: Bool = switch scope {
            case .all: true
            case .ordinary: false
            case .project(let projectID): project.id == projectID
            }
            return inScope && (
                query.isEmpty
                    || project.name.localizedCaseInsensitiveContains(query)
                    || project.summary.localizedCaseInsensitiveContains(query)
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(String(localized: "drawer.search.scope", defaultValue: "Scope"), selection: $scope) {
                        Text(String(localized: "drawer.search.scope.all", defaultValue: "Everything"))
                            .tag(FamiliarSearchScope.all)
                        Text(String(localized: "drawer.search.scope.ordinary", defaultValue: "Chats outside projects"))
                            .tag(FamiliarSearchScope.ordinary)
                        ForEach(projects) { project in
                            Text(project.name)
                                .tag(FamiliarSearchScope.project(project.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                if !filteredProjects.isEmpty {
                    Section(String(localized: "project.projects")) {
                        ForEach(filteredProjects) { project in
                            Button {
                                onSelectProject(project)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .foregroundStyle(.primary)
                                        if !project.summary.isEmpty {
                                            Text(project.summary)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: "folder")
                                }
                            }
                        }
                    }
                }

                if !filteredConversations.isEmpty {
                    Section(String(localized: "project.conversations")) {
                        ForEach(filteredConversations) { conversation in
                            Button {
                                onSelect(conversation)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(conversation.title)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if let project = conversation.project {
                                            Text(project.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    if conversation.id == selectedConversationID {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(FamiliarTheme.accent)
                                    }
                                }
                            }
                            .accessibilityAddTraits(conversation.id == selectedConversationID ? .isSelected : [])
                        }
                    }
                }

                if filteredProjects.isEmpty && filteredConversations.isEmpty {
                    Text(searchText.isEmpty
                         ? String(localized: "drawer.no_conversations")
                         : String(localized: "drawer.no_results"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(String(localized: "drawer.search"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
        }
        .tint(FamiliarTheme.accent)
    }
}

private enum FamiliarSearchScope: Hashable {
    case all
    case ordinary
    case project(UUID)
}
