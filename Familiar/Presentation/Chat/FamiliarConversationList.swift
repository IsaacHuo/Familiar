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
    var projectID: UUID? = nil
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
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var specialRows: AnyView? = nil
    var specialRowsRevision: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .systemBackground
        let view = FamiliarConversationCollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
        view.delegate = context.coordinator
        view.allowsMultipleSelectionDuringEditing = true
        view.keyboardDismissMode = .interactive
        view.contentInsetAdjustmentBehavior = .never
        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        view.topEdgeEffect.style = .soft
        view.bottomEdgeEffect.style = .soft
        view.accessibilityIdentifier = "chats.list"
        context.coordinator.attach(view)
        view.didLayout = { [weak coordinator = context.coordinator, weak view] in
            if let view { coordinator?.restorePosition(in: view) }
        }
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
        private var currentRows: [UUID: FamiliarConversationListSnapshot] = [:]
        private var previousSpecialRevision: Int?
        private let specialID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        private var restoredOffset = false
        private var hasAppliedSnapshot = false
        private var hasUserScrolled = false
        private var updatingLayout = false
        private var pendingOffset: CGFloat?
        private var offsetPublicationScheduled = false
        private var previousEditing = false
        private var previousSelection: Set<UUID> = []
        init(_ parent: FamiliarConversationList) { self.parent = parent }

        func attach(_ view: UICollectionView) {
            let registration = UICollectionView.CellRegistration<UICollectionViewListCell, UUID> { [weak self] cell, _, id in
                guard let self else { return }
                if id == self.specialID {
                    cell.contentConfiguration = UIHostingConfiguration { self.parent.specialRows }.margins(.all, 0)
                    cell.accessories = []
                    cell.accessibilityIdentifier = "chats.specialRows"
                    return
                }
                guard let row = self.currentRows[id] else { return }
                cell.contentConfiguration = UIHostingConfiguration {
                    FamiliarConversationListRow(row: row, isEditing: self.parent.isEditing,
                        onOpen: { [weak self] in
                            guard let self, self.currentRows[id] != nil else { return }
                            if self.parent.isEditing {
                                if self.parent.selection.contains(id) { self.parent.selection.remove(id) }
                                else { self.parent.selection.insert(id) }
                            } else { self.parent.onOpen(id) }
                        }, onAction: { [weak self] action in
                            guard let self, !self.parent.isEditing, let current = self.currentRows[id],
                                  !current.isRunning || (action != .move && action != .delete) else { return }
                            self.parent.onAction(id, action)
                        })
                }
                    .margins(.vertical, 8).margins(.horizontal, 16)
                cell.accessories = [.multiselect()]
                cell.accessibilityIdentifier = "chat.history.row." + id.uuidString
            }
            source = UICollectionViewDiffableDataSource<Int, UUID>(collectionView: view) { collection, index, id in
                collection.dequeueConfiguredReusableCell(using: registration, for: index, item: id)
            }
        }

        func update(_ view: UICollectionView) {
            updatingLayout = true
            defer { updatingLayout = false }
            // Inset updates are layout, not a saved user scroll position.
            pendingOffset = nil
            let previousTop = view.contentInset.top
            let insets = contentInsets(in: view)
            let current = view.contentOffset.y + previousTop
            if view.contentInset != insets {
                view.contentInset = insets
                if restoredOffset { view.contentOffset.y = current - insets.top }
            }
            updateIndicatorInsets(in: view)
            restorePosition(in: view)
            view.isEditing = parent.isEditing
            let rows = parent.rows
            let updated = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            currentRows = updated
            let specialChanged = previousSpecialRevision != parent.specialRowsRevision
            previousSpecialRevision = parent.specialRowsRevision
            let identifiers = (parent.specialRows == nil ? [] : [specialID]) + rows.map(\.id)
            if updated == previous && source.snapshot().itemIdentifiers == identifiers, !specialChanged,
               previousEditing == parent.isEditing && previousSelection == parent.selection { return }
            let editingChanged = previousEditing != parent.isEditing
            previousEditing = parent.isEditing
            previousSelection = parent.selection
            if updated != previous || source.snapshot().itemIdentifiers != identifiers || specialChanged || editingChanged {
                let existing = Set(source.snapshot().itemIdentifiers)
                var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
                snapshot.appendSections([0]); snapshot.appendItems(identifiers)
                if specialChanged, parent.specialRows != nil, existing.contains(specialID) { snapshot.reconfigureItems([specialID]) }
                snapshot.reconfigureItems(rows.filter { existing.contains($0.id) && (editingChanged || previous[$0.id] != $0) }.map(\.id))
                source.apply(snapshot, animatingDifferences: !parent.reduceMotion && !UIAccessibility.isVoiceOverRunning && !editingChanged && !previous.isEmpty) { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.hasAppliedSnapshot = true
                    self.restorePosition(in: view)
                    self.syncSelection(in: view)
                }
                previous = updated
            }
            syncSelection(in: view)
        }

        private func syncSelection(in view: UICollectionView) {
            let selected = Set((view.indexPathsForSelectedItems ?? []).compactMap { source.itemIdentifier(for: $0) })
            for id in selected.subtracting(parent.selection) {
                if let index = source.indexPath(for: id) { view.deselectItem(at: index, animated: false) }
            }
            for id in parent.selection.subtracting(selected) {
                if let index = source.indexPath(for: id) { view.selectItem(at: index, animated: false, scrollPosition: []) }
            }
        }

        func restorePosition(in view: UICollectionView) {
            guard hasAppliedSnapshot, view.bounds.width > 0, view.bounds.height > 0 else { return }
            let normalized = view.contentOffset.y + view.contentInset.top
            let insets = contentInsets(in: view)
            if view.contentInset != insets {
                view.contentInset = insets
                view.contentOffset.y = normalized - insets.top
            }
            // Keep the initial target through self-sizing, then hand ownership to UIKit.
            guard !restoredOffset || !hasUserScrolled else { return }
            restoredOffset = true
            let target = parent.initialOffset - insets.top
            if abs(view.contentOffset.y - target) > 0.5 { view.contentOffset.y = target }
        }

        private func contentInsets(in view: UICollectionView) -> UIEdgeInsets {
            UIEdgeInsets(top: parent.topInset, left: 0, bottom: parent.bottomInset, right: 0)
        }

        private func updateIndicatorInsets(in view: UICollectionView) {
            view.verticalScrollIndicatorInsets = contentInsets(in: view)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard restoredOffset, !updatingLayout else { return }
            // Initial self-sizing/layout callbacks must never become saved user
            // positions. Each page keeps its initial target until its first real drag.
            guard hasUserScrolled else { return }
            pendingOffset = scrollView.contentOffset.y + scrollView.contentInset.top
            guard !offsetPublicationScheduled else { return }
            offsetPublicationScheduled = true
            // UIKit can scroll while SwiftUI is updating insets. Publish after that update.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.offsetPublicationScheduled = false
                if let offset = self.pendingOffset {
                    self.pendingOffset = nil
                    self.parent.onScroll(offset)
                }
            }
        }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            hasUserScrolled = true
        }
        func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
            source.itemIdentifier(for: indexPath) != specialID
        }
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
                  let row = currentRows[id] else { return nil }
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

private final class FamiliarConversationCollectionView: UICollectionView {
    var didLayout: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); didLayout?() }
}

struct FamiliarConversationListRow: View {
    let row: FamiliarConversationListSnapshot
    let isEditing: Bool
    let onOpen: () -> Void
    let onAction: (FamiliarConversationListAction) -> Void
    @ScaledMetric(relativeTo: .body) private var scaledAvatar: CGFloat = 60
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var previewSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var dateSize: CGFloat = 14
    private var avatarSize: CGFloat { min(60, scaledAvatar) }
    private var hue: Double { Double(row.id.uuid.0) / 255 }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(String(row.title.prefix(1)).uppercased())
                .font(.title2.weight(.medium)).foregroundStyle(.white)
                .frame(width: avatarSize, height: avatarSize)
                .background(Color(hue: hue, saturation: 0.52, brightness: 0.8).gradient, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title).font(.system(size: titleSize, weight: .semibold)).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    Spacer(minLength: 6)
                    Text(row.date, format: row.date.isToday ? .dateTime.hour().minute() : .dateTime.month(.twoDigits).day(.twoDigits))
                        .font(.system(size: dateSize)).foregroundStyle(row.isUnread ? FamiliarTheme.accent : .secondary)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text((row.projectName.map { $0 + " · " } ?? "") + (row.preview.isEmpty ? String(localized: "chat.no_messages") : row.preview))
                            .font(.system(size: previewSize))
                            .foregroundStyle(row.hasDraft ? FamiliarTheme.accent : .secondary).lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                    }
                    Spacer(minLength: 4)
                    VStack(spacing: 6) {
                        if row.isRunning { Image(systemName: row.needsAttention ? "questionmark.circle.fill" : "ellipsis.bubble.fill").foregroundStyle(FamiliarTheme.accent) }
                        else if row.hasFailure { Image(systemName: "exclamationmark.circle").foregroundStyle(FamiliarTheme.failure) }
                        if row.isUnread { Circle().fill(FamiliarTheme.accent).frame(width: 10, height: 10) }
                        if row.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tertiary) }
                    }.accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: avatarSize, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue([
            row.isUnread ? String(localized: "chat.unread") : "",
            row.isPinned ? String(localized: "drawer.pinned") : "",
            row.isRunning ? String(localized: row.needsAttention ? "chat.needs_attention" : "chat.running") :
                row.hasFailure ? String(localized: "accessibility.reply_failed") : ""
        ].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityActions {
            if !isEditing {
                Button(String(localized: row.isPinned ? "drawer.unpin" : "drawer.pin")) { onAction(.pin) }
                Button(String(localized: row.isUnread ? "chat.mark_read" : "chat.mark_unread")) { onAction(.read) }
                Button(String(localized: row.isArchived ? "chat.unarchive" : "chat.archive")) { onAction(.archive) }
                Button(String(localized: "conversation.rename")) { onAction(.rename) }
                if !row.isRunning {
                    Button(String(localized: "chat.move")) { onAction(.move) }
                    Button(String(localized: "common.delete")) { onAction(.delete) }
                }
            }
        }
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
                    if message.role == .user { Text(String(message.content.prefix(1_200))).font(FamiliarTypography.body).familiarMessageBubble(isUser: true) }
                    else { FamiliarMarkdownFallbackText(markdown: String(message.finalAnswerText.prefix(1_200))).font(.body).familiarMessageBubble(isUser: false) }
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
        modifier(FamiliarMessageBubbleInsets(isUser: isUser))
    }
}

/// ChatMessageItemCommon.swift:138–139 compact bubble/text constants.
private struct FamiliarMessageBubbleInsets: ViewModifier {
    @Environment(\.displayScale) private var scale
    let isUser: Bool
    func body(content: Content) -> some View {
        content.padding(.horizontal, 11)
            .padding(.top, 6 + 1 / max(1, scale))
            .padding(.bottom, 6 - 1 / max(1, scale))
            .frame(minWidth: 40, minHeight: 35, alignment: .leading)
            .background(isUser ? FamiliarTheme.accent.opacity(0.12) : FamiliarTheme.elevatedFill,
                        in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
    }
}
