import SwiftData
import SwiftUI
import UIKit

struct FamiliarAppShell: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.familiarCanMarkRead) private var rootCanMarkRead
    @Query private var projects: [FamiliarProject]
    @Query private var conversations: [FamiliarConversation]
    @Query private var listStates: [FamiliarConversationListStateRecord]
    @State private var coordinator: FamiliarChatSessionCoordinator
    @State private var tab = FamiliarAppTab.chats
    @State private var chatPath: [FamiliarChatRoute] = []
    @State private var filesPath = NavigationPath()
    @State private var settings = FamiliarSettingsStore.load()
    @State private var settingsRoute: FamiliarSettingsRoute?
    @State private var settingsIdentity = UUID()
    @State private var hasInitialized = false
    @State private var importingShared = false
    @State private var sharedDraft: FamiliarPreparedSharedDraft?
    @State private var errorMessage: String?
    @Binding var pendingSystemEntry: FamiliarSystemEntryRequest?

    init(dependencies: FamiliarAppDependencies, pendingSystemEntry: Binding<FamiliarSystemEntryRequest?>) {
        _coordinator = State(initialValue: FamiliarChatSessionCoordinator(dependencies: dependencies))
        _pendingSystemEntry = pendingSystemEntry
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab(String(localized: "tab.files"), systemImage: "folder", value: .files) {
                NavigationStack(path: $filesPath) { FamiliarFileLibraryView() }
            }
            Tab(String(localized: "tab.chats"), systemImage: "bubble.left.and.bubble.right", value: .chats) {
                NavigationStack(path: $chatPath) {
                    FamiliarChatsHome(coordinator: coordinator, onNavigate: navigate, onNew: newDraft, onActiveRun: openActiveRun)
                        .navigationDestination(for: FamiliarChatRoute.self, destination: destination)
                }
            }.badge(listStates.filter { !$0.isArchived && $0.isUnread }.count)
            Tab(String(localized: "tab.settings"), systemImage: "gearshape", value: .settings) {
                FamiliarSettingsView(initialSettings: settings, initialRoute: settingsRoute,
                    registry: coordinator.dependencies.registry, searchService: coordinator.dependencies.searchService,
                    pythonPackageSourceSettings: coordinator.dependencies.pythonPackageSourceSettings,
                    workspaceStore: coordinator.dependencies.workspaceStore, workspaceID: nil,
                    shellRuntimeStatus: coordinator.dependencies.shellRuntimeStatus,
                    onSaveSettings: saveSettings, isRootTab: true)
                    .id(settingsIdentity)
            }
        }
        .environment(\.familiarCanMarkRead, rootCanMarkRead && tab == .chats && sharedDraft == nil && errorMessage == nil)
        .tabBarMinimizeBehavior(.never)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task {
                await FamiliarThumbnailLoader.shared.purge()
                await coordinator.trim(retaining: retainedSessionIDs, idleLimit: 0, in: context)
            }
        }
        .task(id: sessionCacheState) {
            await coordinator.trim(retaining: retainedSessionIDs, in: context)
        }
        .task { initialize() }
        .onChange(of: pendingSystemEntry) { _, _ in handleSystemEntry() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { handleSystemEntry(); handleSharedInbox() }
            else {
                for session in coordinator.sessions.values { session.cancelFollowUps() }
                Task { await coordinator.checkpoint(in: context) }
            }
        }
        .onChange(of: tab) { _, value in
            if value == .settings { settings = FamiliarSettingsStore.load() }
            Task { await coordinator.checkpoint(in: context) }
        }
        .onChange(of: coordinator.dependencies.foregroundExecution.ownerID) { _, id in
            if id == nil { coordinator.reconcileProjects(Set(projects.map(\.id)), in: context); handleSystemEntry() }
        }
        .onChange(of: projects.map(\.id)) { _, ids in coordinator.reconcileProjects(Set(ids), in: context) }
        .onChange(of: conversations.map { "\($0.id):\($0.updatedAt.timeIntervalSince1970):\($0.title)" }) { _, _ in updateSpotlight() }
        .sheet(item: $sharedDraft, onDismiss: discardShared) { _ in
            ZStack {
                FamiliarSharedDestinationView(onSelect: importShared).disabled(importingShared)
                if importingShared { ProgressView(String(localized: "attachment.processing")).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
            }.interactiveDismissDisabled(importingShared)
        }
        .alert(String(localized: "app.name"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var retainedSessionIDs: Set<UUID> {
        Set(chatPath.compactMap { route in
            switch route { case .chat(let id), .message(let id, _): id; default: nil }
        })
    }

    private var sessionCacheState: [Set<UUID>] {
        [retainedSessionIDs, Set(coordinator.sessions.keys), Set(coordinator.sessions.compactMap { id, session in
            coordinator.canRelease(session) ? id : nil
        })]
    }

    @ViewBuilder private func destination(_ route: FamiliarChatRoute) -> some View {
        switch route {
        case .chat(let id): detail(id)
        case .message(let id, let messageID): detail(id, messageID: messageID)
        case .drafts(let projectID): FamiliarComposerDraftList(coordinator: coordinator, projectID: projectID, onOpen: { navigate(.chat($0)) })
        case .archive: FamiliarChatsHome(coordinator: coordinator, archived: true, onNavigate: navigate, onNew: newDraft)
        case .projects: FamiliarProjectTabsManager()
        case .project(let id):
            if let project = projects.first(where: { $0.id == id }) {
                FamiliarProjectDetailScreen(project: project, coordinator: coordinator, onOpen: { navigate(.chat($0)) }, onNew: newDraft)
            } else { ContentUnavailableView(String(localized: "project.unavailable"), systemImage: "folder.badge.questionmark") }
        }
    }

    private func detail(_ id: UUID, messageID: UUID? = nil) -> some View {
        FamiliarChatDestination(coordinator: coordinator, id: id, messageID: messageID,
            onBack: { if !chatPath.isEmpty { chatPath.removeLast() } },
            onNewDraft: newDraft,
            onRootSettings: { route in
                settingsRoute = route
                settingsIdentity = UUID()
                tab = .settings
            }, onConversationChanged: { newID in
                guard newID != id else { return }
                coordinator.rekey(id, to: newID)
                if !chatPath.isEmpty { chatPath.removeLast() }
                chatPath.append(.chat(newID))
            }, onOpenConversation: { navigate(.chat($0)) }, onProjectDetails: { navigate(.project($0)) })
            .toolbar(.hidden, for: .tabBar)
            .id(id)
    }

    private func openActiveRun() {
        guard let active = coordinator.activeSession else { return }
        tab = .chats
        chatPath = [.chat(active.selectedConversationID ?? active.draftConversationID)]
    }

    private func navigate(_ route: FamiliarChatRoute) {
        if case .chat(let id) = route {
            do { guard try coordinator.existingSession(id: id, in: context) != nil else { return } }
            catch { errorMessage = error.localizedDescription; return }
        } else if case .message(let id, let messageID) = route {
            do {
                guard let session = try coordinator.existingSession(id: id, in: context),
                      session.locateHistoryMessage(messageID, in: context) else { return }
            }
            catch { errorMessage = error.localizedDescription; return }
        }
        tab = .chats
        if chatPath.last != route { chatPath.append(route) }
    }
    private func newDraft(_ projectID: UUID?) {
        let id = coordinator.newDraft(projectID: projectID, in: context)
        navigate(.chat(id))
    }

    private func initialize() {
        guard !hasInitialized else { return }
        hasInitialized = true
        let recovery = FamiliarChatController(dependencies: coordinator.dependencies)
        recovery.recoverInterruptedRuns(in: context)
        do {
            if let error = coordinator.removePreSummaryHistory(in: context) { errorMessage = error; return }
            try FamiliarSkillService().installExampleIfNeeded(in: context)
            try FamiliarChatTestScenario.seedChatList(in: context)
            let paths = try FamiliarChatListStore.retainedDraftPaths(in: context)
            FamiliarAttachmentStore.pruneDrafts(keeping: paths)
        } catch { errorMessage = error.localizedDescription }
        updateSpotlight()
        handleSystemEntry()
        handleSharedInbox()
    }

    private func saveSettings(_ value: FamiliarSettings) -> FamiliarSettings {
        do {
            try FamiliarSettingsStore.save(value)
            settings = value
            // Active requests already hold a frozen settings snapshot.
            for session in coordinator.sessions.values { session.settings = value }
        } catch { errorMessage = error.localizedDescription }
        return settings
    }

    private func handleSystemEntry() {
        guard let request = pendingSystemEntry else { return }
        if request.automaticallySubmit && coordinator.dependencies.foregroundExecution.isBusy { return }
        let id: UUID
        switch request.deepLink {
        case .newDraft(let text):
            id = coordinator.newDraft(projectID: nil, in: context)
            coordinator.session(id: id, in: context).draft = text
        case .conversation(let target):
            guard conversations.contains(where: { $0.id == target }) else { pendingSystemEntry = nil; errorMessage = String(localized: "error.deep_link.conversation_not_found"); return }
            id = target
        case .run(let run):
            guard let chat = conversations.first(where: { $0.agentRuns.contains { $0.runtimeID == run.uuidString } }) else {
                pendingSystemEntry = nil; errorMessage = String(localized: "error.deep_link.run_not_found"); return
            }
            id = chat.id
        }
        pendingSystemEntry = nil
        tab = .chats; chatPath = [.chat(id)]
        let session = coordinator.session(id: id, in: context)
        Task { await session.checkpointDraft(in: context) }
        if request.automaticallySubmit { session.startSending(in: context) }
    }

    private func updateSpotlight() {
        guard !FamiliarChatTestScenario.isEnabled else { return }
        guard let values = try? FamiliarSpotlightIndexer.storedConversations(in: context) else { return }
        Task { await FamiliarSpotlightIndexer.shared.replaceConversations(values) }
    }

    private func handleSharedInbox() {
        guard !importingShared, sharedDraft == nil else { return }
        importingShared = true
        Task { @MainActor in
            defer { importingShared = false }
            do { sharedDraft = try await FamiliarSharedDraftImportService.prepareNext() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func importShared(_ destination: FamiliarSharedDestination) {
        guard let prepared = sharedDraft else { return }
        switch destination {
        case .ordinary:
            let id = coordinator.newDraft(projectID: nil, in: context)
            let session = coordinator.session(id: id, in: context)
            session.draft = prepared.text; session.draftAttachments = prepared.attachments
            Task { @MainActor in
                await session.checkpointDraft(in: context)
                guard session.errorMessage == nil else { errorMessage = session.errorMessage; return }
                FamiliarSharedDraftImportService.consume(prepared)
                sharedDraft = nil
                navigate(.chat(id))
                if let error = prepared.firstImportErrorDescription { errorMessage = error }
            }
        case .project(let project):
            importingShared = true
            Task { @MainActor in
                defer { importingShared = false }
                let service = FamiliarFileImportService()
                var firstError = prepared.firstImportErrorDescription
                for attachment in prepared.attachments {
                    do {
                        guard let url = FamiliarAttachmentStore.url(for: attachment.relativePath) else { throw FamiliarAttachmentStoreError.sourceUnavailable }
                        try await service.importDocument(from: url, into: project, in: context)
                    } catch { firstError = firstError ?? error.localizedDescription }
                }
                let text = prepared.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    do {
                        if let url = URL(string: text), url.scheme == "https", !text.contains(where: \.isWhitespace) {
                            try await service.importWebPage(from: text, into: project, in: context)
                        } else { try service.importPastedText(text, into: project, in: context) }
                    } catch { firstError = firstError ?? error.localizedDescription }
                }
                FamiliarSharedDraftImportService.consume(prepared)
                FamiliarSharedDraftImportService.discardPreparedAttachments(prepared)
                sharedDraft = nil
                navigate(.projects)
                if let firstError { errorMessage = firstError }

            }
        }
    }

    private func discardShared() {
        if let sharedDraft { FamiliarSharedDraftImportService.discardPreparedAttachments(sharedDraft); self.sharedDraft = nil }
    }
}

nonisolated struct FamiliarComposerActions: Equatable {
    let identity: UUID
    let onPolish: @MainActor () -> Void
    let onOpenSkills: @MainActor () -> Void
    let onSkillsChanged: @MainActor (Bool) -> Void
    let onUndo: (@MainActor () -> Void)?
    var onAttachmentImport: @MainActor (Bool) -> Void = { _ in }
    // Actions address the same retained controller and State storage, not streaming values.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity && (lhs.onUndo == nil) == (rhs.onUndo == nil) }
}

extension EnvironmentValues {
    @Entry var familiarCanMarkRead = false
    @Entry var familiarSkillsDismissRevision = 0
    @Entry var familiarExecutionBlocked = false
    @Entry var familiarComposerActions: FamiliarComposerActions? = nil
}

private struct FamiliarChatDestination: View {
    @Environment(\.modelContext) private var context
    let coordinator: FamiliarChatSessionCoordinator
    let id: UUID
    let messageID: UUID?
    let onBack: () -> Void
    let onNewDraft: (UUID?) -> Void
    let onRootSettings: (FamiliarSettingsRoute?) -> Void
    let onConversationChanged: (UUID) -> Void
    let onOpenConversation: (UUID) -> Void
    let onProjectDetails: (UUID) -> Void
    @State private var session: FamiliarChatController?
    @State private var unavailable = false
    var body: some View {
        Group {
            if let session = session ?? preparedSession {
                FamiliarChatView(dependencies: coordinator.dependencies, controller: session,
                    onBack: onBack, onNewDraft: onNewDraft, onRootSettings: onRootSettings,
                    initialMessageID: messageID, onConversationChanged: onConversationChanged,
                    onOpenConversation: onOpenConversation, onProjectDetails: onProjectDetails)
            } else if unavailable {
                ContentUnavailableView(String(localized: "error.deep_link.conversation_not_found"), systemImage: "bubble.left")
            } else { ProgressView() }
        }
        .task(id: id) {
            do {
                if let cached = coordinator.sessions[id] {
                    if let messageID, !cached.locateHistoryMessage(messageID, in: context) { unavailable = true; return }
                    session = cached; return
                }
                let target = id
                var descriptor = FetchDescriptor<FamiliarConversation>(predicate: #Predicate { $0.id == target })
                descriptor.fetchLimit = 1
                let hasConversation = try context.fetch(descriptor).first != nil
                let hasDraft = try FamiliarChatListStore.draft(id, in: context) != nil
                guard coordinator.sessions[id] != nil || hasConversation || hasDraft else {
                    unavailable = true; return
                }
                let loaded = coordinator.session(id: id, in: context)
                if let messageID, !loaded.locateHistoryMessage(messageID, in: context) { unavailable = true; return }
                session = loaded
            } catch { unavailable = true }
        }
    }

    private var preparedSession: FamiliarChatController? {
        guard let cached = coordinator.sessions[id] else { return nil }
        if let messageID {
            guard let target = cached.historyIndex?.messageEntries[messageID], cached.loadedHistoryAnchorID == target else { return nil }
        }
        return cached
    }
}
