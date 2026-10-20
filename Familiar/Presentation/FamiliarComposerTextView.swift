import SwiftUI
import UIKit

@MainActor final class FamiliarComposerInputControl {
    weak var view: UITextView?
    weak var attachmentView: UIView?
    var publish: (() -> Void)?
    func commitText() {
        view?.unmarkText()
        // These actions close editing; resign also commits pending keyboard autocorrection.
        view?.resignFirstResponder()
        publish?()
    }
}

/// One native text layout owns the caret, placeholder, measurement and selection.
struct FamiliarComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: FamiliarComposerSelection?
    let focused: Binding<Bool>
    let fontSize: CGFloat
    let placeholder: String
    let editable: Bool
    let centersSingleLine: Bool
    let trailingInset: CGFloat
    let onHeight: (CGFloat) -> Void
    let inputControl: FamiliarComposerInputControl

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> FamiliarComposerNativeTextView {
        let view = FamiliarComposerNativeTextView(usingTextLayoutManager: false)
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.isScrollEnabled = true
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.keyboardDismissMode = .interactive
        view.showsVerticalScrollIndicator = false
        view.accessibilityIdentifier = "composer.input"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        inputControl.view = view
        inputControl.publish = { [weak coordinator = context.coordinator, weak view] in
            if let view { coordinator?.textViewDidChange(view) }
        }
        view.didMount = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.updateFocus(in: view, force: true)
        }
        view.heightChanged = { [weak coordinator = context.coordinator, weak view] height in
            guard let view else { return }
            let measuredText = view.text, width = view.bounds.width, fontSize = view.font?.pointSize
            Task { @MainActor [weak coordinator, weak view] in
                guard let coordinator, let view, view.text == measuredText,
                      coordinator.parent.text == measuredText,
                      abs(view.bounds.width - width) < 0.5, view.font?.pointSize == fontSize else { return }
                coordinator.parent.onHeight(height)
            }
        }
        return view
    }

    func updateUIView(_ view: FamiliarComposerNativeTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        if view.font?.pointSize != fontSize { view.font = .systemFont(ofSize: fontSize) }
        if view.textColor != .label { view.textColor = .label }
        view.placeholderLabel.text = placeholder
        view.accessibilityLabel = placeholder
        view.placeholderLabel.font = view.font
        view.isEditable = editable
        view.extraTrailingInset = trailingInset
        view.centersSingleLine = centersSingleLine
        // Never replace marked text, including during an unrelated SwiftUI update.
        if view.markedTextRange == nil {
            if view.text != text {
                view.undoManager?.removeAllActions()
                view.text = text
            }
            if let selection {
                let selected = selection.normalized(in: text).nsRange
                if view.selectedRange != selected { view.selectedRange = selected }
            }
        }
        view.setNeedsLayout()
        context.coordinator.updateFocus(in: view)
    }

    static func dismantleUIView(_ view: FamiliarComposerNativeTextView, coordinator: Coordinator) {
        coordinator.cancelFocusRequest()
        view.didMount = nil
        view.heightChanged = nil
        view.delegate = nil
        if coordinator.parent.inputControl.view === view {
            coordinator.parent.inputControl.view = nil
            coordinator.parent.inputControl.publish = nil
        }
        view.resignFirstResponder()
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: FamiliarComposerTextView
        var updating = false
        private var requestedFocus: Bool?
        private var focusGeneration = 0
        private var focusTask: Task<Void, Never>?
        init(_ parent: FamiliarComposerTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            guard !updating else { return }
            parent.text = textView.text
            publishSelection(textView)
            textView.setNeedsLayout()
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updating, textView.markedTextRange == nil, parent.text == textView.text else { return }
            publishSelection(textView)
        }
        private func publishSelection(_ view: UITextView) {
            guard view.markedTextRange == nil else { return }
            let text = view.text ?? "", range = view.selectedRange
            guard range.location != NSNotFound, NSMaxRange(range) <= text.utf16.count else { return }
            parent.selection = FamiliarComposerSelection(start: range.location, end: NSMaxRange(range)).normalized(in: text)
        }

        func updateFocus(in view: UITextView, force: Bool = false) {
            let desired = parent.focused.wrappedValue && parent.editable
            guard force || requestedFocus != desired else { return }
            requestedFocus = desired
            cancelFocusRequest()
            guard view.window != nil, desired != view.isFirstResponder else { return }
            let generation = focusGeneration
            focusTask = Task { @MainActor [weak self, weak view] in
                await Task.yield()
                guard !Task.isCancelled, let self, let view, view.window != nil,
                      self.focusGeneration == generation,
                      self.requestedFocus == desired else { return }
                if desired { view.becomeFirstResponder() }
                else { view.resignFirstResponder() }
            }
        }

        func cancelFocusRequest() {
            focusGeneration += 1
            focusTask?.cancel()
            focusTask = nil
        }

        func textViewDidBeginEditing(_ view: UITextView) {
            cancelFocusRequest()
            requestedFocus = true
            if !parent.focused.wrappedValue { parent.focused.wrappedValue = true }
        }
        func textViewDidEndEditing(_ view: UITextView) {
            cancelFocusRequest()
            requestedFocus = false
            if parent.focused.wrappedValue { parent.focused.wrappedValue = false }
        }
    }
}

final class FamiliarComposerNativeTextView: UITextView {
    let placeholderLabel = UILabel()
    var centersSingleLine = true
    var extraTrailingInset: CGFloat = 0
    var didMount: (() -> Void)?
    var heightChanged: ((CGFloat) -> Void)?
    private var reportedHeight: CGFloat = 0
    private var lastCaretLayout: String = ""
    private var lastCaretSize = CGSize.zero
    private var measurement: (text: String, font: UIFont, width: CGFloat, height: CGFloat)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { didMount?() }
    }

    override func layoutSubviews() {
        let horizontal: CGFloat = 10
        var insets = UIEdgeInsets(top: 8, left: horizontal, bottom: 8, right: horizontal + extraTrailingInset)
        if textContainerInset.left != insets.left || textContainerInset.right != insets.right { textContainerInset = insets }
        let line = font?.lineHeight ?? 22
        // Measure in an unbounded text container. The editing container is a viewport,
        // so its used rect is not an authoritative height once scrolling begins.
        let measuredFont = font ?? .systemFont(ofSize: 18)
        let measuredWidth = max(1, bounds.width - insets.left - insets.right)
        let measuredText = text ?? ""
        if measurement?.text != measuredText || measurement?.font != measuredFont || measurement?.width != measuredWidth {
            measurement = (measuredText, measuredFont, measuredWidth,
                Self.contentHeight(text: measuredText, font: measuredFont, width: measuredWidth))
        }
        let textHeight = measurement?.height ?? line
        if centersSingleLine && textHeight <= line + 1 { insets.top = max(8, (bounds.height - line) * 0.5); insets.bottom = insets.top }
        if textContainerInset != insets { textContainerInset = insets }
        super.layoutSubviews()
        placeholderLabel.isHidden = !text.isEmpty
        placeholderLabel.frame = CGRect(x: insets.left, y: insets.top,
            width: max(0, bounds.width - insets.left - insets.right), height: line)
        // Keep UIKit scrolling enabled even while the outer field grows. This also
        // gives trailing empty paragraphs a real caret viewport at the height cap.
        if isFirstResponder, lastCaretLayout != text || lastCaretSize != bounds.size {
            lastCaretLayout = text ?? ""
            lastCaretSize = bounds.size
            scrollRangeToVisible(selectedRange)
        }
        if abs(textHeight - reportedHeight) > 0.5, bounds.width > 0 {
            reportedHeight = textHeight
            heightChanged?(textHeight)
        }
    }
    static func contentHeight(text: String, font: UIFont, width: CGFloat) -> CGFloat {
        // A sentinel accounts for every trailing newline, including an empty draft.
        let storage = NSTextStorage(string: text + "\u{200B}", attributes: [.font: font])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        return max(font.lineHeight, ceil(manager.usedRect(for: container).height))
    }

}


struct FamiliarComposerAttachmentAnchor: UIViewRepresentable {
    let control: FamiliarComposerInputControl
    func makeUIView(context: Context) -> UIView { let view = UIView(); view.isUserInteractionEnabled = false; control.attachmentView = view; return view }
    func updateUIView(_ view: UIView, context: Context) { control.attachmentView = view }
    static func dismantleUIView(_ view: UIView, coordinator: ()) {}
}
