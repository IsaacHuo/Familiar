import SwiftData
import SwiftUI

/// One File with its versions. Previews push, sharing uses the system ShareLink,
/// and deleting is explicit and confirmed; every failure surfaces instead of
/// being swallowed.
struct FamiliarFileDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let file: FamiliarFileRecord

    @State private var preview: FamiliarPreparedFilePreview?
    @State private var errorMessage: String?
    @State private var confirmsDelete = false

    private var versions: [FamiliarFileVersionRecord] {
        file.versions.sorted { $0.version > $1.version }
    }

    private var latestURL: URL? {
        guard let snapshot = file.snapshot else { return nil }
        return FamiliarFileCatalogService().url(for: snapshot)
    }

    var body: some View {
        List {
            if let snapshot = file.snapshot {
                Section {
                    FamiliarFileLabel(file: .init(snapshot: snapshot))
                        .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                    HStack(spacing: FamiliarSpacing.small) {
                        Button {
                            open(snapshot)
                        } label: {
                            Label(String(localized: "common.preview", defaultValue: "Preview"), systemImage: "eye")
                                .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("file.detail.preview")
                        if let latestURL {
                            ShareLink(item: latestURL) {
                                Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                                    .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("file.detail.share")
                        }
                    }
                }
            }

            Section(String(localized: "file.versions", defaultValue: "Versions")) {
                if versions.isEmpty {
                    Text(String(localized: "settings.runs.no_activities", defaultValue: "No persisted activities"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(versions) { version in
                        Button {
                            open(version)
                        } label: {
                            HStack(spacing: FamiliarSpacing.small) {
                                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                                    Text(version.filename)
                                        .font(FamiliarTypography.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(versionMeta(version))
                                        .font(FamiliarTypography.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: FamiliarSpacing.small)
                                if version.id == file.latestVersion?.id {
                                    Text(String(localized: "file.latest", defaultValue: "Latest"))
                                        .font(FamiliarTypography.caption.weight(.semibold))
                                        .foregroundStyle(FamiliarTheme.accent)
                                }
                                Image(systemName: "chevron.right")
                                    .font(FamiliarTypography.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("file.version.\(version.version)")
                    }
                }
            }

            if file.scope.projectID != nil {
                Section {
                    Toggle(String(localized: "file.project_context"), isOn: Binding(
                        get: { file.isProjectContext },
                        set: { enabled in perform { try FamiliarFileCatalogService().setProjectContext(enabled, file: file, in: context) } }
                    ))
                }
            }

            Section {
                Button(String(localized: "common.delete"), role: .destructive) { confirmsDelete = true }
                    .accessibilityIdentifier("file.detail.delete")
            }
        }
        .navigationTitle(file.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $preview) { item in
            FamiliarAttachmentPreviewView(url: item.url, format: item.format)
        }
        .confirmationDialog(String(localized: "file.delete.title"), isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button(String(localized: "common.delete"), role: .destructive) { deleteFile() }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "file.delete.detail"))
        }
        .alert(String(localized: "settings.error.title"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func versionMeta(_ version: FamiliarFileVersionRecord) -> String {
        let size = ByteCountFormatter.string(fromByteCount: version.byteSize, countStyle: .file)
        return "v\(version.version) · \(size) · \(version.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func open(_ snapshot: FamiliarFileSnapshot) {
        perform {
            guard let url = FamiliarFileCatalogService().url(for: snapshot) else { throw FamiliarFileError.missingFile }
            preview = FamiliarPreparedFilePreview(url: url, format: FamiliarFileFormat.allCases.first { $0.filenameExtension == URL(fileURLWithPath: snapshot.filename).pathExtension.lowercased() })
        }
    }

    private func open(_ version: FamiliarFileVersionRecord) {
        perform {
            guard let snapshot = FamiliarFileCatalogService().snapshot(version) else { throw FamiliarFileError.missingFile }
            open(snapshot)
        }
    }

    private func deleteFile() {
        do {
            try FamiliarFileCatalogService().delete(file, in: context)
            FamiliarHaptics.shared.perform(.destructive)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}
