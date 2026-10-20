import SwiftUI
import UIKit

struct FamiliarImageGalleryItem: Identifiable, Equatable { let id: UUID; let url: URL }
struct FamiliarImageGalleryRequest: Identifiable { let id: UUID; let items: [FamiliarImageGalleryItem] }

@MainActor enum FamiliarImagePresentation {
    static func update(_ action: () -> Void) {
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction, action)
    }
    static let sources = NSMapTable<NSUUID, UIView>(keyOptions: .strongMemory, valueOptions: .weakMemory)
}
struct FamiliarImageSourceAnchor: UIViewRepresentable {
    let id: UUID
    func makeUIView(context: Context) -> Anchor { let view = Anchor(); view.isUserInteractionEnabled = false; updateUIView(view, context: context); return view }
    func updateUIView(_ view: Anchor, context: Context) {
        if let previous = view.id, previous != id, FamiliarImagePresentation.sources.object(forKey: previous as NSUUID) === view { FamiliarImagePresentation.sources.removeObject(forKey: previous as NSUUID) }
        view.id = id; FamiliarImagePresentation.sources.setObject(view, forKey: id as NSUUID)
    }
    static func dismantleUIView(_ view: Anchor, coordinator: ()) {
        if let id = view.id, FamiliarImagePresentation.sources.object(forKey: id as NSUUID) === view { FamiliarImagePresentation.sources.removeObject(forKey: id as NSUUID) }
    }
    final class Anchor: UIView { var id: UUID? }
}

/// GalleryControllerNode: scroll content is 3 viewports; threshold contentHeight/12.
nonisolated struct FamiliarGalleryDrag {
    let distance: CGFloat
    let velocity: CGFloat
    let height: CGFloat
    var controlsAlpha: CGFloat { 1 - min(1, abs(distance) / 50) }
    var backdropAlpha: CGFloat { 1 - min(1, abs(distance) / 80) }
    var shouldDismiss: Bool { abs(velocity) > 1_000 || abs(distance) > height / 4 }
}

struct FamiliarImageGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.familiarChatScrollSession) private var scroll
    let request: FamiliarImageGalleryRequest
    var onRemove: ((UUID) -> Void)? = nil
    @State private var items: [FamiliarImageGalleryItem]
    @State private var inspecting = false
    init(request: FamiliarImageGalleryRequest, onRemove: ((UUID) -> Void)? = nil) { self.request = request; self.onRemove = onRemove; _items = State(initialValue: request.items) }
    var body: some View {
        FamiliarImageGalleryController(items: items, initialID: request.id, onClose: { FamiliarImagePresentation.update { dismiss() } }, onRemove: onRemove.map { remove in
            { id in remove(id); items.removeAll { $0.id == id }; if items.isEmpty { FamiliarImagePresentation.update { dismiss() } } }
        })
        .ignoresSafeArea().presentationBackground(.clear)
        .onAppear { if !inspecting { scroll?.beginInspection(); inspecting = true } }
        .onDisappear { if inspecting { scroll?.endInspection(); inspecting = false } }
    }
}

private struct FamiliarImageGalleryController: UIViewControllerRepresentable {
    let items: [FamiliarImageGalleryItem]
    let initialID: UUID
    let onClose: () -> Void
    let onRemove: ((UUID) -> Void)?
    func makeUIViewController(context: Context) -> UINavigationController {
        let gallery = Controller(items: items, initialID: initialID, onClose: onClose, onRemove: onRemove)
        let navigation = UINavigationController(rootViewController: gallery)
        navigation.overrideUserInterfaceStyle = .dark
        let appearance = UINavigationBarAppearance(); appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigation.navigationBar.standardAppearance = appearance; navigation.navigationBar.scrollEdgeAppearance = appearance
        navigation.navigationBar.tintColor = .white
        navigation.view.backgroundColor = .clear
        return navigation
    }
    func updateUIViewController(_ navigation: UINavigationController, context: Context) {
        guard let gallery = navigation.viewControllers.first as? Controller else { return }
        gallery.onClose = onClose; gallery.onRemove = onRemove; gallery.replace(items); if gallery.isViewLoaded { gallery.installActions() }
    }
    final class Controller: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var items: [FamiliarImageGalleryItem]
        var index: Int
        var onClose: () -> Void
        var onRemove: ((UUID) -> Void)?
        let backdrop = UIView(), pager = UIScrollView(), caption = UILabel()
        var pages: [UUID: ZoomPage] = [:]
        var previousSize = CGSize.zero
        var appeared = false, entered = false, controlsHidden = false, closing = false
        lazy var dismissPan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        init(items: [FamiliarImageGalleryItem], initialID: UUID, onClose: @escaping () -> Void, onRemove: ((UUID) -> Void)?) {
            self.items = items; index = items.firstIndex { $0.id == initialID } ?? 0; self.onClose = onClose; self.onRemove = onRemove
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var canBecomeFirstResponder: Bool { true }
        override var keyCommands: [UIKeyCommand]? { [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closeFromKeyboard))] }
        @objc private func closeFromKeyboard() { close() }
        override func accessibilityPerformEscape() -> Bool { close(); return true }
        override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
            let step = direction == .left ? 1 : direction == .right ? -1 : 0
            let next = index + step
            guard step != 0, items.indices.contains(next) else { return false }
            index = next; pager.setContentOffset(.init(x: CGFloat(index) * view.bounds.width, y: 0), animated: !UIAccessibility.isReduceMotionEnabled); refresh()
            UIAccessibility.post(notification: .pageScrolled, argument: title); return true
        }
        override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
        override func viewDidLoad() {
            super.viewDidLoad(); view.backgroundColor = .clear; view.accessibilityViewIsModal = true
            backdrop.backgroundColor = .black; backdrop.alpha = 0; pager.alpha = 0; view.addSubview(backdrop)
            pager.isPagingEnabled = true; pager.showsHorizontalScrollIndicator = false; pager.delegate = self
            pager.contentInsetAdjustmentBehavior = .never; view.addSubview(pager)
            caption.textColor = .white; caption.font = .preferredFont(forTextStyle: .caption1); caption.textAlignment = .center
            caption.numberOfLines = 2; view.addSubview(caption)
            dismissPan.delegate = self; view.addGestureRecognizer(dismissPan); pager.panGestureRecognizer.require(toFail: dismissPan)
            navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.close() })
            installActions(); refresh()
        }
        func installActions() {
            var actions = [UIBarButtonItem(systemItem: .action, primaryAction: UIAction { [weak self] _ in self?.share() })]
            if onRemove != nil { actions.append(UIBarButtonItem(systemItem: .trash, primaryAction: UIAction { [weak self] _ in
                guard let self, self.items.indices.contains(self.index) else { return }; self.onRemove?(self.items[self.index].id)
            })) }
            navigationItem.rightBarButtonItems = actions
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews(); backdrop.frame = view.bounds
            caption.frame = .init(x: 20, y: view.bounds.height - view.safeAreaInsets.bottom - 52, width: max(0, view.bounds.width - 40), height: 44)
            if previousSize != view.bounds.size {
                pager.transform = .identity; pager.frame = view.bounds
                previousSize = view.bounds.size; pager.contentSize = .init(width: CGFloat(items.count) * view.bounds.width, height: view.bounds.height)
                pager.contentOffset.x = CGFloat(index) * view.bounds.width; refresh()
            }
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            appeared = true; becomeFirstResponder(); animateInIfReady()
        }
        func animateInIfReady() {
            guard appeared, !entered, let page = currentPage, page.finished else { return }; entered = true
            guard !UIAccessibility.isReduceMotionEnabled, let source = sourceRect(), let image = page.imageView.image else { backdrop.alpha = 1; pager.alpha = 1; return }
            let ghost = UIImageView(image: image); ghost.contentMode = .scaleAspectFill; ghost.clipsToBounds = true; ghost.layer.cornerRadius = 18
            ghost.frame = source; view.addSubview(ghost); pager.alpha = 0; backdrop.alpha = 0
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) { ghost.frame = page.imageView.convert(page.imageView.bounds, to: self.view); ghost.layer.cornerRadius = 0; self.backdrop.alpha = 1 } completion: { _ in self.pager.alpha = 1; ghost.removeFromSuperview() }
        }
        var currentPage: ZoomPage? { items.indices.contains(index) ? pages[items[index].id] : nil }
        func replace(_ values: [FamiliarImageGalleryItem]) {
            guard values != items else { return }
            let current = items.indices.contains(index) ? items[index].id : nil
            items = values; index = current.flatMap { id in values.firstIndex { $0.id == id } } ?? min(index, max(0, values.count - 1))
            if isViewLoaded { previousSize = .zero; view.setNeedsLayout(); refresh() }
        }
        func refresh() {
            guard isViewLoaded else { return }
            let wanted = Set(items.indices.filter { abs($0 - index) <= 1 }.map { items[$0].id })
            for id in Array(pages.keys) where !wanted.contains(id) { pages.removeValue(forKey: id)?.removeFromSuperview() }
            for offset in items.indices where abs(offset - index) <= 1 {
                let item = items[offset]
                let page: ZoomPage
                if let existing = pages[item.id] { page = existing }
                else {
                    page = ZoomPage(url: item.url, identity: item.id.uuidString); pages[item.id] = page; pager.addSubview(page)
                    page.panGestureRecognizer.require(toFail: dismissPan)
                    page.zoomChanged = { [weak self] zoomed in self?.pager.isScrollEnabled = !zoomed }
                    page.singleTap = { [weak self] in self?.toggleControls() }
                    page.ready = { [weak self] in self?.animateInIfReady() }
                }
                page.frame = .init(x: CGFloat(offset) * view.bounds.width, y: 0, width: view.bounds.width, height: view.bounds.height)
                page.accessibilityElementsHidden = offset != index
                page.prepare(full: offset == index)
            }
            if items.indices.contains(index) { title = String(format: String(localized: "attachment.preview_count"), index + 1, items.count); caption.text = items[index].url.lastPathComponent }
            pager.isScrollEnabled = (currentPage?.zoomScale ?? 1) <= 1.01
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            index = min(max(0, Int(round(scrollView.contentOffset.x / max(1, view.bounds.width)))), max(0, items.count - 1)); refresh()
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let velocity = dismissPan.velocity(in: view)
            return !closing && (currentPage?.zoomScale ?? 1) <= 1.01 && abs(velocity.y) > abs(velocity.x) * 1.2
        }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let delta = gesture.translation(in: view).y
            switch gesture.state {
            case .changed:
                pager.transform = CGAffineTransform(translationX: 0, y: delta)
                // GalleryControllerNode.swift:523–550: controls 50pt, background 80pt.
                let drag = FamiliarGalleryDrag(distance: delta, velocity: gesture.velocity(in: view).y, height: view.bounds.height)
                backdrop.alpha = drag.backdropAlpha
                let alpha = drag.controlsAlpha
                navigationController?.navigationBar.alpha = alpha; caption.alpha = alpha
            case .ended:
                if FamiliarGalleryDrag(distance: delta, velocity: gesture.velocity(in: view).y, height: view.bounds.height).shouldDismiss { close() }
                else { restoreDrag() }
            case .cancelled, .failed: restoreDrag()
            default: break
            }
        }
        func restoreDrag() {
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.4, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) {
                self.pager.transform = .identity; self.backdrop.alpha = 1
                self.navigationController?.navigationBar.alpha = self.controlsHidden ? 0 : 1; self.caption.alpha = self.controlsHidden ? 0 : 1
            }
        }
        func sourceRect() -> CGRect? {
            guard items.indices.contains(index), let source = FamiliarImagePresentation.sources.object(forKey: items[index].id as NSUUID), source.window != nil else { return nil }
            guard let window = source.window else { return nil }
            let visible = FamiliarViewGeometry.visibleRect(source, in: window)
            let rect = view.convert(visible, from: window)
            return !rect.isNull && rect.width > 1 && rect.height > 1 && rect.intersects(view.bounds) ? rect : nil
        }
        func close() {
            guard !closing else { return }; closing = true
            guard !UIAccessibility.isReduceMotionEnabled, let page = currentPage, let image = page.imageView.image, let target = sourceRect() else {
                UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2) { self.view.alpha = 0 } completion: { _ in self.onClose() }; return
            }
            let ghost = UIImageView(image: image); ghost.contentMode = .scaleAspectFill; ghost.clipsToBounds = true
            ghost.frame = page.imageView.convert(page.imageView.bounds, to: view); view.addSubview(ghost); pager.alpha = 0
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) { ghost.frame = target; ghost.layer.cornerRadius = 18; self.backdrop.alpha = 0; self.navigationController?.navigationBar.alpha = 0; self.caption.alpha = 0 } completion: { _ in ghost.removeFromSuperview(); self.onClose() }
        }
        func toggleControls() { controlsHidden.toggle(); UIView.animate(withDuration: 0.2) { self.navigationController?.navigationBar.alpha = self.controlsHidden ? 0 : 1; self.caption.alpha = self.controlsHidden ? 0 : 1 } }
        func share() {
            guard items.indices.contains(index) else { return }
            let sheet = UIActivityViewController(activityItems: [items[index].url], applicationActivities: nil)
            sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
            present(sheet, animated: true)
        }
    }
    final class ZoomPage: UIScrollView, UIScrollViewDelegate {
        let imageView = UIImageView()
        let url: URL, identity: String
        var task: Task<Void, Never>?
        var preparedPixels = 0, requestedPixels = 0
        var finished = false
        var ready: (() -> Void)?
        var fittedSize = CGSize.zero
        var singleTap: (() -> Void)?, zoomChanged: ((Bool) -> Void)?
        init(url: URL, identity: String) {
            self.url = url; self.identity = identity; super.init(frame: .zero)
            delegate = self; minimumZoomScale = 1; maximumZoomScale = 4
            showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
            contentInsetAdjustmentBehavior = .never; imageView.contentMode = .scaleAspectFit; imageView.isAccessibilityElement = true; imageView.accessibilityLabel = url.lastPathComponent; imageView.accessibilityTraits = .image; addSubview(imageView)
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:))); double.numberOfTapsRequired = 2
            let single = UITapGestureRecognizer(target: self, action: #selector(tap)); single.require(toFail: double)
            addGestureRecognizer(double); addGestureRecognizer(single)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func removeFromSuperview() { task?.cancel(); task = nil; super.removeFromSuperview() }
        func prepare(full: Bool) {
            let pixels = full ? 3_072 : 512
            guard pixels > preparedPixels, pixels > requestedPixels else { return }
            task?.cancel(); requestedPixels = pixels
            task = Task { @MainActor [weak self] in
                guard let self else { return }
                let image = await FamiliarThumbnailLoader.shared.image(url: url, pixels: pixels, identity: identity)
                guard !Task.isCancelled else { return }
                preparedPixels = pixels; requestedPixels = 0; finished = true; imageView.image = image ?? UIImage(systemName: "photo.badge.exclamationmark"); fittedSize = .zero; setNeedsLayout(); layoutIfNeeded(); ready?()
            }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size.width > 0, bounds.size.height > 0 else { return }
            if fittedSize != bounds.size, let image = imageView.image {
                fittedSize = bounds.size; let scale = min(bounds.width / max(1, image.size.width), bounds.height / max(1, image.size.height))
                let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let previous = zoomScale; setZoomScale(1, animated: false); imageView.frame = CGRect(origin: .zero, size: fitted); contentSize = fitted; setZoomScale(previous, animated: false)
            }
            centerImage()
        }
        func centerImage() {
            let center = CGPoint(x: max(bounds.width, contentSize.width) / 2, y: max(bounds.height, contentSize.height) / 2)
            if imageView.center != center { imageView.center = center }
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage(); zoomChanged?(zoomScale > 1.01) }
        @objc func tap() { singleTap?() }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            if zoomScale > minimumZoomScale { setZoomScale(minimumZoomScale, animated: true) }
            else {
                let point = gesture.location(in: imageView), scale = maximumZoomScale
                let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
                zoom(to: .init(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}
