import SwiftData
import SwiftUI

struct FamiliarFileLibraryEntry: Identifiable {
    let id: UUID
    let name: String
    let scope: FamiliarWorkScope
    let scopeName: String
    let date: Date
    let snapshot: FamiliarFileSnapshot?
    var category: FamiliarFileCategory { snapshot.map { .classify(filename: $0.filename, mimeType: $0.mimeType) } ?? .other }
    var subtitle: String {
        guard let snapshot else { return String(localized: "files.no_version") + " · " + scopeName }
        return ByteCountFormatter.string(fromByteCount: snapshot.byteSize, countStyle: .file) + " · " + scopeName
    }
    var deletion: FamiliarFileDeletionTarget { .init(id: id, scope: scope, name: name) }
}

/// Telegram file/selection interaction, with canonical File IDs and exact versions.
struct FamiliarFileLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @Query(sort: \FamiliarFileRecord.updatedAt, order: .reverse) private var files: [FamiliarFileRecord]
    @Query private var projects: [FamiliarProject]
    @Query private var chats: [FamiliarConversation]
    @State private var scopeKey = ""
    @State private var category = FamiliarFileCategory.all
    @State private var sort = FamiliarFileSort.recent
    @State private var searching = false
    @State private var searchTarget: FamiliarFileLibraryEntry?
    @State private var selecting = false
    @State private var selected: [UUID: FamiliarFileLibraryEntry] = [:]
    @State private var deleting = false
    @State private var deletion: [FamiliarFileDeletionTarget]?
    @State private var share: FamiliarFileShareRequest?
    @State private var preview: FamiliarPreparedFilePreview?
    @State private var imagePreview: FamiliarImageGalleryRequest?
    @State private var detailID: UUID?
    @State private var errorMessage: String?

    private var scopeNames: [String: String] {
        var result = Dictionary(uniqueKeysWithValues: projects.map { (FamiliarWorkScope.project($0.id).storageKey, $0.displayName) })
        for chat in chats { result[FamiliarWorkScope.conversation(chat.id).storageKey] = chat.title }
        return result
    }
    var body: some View {
        let names = scopeNames
        let entries = files.map { file in FamiliarFileLibraryEntry(id: file.id, name: file.displayName, scope: file.scope,
            scopeName: names[file.scope.storageKey] ?? String(localized: "file.library.missing"), date: file.updatedAt, snapshot: file.snapshot) }
        let scopes = Array(Set(entries.map { $0.scope.storageKey })).sorted { (names[$0] ?? $0).localizedStandardCompare(names[$1] ?? $1) == .orderedAscending }
        let visible = entries.filter { (scopeKey.isEmpty || $0.scope.storageKey == scopeKey) && (category == .all || $0.category == category) }.sorted { lhs, rhs in
            switch sort {
            case .recent: if lhs.date != rhs.date { return lhs.date > rhs.date }
            case .oldest: if lhs.date != rhs.date { return lhs.date < rhs.date }
            case .name: if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            case .size: if lhs.snapshot?.byteSize != rhs.snapshot?.byteSize { return (lhs.snapshot?.byteSize ?? 0) > (rhs.snapshot?.byteSize ?? 0) }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let grouped = Dictionary(grouping: visible) { Calendar.current.startOfDay(for: $0.date) }
        List {
            if visible.isEmpty { ContentUnavailableView(String(localized: "file.empty"), systemImage: "folder").listRowSeparator(.hidden) }
            else if sort.groupsDates {
                ForEach(grouped.keys.sorted { sort == .oldest ? $0 < $1 : $0 > $1 }, id: \.self) { day in
                    Section(day.formatted(date: .abbreviated, time: .omitted)) { ForEach(grouped[day] ?? []) { row($0) } }
                }
            } else { ForEach(visible) { row($0) } }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .top, spacing: 0) { categoryBar }
        .navigationTitle(selecting ? String(format: String(localized: "files.selection.count"), selected.count) : String(localized: "tab.files"))
        .navigationBarTitleDisplayMode(.inline).toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(selecting ? .hidden : .visible, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(String(localized: selecting ? "common.cancel" : "files.select")) { selecting.toggle(); selected = [:] }.disabled(deleting)
                    .accessibilityIdentifier("files.select")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selecting {
                    Button(String(localized: selected.count == visible.count && !visible.isEmpty ? "files.deselect_all" : "files.select_all")) {
                        selected = selected.count == visible.count ? [:] : Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
                    }.disabled(deleting)
                } else {
                    Button { searching = true } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel(String(localized: "drawer.search"))
                    Menu {
                        Picker(String(localized: "file.library.scope"), selection: $scopeKey) {
                            Text(String(localized: "file.library.all")).tag("")
                            ForEach(scopes, id: \.self) { Text(names[$0] ?? "").tag($0) }
                        }
                        Picker(String(localized: "files.sort"), selection: $sort) { ForEach(FamiliarFileSort.allCases) { Text($0.title).tag($0) } }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel(String(localized: "files.filters")).accessibilityIdentifier("files.filters")
                }
            }
            if selecting {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { prepareShare() } label: { Image(systemName: "square.and.arrow.up") }.disabled(selected.isEmpty || deleting).accessibilityLabel(String(localized: "common.share"))
                    Spacer()
                    if deleting { ProgressView() }
                    Button(role: .destructive) { deletion = selected.values.map(\.deletion).sorted { $0.id.uuidString < $1.id.uuidString } } label: { Image(systemName: "trash") }
                        .disabled(selected.isEmpty || deleting).accessibilityLabel(String(localized: "common.delete"))
                }
            }
        }
        .navigationDestination(for: FamiliarFileLibraryRoute.self) { if case .file(let id) = $0 { details(id) } }
        .navigationDestination(item: $detailID) { details($0) }
        .navigationDestination(item: $preview) { FamiliarAttachmentPreviewView(url: $0.url, format: $0.format) }
        .sheet(isPresented: $searching, onDismiss: { if let entry = searchTarget { searchTarget = nil; open(entry) } }) {
            FamiliarFileSearchPage(entries: entries) { searchTarget = $0; searching = false }
        }
        .sheet(item: $share) { FamiliarFileShareSheet(urls: $0.urls) }
        .fullScreenCover(item: $imagePreview) { FamiliarImageGalleryView(request: $0) }
        .confirmationDialog(String(format: String(localized: "files.delete.count"), deletion?.count ?? 0), isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button(String(localized: "common.delete"), role: .destructive) {
                let targets = deletion ?? []; deletion = nil; deleting = true
                Task { @MainActor in
                    let result = await FamiliarFileBatchDeletion.execute(targets, in: context)
                    for id in result.succeeded { selected.removeValue(forKey: id) }
                    deleting = false
                    if result.failures.isEmpty { if selected.isEmpty { selecting = false }; FamiliarHaptics.shared.perform(.destructive) }
                    else {
                        errorMessage = String(format: String(localized: "files.delete.partial"), result.succeeded.count, result.failures.count) + "\n" + targets.compactMap { target in result.failures[target.id].map { target.name + ": " + $0 } }.joined(separator: "\n")
                    }
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) { deletion = nil }
        } message: { Text(String(localized: "files.delete.all_versions")) }
        .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button(String(localized: "common.ok"), role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .onChange(of: scopes) { _, keys in if !scopeKey.isEmpty && !keys.contains(scopeKey) { scopeKey = "" } }
        .accessibilityIdentifier("files.library")
    }
    private var categoryBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(FamiliarFileCategory.allCases) { item in
                        Button { withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) { category = item } } label: {
                            Text(item.title).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 44)
                                .background(item == category ? FamiliarTheme.hoverStrong : .clear, in: Capsule())
                        }.buttonStyle(.plain).id(item).accessibilityAddTraits(item == category ? .isSelected : [])
                    }
                }.padding(3)
            }.familiarGlassSurface(interactive: true, cornerRadius: 25).padding(.horizontal, 16).padding(.bottom, 8)
                .disabled(selecting || deleting)
                .onChange(of: category) { _, value in withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) { proxy.scrollTo(value, anchor: .center) } }
        }
    }
    private func row(_ entry: FamiliarFileLibraryEntry) -> some View {
        Button {
            if selecting { if selected[entry.id] == nil { selected[entry.id] = entry } else { selected.removeValue(forKey: entry.id) } }
            else { open(entry) }
        } label: { FamiliarTelegramFileRow(name: entry.name, subtitle: entry.subtitle, snapshot: entry.snapshot, selecting: selecting, selected: selected[entry.id] != nil) }
        .buttonStyle(FamiliarTelegramFilePressStyle()).disabled(deleting)
        .listRowInsets(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
        .accessibilityIdentifier("file.row." + entry.id.uuidString)
        .contextMenu {
            if !selecting {
                if let snapshot = entry.snapshot, let url = FamiliarFileByteReader.url(for: snapshot) {
                    Button { open(entry) } label: { Label(String(localized: "common.preview"), systemImage: "eye") }
                    ShareLink(item: url) { Label(String(localized: "common.share"), systemImage: "square.and.arrow.up") }
                }
                Button { detailID = entry.id } label: { Label(String(localized: "files.details"), systemImage: "info.circle") }
                Button { selecting = true; selected[entry.id] = entry } label: { Label(String(localized: "files.select"), systemImage: "checkmark.circle") }
                Button(role: .destructive) { deletion = [entry.deletion] } label: { Label(String(localized: "common.delete"), systemImage: "trash") }
            }
        }
    }
    @ViewBuilder private func details(_ id: UUID) -> some View {
        if let file = files.first(where: { $0.id == id }) { FamiliarFileDetailView(file: file) }
        else { ContentUnavailableView(String(localized: "file.library.missing"), systemImage: "doc.badge.ellipsis") }
    }
    private func open(_ entry: FamiliarFileLibraryEntry) {
        guard let current = files.first(where: { $0.id == entry.id }), current.scope == entry.scope else { errorMessage = String(localized: "file.library.missing"); return }
        if let snapshot = entry.snapshot, current.versions.contains(where: { $0.id == snapshot.reference.versionID && $0.scope == entry.scope && $0.fileID == entry.id }), let url = FamiliarFileByteReader.url(for: snapshot) {
            if entry.category == .image {
                FamiliarImagePresentation.update { imagePreview = .init(id: snapshot.reference.versionID, items: [.init(id: snapshot.reference.versionID, url: url)]) }
            } else { preview = .init(url: url, format: FamiliarFilePresentation(snapshot: snapshot).format) }
        } else { detailID = entry.id }
    }
    private func prepareShare() {
        do {
            let urls = try selected.values.sorted { $0.id.uuidString < $1.id.uuidString }.map { entry in
                guard let current = files.first(where: { $0.id == entry.id }), current.scope == entry.scope,
                      let snapshot = entry.snapshot, current.versions.contains(where: { $0.id == snapshot.reference.versionID && $0.scope == entry.scope && $0.fileID == entry.id }),
                      let url = FamiliarFileByteReader.url(for: snapshot) else { throw FamiliarFileError.missingFile }
                return url
            }
            if !urls.isEmpty { share = .init(urls: urls) }
        } catch { errorMessage = error.localizedDescription }
    }
}
private enum FamiliarFileLibraryRoute: Hashable { case file(UUID) }
private struct FamiliarFileSearchPage: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [FamiliarFileLibraryEntry]
    let onOpen: (FamiliarFileLibraryEntry) -> Void
    @State private var query = ""
    @State private var active = true
    var body: some View {
        NavigationStack {
            List(entries.filter { !query.isEmpty && ($0.name.localizedStandardContains(query) || $0.scopeName.localizedStandardContains(query) || $0.snapshot?.filename.localizedStandardContains(query) == true) }) { entry in
                Button { onOpen(entry) } label: { FamiliarTelegramFileRow(name: entry.name, subtitle: entry.subtitle, snapshot: entry.snapshot, selecting: false, selected: false) }.buttonStyle(.plain)
            }.navigationTitle(String(localized: "tab.files")).navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, isPresented: $active, placement: .navigationBarDrawer(displayMode: .always))
                .toolbar { ToolbarItem(placement: .confirmationAction) { FamiliarDismissButton() } }
        }.onChange(of: active) { _, value in if !value { dismiss() } }
    }
}
