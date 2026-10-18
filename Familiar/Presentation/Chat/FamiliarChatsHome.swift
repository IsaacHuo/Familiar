import SwiftData
import SwiftUI

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
    @State private var filter = FamiliarChatListFilter.recent
    @State private var query = ""
    @State private var searchAll = false
    @State private var editing = false
    @State private var selection: Set<UUID> = []
    @State private var pendingDelete: Set<UUID> = []
    @State private var renameID: UUID?
    @State private var renameText = ""
    @State private var moving: FamiliarMoveConversationDestination?
    @State private var errorMessage: String?

    private var orderedProjects: [FamiliarProject] {
        let ids = projectOrder.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        return projects.filter { $0.status == .active }.sorted {
            let lhs = ids.firstIndex(of: $0.id) ?? Int.max, rhs = ids.firstIndex(of: $1.id) ?? Int.max
            if lhs != rhs { return lhs < rhs }
            return $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
    }

    private var rows: [FamiliarConversationListSnapshot] {
        let stateByID = Dictionary(uniqueKeysWithValues: states.map { ($0.conversationID, $0) })
        let draftByID = Dictionary(uniqueKeysWithValues: drafts.compactMap { draft in draft.conversationID.map { ($0, draft) } })
        let pinned = Set(pins.filter { $0.targetType == .conversation }.map(\.targetID))
        let active = coordinator.activeSession
        return conversations.compactMap { conversation in
            let state = stateByID[conversation.id]
            guard (state?.isArchived ?? false) == archived else { return nil }
            let draft = draftByID[conversation.id]
            let running = active?.selectedConversationID == conversation.id
            let attention = running && (!(active?.pendingConfirmations.isEmpty ?? true) || !(active?.pendingClarifications.isEmpty ?? true))
            let preview: String
            if let draft { preview = String(localized: "chat.draft") + " · " + String(draft.text.prefix(180)) }
            else if attention { preview = String(localized: "chat.needs_attention") }
            else if running { preview = String(localized: "chat.running") }
            else { preview = state?.preview ?? "…" }
            return .init(id: conversation.id, title: conversation.title, preview: preview,
                projectName: conversation.project?.displayName,
                date: max(draft?.updatedAt ?? .distantPast, state?.latestActivityAt ?? conversation.updatedAt),
                isPinned: pinned.contains(conversation.id), isUnread: state?.isUnread ?? false,
                isArchived: archived, hasDraft: draft != nil, isRunning: running,
                needsAttention: attention, hasFailure: state?.hasFailure ?? false)
        }.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.isPinned {
                let left = pins.firstIndex { $0.targetID == lhs.id } ?? Int.max
                let right = pins.firstIndex { $0.targetID == rhs.id } ?? Int.max
                if left != right { return left < right }
            }
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func filtered(_ rows: [FamiliarConversationListSnapshot], by filter: FamiliarChatListFilter) -> [FamiliarConversationListSnapshot] {
        guard case .project(let id) = filter else { return rows }
        let ids = Set(conversations.filter { $0.project?.id == id }.map(\.id))
        return rows.filter { ids.contains($0.id) }
    }

    var body: some View {
        let entries = rows
        VStack(spacing: 0) {
            if !query.isEmpty {
                searchResults(entries)
            } else {
                FamiliarChatProjectPager(rows: entries, projects: orderedProjects, filter: $filter,
                    editing: editing, selection: $selection,
                    counts: projectUnreadCounts,
                    specialRows: AnyView(specialRows),
                    rowFilter: filtered,
                    onManage: { onNavigate(.projects) },
                    onOpen: { onNavigate(.chat($0)) }, onAction: perform,
                    preview: previewMessages)
            }
        }
        .navigationTitle(String(localized: archived ? "chat.archived" : "tab.chats"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: String(localized: "drawer.search"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: editing ? "common.done" : "common.edit")) { editing.toggle(); selection.removeAll() }
                    .accessibilityIdentifier("chats.edit")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { if case .project(let id) = filter { onNew(id) } else { onNew(nil) } } label: {
                    Image(systemName: "square.and.pencil")
                }.accessibilityLabel(String(localized: "conversation.new")).accessibilityIdentifier("chats.new")
            }
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
        .onChange(of: query) { _, value in if !value.isEmpty { editing = false; selection.removeAll() } }
        .onChange(of: orderedProjects.map(\.id)) { _, ids in
            if case .project(let id) = filter, !ids.contains(id) { filter = .recent }
        }
        .accessibilityIdentifier(archived ? "chats.archive" : "chats.home")
    }

    private var projectUnreadCounts: [UUID: Int] {
        let unreadIDs = Set(states.filter { !$0.isArchived && $0.isUnread }.map(\.conversationID))
        return conversations.reduce(into: [:]) { counts, chat in
            if unreadIDs.contains(chat.id), let id = chat.project?.id { counts[id, default: 0] += 1 }
        }
    }

    private var specialRows: some View {
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

    @ViewBuilder private func searchResults(_ entries: [FamiliarConversationListSnapshot]) -> some View {
        let scoped = searchAll ? entries : filtered(entries, by: filter)
        let ids = Set(scoped.map(\.id))
        let candidates = conversations.filter { searchAll || ids.contains($0.id) }
        List {
            Toggle(String(localized: "chat.search.all"), isOn: $searchAll)
            Section(String(localized: "tab.chats")) {
                ForEach(scoped.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.preview.localizedCaseInsensitiveContains(query) }) { row in
                    Button { onNavigate(.chat(row.id)) } label: { FamiliarConversationListRow(row: row) }.buttonStyle(.plain)
                }
                // Archived conversations remain discoverable in an explicit all-chat search.
                if searchAll {
                    ForEach(conversations.filter { chat in !ids.contains(chat.id) && chat.title.localizedCaseInsensitiveContains(query) }) { chat in
                        Button { onNavigate(.chat(chat.id)) } label: { Label(chat.title, systemImage: "archivebox") }
                    }
                }
            }
            Section(String(localized: "chat.search.messages")) {
                ForEach(candidates.flatMap { conversation in
                    conversation.messages.filter { $0.content.localizedCaseInsensitiveContains(query) }
                        .map { FamiliarMessageSearchMatch(id: $0.id, chatID: conversation.id, title: conversation.title, text: String($0.content.prefix(240))) }
                }.prefix(100)) { match in
                    Button { onNavigate(.message(match.chatID, match.id)) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(match.title).font(.headline)
                            Text(match.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }.listStyle(.plain)
    }

    private func initializeMetadata() {
        do {
            for conversation in conversations { _ = try FamiliarChatListStore.state(for: conversation, in: context) }
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
        guard let chat = conversations.first(where: { $0.id == id }) else { return [] }
        return chat.messages.sorted { $0.sequence < $1.sequence }.suffix(3).map(FamiliarMessageSnapshot.init(previewing:))
    }
}

private struct FamiliarMoveConversationDestination: Identifiable { let id: UUID }
private struct FamiliarMessageSearchMatch: Identifiable { let id: UUID; let chatID: UUID; let title: String; let text: String }

private struct FamiliarChatProjectPager: View {
    @Environment(\.familiarReduceMotion) private var reduceMotion
    let rows: [FamiliarConversationListSnapshot]
    let projects: [FamiliarProject]
    @Binding var filter: FamiliarChatListFilter
    let editing: Bool
    @Binding var selection: Set<UUID>
    let counts: [UUID: Int]
    let specialRows: AnyView
    let rowFilter: ([FamiliarConversationListSnapshot], FamiliarChatListFilter) -> [FamiliarConversationListSnapshot]
    let onManage: () -> Void
    let onOpen: (UUID) -> Void
    let onAction: (UUID, FamiliarConversationListAction) -> Void
    let preview: (UUID) -> [FamiliarMessageSnapshot]
    @State private var offsets = FamiliarChatListPositions()
    @State private var pageID: FamiliarChatListFilter? = .recent
    @State private var progress: CGFloat = 0
    @State private var tabFrames: [FamiliarChatListFilter: CGRect] = [:]
    private var filters: [FamiliarChatListFilter] { [.recent] + projects.map { .project($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FamiliarSpacing.xSmall) {
                    ForEach(filters, id: \.self) { item in
                        Button {
                            filter = item
                            withAnimation(reduceMotion ? nil : FamiliarMotion.interactiveSpring) { pageID = item }
                        } label: {
                            HStack(spacing: 5) {
                                Text(title(item)).font(.subheadline.weight(.semibold)).lineLimit(1)
                                if case .project(let id) = item, let count = counts[id], count > 0 { Text(count, format: .number).font(.caption2.weight(.bold)) }
                            }.padding(.horizontal, 14).frame(minHeight: 44)
                        }.buttonStyle(.plain).accessibilityAddTraits(filter == item ? .isSelected : [])
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("project-tabs")) } action: { frame in
                                if tabFrames[item] != frame { tabFrames[item] = frame }
                            }
                    }
                    Button(action: onManage) { Image(systemName: "folder.badge.gearshape").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel(String(localized: "project.manage"))
                        .accessibilityIdentifier("chats.manageProjects")
                }
                .coordinateSpace(name: "project-tabs")
                .background(alignment: .topLeading) {
                    if let frame = selectionFrame {
                        Capsule().fill(FamiliarTheme.accentTint)
                            .frame(width: frame.width, height: frame.height)
                            .familiarGlassSurface(cornerRadius: 22)
                            .offset(x: frame.minX, y: frame.minY)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, FamiliarSpacing.medium).padding(.vertical, 5)
            }.background(.bar)
            specialRows
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(filters, id: \.self) { item in
                            let visible = rowFilter(rows, item)
                            FamiliarConversationList(rows: visible, isEditing: editing, selection: $selection,
                                initialOffset: offsets.values[item] ?? 0, reduceMotion: reduceMotion,
                                onScroll: { offsets.values[item] = $0 }, onOpen: onOpen, onAction: onAction, preview: preview)
                                .overlay { if visible.isEmpty { ContentUnavailableView(String(localized: "chat.list.empty"), systemImage: "bubble.left.and.bubble.right") } }
                                .frame(width: geometry.size.width, height: geometry.size.height).id(item)
                        }
                    }.scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging).scrollIndicators(.hidden).scrollDisabled(editing)
                .scrollPosition(id: $pageID)
                .onScrollGeometryChange(for: CGFloat.self) { value in
                    value.contentOffset.x / max(value.containerSize.width, 1)
                } action: { _, value in progress = value }
                .onScrollPhaseChange { _, phase in if phase == .idle, let pageID { filter = pageID } }
                .onChange(of: pageID) { _, value in if let value { filter = value } }
                .onChange(of: filter) { _, value in if pageID != value { pageID = value } }
            }
        }
    }
    private var selectionFrame: CGRect? {
        guard !filters.isEmpty else { return nil }
        let position = min(max(progress, 0), CGFloat(filters.count - 1))
        let lower = Int(floor(position)), upper = min(lower + 1, filters.count - 1)
        guard let start = tabFrames[filters[lower]] else { return nil }
        let end = tabFrames[filters[upper]] ?? start
        let fraction = position - CGFloat(lower)
        return .init(x: start.minX + (end.minX - start.minX) * fraction,
                     y: start.minY, width: start.width + (end.width - start.width) * fraction,
                     height: start.height)
    }

    private func title(_ filter: FamiliarChatListFilter) -> String {
        switch filter { case .recent: String(localized: "chat.recent"); case .project(let id): projects.first { $0.id == id }?.displayName ?? "" }
    }
}

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

@MainActor private final class FamiliarChatListPositions {
    // Geometry is not observable; native vertical scrolling must not rebuild the pager.
    var values: [FamiliarChatListFilter: CGFloat] = [:]
}
