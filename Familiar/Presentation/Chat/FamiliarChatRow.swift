import Observation
import SwiftData
import SwiftUI
import UIKit

struct FamiliarMessageRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .body) private var textSize: CGFloat = 17
    @Environment(\.familiarExecutionBlocked) private var executionBlocked
    @Environment(\.familiarOpenMessageFile) private var openMessageFile
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

    @State private var imagePreview: FamiliarImageGalleryRequest?
    @State private var imageUnavailable = false

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
        .fullScreenCover(item: $imagePreview) { request in
            FamiliarImageGalleryView(request: request)
        }
        .alert(String(localized: "attachment.error.source_unavailable"), isPresented: $imageUnavailable) { Button(String(localized: "common.ok"), role: .cancel) {} }
    }

    private var userMessage: some View {
        FamiliarMessageGroupLayout(fraction: dynamicType.isAccessibilitySize ? 0.98 : 0.85, trailing: true) {
            VStack(alignment: .trailing, spacing: FamiliarAISurfaceMetric.spaceS) {
                ForEach(imageAttachments) { attachment in
                    Button {
                        let items = imageAttachments.compactMap { item -> FamiliarImageGalleryItem? in
                            guard let url = FamiliarAttachmentStore.url(for: item.relativePath) else { return nil }
                            return .init(id: item.id, url: url)
                        }
                        if items.contains(where: { $0.id == attachment.id }) { FamiliarImagePresentation.update { imagePreview = .init(id: attachment.id, items: items) } }
                        else { imageUnavailable = true }
                    } label: {
                        FamiliarImageAttachmentView(relativePath: attachment.relativePath)
                            .background(FamiliarImageSourceAnchor(id: attachment.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: String(localized: "attachment.preview"), attachment.filename))
                }

                ForEach(documentAttachments) { attachment in
                    FamiliarFileTile(file: .init(attachment: attachment)) {
                        if let url = FamiliarAttachmentStore.url(for: attachment.relativePath) {
                            openMessageFile?.open(.init(url: url))
                        }
                    }
                    .frame(maxWidth: 280)
                }

                if !message.content.isEmpty {
                    FamiliarTextAndTimeLayout(lineHeight: UIFont.systemFont(ofSize: textSize).lineHeight, text: message.content) {
                        FamiliarMessageText(text: message.content, messageID: message.id, edit: executionBlocked ? nil : { onEdit(message) })
                        FamiliarMessageTimestamp(date: message.createdAt)
                    }
                    .familiarMessageBubble(isUser: true)
                    .modifier(FamiliarSentMessageModifier(id: message.id))
                } else {
                    FamiliarMessageTimestamp(date: message.createdAt)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .modifier(FamiliarSentMessageModifier(id: message.content.isEmpty ? message.id : nil))

        }
    }

    private var imageAttachments: [FamiliarAttachmentSnapshot] {
        message.attachments.filter { $0.kind == .image }
    }

    private var documentAttachments: [FamiliarAttachmentSnapshot] {
        message.attachments.filter { $0.kind != .image }
    }
}

struct FamiliarImageAttachmentView: View {
    let relativePath: String
    @State private var image: UIImage?
    @State private var loading = true

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
                    .overlay {
                        if loading { ProgressView() }
                        else { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                    }
            }
        }
        .task(id: relativePath) {
            image = nil; loading = true
            let result: UIImage?
            if let url = FamiliarAttachmentStore.url(for: relativePath) { result = await FamiliarThumbnailLoader.shared.image(url: url, pixels: 960) }
            else { result = nil }
            guard !Task.isCancelled else { return }
            image = result; loading = false
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
