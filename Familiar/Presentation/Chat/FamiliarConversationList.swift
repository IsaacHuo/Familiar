import SwiftUI
import UIKit

struct FamiliarConversationListSnapshot: Identifiable, Equatable {
    let id: UUID
    let title: String
    let preview: String
    let projectName: String?
    let date: Date
    let isPinned: Bool
    let isUnread: Bool
    let isArchived: Bool
    let hasDraft: Bool
    let isRunning: Bool
    let needsAttention: Bool
    let hasFailure: Bool
}

enum FamiliarConversationListAction { case pin, read, archive, rename, move, delete }

/// UIKit owns native list identity, multi-selection and preview commit. Cells remain SwiftUI.
struct FamiliarConversationList: UIViewRepresentable {
    let rows: [FamiliarConversationListSnapshot]
    let isEditing: Bool
    @Binding var selection: Set<UUID>
    let initialOffset: CGFloat
    let reduceMotion: Bool
    let onScroll: (CGFloat) -> Void
    let onOpen: (UUID) -> Void
    let onAction: (UUID, FamiliarConversationListAction) -> Void
    let preview: (UUID) -> [FamiliarMessageSnapshot]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .systemBackground
        let view = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
        view.delegate = context.coordinator
        view.allowsMultipleSelectionDuringEditing = true
        view.keyboardDismissMode = .interactive
        view.contentInsetAdjustmentBehavior = .automatic
        view.accessibilityIdentifier = "chats.list"
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(view)
    }

    @MainActor final class Coordinator: NSObject, UICollectionViewDelegate {
        var parent: FamiliarConversationList
        private var source: UICollectionViewDiffableDataSource<Int, UUID>!
        private var previous: [UUID: FamiliarConversationListSnapshot] = [:]
        private var restoredOffset = false
        private var previousEditing = false
        private var previousSelection: Set<UUID> = []
        init(_ parent: FamiliarConversationList) { self.parent = parent }

        func attach(_ view: UICollectionView) {
            let registration = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> { [weak self] cell, _, id in
                guard let self, let row = self.parent.rows.first(where: { $0.id == id }) else { return }
                cell.contentConfiguration = UIHostingConfiguration { FamiliarConversationListRow(row: row) }
                    .margins(.vertical, 10).margins(.horizontal, 16)
                cell.accessories = [.multiselect()]
                cell.accessibilityIdentifier = "chat.history.row." + id.uuidString
            }
            source = UICollectionViewDiffableDataSource<Int, UUID>(collectionView: view) { collection, index, id in
                collection.dequeueConfiguredReusableCell(using: registration, for: index, item: id)
            }
        }

        func update(_ view: UICollectionView) {
            view.isEditing = parent.isEditing
            let rows = parent.rows
            let updated = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            if updated == previous && source.snapshot().itemIdentifiers == rows.map(\.id),
               previousEditing == parent.isEditing && previousSelection == parent.selection { return }
            previousEditing = parent.isEditing
            previousSelection = parent.selection
            if updated != previous || source.snapshot().itemIdentifiers != rows.map(\.id) {
                let existing = Set(source.snapshot().itemIdentifiers)
                var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
                snapshot.appendSections([0]); snapshot.appendItems(rows.map(\.id))
                snapshot.reconfigureItems(rows.filter { existing.contains($0.id) && previous[$0.id] != $0 }.map(\.id))
                source.apply(snapshot, animatingDifferences: !parent.reduceMotion && !previous.isEmpty)
                previous = updated
            }
            for id in rows.map(\.id) {
                guard let index = source.indexPath(for: id) else { continue }
                if parent.selection.contains(id) { view.selectItem(at: index, animated: false, scrollPosition: []) }
                else { view.deselectItem(at: index, animated: false) }
            }
            if !restoredOffset, !rows.isEmpty {
                restoredOffset = true
                view.layoutIfNeeded()
                view.contentOffset.y = max(-view.adjustedContentInset.top, parent.initialOffset)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { parent.onScroll(scrollView.contentOffset.y) }
        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard let id = source.itemIdentifier(for: indexPath) else { return }
            if parent.isEditing { parent.selection.insert(id) }
            else { collectionView.deselectItem(at: indexPath, animated: false); parent.onOpen(id) }
        }
        func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
            if parent.isEditing, let id = source.itemIdentifier(for: indexPath) { parent.selection.remove(id) }
        }

        func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
            guard !parent.isEditing, let index = indexPaths.first, let id = source.itemIdentifier(for: index),
                  let row = parent.rows.first(where: { $0.id == id }) else { return nil }
            let messages = parent.preview(id)
            return UIContextMenuConfiguration(identifier: id.uuidString as NSString, previewProvider: {
                let controller = UIHostingController(rootView: FamiliarConversationPreview(title: row.title, messages: messages))
                controller.preferredContentSize = CGSize(width: max(240, collectionView.bounds.width - 32), height: min(500, collectionView.window?.bounds.height ?? 600) * 0.8)
                return controller
            }, actionProvider: { [weak self] _ in
                guard let self else { return UIMenu() }
                @MainActor func action(_ key: String.LocalizationValue, _ symbol: String, _ value: FamiliarConversationListAction, disabled: Bool = false, destructive: Bool = false) -> UIAction {
                    var attributes: UIMenuElement.Attributes = []
                    if disabled { attributes.insert(.disabled) }
                    if destructive { attributes.insert(.destructive) }
                    return UIAction(title: String(localized: key), image: UIImage(systemName: symbol), attributes: attributes) { [weak self] _ in self?.parent.onAction(id, value) }
                }
                return UIMenu(children: [
                    UIAction(title: String(localized: "chat.open"), image: UIImage(systemName: "bubble.left")) { [weak self] _ in self?.parent.onOpen(id) },
                    action(row.isPinned ? "drawer.unpin" : "drawer.pin", "pin", .pin),
                    action(row.isUnread ? "chat.mark_read" : "chat.mark_unread", "checkmark.bubble", .read),
                    action(row.isArchived ? "chat.unarchive" : "chat.archive", "archivebox", .archive),
                    action("conversation.rename", "pencil", .rename),
                    action("chat.move", "folder", .move, disabled: row.isRunning),
                    action("common.delete", "trash", .delete, disabled: row.isRunning, destructive: true)
                ])
            })
        }

        func collectionView(_ collectionView: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: any UIContextMenuInteractionCommitAnimating) {
            guard let value = configuration.identifier as? String, let id = UUID(uuidString: value) else { return }
            animator.addCompletion { [weak self] in self?.parent.onOpen(id) }
        }
    }
}

struct FamiliarConversationListRow: View {
    let row: FamiliarConversationListSnapshot
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 54
    private var hue: Double { Double(row.id.uuid.0) / 255 }
    var body: some View {
        HStack(alignment: .top, spacing: FamiliarSpacing.medium) {
            Text(String(row.title.prefix(1)).uppercased())
                .font(.title2.weight(.medium)).foregroundStyle(.white)
                .frame(width: avatarSize, height: avatarSize)
                .background(Color(hue: hue, saturation: 0.52, brightness: 0.8).gradient, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title).font(.headline).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(row.date, format: row.date.isToday ? .dateTime.hour().minute() : .dateTime.month(.twoDigits).day(.twoDigits))
                        .font(.caption).foregroundStyle(row.isUnread ? FamiliarTheme.accent : .secondary)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let project = row.projectName {
                            Text(project).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(row.preview.isEmpty ? String(localized: "chat.no_messages") : row.preview)
                            .font(FamiliarTypography.secondary)
                            .foregroundStyle(row.hasDraft ? FamiliarTheme.accent : .secondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    VStack(spacing: 6) {
                        if row.isRunning { Image(systemName: row.needsAttention ? "questionmark.circle.fill" : "ellipsis.bubble.fill").foregroundStyle(FamiliarTheme.accent) }
                        else if row.hasFailure { Image(systemName: "exclamationmark.circle").foregroundStyle(FamiliarTheme.failure) }
                        if row.isUnread { Circle().fill(FamiliarTheme.accent).frame(width: 10, height: 10) }
                        else if row.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tertiary) }
                    }.accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: avatarSize, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(row.isUnread ? String(localized: "chat.unread") : "")
    }
}

private extension Date { var isToday: Bool { Calendar.current.isDateInToday(self) } }

struct FamiliarConversationPreview: View {
    let title: String
    let messages: [FamiliarMessageSnapshot]
    var body: some View {
        VStack(spacing: FamiliarSpacing.medium) {
            Text(title).font(.headline).lineLimit(1).padding(.top, FamiliarSpacing.large)
            Divider()
            ScrollView {
                VStack(spacing: FamiliarSpacing.small) {
                    ForEach(messages) { message in
                        FamiliarReadOnlyMessage(message: message)
                    }
                }.padding(FamiliarSpacing.medium)
            }.defaultScrollAnchor(.bottom)
        }
        .background(FamiliarTheme.canvas)
        .allowsHitTesting(false)
        .accessibilityIdentifier("chat.preview")
    }
}

struct FamiliarReadOnlyMessage: View {
    let message: FamiliarMessageSnapshot
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 30) }
            VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
                if !message.content.isEmpty {
                    if message.role == .user { Text(message.content).font(FamiliarTypography.body).familiarMessageBubble(isUser: true) }
                    else { FamiliarMarkdownWebView(markdown: message.content, sources: message.citedSources).familiarMessageBubble(isUser: false) }
                }
                ForEach(message.attachments) { attachment in
                    if attachment.kind == .image { FamiliarImageAttachmentView(relativePath: attachment.relativePath) }
                    else { FamiliarFileLabel(file: .init(attachment: attachment)) }
                }
            }
            if message.role == .assistant { Spacer(minLength: 12) }
        }
    }
}

extension View {
    func familiarMessageBubble(isUser: Bool) -> some View {
        padding(.horizontal, FamiliarSpacing.medium)
            .padding(.vertical, FamiliarSpacing.small)
            .background(isUser ? FamiliarTheme.accent.opacity(0.12) : FamiliarTheme.elevatedFill,
                        in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
    }
}
