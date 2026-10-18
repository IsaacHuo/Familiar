import Observation
import SwiftData
import SwiftUI
import UIKit

struct FamiliarMessageRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.familiarExecutionBlocked) private var executionBlocked
    let message: FamiliarMessageSnapshot
    let run: FamiliarAgentRunSnapshot?
    let disclosure: FamiliarRuntimeDisclosureState
    let availableUndoKeys: Set<String>
    let completedUndoKeys: Set<String>
    let onInsertPrompt: (String) -> Void
    let onUndo: (String, String) -> Void
    let onEdit: (FamiliarMessageSnapshot) -> Void
    let onRetry: (FamiliarMessageSnapshot) -> Void
    let onRetryRecovery: (String) -> Void

    @State private var previewAttachment: FamiliarPreparedFilePreview?

    var body: some View {
        Group {
            if message.role == .user {
                userMessage
            } else {
                FamiliarAssistantTurn(
                    message: message,
                    run: run,
                    surfaces: run.map(FamiliarSurfaceStore.projectedSurfaces) ?? [],
                    disclosure: disclosure,
                    availableUndoKeys: availableUndoKeys,
                    completedUndoKeys: completedUndoKeys,
                    onInsertPrompt: onInsertPrompt,
                    onUndo: onUndo,
                    onRetryRecovery: onRetryRecovery,
                    onRetryMessage: { onRetry(message) }
                )
            }
        }
        .navigationDestination(item: $previewAttachment) { file in
            FamiliarAttachmentPreviewView(url: file.url, format: file.format)
        }
    }

    private var userMessage: some View {
        FamiliarMessageGroupLayout(fraction: dynamicType.isAccessibilitySize ? 0.98 : 0.82, trailing: true) {
            VStack(alignment: .trailing, spacing: FamiliarAISurfaceMetric.spaceS) {
                ForEach(imageAttachments) { attachment in
                    Button { if let url = FamiliarAttachmentStore.url(for: attachment.relativePath) { previewAttachment = .init(url: url) } } label: {
                        FamiliarImageAttachmentView(relativePath: attachment.relativePath)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: String(localized: "attachment.preview"), attachment.filename))
                }

                ForEach(documentAttachments) { attachment in
                    FamiliarFileTile(file: .init(attachment: attachment)) {
                        if let url = FamiliarAttachmentStore.url(for: attachment.relativePath) {
                            previewAttachment = .init(url: url)
                        }
                    }
                    .frame(maxWidth: 280)
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(FamiliarTypography.body)
                        .textSelection(.enabled)
                        .familiarMessageBubble(isUser: true)
                }
                Text(message.createdAt, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contextMenu {
                if !message.content.isEmpty {
                    Button { UIPasteboard.general.string = message.content } label: {
                        Label(String(localized: "common.copy"), systemImage: "doc.on.doc")
                    }
                }
                Button { onEdit(message) } label: {
                    Label(String(localized: "common.edit"), systemImage: "pencil")
                }.disabled(executionBlocked)
            }
        }
    }

    private var imageAttachments: [FamiliarAttachmentSnapshot] {
        message.attachments.filter { $0.kind == .image }
    }

    private var documentAttachments: [FamiliarAttachmentSnapshot] {
        message.attachments.filter { $0.kind != .image }
    }
}

struct FamiliarMessageAction: View {
    @Environment(\.familiarReduceMotion) private var reduceMotion
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .font(.system(size: FamiliarIconSize.standard, weight: .regular))
                .frame(width: FamiliarControlSize.minimumHitTarget, height: FamiliarControlSize.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(FamiliarIconButtonStyle())
        .accessibilityLabel(label)
    }
}

struct FamiliarImageAttachmentView: View {
    let relativePath: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: displaySize(for: image).width, height: displaySize(for: image).height)
                    .clipShape(RoundedRectangle(cornerRadius: FamiliarRadius.overlay, style: .continuous))
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: FamiliarRadius.overlay, style: .continuous)
                    .fill(FamiliarTheme.inset)
                    .frame(width: 220, height: 180)
                    .overlay { ProgressView() }
            }
        }
        .task(id: relativePath) {
            if let url = FamiliarAttachmentStore.url(for: relativePath) { image = UIImage(contentsOfFile: url.path) }
        }
    }

    private func displaySize(for image: UIImage) -> CGSize {
        let maximum = CGSize(width: 240, height: 320)
        guard image.size.width > 0, image.size.height > 0 else { return CGSize(width: 220, height: 180) }
        let scale = min(maximum.width / image.size.width, maximum.height / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }
}

struct FamiliarModelSwitchRow: View {
    let marker: FamiliarModelSwitchSnapshot

    var body: some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
            Rectangle().fill(FamiliarTheme.line).frame(height: FamiliarAISurfaceMetric.hairline)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(FamiliarTheme.inkSecondary).lineLimit(1)
            Rectangle().fill(FamiliarTheme.line).frame(height: FamiliarAISurfaceMetric.hairline)
        }
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        let provider = FamiliarProviderCatalog.descriptor(for: marker.currentProviderID)
        return String(format: String(localized: "model.switched_marker"), provider?.displayName ?? marker.currentProviderID, provider?.model(for: marker.currentModelID).displayName ?? marker.currentModelID)
    }
}
