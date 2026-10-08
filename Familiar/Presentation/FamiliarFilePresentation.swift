import SwiftUI
import SwiftData

/// Shared file vocabulary. Density belongs to the host; file identity and actions do not.
struct FamiliarFilePresentation: Identifiable {
    let id: String
    let title: String
    let filename: String
    let byteSize: Int64
    let version: Int?
    let url: URL?
    let format: FamiliarFileFormat?
    let isRevoked: Bool
    let snapshot: FamiliarFileSnapshot?

    var metadata: String {
        let ext = URL(fileURLWithPath: filename).pathExtension.uppercased()
        let size = ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
        return [ext.isEmpty ? nil : ext, size, version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
    var symbol: String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "xlsx", "csv", "tsv": "tablecells"
        case "png", "jpg", "jpeg", "heic": "photo"
        case "html", "swift", "js", "py": "chevron.left.forwardslash.chevron.right"
        default: "doc.text"
        }
    }

    init(snapshot: FamiliarFileSnapshot) {
        self.snapshot = snapshot
        id = snapshot.reference.versionID.uuidString
        title = snapshot.name
        filename = snapshot.filename
        byteSize = snapshot.byteSize
        version = snapshot.version
        url = FamiliarFileByteReader.url(for: snapshot)
        format = FamiliarFileFormat.allCases.first { $0.mimeType == snapshot.mimeType }
        isRevoked = false
    }

    init(file: FamiliarFileDescriptor, revoked: Bool) {
        snapshot = nil
        id = file.id.uuidString
        title = file.title
        filename = URL(fileURLWithPath: file.relativePath).lastPathComponent
        byteSize = file.byteSize
        version = nil
        format = file.format
        url = revoked || !file.relativePath.hasPrefix("Projects/\(file.projectID.uuidString)/")
            ? nil : FamiliarFileStore().url(relativePath: file.relativePath)
        isRevoked = revoked
    }

    init(attachment: FamiliarAttachmentSnapshot) {
        id = attachment.id.uuidString
        title = attachment.filename
        filename = attachment.filename
        byteSize = attachment.byteSize
        version = nil
        format = FamiliarFileFormat.allCases.first { $0.mimeType == attachment.mimeType }
        url = FamiliarAttachmentStore.url(for: attachment.relativePath)
        isRevoked = false
        snapshot = nil
    }

    init(draft: FamiliarAttachmentDraft) {
        self.init(attachment: .init(id: draft.id, kind: draft.kind, filename: draft.filename,
            mimeType: draft.mimeType, relativePath: draft.relativePath, extractedText: draft.extractedText,
            byteSize: draft.byteSize, extractionEngine: draft.extractionEngine,
            extractionVersion: draft.extractionVersion, detectedFormat: draft.detectedFormat, usedOCR: draft.usedOCR))
    }

    func validatedURL() throws -> URL {
        if let snapshot { _ = try FamiliarFileByteReader.read(snapshot, projectID: snapshot.reference.projectID) }
        guard let url else { throw FamiliarFileError.missingFile }
        return url
    }

    func resolved(in context: ModelContext, projectID: UUID? = nil) -> Self {
        guard !isRevoked, let versionID = UUID(uuidString: id),
              let version = try? context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(
                predicate: #Predicate { $0.id == versionID })).first,
              projectID == nil || version.projectID == projectID,
              let snapshot = FamiliarFileCatalogService().snapshot(version) else { return self }
        return .init(snapshot: snapshot)
    }
}

struct FamiliarFileLabel: View {
    let file: FamiliarFilePresentation
    var compact = false
    var body: some View {
        HStack(spacing: FamiliarSpacing.medium) {
            Image(systemName: file.symbol)
                .font(.system(size: compact ? FamiliarIconSize.standard : FamiliarIconSize.prominent))
                .foregroundStyle(.secondary)
                .frame(width: compact ? FamiliarIconSize.standard : FamiliarControlSize.standardVisual)
            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                Text(file.title).font(compact ? FamiliarTypography.caption : FamiliarTypography.secondary.weight(.medium))
                    .lineLimit(compact ? 1 : 2)
                Text(file.metadata).font(FamiliarTypography.caption).foregroundStyle(.secondary)
                if file.url == nil {
                    Text(String(localized: file.isRevoked ? "runtime.ui.file_revoked" : "runtime.ui.file_unavailable"))
                        .font(FamiliarTypography.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct FamiliarFileTile: View {
    let file: FamiliarFilePresentation
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: FamiliarSpacing.small) {
            Button(action: onOpen) {
                HStack(spacing: FamiliarSpacing.medium) {
                    FamiliarFileLabel(file: file)
                    Spacer(minLength: FamiliarSpacing.small)
                    if file.url != nil { Image(systemName: "chevron.right").font(FamiliarTypography.caption).foregroundStyle(.tertiary) }
                }
                .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
                .padding(FamiliarSpacing.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(FamiliarIconButtonStyle())
            .disabled(file.url == nil)
            .accessibilityIdentifier("file.open.\(file.id)")
            if let url = file.url {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: FamiliarControlSize.minimumHitTarget, height: FamiliarControlSize.minimumHitTarget)
                }
                .buttonStyle(FamiliarIconButtonStyle())
                .padding(.trailing, FamiliarSpacing.small)
                .accessibilityLabel(String(localized: "common.share"))
            }
        }
        .foregroundStyle(.primary)
        .background(FamiliarTheme.inset, in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
    }
}
