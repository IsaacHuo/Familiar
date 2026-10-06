import SwiftUI
import SwiftData

/// Project and Chat share one scoped Files surface and the same File identities.
struct FamiliarFilesView: View {
    @Environment(\.modelContext) private var context
    @Query private var files: [FamiliarFileRecord]
    let chatID: UUID?
    let projectID: UUID
    @State private var query = ""
    @State private var preview: Preview?
    @State private var errorMessage: String?
    @State private var pendingDeletion: FamiliarFileRecord?

    private struct Preview: Identifiable {
        let id: UUID
        let url: URL
    }

    init(projectID: UUID, chatID: UUID? = nil) {
        self.chatID = chatID
        self.projectID = projectID
        _files = Query(filter: #Predicate<FamiliarFileRecord> { $0.projectID == projectID }, sort: \FamiliarFileRecord.updatedAt, order: .reverse)
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
                if let snapshot = file.snapshot {
                    DisclosureGroup {
                        Toggle(String(localized: "file.project_context"), isOn: Binding(
                            get: { file.isProjectContext },
                            set: { enabled in perform { try FamiliarFileCatalogService().setProjectContext(enabled, file: file, in: context) } }
                        ))
                        ForEach(file.versions.sorted { $0.version > $1.version }) { version in
                            Button("\(version.filename) · v\(version.version)") { open(version, file: file) }
                        }
                        if let url = FamiliarFileCatalogService().url(for: snapshot) {
                            ShareLink(item: url) { Label(String(localized: "common.share"), systemImage: "square.and.arrow.up") }
                        }
                        Button(String(localized: "common.delete"), role: .destructive) { pendingDeletion = file }
                    } label: {
                        Button { openLatest(file) } label: {
                            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                                Text(file.displayName)
                                Text(ByteCountFormatter.string(fromByteCount: snapshot.byteSize, countStyle: .file))
                                    .font(FamiliarTypography.caption).foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
        }
        .overlay { if visibleFiles.isEmpty { ContentUnavailableView(String(localized: "file.empty"), systemImage: "folder") } }
        .navigationTitle(String(localized: "chat.files"))
        .searchable(text: $query)
        .sheet(item: $preview) { preview in FamiliarAttachmentPreviewView(url: preview.url) }
        .alert(String(localized: "file.delete.title"), isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button(String(localized: "common.delete"), role: .destructive) {
                if let file = pendingDeletion { perform { try FamiliarFileCatalogService().delete(file, in: context) } }
                pendingDeletion = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) { pendingDeletion = nil }
        } message: { Text(String(localized: "file.delete.detail")) }
        .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok"), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func openLatest(_ file: FamiliarFileRecord) {
        if let version = file.latestVersion { open(version, file: file) }
    }

    private func open(_ version: FamiliarFileVersionRecord, file: FamiliarFileRecord) {
        perform {
            let reference = FamiliarFileReference(fileID: file.id, versionID: version.id, projectID: file.projectID)
            _ = try FamiliarFileCatalogService().read(reference, inProject: file.projectID, context: context)
            guard let origin = FamiliarFileOrigin(rawValue: file.originRawValue),
                  let kind = FamiliarFileStorageKind(rawValue: version.storageKindRawValue) else { throw FamiliarFileError.invalidPath }
            let snapshot = FamiliarFileSnapshot(reference: reference, name: file.displayName, origin: origin,
                version: version.version, filename: version.filename, mimeType: version.mimeType,
                byteSize: version.byteSize, contentHash: version.contentHash,
                storage: .init(kind: kind, relativePath: version.storageRelativePath),
                isProjectContext: file.isProjectContext, updatedAt: file.updatedAt)
            guard let url = FamiliarFileCatalogService().url(for: snapshot) else { throw FamiliarFileError.missingFile }
            preview = .init(id: version.id, url: url)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}
