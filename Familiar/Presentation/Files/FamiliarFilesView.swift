import SwiftData
import SwiftUI

/// Project and Chat share one scoped Files surface and the same File identities.
struct FamiliarFilesView: View {
    @Query private var files: [FamiliarFileRecord]
    let chatID: UUID?
    let scope: FamiliarWorkScope
    @State private var query = ""

    init(scope: FamiliarWorkScope, chatID: UUID? = nil) {
        self.chatID = chatID
        self.scope = scope
        let key = scope.storageKey
        _files = Query(filter: #Predicate<FamiliarFileRecord> { $0.scopeKey == key }, sort: \FamiliarFileRecord.updatedAt, order: .reverse)
    }

    private var visibleFiles: [FamiliarFileRecord] {
        files.filter { file in
            (chatID.map { file.chatIDs.contains($0) } ?? true) &&
                (query.isEmpty || file.displayName.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        List {
            ForEach(visibleFiles) { file in
                NavigationLink {
                    FamiliarFileDetailView(file: file)
                } label: {
                    if let snapshot = file.snapshot {
                        FamiliarFileLabel(file: .init(snapshot: snapshot))
                            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                    } else {
                        Text(file.displayName)
                    }
                }
                .accessibilityIdentifier("file.row.\(file.id.uuidString)")
            }
        }
        .overlay { if visibleFiles.isEmpty { ContentUnavailableView(String(localized: "file.empty"), systemImage: "folder") } }
        .navigationTitle(String(localized: "chat.files"))
        .searchable(text: $query)
    }
}
