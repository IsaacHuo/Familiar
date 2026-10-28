import SwiftData
import SwiftUI
import SafariServices

struct FamiliarChatView: View {
    @Environment(\.dismiss) private var dismiss
    let isHosted: Bool
    let onBack: (() -> Void)?
    let onNewDraft: ((UUID?) -> Void)?
    let onRootSettings: ((FamiliarSettingsRoute?) -> Void)?
    let initialMessageID: UUID?
    @State private var findState = FamiliarConversationFindState()
    @State private var skillsMenuOpen = false
    @State private var skillsDismissRevision = 0
    @State private var showsRewrite = false
    @State private var detailVisible = false
    @Environment(\.familiarCanMarkRead) private var rootCanMarkRead
    let onConversationChanged: ((UUID) -> Void)?
    let onOpenConversation: ((UUID) -> Void)?
    let onProjectDetails: ((UUID) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.familiarReduceMotion) private var reduceMotion
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
    @State private var speechTranscriber = FamiliarSpeechTranscriber()
    @State private var isDrawerOpen = false
    @State private var drawerDrag: CGFloat = 0
    @State private var isDragging = false
    @State private var presentedSheet: FamiliarSheetDestination?
    @State private var projectChatSheet: FamiliarSheetDestination?
    @State private var requestedProjectDetailsID: UUID?
    @State private var renameRequest: FamiliarRenameRequest?
    @State private var pendingMessageOperation: FamiliarPendingMessageOperation?
    @State private var pendingProjectEntry: (() -> Void)?
    @State private var isProjectChatVisible = false
    @State private var pendingDraftNavigation: FamiliarPendingDraftNavigation?
    @State private var conversationPendingDeletion: FamiliarConversation?
    @State private var speechBaseDraft = ""
    @State private var speechDraftID: UUID?
    @State private var configuredProviderIDs: Set<String> = []
    @State private var isImportingSharedItem = false
    @State private var pendingSharedDraft: FamiliarPreparedSharedDraft?
    @State private var confirmsClearChat = false
    @State private var speechPlayer = FamiliarReplySpeechPlayer()
    @State private var webDestination: FamiliarWebDestination?
    @State private var isComposerFocused = false
    private let toolRegistry: FamiliarToolRegistry
    private let searchService: FamiliarWebSearchService
    private let pythonPackageSourceSettings: FamiliarPythonPackageSourceSettingsStore
    private let workspaceStore: FamiliarWorkspaceStore
    private let shellRuntimeStatus: FamiliarShellRuntimeStatus
    @Binding private var pendingSystemEntry: FamiliarSystemEntryRequest?

    init(
        dependencies: FamiliarAppDependencies,
        pendingSystemEntry: Binding<FamiliarSystemEntryRequest?> = .constant(nil),
        controller: FamiliarChatController? = nil,
        onBack: (() -> Void)? = nil,
        onNewDraft: ((UUID?) -> Void)? = nil,
        onRootSettings: ((FamiliarSettingsRoute?) -> Void)? = nil,
        initialMessageID: UUID? = nil,
        onConversationChanged: ((UUID) -> Void)? = nil,
        onOpenConversation: ((UUID) -> Void)? = nil,
        onProjectDetails: ((UUID) -> Void)? = nil
    ) {
        isHosted = controller != nil
        self.onBack = onBack
        self.onNewDraft = onNewDraft
        self.onRootSettings = onRootSettings
        self.initialMessageID = initialMessageID
        self.onConversationChanged = onConversationChanged
        self.onOpenConversation = onOpenConversation
        self.onProjectDetails = onProjectDetails
        _controller = State(initialValue: controller ?? FamiliarChatController(dependencies: dependencies))
        toolRegistry = dependencies.registry
        searchService = dependencies.searchService
        pythonPackageSourceSettings = dependencies.pythonPackageSourceSettings
        workspaceStore = dependencies.workspaceStore
        shellRuntimeStatus = dependencies.shellRuntimeStatus
        _pendingSystemEntry = pendingSystemEntry
    }

    var body: some View { observedChatSurface.modifier(FamiliarMessageFileNavigation()).environment(\.familiarSendPresentation, controller.sendPresentation).environment(\.familiarSelectedTextSink, .init(controller: controller, sourceID: controller.selectedConversationID ?? controller.draftConversationID, focus: $isComposerFocused)) }

    private var chatSurface: some View {
        GeometryReader { geometry in
            chatSession(availableHeight: geometry.size.height)
        }
        .environment(\.familiarExecutionBlocked, controller.execution.isBusy && !controller.isSending)
        .sheet(isPresented: $showsRewrite, onDismiss: { if detailVisible { isComposerFocused = true }; controller.scheduleDraftCheckpoint(in: modelContext) }) {
            FamiliarDraftRewriteSheet(controller: controller, settings: controller.effectiveSettings(for: selectedProject))
        }
        .ignoresSafeArea(.keyboard, edges: isDrawerOpen || drawerDrag != 0 ? .all : [])
        .onChange(of: isDrawerOpen) { _, _ in FamiliarHaptics.shared.perform(.selection) }
        .onChange(of: isComposerFocused) { _, focused in
            // The keyboard belongs to the chat surface: acquiring focus settles any
            // interrupted drag and closes the drawer instead of leaving it stranded
            // between the drawer, the keyboard and the chat.
            if focused { closeDrawer() }
        }
    }

    private var presentedChatSurface: some View {
        chatSurface
        .sheet(item: $presentedSheet, onDismiss: {
            projectChatSheet = nil
            refreshConfiguredProviders()
        }) { destination in
            sheetContent(destination)
        }
        .sheet(item: Binding(get: { isProjectChatVisible ? nil : webDestination }, set: { webDestination = $0 })) { destination in
            FamiliarSafariView(url: destination.url) {
                webDestination = nil
            }
            .ignoresSafeArea()
            .presentationSizing(.page)
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $pendingSharedDraft, onDismiss: discardPendingSharedDraftIfNeeded) { _ in
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
                    present(.settings(nil))
                }
            }
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(controller.errorMessage ?? String(localized: "error.unknown"))
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
                set: { if !$0 { pendingDraftNavigation = nil; pendingProjectEntry = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "draft.discard.action", defaultValue: "Discard Draft"), role: .destructive) {
                performPendingDraftNavigation()
            }
            Button(String(localized: "common.cancel"), role: .cancel) { pendingProjectEntry = nil }
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
                FamiliarHaptics.shared.perform(.destructive)
                controller.delete([conversationPendingDeletion], in: modelContext)
                self.conversationPendingDeletion = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: conversationPendingDeletion?.project == nil ? "conversation.delete.ordinary_detail" : "conversation.delete.detail"))
        }
        .confirmationDialog(String(localized: "chat.clear.confirm"), isPresented: $confirmsClearChat, titleVisibility: .visible) {
            Button(String(localized: "chat.clear"), role: .destructive) {
                speechPlayer.stop()
                FamiliarHaptics.shared.perform(.destructive)
                controller.clearCurrentConversation(in: modelContext)
            }
        }
    }

    private var observedChatSurface: some View {
        presentedChatSurface
        .onAppear {
            detailVisible = true
            controller.presentationContext = modelContext
            controller.settings = FamiliarSettingsStore.load()
            if !isHosted { controller.recoverInterruptedRuns(in: modelContext) }
            if !isHosted { try? FamiliarSkillService().installExampleIfNeeded(in: modelContext) }
            if !isHosted, controller.selectedConversationID == nil,
               let first = conversations.first(where: { $0.project == nil }) {
                controller.select(first.id, in: modelContext)
            }
            FamiliarChatTestScenario.seedHistory(in: controller)
            if controller.selectedConversationID == nil, !controller.hasHistory {
                Task { @MainActor in await Task.yield(); if detailVisible { isComposerFocused = true } }
            }
            refreshConfiguredProviders()
            if !isHosted, !controller.isSending && !controller.isCompacting {
                let retained = (try? FamiliarChatListStore.retainedDraftPaths(in: modelContext)) ?? []
                FamiliarAttachmentStore.pruneDrafts(keeping: retained.union(controller.draftAttachments.map(\.relativePath)))
                if let owned = try? FamiliarFileCatalogService().ownedAttachmentPaths(in: modelContext) {
                    FamiliarAttachmentStore.pruneMessageFiles(keeping: owned.union(
                        conversations.flatMap { $0.messages.flatMap { $0.attachments.map(\.relativePath) } }
                    ))
                }
            }
            handlePendingSystemEntry()
            handleSharedInbox()
            updateSpotlightIndex(spotlightConversations)
        }
        .onChange(of: speechPlayer.errorMessage) { _, message in
            if let message { controller.errorMessage = message }
        }
        .onChange(of: controller.selectedConversationID) { _, _ in speechPlayer.stop() }
        .onChange(of: speechTranscriber.errorMessage) { _, message in
            if let message { controller.errorMessage = message }
        }
        .onDisappear {
            detailVisible = false
            controller.sendPresentation.cancel()
            isComposerFocused = false
            if !isHosted { controller.cancelFollowUps() }
            speechPlayer.stop()
            Task { await controller.checkpointDraft(in: modelContext); await speechTranscriber.stop(); await controller.checkpointDraft(in: modelContext) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { controller.cancelFollowUps() }
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
            if isSending { FamiliarHaptics.shared.perform(.send) }
            else {
                handlePendingSystemEntry()
                handleSharedInbox()
            }
        }
        .onChange(of: controller.surfaces.orderedSurfaces.first(where: { $0.kind == .runStatus })?.phase) { _, phase in
            guard detailAllowsReading, scenePhase == .active, !controller.scrollSession.isInspecting,
                  let phase, let announcement = FamiliarAccessibility.runAnnouncement(for: phase) else { return }
            FamiliarAccessibility.announce(announcement)
        }
        .onChange(of: controller.draft) { _, _ in
            controller.scheduleDraftCheckpoint(in: modelContext)
            handlePendingSystemEntry()
            handleSharedInbox()
        }
        .onChange(of: controller.draftAttachments) { _, _ in
            controller.scheduleDraftCheckpoint(in: modelContext, immediately: true)
            handlePendingSystemEntry()
            handleSharedInbox()
        }
        .onChange(of: controller.draftImages.map(\.id)) { _, _ in
            controller.scheduleDraftCheckpoint(in: modelContext, immediately: true)
            handlePendingSystemEntry()
            handleSharedInbox()
        }
        .onChange(of: controller.selectedConversationID ?? controller.draftConversationID) { _, id in onConversationChanged?(id) }
        .onChange(of: controller.selectedSkillID) { _, _ in controller.scheduleDraftCheckpoint(in: modelContext) }
        .onChange(of: controller.draftSelection) { _, _ in controller.scheduleDraftCheckpoint(in: modelContext) }
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

    // Frozen legacy drawer layout. No production route or edge target mounts this surface.
    private var frozenDrawerSurface: some View {
        GeometryReader { safeGeometry in
            let safeAreaInsets = safeGeometry.safeAreaInsets

            GeometryReader { geometry in
                // The inner geometry ignores the container safe area but still stops
                // above the keyboard, so its bottom inset is the keyboard's own
                // contribution. Padding by the difference keeps the surface above the
                // home indicator when idle and flush over the keyboard when it shows.
                let bottomInset = max(safeAreaInsets.bottom - geometry.safeAreaInsets.bottom, 0)
                let drawerWidth = geometry.size.width * (2.0 / 3.0)
                let visibleDrawerWidth = drawerOffset(width: drawerWidth)
                let drawerProgress = visibleDrawerWidth / max(drawerWidth, 1)
                let cornerRadius = FamiliarTheme.displayCornerRadius * drawerProgress
                let isDrawerVisible = drawerProgress > 0.001

                ZStack(alignment: .leading) {
                    FamiliarTheme.drawerFill
                        .ignoresSafeArea()

                    FamiliarConversationDrawer(
                        isOpen: isDrawerOpen,
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
                    // The gesture stays attached and enforces the focus policy inside
                    // `onChanged`: toggling the mask mid-drag used to remove the
                    // gesture without an end event, stranding a half-open drawer.
                    .simultaneousGesture(drawerGesture(width: drawerWidth))

                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 30)
                        .padding(.bottom, 100 + bottomInset)
                        // The edge history target must not cover the Settings
                        // button installed in the top safe-area bar.
                        .padding(.top, safeAreaInsets.top + FamiliarControlSize.minimumHitTarget + FamiliarSpacing.small * 2)
                        .frame(maxHeight: .infinity)
                        .onTapGesture {
                            isComposerFocused = false
                            setDrawerOpen(true)
                        }
                        .gesture(drawerGesture(width: drawerWidth))
                        .allowsHitTesting(!isDrawerOpen && !isComposerFocused)
                        .zIndex(100)
                        .accessibilityLabel(String(localized: "drawer.open"))
                        .accessibilityIdentifier("chat.history.open")
                        .accessibilityAddTraits(.isButton)
                }
                .background(FamiliarTheme.drawerFill.ignoresSafeArea())
            }
            .ignoresSafeArea(.container)
        }
    }

    private var spotlightConversations: [FamiliarSpotlightConversation] {
        guard !isHosted else { return [] }
        return (try? FamiliarSpotlightIndexer.storedConversations(in: modelContext)) ?? []
    }

    private var installedSkillIDs: [UUID] {
        installedSkills.map(\.id)
    }

    private var isSelectedProviderConfigured: Bool {
        FamiliarChatTestScenario.isEnabled || configuredProviderIDs.contains(controller.effectiveSettings(for: selectedProject).providerID)
    }

    private var isInNewConversation: Bool {
        !controller.isSending && !controller.isCompacting
            && !controller.hasHistory
            && controller.pendingConfirmations.isEmpty
            && controller.pendingClarifications.isEmpty
            && controller.streamingText.isEmpty
            && !controller.hasTransientActivity
    }

    private func updateSpotlightIndex(_ conversations: [FamiliarSpotlightConversation]) {
        guard !isHosted else { return }
        Task {
            await FamiliarSpotlightIndexer.shared.replaceConversations(conversations)
        }
    }

    private func handlePendingSystemEntry() {
        guard !isHosted, let request = pendingSystemEntry, !controller.isSending else { return }

        guard !hasUnsentDraft else {
            pendingSystemEntry = nil
            controller.errorMessage = String(localized: "error.system_entry.draft_pending")
            return
        }

        guard controller.openDeepLink(request.deepLink, conversations: conversations, in: modelContext) else { return }

        pendingSystemEntry = nil
        speechDraftID = nil
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
        guard !isHosted, pendingSystemEntry == nil,
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
            isImportingSharedItem = true
            Task { @MainActor in
                defer { isImportingSharedItem = false }
                let service = FamiliarFileImportService()
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

    private func present(_ destination: FamiliarSheetDestination) {
        if isHosted, case .settings(let route) = destination, let onRootSettings { presentedSheet = nil; projectChatSheet = nil; onRootSettings(route); return }
        if case .projects = destination { presentedSheet = destination }
        else if isProjectChatVisible { projectChatSheet = destination }
        else { presentedSheet = destination }
    }

    private func dismissActiveSheet() {
        if projectChatSheet != nil { projectChatSheet = nil }
        else { presentedSheet = nil }
    }

    @ViewBuilder private func sheetContent(_ destination: FamiliarSheetDestination) -> some View {
            switch destination {
            case .settings(let route):
                FamiliarSettingsView(
                    initialSettings: controller.settings,
                    initialRoute: route,
                    registry: toolRegistry,
                    searchService: searchService,
                    pythonPackageSourceSettings: pythonPackageSourceSettings,
                    workspaceStore: workspaceStore,
                    workspaceID: controller.selectedProjectID.map(FamiliarWorkScope.project)
                        ?? controller.selectedConversationID.map(FamiliarWorkScope.conversation),
                    shellRuntimeStatus: shellRuntimeStatus,
                    onSaveSettings: {
                        controller.updateSettings($0, in: modelContext)
                        refreshConfiguredProviders()
                        return controller.settings
                    }
                )
            case .terminal(let scope):
                FamiliarTerminalView(scope: scope, workspaceStore: workspaceStore)
            case .move:
                NavigationStack {
                    List {
                        Button(String(localized: "conversation.ordinary")) {
                            controller.moveCurrentConversation(to: nil, in: modelContext)
                            dismissActiveSheet()
                        }
                        ForEach(activeProjects) { project in
                        Button(project.displayName) {
                            controller.moveCurrentConversation(to: project, in: modelContext)
                            dismissActiveSheet()
                        }
                    }
                    }
                    .navigationTitle(String(localized: "chat.move"))
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { dismissActiveSheet() } } }
                }
            case .export:
                FamiliarChatExportView(conversationID: controller.selectedConversationID)
            case .usage:
                FamiliarUsageView(conversationID: controller.selectedConversationID)
            case .files:
                NavigationStack {
                    FamiliarFilesView(scope: controller.currentScope,
                                      chatID: controller.selectedConversationID)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { FamiliarDismissButton() } }
                }
            case .projects(let projectID):
                FamiliarProjectsView(
                    initialProjectID: projectID,
                    requestedProjectDetailsID: $requestedProjectDetailsID,
                    registry: toolRegistry,
                    onConversationRequest: { request, accepted in
                        handleProjectConversationRequest(request, onAccepted: accepted)
                    },
                    onDeleteConversations: { controller.delete($0, in: modelContext) },
                    onChatVisibilityChange: { isProjectChatVisible = $0 },
                    chatContent: {
                        GeometryReader { geometry in chatSession(availableHeight: geometry.size.height) }
                            .sheet(item: $projectChatSheet, onDismiss: refreshConfiguredProviders) { secondary in
                                AnyView(sheetContent(secondary))
                            }
                            .sheet(item: $webDestination) { destination in
                                FamiliarSafariView(url: destination.url) { webDestination = nil }
                                    .ignoresSafeArea().presentationSizing(.page)
                            }
                    }
                )
            }
    }

    private func discardPendingSharedDraftIfNeeded() {
        guard let pendingSharedDraft else { return }
        FamiliarSharedDraftImportService.discardPreparedAttachments(pendingSharedDraft)
        self.pendingSharedDraft = nil
    }

    @ViewBuilder
    private func mainSurface(availableHeight: CGFloat) -> some View {
        NavigationStack {
            if isProjectChatVisible { Color.clear }
            else { chatSession(availableHeight: availableHeight) }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func chatSession(availableHeight: CGFloat) -> some View {
            chatBody
                .background { FamiliarChatWallpaper() }
                .overlay {
                    if skillsMenuOpen {
                        Color.clear.contentShape(Rectangle()).onTapGesture { skillsDismissRevision += 1 }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FamiliarChatInputDock(
                        controller: controller,
                        skills: installedSkills.map {
                            FamiliarSkillMenuItem(
                                id: $0.id,
                                stableID: $0.stableID,
                                name: $0.name,
                                detail: $0.descriptionText
                            )
                        },
                        isListening: speechTranscriber.isListening,
                        focus: $isComposerFocused,
                        availableHeight: availableHeight,
                        onSpeech: toggleSpeech,
                        onSend: {
                            speechDraftID = nil
                            Task { await speechTranscriber.stop() }
                            isComposerFocused = false
                            if controller.isSending {
                                controller.cancelSending(in: modelContext)
                            } else {
                                controller.startSending(in: modelContext)
                            }
                        },
                        onStop: {
                            isComposerFocused = false
                            controller.cancelSending(in: modelContext)
                        }
                    )
                    .environment(\.familiarExecutionBlocked, controller.execution.isBusy && !controller.isSending)
                    .environment(\.familiarComposerActions, composerActions)
                    .environment(\.familiarSkillsDismissRevision, skillsDismissRevision)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if findState.isPresented, let id = controller.selectedConversationID {
                        FamiliarConversationFindBar(conversationID: id, state: findState)
                    }
                }
                .environment(\.familiarChatScrollSession, controller.scrollSession)
                .modifier(FamiliarChatNavigationChrome(bar: topBar, hosted: isHosted))
    }

    @ViewBuilder
    private var chatBody: some View {
        if !controller.isSending, !controller.isCompacting,
           !controller.hasHistory,
           controller.pendingConfirmations.isEmpty,
           controller.pendingClarifications.isEmpty,
           controller.streamingText.isEmpty,
           controller.streamingReasoningSummary.isEmpty,
           !controller.hasTransientActivity {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(controller.selectedConversationID)
        } else {
            FamiliarMessageTimeline(
                messages: controller.messages,
                modelSwitches: controller.modelSwitches,
                agentRuns: controller.agentRuns,
                liveController: controller,
                availableUndoKeys: controller.availableUndoKeys,
                completedUndoKeys: controller.completedUndoKeys,
                onInsertPrompt: { prompt in
                    guard controller.messageEdit == nil || !controller.isSending else { return }
                    controller.draftSelection = nil
                    controller.draft = prompt
                    isComposerFocused = true
                },
                onUndo: { runID, toolCallID in
                    controller.undo(runID: runID, toolCallID: toolCallID, in: modelContext)
                },
                onEdit: { message in
                    if controller.prepareToEdit(message, in: modelContext) { isComposerFocused = true }
                },
                onRetry: { pendingMessageOperation = .retry($0) },
                onRetryRecovery: { controller.retry(runID: $0, in: modelContext) },
                scrollSession: controller.scrollSession,
                initialMessageID: initialMessageID, findState: findState,
                historyIndex: controller.historyIndex,
                onLoadHistory: { controller.historyIndex == nil || controller.loadHistory(anchor: $0, in: modelContext) }
            )
            .id(controller.selectedConversationID)
            .environment(\.familiarCanMarkRead, detailAllowsReading)
            .environment(\.openURL, OpenURLAction { url in
                guard FamiliarConversationURLRouter.shouldOpenInApp(url) else {
                    return .systemAction
                }
                webDestination = FamiliarWebDestination(url: url)
                return .handled
            })
        }
    }

    private var detailAllowsReading: Bool {
        rootCanMarkRead && !findState.isPresented && detailVisible && presentedSheet == nil &&
            projectChatSheet == nil && webDestination == nil && !showsRewrite && controller.errorMessage == nil &&
            pendingMessageOperation == nil && !confirmsClearChat
    }

    private var composerActions: FamiliarComposerActions {
        let undo: (@MainActor () -> Void)?
        if controller.draftRewriteUndo?.applied == controller.draft { undo = { controller.undoDraftRewrite() } }
        else { undo = nil }
        return .init(identity: controller.executionID,
            onPolish: { showsRewrite = true },
            onOpenSkills: { present(.settings(.skills)) }, onSkillsChanged: { skillsMenuOpen = $0 }, onUndo: undo,
            onAttachmentImport: { started in
                controller.pendingAttachmentImports = max(0, controller.pendingAttachmentImports + (started ? 1 : -1))
                if !started { controller.scheduleDraftCheckpoint(in: modelContext, immediately: true) }
            })
    }

    private var topBar: FamiliarChatTopBar {
        let project = selectedProject
        let effective = controller.effectiveSettings(for: project)
        let providers = FamiliarProviderCatalog.builtIn.filter { configuredProviderIDs.contains($0.id) }
        let title = conversations.first { $0.id == controller.selectedConversationID }?.title ?? String(localized: "app.name")
        return FamiliarChatTopBar(
            title: title,
            provider: effective.selectedProvider,
            model: effective.selectedModel,
            project: project,
            providerOptions: providers,
            isSending: controller.isSending || controller.isCompacting || controller.execution.isBusy,
            isNewConversation: isInNewConversation,
            onOpenSettings: { if isHosted { onBack?() } else { present(.settings(nil)) } },
            isHosted: isHosted,
            onSearch: {
                isComposerFocused = false
                skillsDismissRevision += 1
                findState.isPresented = true
            },
            onCompact: { controller.compactCurrentConversation(in: modelContext) },
            canCompact: controller.durableMessageCount > 4,
            onClear: { confirmsClearChat = true },
            onFiles: { present(.files) },
            onTerminal: { present(.terminal(controller.currentScope)) },
            onUsage: { present(.usage) },
            onFork: {
                let navigation = FamiliarPendingDraftNavigation.fork
                if hasUnsentDraft { pendingDraftNavigation = navigation }
                else { perform(navigation) }
            },
            onMove: { present(.move) },
            onExport: { present(.export) },
            onSpeak: {
                Task { @MainActor in
                    await speechTranscriber.stop()
                    if speechPlayer.isSpeaking { speechPlayer.stop() }
                    else if let id = controller.selectedConversationID {
                        do {
                            if let reply = try FamiliarChatHistoryStore.latestAssistantMessage(conversationID: id, in: modelContext) {
                                speechPlayer.speak(reply.content)
                            }
                        } catch { controller.errorMessage = error.localizedDescription }
                    }
                }
            },
            isSpeaking: speechPlayer.isSpeaking,
            onSelectModel: { providerID, modelID in
                controller.selectModel(providerID: providerID, modelID: modelID, in: modelContext)
            },
            onFollowDefaultModel: { controller.followDefaultModel(in: modelContext) },
            onConfigure: { present(.settings(nil)) },
            onOpenProject: {
                guard let project else { return }
                if isHosted { onProjectDetails?(project.id); return }
                if isProjectChatVisible { requestedProjectDetailsID = project.id }
                else { presentedSheet = .projects(project.id) }
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
        if isHosted, let onNewDraft {
            Task { await controller.checkpointDraft(in: modelContext); onNewDraft(project?.id) }
            return
        }
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

    private func handleProjectConversationRequest(_ request: FamiliarProjectConversationRequest, onAccepted: @escaping () -> Void) {
        if isHosted {
            Task { @MainActor in
                await controller.checkpointDraft(in: modelContext)
                presentedSheet = nil
                projectChatSheet = nil
                switch request {
                case .open(let id): onOpenConversation?(id)
                case .create(let id): onNewDraft?(id)
                }
            }
            return
        }
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
            pendingProjectEntry = onAccepted
            pendingDraftNavigation = navigation
        } else {
            perform(navigation)
            onAccepted()
        }
    }

    private func performPendingDraftNavigation() {
        guard let pendingDraftNavigation else { return }
        self.pendingDraftNavigation = nil
        FamiliarHaptics.shared.perform(.destructive)
        let accepted = pendingProjectEntry
        pendingProjectEntry = nil
        perform(pendingDraftNavigation)
        if !controller.isSending { accepted?() }
    }

    private func perform(_ navigation: FamiliarPendingDraftNavigation) {
        guard !controller.isSending else {
            controller.errorMessage = String(localized: "error.deep_link.busy")
            return
        }
        speechDraftID = nil
        Task { await speechTranscriber.stop() }
        switch navigation {
        case .fork:
            controller.forkCurrentConversation(in: modelContext)
            isComposerFocused = false
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
                if !isDragging {
                    // A drag that starts while the composer owns the keyboard would
                    // fight text selection; the swipe is ignored until it ends.
                    guard !isComposerFocused else { return }
                    isComposerFocused = false
                }
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical || isDragging else { return }
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
                    withAnimation(FamiliarMotion.interactiveSpring) {
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
        // Clearing the in-flight drag here is what makes the state recoverable: an
        // interrupted gesture may never deliver its end event, and a stale
        // translation must not survive a programmatic open or close.
        isDragging = false
        if reduceMotion {
            drawerDrag = 0
            isDrawerOpen = isOpen
        } else {
            withAnimation(FamiliarMotion.interactiveSpring) {
                drawerDrag = 0
                isDrawerOpen = isOpen
            }
        }
    }

    private func toggleSpeech() {
        speechPlayer.stop()
        if !speechTranscriber.isListening {
            speechBaseDraft = controller.draft
            speechDraftID = UUID()
        }
        let expectedDraft = speechDraftID
        Task {
            await speechTranscriber.toggle { transcript in
                guard speechDraftID == expectedDraft else { return }
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

private enum FamiliarSheetDestination: Identifiable {
    case settings(FamiliarSettingsRoute?)
    case projects(UUID?)
    case files
    case terminal(FamiliarWorkScope)
    case usage
    case move
    case export

    var id: String {
        switch self {
        case .move: "move"
        case .export: "export"
        case .usage: "usage"
        case .files: "files"
        case .terminal(let id): "terminal-\(id)"
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
    case fork
    case select(FamiliarConversation)
    case newConversation(FamiliarProject?)

    var id: String {
        switch self {
        case .fork: "fork"
        case .select(let conversation): "select-\(conversation.id.uuidString)"
        case .newConversation(let project): "new-\(project?.id.uuidString ?? "ordinary")"
        }
    }
}

private enum FamiliarPendingMessageOperation: Identifiable {
    case retry(FamiliarMessageSnapshot)

    var id: String {
        switch self {
        case .retry(let message): "retry-\(message.id.uuidString)"
        }
    }

    var actionTitle: String {
        switch self {
        case .retry: String(localized: "message.retry")
        }
    }
}



private struct FamiliarChatNavigationChrome: ViewModifier {
    let bar: FamiliarChatTopBar
    let hosted: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if hosted {
            content
                .toolbar(.visible, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .scrollEdgeEffectHidden(true, for: .top)
                .toolbar {
                    ToolbarItem(placement: .principal) { bar.titleView }
                    ToolbarItem(placement: .topBarTrailing) { bar.actionMenu }
                }
        } else {
            content.modifier(FamiliarTopBarInstaller(content: bar)).toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct FamiliarTopBarInstaller<Bar: View>: ViewModifier {
    let content: Bar

    func body(content root: Content) -> some View {
        root.safeAreaBar(edge: .top) {
            content
                .padding(.horizontal, FamiliarSpacing.large)
                .padding(.vertical, FamiliarSpacing.small)
        }
    }
}

private struct FamiliarChatTopBar: View {
    private let toolbarIconSize = FamiliarIconSize.prominent
    let title: String
    let provider: FamiliarProviderDescriptor
    let model: FamiliarModelDescriptor
    let project: FamiliarProject?
    let providerOptions: [FamiliarProviderDescriptor]
    let isSending: Bool
    let isNewConversation: Bool
    let onOpenSettings: () -> Void
    var isHosted: Bool = false
    let onSearch: () -> Void
    let onCompact: () -> Void
    let canCompact: Bool
    let onClear: () -> Void
    let onFiles: () -> Void
    let onTerminal: () -> Void
    let onUsage: () -> Void
    let onFork: () -> Void
    let onMove: () -> Void
    let onExport: () -> Void
    let onSpeak: () -> Void
    let isSpeaking: Bool
    let onSelectModel: (String, String) -> Void
    let onFollowDefaultModel: () -> Void
    let onConfigure: () -> Void
    let onOpenProject: () -> Void
    let onNewConversation: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: FamiliarSpacing.medium) { controls }
            .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: FamiliarSpacing.small) {
            Button(action: onOpenSettings) {
                Image(systemName: isHosted ? "chevron.left" : "gearshape")
                    .font(.system(size: toolbarIconSize, weight: .semibold))
                .frame(
                    width: FamiliarControlSize.minimumHitTarget,
                    height: FamiliarControlSize.minimumHitTarget
                )
            }
            .buttonStyle(FamiliarIconButtonStyle())
            .familiarGlassCircle(interactive: true)
            .accessibilityLabel(String(localized: isHosted ? "common.back" : "drawer.settings"))
            .accessibilityIdentifier(isHosted ? "chat.back" : "chat.settings")

            Spacer(minLength: 0)
            titleView
            Spacer(minLength: 0)
            actionMenu
        }
    }

    /// Telegram ChatTitleView: 17pt semibold title and 13pt subtitle.
    /// The real current model replaces a peer's online status.
    var titleView: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            Text(model.displayName).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.title")
    }

    private var modelMenu: some View {
        Menu {
            if project?.modelIDOverride != nil {
                Button(String(localized: "project.model.follow_global"), action: onFollowDefaultModel)
            }
            if providerOptions.isEmpty {
                Button(action: onConfigure) { Label(String(localized: "empty.configure"), systemImage: "key") }
            } else {
                ForEach(providerOptions) { provider in providerMenu(provider) }
            }
        } label: {
            Label(String(localized: "model.current.entry"), systemImage: "cpu")
        }
        .disabled(isSending)
        .accessibilityIdentifier("chat.model")
    }

    var actionMenu: some View {
Menu {
                    Button(action: onNewConversation) {
                        Label(String(localized: "conversation.new"), systemImage: "square.and.pencil")
                    }
                    .disabled(isSending || isNewConversation)
                    .accessibilityIdentifier("chat.new")
                    Divider()
                    modelMenu
                    Button(action: onSearch) { Label(String(localized: "local_search.find"), systemImage: "magnifyingglass") }
                        .disabled(isNewConversation).accessibilityIdentifier("chat.find")
                    Divider()
                    if project != nil { Button(action: onOpenProject) { Label(String(localized: "project.details"), systemImage: "folder.badge.gearshape") }.accessibilityIdentifier("chat.projectDetails") }
                    Button(action: onFork) { Label(String(localized: "chat.branch"), systemImage: "arrow.branch") }.disabled(isSending || isNewConversation)
                    Button(action: onMove) { Label(String(localized: "chat.move"), systemImage: "folder") }.disabled(isSending || isNewConversation)
                    Button(action: onExport) { Label(String(localized: "chat.export"), systemImage: "square.and.arrow.up") }.disabled(isNewConversation)
                    Button(action: onCompact) { Label(String(localized: "chat.compact"), systemImage: "arrow.down.right.and.arrow.up.left") }.disabled(isSending || !canCompact)
                    Button(role: .destructive, action: onClear) { Label(String(localized: "chat.clear"), systemImage: "trash") }.disabled(isSending || isNewConversation)
                    Divider()
                    Button(action: onTerminal) {
                        Label(String(localized: "terminal.title", defaultValue: "Terminal"), systemImage: "terminal")
                    }.disabled(isSending).accessibilityIdentifier("chat.terminal")
                    Button(action: onFiles) { Label(String(localized: "chat.files"), systemImage: "folder") }
                    Button(action: onSpeak) { Label(String(localized: isSpeaking ? "chat.speech.stop" : "chat.speech"), systemImage: "speaker.wave.2") }.disabled(isNewConversation)
                    Divider()
                    Button(action: onUsage) { Label(String(localized: "usage.title"), systemImage: "number") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel(String(localized: "chat.more"))
                .accessibilityIdentifier("chat.more")
                .buttonStyle(.plain)
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



private struct FamiliarConversationDrawer: View {
    @Environment(\.familiarReduceMotion) private var reduceMotion

    let isOpen: Bool
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
    @State private var conversationList: ConversationListDestination?
    private struct ConversationListDestination: Identifiable {
        let projectID: UUID?
        var id: String { projectID?.uuidString ?? "ordinary" }
    }
    private func ordered(_ chats: [FamiliarConversation]) -> [FamiliarConversation] {
        chats.sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
    }


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
                                    .font(FamiliarTypography.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.leading, FamiliarSpacing.large)
                            .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget)
                            Image(systemName: "chevron.right")
                                .font(FamiliarTypography.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: FamiliarControlSize.minimumHitTarget)
                        }
                        .font(FamiliarTypography.body)
                        .frame(height: FamiliarControlSize.minimumHitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, FamiliarSpacing.small)

                    sectionTitle(String(localized: "conversation.ordinary"))
                    let ordinary = ordered(conversations.filter { $0.project == nil && !pinnedConversationIDs.contains($0.id) })
                    ForEach(Array(ordinary.prefix(20))) { conversation in
                        conversationRow(conversation, isPinned: false)
                    }
                    if ordinary.count > 20 { showMoreButton { conversationList = .init(projectID: nil) } }


                }
                .padding(.top, drawerHeaderHeight + FamiliarSpacing.small)
                .padding(.bottom, FamiliarSpacing.medium)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            drawerHeader
        }
        .background(FamiliarTheme.drawerFill)
        .onAppear { expandedProjectIDs.removeAll() }
        .onDisappear { expandedProjectIDs.removeAll() }
        .onChange(of: isOpen) { _, _ in expandedProjectIDs.removeAll() }
        .sheet(item: $conversationList) { destination in
            NavigationStack {
                FamiliarProjectConversationsView(
                    conversations: ordered(conversations.filter { $0.project?.id == destination.projectID }),
                    onSelect: { chat in conversationList = nil; onSelect(chat) },
                    onDeleteAll: nil,
                    title: destination.projectID == nil ? String(localized: "conversation.ordinary") : String(localized: "project.conversations"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { FamiliarDismissButton() } }
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
            .font(FamiliarTypography.sectionTitle.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, FamiliarSpacing.xLarge)
            .padding(.top, FamiliarSpacing.medium)
            .padding(.bottom, FamiliarSpacing.xSmall)
    }

    @ViewBuilder
    private func projectSection(_ project: FamiliarProject, isPinned: Bool) -> some View {
        let projectConversations = ordered(conversations.filter {
            $0.project?.id == project.id && !pinnedConversationIDs.contains($0.id)
        })
        let isExpanded = expandedProjectIDs.contains(project.id)
        HStack(spacing: 0) {
            Button {
                setProjectExpanded(project.id, expanded: !isExpanded)
            } label: {
                HStack(spacing: FamiliarSpacing.small) {
                    Image(systemName: isPinned ? "folder.fill" : "folder")
                    Text(project.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(projectConversations.count)")
                        .font(FamiliarTypography.caption)
                        .foregroundStyle(.tertiary)
                }
                .font(FamiliarTypography.body)
                .padding(.leading, FamiliarSpacing.large)
                .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                setProjectExpanded(project.id, expanded: !isExpanded)
            } label: {
                Image(systemName: "chevron.right")
                    .font(FamiliarTypography.caption.weight(.bold))
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
            let limit = 5
            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                ForEach(Array(projectConversations.prefix(limit))) { conversation in
                    conversationRow(conversation, isPinned: false, isNested: true)
                }
                if projectConversations.count > limit {
                    showMoreButton {
                        conversationList = .init(projectID: project.id)
                    }
                    .padding(.leading, FamiliarSpacing.large)
                }
            }
            .transition(reduceMotion ? .opacity : FamiliarMotion.softRise)
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
            withAnimation(FamiliarMotion.emphasized, update)
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
                        .font(FamiliarTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Text(conversation.title)
                    .font(FamiliarTypography.body)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.leading, isNested ? FamiliarSpacing.xLarge + FamiliarSpacing.large : FamiliarSpacing.large)
            .padding(.trailing, FamiliarSpacing.large)
            .frame(height: FamiliarControlSize.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.history.row.\(conversation.id.uuidString)")
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
                .font(FamiliarTypography.secondary.weight(.medium))
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
                    .font(.system(size: FamiliarIconSize.prominent, weight: .regular))
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
                    || project.displayName.localizedCaseInsensitiveContains(query)
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
                            Text(project.displayName)
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
                                    VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                                        Text(project.displayName)
                                            .foregroundStyle(.primary)
                                        if !project.summary.isEmpty {
                                            Text(project.summary)
                                                .font(FamiliarTypography.caption)
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
                                HStack(spacing: FamiliarSpacing.small) {
                                    VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                                        Text(conversation.title)
                                            .font(FamiliarTypography.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if let project = conversation.project {
                                            Text(project.displayName)
                                                .font(FamiliarTypography.caption)
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
                        .font(FamiliarTypography.secondary)
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
