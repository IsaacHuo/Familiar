import SwiftUI
import SwiftData

extension EnvironmentValues {
    @Entry var familiarOpenMessageFile: FamiliarMessageFilePreviewAction? = nil
}

struct FamiliarMessageFilePreviewAction: Equatable {
    let ownerID: UUID
    let presentation: Binding<FamiliarPreparedFilePreview?>
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.ownerID == rhs.ownerID }
    @MainActor func open(_ file: FamiliarPreparedFilePreview) { presentation.wrappedValue = file }
}

/// Navigation destinations belong to the mounted page, never lazy message rows.
struct FamiliarMessageFileNavigation: ViewModifier {
    @State private var preview: FamiliarPreparedFilePreview?
    @State private var ownerID = UUID()
    func body(content: Content) -> some View {
        content
            .environment(\.familiarOpenMessageFile, .init(ownerID: ownerID, presentation: $preview))
            .navigationDestination(item: $preview) { file in
                FamiliarAttachmentPreviewView(url: file.url, format: file.format)
            }
    }
}

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
        url = revoked || !file.relativePath.hasPrefix(file.scope.filePrefix)
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
        if let snapshot { _ = try FamiliarFileByteReader.read(snapshot, scope: snapshot.reference.scope) }
        guard let url else { throw FamiliarFileError.missingFile }
        return url
    }

    func resolved(in context: ModelContext, scope: FamiliarWorkScope? = nil) -> Self {
        guard !isRevoked, let versionID = UUID(uuidString: id) else { return self }
        var request = FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.id == versionID })
        request.fetchLimit = 1
        let direct = (try? context.fetch(request))?.first
        let version: FamiliarFileVersionRecord?
        if let direct, scope == nil || direct.scope == scope { version = direct }
        else if let scope {
            let key = scope.storageKey
            let scoped = (try? context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.scopeKey == key }))) ?? []
            version = scoped.first { $0.sourceFileVersionIDs.contains(versionID) }
        } else { version = nil }
        guard let version, let snapshot = FamiliarFileCatalogService().snapshot(version) else { return self }
        return .init(snapshot: snapshot)
    }
}

struct FamiliarFileLabel: View {
    let file: FamiliarFilePresentation
    var compact = false
    var body: some View {
        HStack(spacing: FamiliarSpacing.medium) {
            if compact { Image(systemName: file.symbol).font(.system(size: FamiliarIconSize.standard)).foregroundStyle(.secondary) }
            else { FamiliarFileThumbnail(url: file.url, identity: file.id, symbol: file.symbol) }
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
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var metadataSize: CGFloat = 13
    let file: FamiliarFilePresentation
    var isUser = false
    var date: Date? = nil
    var onOpen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                if let onOpen {
                    Button(action: onOpen) { fileLabel.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .disabled(file.url == nil)
                        .accessibilityIdentifier("file.open.\(file.id)")
                } else { fileLabel.accessibilityElement(children: .combine) }
                if onOpen != nil, let url = file.url {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(statusColor)
                            .frame(width: FamiliarControlSize.minimumHitTarget, height: FamiliarControlSize.minimumHitTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "common.share"))
                }
            }
            if let date {
                if !isUser && onOpen != nil {
                    FamiliarMessageTimestamp(date: date).accessibilityIdentifier("message.completed")
                } else { FamiliarMessageTimestamp(date: date) }
            }
        }
        .padding(EdgeInsets(top: 15, leading: 9, bottom: 15, trailing: 12))
        .foregroundStyle(isUser ? FamiliarChatAppearance.outgoingText : FamiliarChatAppearance.incomingText)
        .environment(\.familiarOutgoingMessage, isUser)
        .background { FamiliarMessageBubbleBackground(isUser: isUser) }
    }

    private var statusColor: Color { isUser ? FamiliarChatAppearance.outgoingTime : FamiliarChatAppearance.incomingTime }

    private var fileLabel: some View {
        HStack(spacing: 8) {
            FamiliarFileThumbnail(url: file.url, identity: file.id, symbol: file.symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.title).font(.system(size: floor(titleSize))).lineLimit(2).truncationMode(.middle)
                Text(file.metadata).font(.system(size: floor(metadataSize))).monospacedDigit().foregroundStyle(statusColor)
                if file.url == nil {
                    Text(String(localized: file.isRevoked ? "runtime.ui.file_revoked" : "runtime.ui.file_unavailable"))
                        .font(.system(size: floor(metadataSize))).foregroundStyle(statusColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
    }
}
