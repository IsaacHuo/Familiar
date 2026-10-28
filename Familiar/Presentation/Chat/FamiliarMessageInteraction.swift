import SwiftUI
import UIKit

@MainActor final class FamiliarMessageSelectionControl { var finish: (() -> Void)? }

struct FamiliarMessageActions {
    let text: String
    var messageID: UUID? = nil
    var blockID: String? = nil
    var edit: (() -> Void)? = nil
    var retry: (() -> Void)? = nil
    var available: [FamiliarMessageAction] {
        guard !text.isEmpty else { return [] }
        return [.copy, .select] + (edit == nil ? [] : [.edit]) + (retry == nil ? [] : [.retry])
    }
    struct Context: Equatable {
        let messageID: UUID?
        let blockID: String?
        let text: String
        let available: [FamiliarMessageAction]
    }
    var context: Context { .init(messageID: messageID, blockID: blockID, text: text, available: available) }
}

enum FamiliarMessageAction: String {
    case copy, select, edit, retry
    var title: String {
        switch self {
        case .copy: String(localized: "common.copy")
        case .select: String(localized: "message.select_text")
        case .edit: String(localized: "common.edit")
        case .retry: String(localized: "message.retry")
        }
    }
}

/// Attached to the actual text view, not a transparent gesture layer over its children.
@MainActor final class FamiliarMessageInteraction: NSObject, UIContextMenuInteractionDelegate {
    weak var view: UIView?
    weak var scroll: FamiliarChatScrollSession?
    var actions: FamiliarMessageActions? {
        didSet {
            if oldValue?.context != actions?.context { invalidatePendingActions() }
            if oldValue?.available != actions?.available { updateAccessibilityActions() }
        }
    }
    var selectedTextSink: FamiliarSelectedTextSink?
    var selectedText = ""
    var selectedRect = CGRect.zero
    var interactiveRegions: [CGRect] = []
    var selectText: ((CGPoint) -> Void)?
    var endTextSelection: (() -> Void)?
    var selectionChanged: ((Bool) -> Void)?
    private(set) var selecting = false
    private var inspecting = false
    private var actionAfterMenu: (() -> Void)?
    private let selectionID = UUID()
    private var selectionGeneration = UUID()
    private var editMenuVisible = false
    private var actionAfterEditMenu: (() -> Void)?
    private var hasSelectedText = false
    private var location = CGPoint.zero
    private var interaction: UIContextMenuInteraction?
    private var menuID: UUID?
    private var menuActions: FamiliarMessageActions?
    private var editMenuID = UUID()

    private func invalidatePendingActions() {
        menuID = nil; menuActions = nil
        actionAfterMenu = nil; actionAfterEditMenu = nil
        editMenuID = UUID(); editMenuVisible = false
        if inspecting && !selecting { scroll?.endInspection(); inspecting = false }
    }

    private func acceptsMenu(_ id: UUID, context: FamiliarMessageActions.Context) -> Bool {
        menuID == id && menuActions?.context == context && actions?.context == context && view?.window != nil
    }

    func attach(to view: UIView) {
        self.view = view
        let interaction = UIContextMenuInteraction(delegate: self)
        self.interaction = interaction
        view.addInteraction(interaction)
        updateAccessibilityActions()
    }

    private func updateAccessibilityActions() {
        // UITextView exposes these on its native text element. WebKit keeps its
        // structured DOM tree and supplies equivalent labelled DOM buttons.
        guard view is UITextView else { return }
        view?.accessibilityCustomActions = (actions?.available ?? []).map { kind in
            UIAccessibilityCustomAction(name: kind.title) { [weak self] _ in self?.perform(kind) ?? false }
        }
    }

    @discardableResult func perform(_ kind: FamiliarMessageAction) -> Bool {
        guard view?.window != nil, let actions, actions.available.contains(kind) else { return false }
        switch kind {
        case .copy:
            UIPasteboard.general.string = actions.text
            FamiliarHaptics.shared.perform(.success)
            FamiliarAccessibility.announce(String(localized: "common.copied"))
        case .select:
            location = CGPoint(x: -1, y: -1) // Accessibility selects the whole message.
            beginSelection()
        case .edit: actions.edit?()
        case .retry: actions.retry?()
        }
        return true
    }

    func detach() {
        selectionChanged = nil
        invalidatePendingActions()
        finishSelection()
        if inspecting { scroll?.endInspection(); inspecting = false }
        if let interaction { view?.removeInteraction(interaction) }
        view?.accessibilityCustomActions = nil
        interaction = nil
        view = nil
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard !selecting, let actions, !actions.text.isEmpty,
              !interactiveRegions.contains(where: { $0.contains(location) }) else { return nil }
        if let textView = view as? UITextView,
           FamiliarMessageNativeLink.url(at: location, in: textView) != nil { return nil }
        self.location = location
        invalidatePendingActions()
        let id = UUID()
        menuID = id; menuActions = actions
        // Capture the message at menu opening; later UI updates cannot retarget an action.
        return UIContextMenuConfiguration(identifier: id as NSUUID, previewProvider: nil) { [weak self] _ in
            self?.makeContextMenu(id: id)
        }
    }

    /// The actual UIKit provider and regressions share one menu composition path.
    func makeContextMenu(id: UUID) -> UIMenu? {
        guard let actions = menuActions, acceptsMenu(id, context: actions.context) else { return nil }
        let context = actions.context
        var items: [UIMenuElement] = [
            UIAction(title: String(localized: "common.copy"), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                guard self?.acceptsMenu(id, context: context) == true else { return }
                UIPasteboard.general.string = actions.text
                FamiliarHaptics.shared.perform(.success)
                FamiliarAccessibility.announce(String(localized: "common.copied"))
            },
            UIAction(title: String(localized: "message.select_text"), image: UIImage(systemName: "text.cursor")) { [weak self] _ in
                guard self?.acceptsMenu(id, context: context) == true else { return }
                self?.actionAfterMenu = { [weak self] in self?.beginSelection() }
            }
        ]
        if let edit = actions.edit {
            items.append(UIAction(title: String(localized: "common.edit"), image: UIImage(systemName: "pencil")) { [weak self] _ in
                guard self?.acceptsMenu(id, context: context) == true else { return }
                self?.actionAfterMenu = edit
            })
        }
        if let retry = actions.retry {
            items.append(UIAction(title: String(localized: "message.retry"), image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                guard self?.acceptsMenu(id, context: context) == true else { return }
                self?.actionAfterMenu = retry
            })
        }
        return UIMenu(children: items)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        guard let id = configuration.identifier as? UUID, let context = menuActions?.context, acceptsMenu(id, context: context) else { return }
        beginInspection()
    }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        guard let id = configuration.identifier as? UUID, let context = menuActions?.context, menuID == id else { return }
        let action = actionAfterMenu
        actionAfterMenu = nil
        let complete: () -> Void = { [weak self] in
            guard let self, self.menuID == id, self.menuActions?.context == context else { return }
            self.menuID = nil; self.menuActions = nil
            if self.inspecting && !self.selecting { self.scroll?.endInspection(); self.inspecting = false }
            if self.actions?.context == context && self.view?.window != nil { action?() }
        }
        if let animator { animator.addCompletion(complete) }
        else { complete() }
    }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let id = configuration.identifier as? UUID, let context = menuActions?.context,
              acceptsMenu(id, context: context), let view, let window = view.window else { return nil }
        var visible = view.bounds
        var ancestor = view.superview
        while let parent = ancestor {
            if parent.clipsToBounds { visible = visible.intersection(view.convert(parent.bounds, from: parent)) }
            ancestor = parent.superview
        }
        visible = visible.intersection(view.convert(window.safeAreaLayoutGuide.layoutFrame, from: window))
        guard !visible.isNull, visible.width > 0, visible.height > 0,
              let snapshot = view.resizableSnapshotView(from: visible, afterScreenUpdates: false, withCapInsets: .zero) else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .secondarySystemBackground
        parameters.visiblePath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: visible.size), cornerRadius: 16)
        let center = view.convert(CGPoint(x: visible.midX, y: visible.midY), to: window)
        return UITargetedPreview(view: snapshot, parameters: parameters, target: UIPreviewTarget(container: window, center: center))
    }

    /// TextSelectionNode: actions capture the selection; clear it before returning to input.
    func editActions(text: String) -> [UIMenuElement] {
        guard selecting, !text.isEmpty, let sink = selectedTextSink, sink.isAvailable, let actions, let messageID = actions.messageID else { return [] }
        let frozenText = String(text.prefix(4_000)), source = actions.text, blockID = actions.blockID
        let generation = selectionGeneration
        return FamiliarSelectionAction.allCases.map { kind in
            UIAction(title: kind.title, image: UIImage(systemName: kind.symbol)) { [weak self] _ in
                guard let self, self.selecting, self.selectionGeneration == generation,
                      self.actions?.messageID == messageID, self.actions?.blockID == blockID, self.actions?.text == source else { return }
                self.actionAfterEditMenu = { sink.perform(kind, text: frozenText) }
                self.finishSelection()
                if !self.editMenuVisible {
                    let id = self.editMenuID
                    DispatchQueue.main.async { [weak self] in
                        guard self?.editMenuID == id else { return }
                        self?.finishEditMenuAction()
                    }
                }
            }
        }
    }

    func editMenuWillPresent() { editMenuID = UUID(); editMenuVisible = true }
    func editMenuWillDismiss(_ animator: any UIEditMenuInteractionAnimating) {
        let id = editMenuID
        animator.addCompletion { [weak self] in
            guard let self, self.editMenuID == id else { return }
            self.editMenuVisible = false; self.finishEditMenuAction()
        }
    }
    private func finishEditMenuAction() {
        let action = actionAfterEditMenu; actionAfterEditMenu = nil
        guard view?.window != nil else { return }; action?()
    }

    func beginSelection() {
        guard !selecting else { return }
        selectionGeneration = UUID()
        scroll?.beginMessageSelection(selectionID) { [weak self] in self?.finishSelection() }
        selecting = true
        hasSelectedText = false
        beginInspection()
        selectionChanged?(true)
        let context = actions?.context, generation = selectionGeneration
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.selecting, self.selectionGeneration == generation else { return }
            guard self.actions?.context == context else { self.finishSelection(); return }
            self.selectText?(self.location)
            FamiliarAccessibility.announce(String(localized: "accessibility.selection_started"))
        }
    }
    func finishSelection() {
        guard selecting else { return }
        selecting = false
        selectionGeneration = UUID()
        scroll?.endMessageSelection(selectionID)
        selectedText = ""; selectedRect = .zero
        endTextSelection?()
        selectionChanged?(false)
        if inspecting { scroll?.endInspection(); inspecting = false }
    }
    func didChangeSelection(hasText: Bool) {
        guard selecting else { return }
        if hasText { hasSelectedText = true }
        else if hasSelectedText { finishSelection() }
    }
    private func beginInspection() {
        if !inspecting { inspecting = true; scroll?.beginInspection() }
    }
}

struct FamiliarMessageText: View {
    let text: String
    let actions: FamiliarMessageActions
    @State private var selecting = false
    @State private var selectionControl = FamiliarMessageSelectionControl()
    var body: some View {
        FamiliarMessageNativeText(text: text, actions: actions,
            onSelection: { selecting = $0 }, onFinish: { selectionControl.finish = $0 })
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Button(String(localized: "common.done")) { selectionControl.finish?() }
                        .font(.subheadline).frame(minHeight: 44).buttonStyle(.glass)
                        .offset(y: -44).accessibilityIdentifier("message.selection.done")
                }
            }

    }
}

private struct FamiliarMessageNativeText: UIViewRepresentable {
    @Environment(\.openURL) private var openURL
    @Environment(\.familiarOutgoingMessage) private var outgoing
    @Environment(\.familiarChatScrollSession) private var scroll
    @Environment(\.familiarSelectedTextSink) private var selectedTextSink
    @Environment(\.familiarMessageSearchTerm) private var searchTerm
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17
    let text: String
    let actions: FamiliarMessageActions
    let onSelection: (Bool) -> Void
    let onFinish: (@escaping () -> Void) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UITextView {
        let view = FamiliarMessageNativeTextView.makeTextKit1View()
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isEditable = false; view.isSelectable = false; view.isScrollEnabled = false
        view.delegate = context.coordinator
        let linkTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.openLink(_:)))
        linkTap.delegate = context.coordinator
        linkTap.cancelsTouchesInView = false
        view.addGestureRecognizer(linkTap)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.interaction.attach(to: view)
        view.onEscape = { [weak interaction = context.coordinator.interaction] in
            guard interaction?.selecting == true else { return false }
            interaction?.finishSelection(); return true
        }
        context.coordinator.interaction.selectText = { [weak view] _ in
            view?.isSelectable = true; view?.becomeFirstResponder(); view?.selectAll(nil)
        }
        context.coordinator.interaction.endTextSelection = { [weak view] in
            view?.selectedRange = NSRange(location: 0, length: 0)
            view?.isSelectable = false; view?.resignFirstResponder()
        }
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        if view.text != text || context.coordinator.searchTerm != searchTerm || view.font?.pointSize != fontSize || context.coordinator.outgoing != outgoing {
            if context.coordinator.searchTerm != searchTerm, context.coordinator.interaction.selecting {
                let interaction = context.coordinator.interaction
                Task { @MainActor [weak interaction] in interaction?.finishSelection() }
            }
            context.coordinator.searchTerm = searchTerm
            context.coordinator.outgoing = outgoing
            let foreground = UIColor(outgoing ? FamiliarChatAppearance.outgoingText : FamiliarChatAppearance.incomingText)
            let value = NSMutableAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: foreground])
            let range = NSRange(location: 0, length: text.utf16.count)
            for match in FamiliarMessageNativeLink.detector?.matches(in: text, range: range) ?? [] {
                guard let url = match.url else { continue }
                value.addAttributes([.link: url, .foregroundColor: UIColor(FamiliarChatAppearance.link)], range: match.range)
            }
            view.linkTextAttributes = [.foregroundColor: UIColor(FamiliarChatAppearance.link)]
            if !searchTerm.isEmpty {
                var start = text.startIndex
                var count = 0
                while start < text.endIndex, count < 500,
                      let range = text.range(of: searchTerm, options: FamiliarSearchText.options, range: start..<text.endIndex, locale: .current) {
                    value.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), range: NSRange(range, in: text))
                    start = range.upperBound; count += 1
                }
            }
            view.attributedText = value
        }
        context.coordinator.onOpenURL = { url in openURL(url) }
        let interaction = context.coordinator.interaction
        interaction.scroll = scroll
        interaction.actions = actions
        interaction.selectedTextSink = selectedTextSink
        interaction.selectionChanged = onSelection
        onFinish { [weak interaction] in interaction?.finishSelection() }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let font = uiView.font ?? .preferredFont(forTextStyle: .body)
        let natural = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        let fittedWidth = min(width, max(1, ceil(natural.width) + 1))
        return CGSize(width: fittedWidth, height: ceil(uiView.sizeThatFits(CGSize(width: fittedWidth, height: .greatestFiniteMagnitude)).height))
    }
    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) { coordinator.interaction.detach() }
    @MainActor final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        let interaction = FamiliarMessageInteraction()
        var onOpenURL: ((URL) -> Void)?
        @objc func openLink(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, !interaction.selecting, let view = gesture.view as? UITextView,
                  let url = FamiliarMessageNativeLink.url(at: gesture.location(in: view), in: view) else { return }
            onOpenURL?(url)
        }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard !interaction.selecting, let view = gesture.view as? UITextView else { return false }
            return FamiliarMessageNativeLink.url(at: gesture.location(in: view), in: view) != nil
        }
        var searchTerm = ""
        var outgoing: Bool?
        var updating = false
        @objc(textView:editMenuForTextInRanges:suggestedActions:)
        func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            let text = textView.text ?? ""
            let valid = ranges.map(\.rangeValue).filter { $0.location != NSNotFound && NSMaxRange($0) <= text.utf16.count }
            let selected = valid.map { (text as NSString).substring(with: $0) }.joined(separator: "\n")
            return UIMenu(children: suggestedActions + interaction.editActions(text: selected))
        }
        func textView(_ textView: UITextView, willPresentEditMenuWith animator: any UIEditMenuInteractionAnimating) { interaction.editMenuWillPresent() }
        func textView(_ textView: UITextView, willDismissEditMenuWith animator: any UIEditMenuInteractionAnimating) { interaction.editMenuWillDismiss(animator) }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updating else { return }
            interaction.didChangeSelection(hasText: textView.selectedRange.length > 0)
        }
    }
}

final class FamiliarMessageNativeTextView: UITextView {
    var onEscape: (() -> Bool)?
    static func makeTextKit1View() -> FamiliarMessageNativeTextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let view = FamiliarMessageNativeTextView(frame: .zero, textContainer: container)
        withExtendedLifetime(storage) {}
        return view
    }
    override func accessibilityPerformEscape() -> Bool { onEscape?() == true || super.accessibilityPerformEscape() }
}

/// TextKit hit-testing keeps links on the native text surface, without an
/// overlay that intercepts selection handles or the message context menu.
@MainActor private enum FamiliarMessageNativeLink {
    static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    static func url(at point: CGPoint, in view: UITextView) -> URL? {
        let layout = view.layoutManager
        let location = CGPoint(x: point.x + view.contentOffset.x - view.textContainerInset.left,
                               y: point.y + view.contentOffset.y - view.textContainerInset.top)
        guard layout.numberOfGlyphs > 0 else { return nil }
        let glyph = layout.glyphIndex(for: location, in: view.textContainer)
        guard glyph < layout.numberOfGlyphs,
              layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer).contains(location) else { return nil }
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < view.attributedText.length else { return nil }
        return view.attributedText.attribute(.link, at: index, effectiveRange: nil) as? URL
    }
}
