import Observation
import SwiftData
import SwiftUI
import UIKit

/// Shared, local attachment ordering and status ownership for chat and previews.
nonisolated struct FamiliarMessageAttachmentPresentation {
    let attachments: [FamiliarAttachmentSnapshot]
    let hasCaption: Bool
    let outerNeighbors: FamiliarMessageNeighbors

    init(attachments: [FamiliarAttachmentSnapshot], hasCaption: Bool, neighbors: FamiliarMessageNeighbors = .init()) {
        self.attachments = attachments.filter { $0.kind == .image } + attachments.filter { $0.kind != .image }
        self.hasCaption = hasCaption
        outerNeighbors = neighbors
    }

    var statusAttachmentID: UUID? { hasCaption ? nil : attachments.last?.id }
    var captionNeighbors: FamiliarMessageNeighbors {
        .init(top: outerNeighbors.top || !attachments.isEmpty, bottom: outerNeighbors.bottom)
    }
    func neighbors(for id: UUID) -> FamiliarMessageNeighbors {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return outerNeighbors }
        return .init(top: outerNeighbors.top || index > 0,
                     bottom: outerNeighbors.bottom || index < attachments.count - 1 || hasCaption)
    }
    func hasContentAbove(_ id: UUID) -> Bool { attachments.first?.id != id }
    func hasContentBelow(_ id: UUID) -> Bool { attachments.last?.id != id || hasCaption }
}

struct FamiliarMessageRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .body) private var textSize: CGFloat = 17
    @Environment(\.familiarExecutionBlocked) private var executionBlocked
    @Environment(\.familiarOpenMessageFile) private var openMessageFile
    @Environment(\.familiarMessageNeighbors) private var neighbors
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
        let presentation = FamiliarMessageAttachmentPresentation(attachments: message.attachments, hasCaption: !message.content.isEmpty, neighbors: neighbors)
        return FamiliarMessageGroupLayout(accessibilityWide: dynamicType.isAccessibilitySize, trailing: true) {
            VStack(alignment: .trailing, spacing: FamiliarChatAppearance.attachmentSpacing) {
                ForEach(imageAttachments) { attachment in
                    Button {
                        let items = imageAttachments.compactMap { item -> FamiliarImageGalleryItem? in
                            guard let url = FamiliarAttachmentStore.url(for: item.relativePath) else { return nil }
                            return .init(id: item.id, url: url)
                        }
                        if items.contains(where: { $0.id == attachment.id }) { FamiliarImagePresentation.update { imagePreview = .init(id: attachment.id, items: items) } }
                        else { imageUnavailable = true }
                    } label: {
                        FamiliarImageAttachmentView(relativePath: attachment.relativePath,
                            date: attachment.id == presentation.statusAttachmentID ? message.createdAt : nil,
                            joinsContentAbove: presentation.hasContentAbove(attachment.id),
                            joinsContentBelow: presentation.hasContentBelow(attachment.id))
                            .background(FamiliarImageSourceAnchor(id: attachment.id))
                            .environment(\.familiarMessageNeighbors, presentation.neighbors(for: attachment.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: String(localized: "attachment.preview"), attachment.filename))
                }

                ForEach(documentAttachments) { attachment in
                    FamiliarFileTile(file: .init(attachment: attachment), isUser: true, date: attachment.id == presentation.statusAttachmentID ? message.createdAt : nil) {
                        if let url = FamiliarAttachmentStore.url(for: attachment.relativePath) {
                            openMessageFile?.open(.init(url: url))
                        }
                    }
                    .frame(maxWidth: 300)
                    .environment(\.familiarMessageNeighbors, presentation.neighbors(for: attachment.id))
                }

                if !message.content.isEmpty {
                    FamiliarTextAndTimeLayout(fontSize: textSize, text: message.content) {
                        FamiliarMessageText(text: message.content, actions: .init(text: message.content, messageID: message.id, edit: executionBlocked ? nil : { onEdit(message) }))
                        FamiliarMessageTimestamp(date: message.createdAt)
                    }
                    .familiarMessageBubble(isUser: true)
                    .environment(\.familiarMessageNeighbors, presentation.captionNeighbors)
                    .modifier(FamiliarSentMessageModifier(id: message.id))
                } else if message.attachments.isEmpty {
                    FamiliarMessageTimestamp(date: message.createdAt)
                        .environment(\.familiarOutgoingMessage, true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .environment(\.familiarOutgoingMessage, true)
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
    @Environment(\.familiarMessageNeighbors) private var neighbors
    @Environment(\.familiarOutgoingMessage) private var outgoing
    let relativePath: String
    var date: Date? = nil
    var joinsContentAbove = false
    var joinsContentBelow = false
    @State private var image: UIImage?
    @State private var loading = true

    var body: some View {
        Group {
            if let image {
                FamiliarChatImageLayout(nativeSize: image.size) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .clipped()
            } else {
                FamiliarTheme.inset
                    .frame(width: 220, height: 180)
                    .overlay {
                        if loading { ProgressView() }
                        else { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                    }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let date {
                FamiliarMessageTimestamp(date: date, onMedia: true)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(FamiliarChatAppearance.serviceFill, in: Capsule())
                    .padding(FamiliarChatAppearance.mediaStatusInset)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(FamiliarChatAppearance.mediaShape(outgoing: outgoing, neighbors: neighbors,
            contentAbove: joinsContentAbove, contentBelow: joinsContentBelow))
        .accessibilityValue(loading ? String(localized: "attachment.loading_image") : image == nil ? String(localized: "attachment.error.source_unavailable") : "")
        .task(id: relativePath) {
            image = nil; loading = true
            let result: UIImage?
            if let url = FamiliarAttachmentStore.url(for: relativePath) { result = await FamiliarThumbnailLoader.shared.image(url: url, pixels: 960) }
            else { result = nil }
            guard !Task.isCancelled else { return }
            image = result; loading = false
        }
    }


}

/// Telegram's constrained media sizing: fit within 300×380, retain a 170×74
/// minimum viewport, and crop extreme aspect ratios without stretching pixels.
struct FamiliarChatImageLayout: Layout {
    let nativeSize: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        size(availableWidth: proposal.width ?? 300)
    }

    func size(availableWidth: CGFloat) -> CGSize {
        let nativeWidth = max(1, nativeSize.width), nativeHeight = max(1, nativeSize.height)
        let fit = min(300 / nativeWidth, 380 / nativeHeight)
        let width = min(max(1, availableWidth), max(170, min(nativeWidth, nativeWidth * fit)))
        return .init(width: width, height: min(380, max(74, width * nativeHeight / nativeWidth)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: .init(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .init(bounds.size))
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
