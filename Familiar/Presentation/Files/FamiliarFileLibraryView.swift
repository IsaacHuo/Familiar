import SwiftData
import SwiftUI

/// An aggregate browser. Every detail still receives the File's original scope.
struct FamiliarFileLibraryView: View {
    @Query(sort: \FamiliarFileRecord.updatedAt, order: .reverse) private var files: [FamiliarFileRecord]
    @Query private var projects: [FamiliarProject]
    @Query private var chats: [FamiliarConversation]
    @State private var query = ""
    @State private var scopeKey = ""
    private var visible: [FamiliarFileRecord] {
        files.filter { (scopeKey.isEmpty || $0.scope.storageKey == scopeKey) &&
            (query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        List {
            Section {
                Picker(String(localized: "file.library.scope"), selection: $scopeKey) {
                    Text(String(localized: "file.library.all")).tag("")
                    ForEach(Array(Set(files.map { $0.scope.storageKey })).sorted(), id: \.self) { key in
                        Text(scopeName(key)).tag(key)
                    }
                }
            }
            ForEach(visible) { file in
                NavigationLink(value: FamiliarFileLibraryRoute.file(file.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let snapshot = file.snapshot { FamiliarFileLabel(file: .init(snapshot: snapshot)) }
                        else { Text(file.displayName) }
                        Text(scopeName(file.scope.storageKey)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.accessibilityIdentifier("file.row." + file.id.uuidString)
            }
        }
        .navigationTitle(String(localized: "tab.files"))
        .navigationDestination(for: FamiliarFileLibraryRoute.self) { route in
            switch route {
            case .file(let id):
                if let file = files.first(where: { $0.id == id }) { FamiliarFileDetailView(file: file) }
                else { ContentUnavailableView(String(localized: "file.library.missing"), systemImage: "doc.badge.ellipsis") }
            }
        }
        .onChange(of: files.map { $0.scope.storageKey }) { _, keys in
            if !scopeKey.isEmpty && !keys.contains(scopeKey) { scopeKey = "" }
        }
        .searchable(text: $query)
        .overlay { if visible.isEmpty { ContentUnavailableView(String(localized: "file.empty"), systemImage: "folder").allowsHitTesting(false) } }
        .accessibilityIdentifier("files.library")
    }

    private func scopeName(_ key: String) -> String {
        guard let scope = FamiliarWorkScope(storageKey: key) else { return String(localized: "conversation.ordinary") }
        switch scope {
        case .project(let id): return projects.first { $0.id == id }?.displayName ?? String(localized: "project.unavailable")
        case .conversation(let id): return chats.first { $0.id == id }?.title ?? String(localized: "conversation.ordinary")
        }
    }
}

private enum FamiliarFileLibraryRoute: Hashable { case file(UUID) }
