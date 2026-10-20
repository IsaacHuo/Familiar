import SwiftData
import SwiftUI
import Observation

struct FamiliarChatsHome: View {
    @Environment(\.modelContext) private var context
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @Query(sort: \FamiliarConversation.updatedAt, order: .reverse) private var conversations: [FamiliarConversation]
    @Query(sort: \FamiliarProject.updatedAt, order: .reverse) private var projects: [FamiliarProject]
    @Query private var states: [FamiliarConversationListStateRecord]
    @Query(sort: \FamiliarComposerDraftRecord.updatedAt, order: .reverse) private var drafts: [FamiliarComposerDraftRecord]
    @Query(sort: \FamiliarPinnedItemRecord.pinnedAt, order: .reverse) private var pins: [FamiliarPinnedItemRecord]
    @AppStorage("familiar.project-tabs.order") private var projectOrder = ""
    let coordinator: FamiliarChatSessionCoordinator
    var archived = false
    let onNavigate: (FamiliarChatRoute) -> Void
    let onNew: (UUID?) -> Void
    var onActiveRun: (() -> Void)? = nil
    @State private var filter = FamiliarChatListFilter.recent
    @State private var search = FamiliarHomeSearchState()
    @State private var searching = false
    @State private var searchDestination: FamiliarChatRoute?
    @State private var editing = false
    @State private var selection: Set<UUID> = []
    @State private var pendingDelete: Set<UUID> = []
    @State private var renameID: UUID?
    @State private var renameText = ""
    @State private var moving: FamiliarMoveConversationDestination?
    @State private var errorMessage: String?

    private var orderedProjects: [FamiliarProject] {
        let ids = projectOrder.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        let order = ids.enumerated().reduce(into: [UUID: Int]()) { values, entry in
            if values[entry.element] == nil { values[entry.element] = entry.offset }
        }
        return projects.filter { $0.status == .active }.sorted {
            let lhs = order[$0.id] ?? Int.max, rhs = order[$1.id] ?? Int.max
            if lhs != rhs { return lhs < rhs }
            return $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
    }

    private var rows: [FamiliarConversationListSnapshot] {
        let stateByID = Dictionary(uniqueKeysWithValues: states.map { ($0.conversationID, $0) })
        let draftByID = Dictionary(uniqueKeysWithValues: drafts.compactMap { draft in draft.conversationID.map { ($0, draft) } })
        let pinOrder = pins.enumerated().reduce(into: [UUID: Int]()) { result, entry in
            if entry.element.targetType == .conversation, result[entry.element.targetID] == nil { result[entry.element.targetID] = entry.offset }
        }
        let pinned = Set(pinOrder.keys)
        let active = coordinator.activeSession
        return conversations.compactMap { conversation in
            let state = stateByID[conversation.id]
            guard (state?.isArchived ?? false) == archived else { return nil }
            let draft = draftByID[conversation.id]
            let running = active?.selectedConversationID == conversation.id
            let attention = running && (!(active?.pendingConfirmations.isEmpty ?? true) || !(active?.pendingClarifications.isEmpty ?? true))
            let preview: String
            if let draft { preview = String(localized: "chat.draft") + " · " + FamiliarChatListStore.draftSummary(draft) }
            else if attention { preview = String(localized: "chat.needs_attention") }
            else if running { preview = String(localized: "chat.running") }
            else { preview = state?.preview ?? "…" }
            return .init(id: conversation.id, title: conversation.title, preview: preview,
                projectName: conversation.project?.displayName,
                date: max(draft?.updatedAt ?? .distantPast, state?.latestActivityAt ?? conversation.updatedAt),
                isPinned: pinned.contains(conversation.id), isUnread: state?.isUnread ?? false,
                isArchived: archived, hasDraft: draft != nil, isRunning: running,
                needsAttention: attention, hasFailure: state?.hasFailure ?? false, projectID: conversation.project?.id)
        }.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.isPinned {
                let left = pinOrder[lhs.id] ?? Int.max
                let right = pinOrder[rhs.id] ?? Int.max
                if left != right { return left < right }
            }
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var body: some View {
        let entries = rows
        let filters: [FamiliarChatListFilter] = [.recent] + orderedProjects.map { .project($0.id) }
        let grouped = Dictionary(grouping: entries.compactMap { row in row.projectID.map { ($0, row) } }, by: { $0.0 })
        let lists = Dictionary(uniqueKeysWithValues: filters.map { item in
            switch item {
            case .recent: return (item, entries)
            case .project(let id): return (item, grouped[id]?.map { $0.1 } ?? [])
            }
        })
        let special = Dictionary(uniqueKeysWithValues: filters.compactMap { item in
            hasSpecialRows(for: item) ? (item, AnyView(specialRows(for: item))) : nil
        })
        FamiliarChatProjectPager(rowsByFilter: lists, projects: orderedProjects, filter: $filter,
            editing: editing, selection: $selection,
            counts: projectUnreadCounts,
            specialRowsByFilter: special, specialRowsRevision: specialRevision,
            onManage: { onNavigate(.projects) },
            onOpen: { onNavigate(.chat($0)) }, onAction: perform, preview: previewMessages)
        .navigationTitle(archived ? String(localized: "chat.archived") : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: editing ? "common.done" : "common.edit")) { searching = false; search.query = ""; editing.toggle(); selection.removeAll() }
                    .accessibilityIdentifier("chats.edit")
            }
            if let active = coordinator.activeSession, let onActiveRun {
                ToolbarItem(placement: .principal) {
                    Button(action: onActiveRun) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(String(localized: active.pendingConfirmations.isEmpty && active.pendingClarifications.isEmpty ? "chat.running" : "chat.needs_attention"))
                                .font(.subheadline.weight(.medium)).lineLimit(1)
                        }.padding(.horizontal, 12).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain).familiarGlassSurface(interactive: true)
                    .accessibilityIdentifier("chat.activeRun")
                }.sharedBackgroundVisibility(.hidden)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { searching = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel(String(localized: "drawer.search"))
                    .accessibilityIdentifier("chats.search.open").disabled(editing)
                Button { if case .project(let id) = filter { onNew(id) } else { onNew(nil) } } label: {
                    Image(systemName: "square.and.pencil")
                }.accessibilityLabel(String(localized: "conversation.new")).accessibilityIdentifier("chats.new")
            }
        }
        .sheet(isPresented: $searching, onDismiss: {
            search.query = ""
            if let route = searchDestination { searchDestination = nil; onNavigate(route) }
        }) {
            FamiliarHomeSearchPage(state: search, conversationIDs: searchConversationIDs,
                onOpen: { searchDestination = .chat($0); searching = false },
                onMessage: { searchDestination = .message($0, $1); searching = false })
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if editing {
                HStack {
                    Button(String(localized: "chat.mark_read")) { bulk(.read) }
                    Spacer()
                    Button(String(localized: archived ? "chat.unarchive" : "chat.archive")) { bulk(.archive) }
                    Spacer()
                    Button(String(localized: "common.delete"), role: .destructive) { pendingDelete = selection }
                }.font(.subheadline).padding().background(.bar).disabled(selection.isEmpty)
            }
        }
        .alert(String(localized: "conversation.rename.title"), isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField(String(localized: "conversation.rename.placeholder"), text: $renameText)
            Button(String(localized: "common.save")) { rename() }
            Button(String(localized: "common.cancel"), role: .cancel) { renameID = nil }
        }
        .alert(String(localized: "app.name"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog(String(localized: "conversation.delete.title"), isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }), titleVisibility: .visible) {
            Button(String(localized: "common.delete"), role: .destructive) { deleteSelected() }
            Button(String(localized: "common.cancel"), role: .cancel) { pendingDelete = [] }
        }
        .sheet(item: $moving) { destination in
            NavigationStack {
                List {
                    Button(String(localized: "conversation.ordinary")) { move(destination.id, to: nil) }
                    ForEach(orderedProjects) { project in Button(project.displayName) { move(destination.id, to: project) } }
                }.navigationTitle(String(localized: "chat.move"))
                    .toolbar { ToolbarItem(placement: .cancellationAction) { FamiliarDismissButton() } }
            }
        }
        .task { initializeMetadata() }
        .onChange(of: filter) { _, _ in selection.removeAll() }
        .onChange(of: orderedProjects.map(\.id)) { _, ids in
            if case .project(let id) = filter, !ids.contains(id) { filter = .recent }
        }
        .accessibilityIdentifier(archived ? "chats.archive" : "chats.home")
    }

    private var projectUnreadCounts: [UUID: Int] {
        let unreadIDs = Set(states.filter { $0.isArchived == archived && $0.isUnread }.map(\.conversationID))
        return conversations.reduce(into: [:]) { counts, chat in
            if unreadIDs.contains(chat.id), let id = chat.project?.id { counts[id, default: 0] += 1 }
        }
    }

    private func hasSpecialRows(for filter: FamiliarChatListFilter) -> Bool {
        !archived && (states.contains(where: \.isArchived) || drafts.contains { draft in
            guard draft.conversationID == nil else { return false }
            if case .project(let id) = filter { return draft.projectID == id }
            return true
        })
    }

    private func specialRows(for filter: FamiliarChatListFilter) -> some View {
        VStack(spacing: 0) {
            if !archived {
                let visibleDrafts = drafts.filter { draft in
                    guard draft.conversationID == nil else { return false }
                    if case .project(let id) = filter { return draft.projectID == id }
                    return true
                }
                if !visibleDrafts.isEmpty {
                    Button {
                        if case .project(let id) = filter { onNavigate(.drafts(id)) }
                        else { onNavigate(.drafts(nil)) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.pencil").foregroundStyle(FamiliarTheme.accent)
                                .frame(width: 54, height: 50)
                            Text(String(localized: "chat.drafts")).font(.headline)
                            Spacer()
                            Text(visibleDrafts.count, format: .number).font(.subheadline).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(.horizontal).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("chats.drafts")
                }
                if states.contains(where: \.isArchived) {
                    Button { onNavigate(.archive) } label: {
                        HStack {
                            Image(systemName: "archivebox.fill").foregroundStyle(.white).frame(width: 54, height: 54).background(.gray.gradient, in: Circle())
                            Text(String(localized: "chat.archived")).font(.headline)
                            Spacer()
                            let unread = states.filter { $0.isArchived && $0.isUnread }.count
                            if unread > 0 { Text(unread, format: .number).font(.caption.weight(.semibold)).padding(6).background(FamiliarTheme.accentTint, in: Capsule()) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(.horizontal).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("chats.archived")
                }
            }
        }
    }

    private var searchConversationIDs: [UUID] {
        let archivedIDs = Set(states.filter(\.isArchived).map(\.conversationID))
        return conversations.filter { chat in
            guard archivedIDs.contains(chat.id) == archived else { return false }
            if case .project(let id) = filter { return chat.project?.id == id }
            return true
        }.map(\.id).sorted { $0.uuidString < $1.uuidString }
    }

    private var specialRevision: Int {
        var hash = Hasher()
        for draft in drafts { hash.combine(draft.id); hash.combine(draft.projectID); hash.combine(draft.updatedAt) }
        for state in states { hash.combine(state.conversationID); hash.combine(state.isArchived); hash.combine(state.isUnread) }
        return hash.finalize()
    }

    private func initializeMetadata() {
        do {
            let known = Set(states.map(\.conversationID))
            for conversation in conversations where !known.contains(conversation.id) {
                _ = try FamiliarChatListStore.state(for: conversation, in: context)
            }
            if context.hasChanges { try context.save() }
            if projectOrder.isEmpty {
                let pinned = pins.filter { $0.targetType == .project }.map(\.targetID)
                let remainder = orderedProjects.map(\.id).filter { !pinned.contains($0) }
                projectOrder = (pinned + remainder).map(\.uuidString).joined(separator: ",")
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func perform(_ id: UUID, _ action: FamiliarConversationListAction) {
        guard let chat = conversations.first(where: { $0.id == id }) else { return }
        do {
            let state = try FamiliarChatListStore.state(for: chat, in: context)
            switch action {
            case .pin: _ = try FamiliarPinService().toggle(.conversation, targetID: id, in: context)
            case .read:
                if state.isUnread { FamiliarChatListStore.markRead(state) } else { state.manuallyUnread = true }
            case .archive: state.isArchived.toggle()
            case .rename: renameID = id; renameText = chat.title
            case .move: moving = .init(id: id)
            case .delete: pendingDelete = [id]
            }
            if context.hasChanges { try context.save() }
        } catch { context.rollback(); errorMessage = error.localizedDescription }
    }

    private func bulk(_ action: FamiliarConversationListAction) {
        for id in selection {
            guard let chat = conversations.first(where: { $0.id == id }) else { continue }
            do {
                let state = try FamiliarChatListStore.state(for: chat, in: context)
                switch action { case .read: FamiliarChatListStore.markRead(state); case .archive: state.isArchived = !archived; default: break }
            } catch { errorMessage = error.localizedDescription; return }
        }
        do { try context.save(); selection = [] } catch { context.rollback(); errorMessage = error.localizedDescription }
    }

    private func rename() {
        defer { renameID = nil }
        guard let id = renameID, let chat = conversations.first(where: { $0.id == id }) else { return }
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        chat.title = String(title.prefix(80))
        chat.titleOrigin = "manual"
        chat.titleRevision = UUID()
        do { try context.save() } catch { context.rollback(); errorMessage = error.localizedDescription }
    }

    private func deleteSelected() {
        let ids = pendingDelete; pendingDelete = []
        errorMessage = coordinator.deleteChats(conversations.filter { ids.contains($0.id) }, in: context)
        if errorMessage == nil { selection.subtract(ids) }
    }

    private func move(_ id: UUID, to project: FamiliarProject?) {
        let session = coordinator.session(id: id, in: context)
        guard !session.isSending && !session.isCompacting else { return }
        Task { @MainActor in
            await session.checkpointDraft(in: context)
            session.moveCurrentConversation(to: project, in: context)
            await session.checkpointDraft(in: context)
            if let error = session.errorMessage { errorMessage = error }
            moving = nil
        }
    }

    private func previewMessages(_ id: UUID) -> [FamiliarMessageSnapshot] {
        guard conversations.contains(where: { $0.id == id }) else { return [] }
        do {
            var request = FetchDescriptor<FamiliarMessage>(predicate: #Predicate { $0.conversation?.id == id }, sortBy: [SortDescriptor(\.sequence, order: .reverse)])
            request.fetchLimit = 3
            return try context.fetch(request).reversed().map(FamiliarMessageSnapshot.init(previewing:))
        } catch { return [] }
    }
}

private struct FamiliarMoveConversationDestination: Identifiable { let id: UUID }

extension FamiliarMessageSnapshot {
    init(previewing record: FamiliarMessage) {
        self.init(id: record.id, role: record.role, content: record.content, createdAt: record.createdAt,
            sequence: record.sequence, providerID: record.providerID, modelID: record.modelID,
            attachments: record.attachments.map {
                .init(id: $0.id, kind: $0.kind, filename: $0.filename, mimeType: $0.mimeType,
                    relativePath: $0.relativePath, extractedText: $0.extractedText, byteSize: $0.byteSize,
                    extractionEngine: $0.extractionEngine, extractionVersion: $0.extractionVersion,
                    detectedFormat: $0.detectedFormat, usedOCR: $0.usedOCR)
            }, sources: record.sources.compactMap { source in
                guard let url = URL(string: source.urlString) else { return nil }
                return .init(id: source.sourceID, kind: source.kind, title: source.title, url: url,
                    siteName: source.siteName, snippet: source.snippet, retrievedAt: source.retrievedAt,
                    responseBlockID: source.responseBlockID, retrievalActivityID: source.retrievalActivityID, citationOrdinal: source.citationOrdinal)
            })
    }
}
