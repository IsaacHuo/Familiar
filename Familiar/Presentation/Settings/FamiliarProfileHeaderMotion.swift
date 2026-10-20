import SwiftUI
import UIKit

/// PeerInfoHeaderNode / DynamicIslandBlurNode. One scroll offset, isolated UIKit output.
nonisolated struct FamiliarProfileCollapse {
    let mask: CGFloat
    let fade: CGFloat
    let blur: CGFloat
    init(offset: CGFloat) {
        mask = min(1, max(0, offset / 120))
        fade = min(1, max(0, -0.25 + mask * 1.55))
        blur = min(1, max(0, -0.1 + mask * 1.1))
    }
}

private struct FamiliarAvatarMaskData: Decodable {
    struct Frame: Decodable { let time: CGFloat; let v: [[CGFloat]]; let i: [[CGFloat]]; let o: [[CGFloat]] }
    struct Shape: Decodable { let position: [CGFloat]; let frames: [Frame] }
    let duration: CGFloat
    let shapes: [Shape]
    @MainActor static let shared: Self? = Bundle.main.url(forResource: "TelegramAvatarMask", withExtension: "json").flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    /// Original keyframes use a linear temporal curve; cubic spatial tangents are retained.
    func path(progress: CGFloat) -> CGPath {
        let path = CGMutablePath(), time = progress * duration
        for shape in shapes {
            guard let first = shape.frames.first else { continue }
            let from = shape.frames.last(where: { $0.time <= time }) ?? first
            let to = shape.frames.first(where: { $0.time > time }) ?? from
            let p = from.time == to.time ? 0 : min(1, max(0, (time - from.time) / (to.time - from.time)))
            func point(_ a: [[CGFloat]], _ b: [[CGFloat]], _ index: Int) -> CGPoint {
                .init(x: a[index][0] + (b[index][0] - a[index][0]) * p, y: a[index][1] + (b[index][1] - a[index][1]) * p)
            }
            guard from.v.count == to.v.count, !from.v.isEmpty else { continue }
            func absolute(_ point: CGPoint) -> CGPoint { .init(x: (point.x + shape.position[0] - 256) / 3 + 50, y: (point.y + shape.position[1] - 234) / 3 + 50) }
            let vertices = from.v.indices.map { point(from.v, to.v, $0) }
            path.move(to: absolute(vertices[0]))
            for index in vertices.indices {
                let next = (index + 1) % vertices.count, out = point(from.o, to.o, index), input = point(from.i, to.i, next)
                path.addCurve(to: absolute(vertices[next]), control1: absolute(.init(x: vertices[index].x + out.x, y: vertices[index].y + out.y)), control2: absolute(.init(x: vertices[next].x + input.x, y: vertices[next].y + input.y)))
            }
            path.closeSubpath()
        }
        return path
    }
}

@MainActor final class FamiliarProfileMotionAnchor {
    weak var source: UIView?
    var updated: (() -> Void)?
}
struct FamiliarProfileSourceView: UIViewRepresentable {
    let anchor: FamiliarProfileMotionAnchor
    func makeUIView(context: Context) -> Source { let view = Source(); view.anchor = anchor; anchor.source = view; return view }
    func updateUIView(_ view: Source, context: Context) { anchor.source = view; view.anchor = anchor }
    static func dismantleUIView(_ view: Source, coordinator: ()) { if view.anchor?.source === view { view.anchor?.source = nil } }
    final class Source: UIView {
        weak var anchor: FamiliarProfileMotionAnchor?
        override func layoutSubviews() { super.layoutSubviews(); anchor?.updated?() }
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { anchor?.updated?() } }
    }
}

struct FamiliarProfileHeaderMotion: UIViewControllerRepresentable {
    let profile: FamiliarLocalProfile
    let anchor: FamiliarProfileMotionAnchor
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    static func height(_ profile: FamiliarLocalProfile) -> CGFloat {
        100 + 12 + UIFont.preferredFont(forTextStyle: .title1).lineHeight + (profile.bio.isEmpty ? 0 : 8 + UIFont.preferredFont(forTextStyle: .subheadline).lineHeight * 2) + 36
    }
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.configure(profile, anchor: anchor, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency) }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.detach() }

    final class Controller: UIViewController {
        let overlay = UIView(), avatar = UIView(), photo = UIImageView(), initial = UILabel(), titleLabel = UILabel(), bio = UILabel()
        let blur = UIVisualEffectView(effect: nil), fade = UIView(), mask = CAShapeLayer()
        var animator: UIViewPropertyAnimator?
        weak var scroll: UIScrollView?
        var observation: NSKeyValueObservation?
        var avatarData: Data?
        weak var anchor: FamiliarProfileMotionAnchor?
        var documentOrigin: CGPoint?
        var reduceMotion = false, reduceTransparency = false, active = false
        override func loadView() {
            view = UIView(); view.isUserInteractionEnabled = false
            overlay.isUserInteractionEnabled = false; overlay.accessibilityElementsHidden = true
            photo.contentMode = .scaleAspectFill; avatar.clipsToBounds = true; avatar.layer.cornerRadius = 50
            avatar.backgroundColor = .systemBlue; photo.frame = .init(x: 0, y: 0, width: 100, height: 100)
            initial.textAlignment = .center; initial.font = .systemFont(ofSize: 40, weight: .medium); initial.textColor = .white; initial.frame = photo.frame
            blur.frame = photo.frame; fade.frame = photo.frame; fade.backgroundColor = .black
            avatar.addSubview(photo); avatar.addSubview(initial); avatar.addSubview(blur); avatar.addSubview(fade)
            overlay.addSubview(avatar); overlay.addSubview(titleLabel); overlay.addSubview(bio)
            titleLabel.textAlignment = .center; titleLabel.textColor = .label; titleLabel.lineBreakMode = .byTruncatingTail
            bio.textAlignment = .center; bio.textColor = .secondaryLabel; bio.numberOfLines = 2
        }
        func configure(_ profile: FamiliarLocalProfile, anchor: FamiliarProfileMotionAnchor, reduceMotion: Bool, reduceTransparency: Bool) {
            loadViewIfNeeded()
            self.anchor = anchor
            anchor.updated = { [weak self] in if self?.active == true { self?.attach() } }
            self.reduceMotion = reduceMotion; self.reduceTransparency = reduceTransparency
            if avatarData != profile.avatar { avatarData = profile.avatar; photo.image = profile.avatar.flatMap(UIImage.init(data:)) }
            initial.text = String(profile.displayName.prefix(1)); initial.isHidden = photo.image != nil
            titleLabel.text = profile.displayName; titleLabel.font = .preferredFont(forTextStyle: .title1).withTraits(.traitBold)
            bio.text = profile.bio; bio.font = .preferredFont(forTextStyle: .subheadline)
            if active { attach(); updateOverlay() }
        }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); active = true; attach() }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); detach() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); if active { attach(); updateOverlay() } }
        func attach() {
            guard active, view.window != nil, let container = parent?.view else { return }
            if overlay.superview !== container { overlay.removeFromSuperview(); container.addSubview(overlay) }
            var candidate = scroll
            var ancestor = anchor?.source?.superview
            while let current = ancestor {
                if let found = current as? UIScrollView { candidate = found; break }
                ancestor = current.superview
            }
            if candidate == nil { candidate = findScroll(in: container) }
            if let candidate, scroll !== candidate || observation == nil {
                scroll = candidate
                observation = candidate.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { if self?.active == true { self?.updateOverlay() } }
                }
            }
            updateOverlay()
        }
        func detach() {
            active = false; observation = nil; overlay.removeFromSuperview()
            animator?.stopAnimation(true); animator = nil; blur.effect = nil
        }
        private func findScroll(in root: UIView) -> UIScrollView? {
            guard !root.isHidden else { return nil }
            if let scroll = root as? UIScrollView, scroll.isScrollEnabled { return scroll }
            for child in root.subviews { if let scroll = findScroll(in: child) { return scroll } }
            return nil
        }
        func updateOverlay() {
            guard active, let window = view.window, let container = overlay.superview, view.bounds.width > 0 else { return }
            let offset = max(0, (scroll?.contentOffset.y ?? 0) + (scroll?.adjustedContentInset.top ?? 0))
            if let source = anchor?.source, source.window != nil {
                let frameOrigin = source.convert(CGPoint.zero, to: container)
                documentOrigin = CGPoint(x: frameOrigin.x, y: frameOrigin.y + offset)
            }
            guard let documentOrigin else { return }
            let origin = CGPoint(x: documentOrigin.x, y: documentOrigin.y - offset)
            let progress = FamiliarProfileCollapse(offset: offset)
            overlay.frame = container.bounds
            let navigationY = container.convert(CGPoint(x: window.bounds.midX, y: window.safeAreaInsets.top + 22), from: window).y
            let titleHeight = titleLabel.font.lineHeight
            let titleY = origin.y + 112 + titleHeight / 2
            let titleProgress = min(1, offset / max(1, titleY + offset - navigationY))
            let scale: CGFloat = reduceMotion ? 1 : 1 - titleProgress * 0.4
            CATransaction.begin(); CATransaction.setDisableActions(true)
            avatar.bounds = .init(x: 0, y: 0, width: 100, height: 100)
            avatar.center = .init(x: container.bounds.midX, y: origin.y + 50 + titleProgress * 17)
            avatar.transform = reduceMotion ? .identity : .init(scaleX: 1 - titleProgress * 0.45, y: 1 - titleProgress * 0.45)
            if !reduceMotion, container.bounds.height > container.bounds.width, let data = FamiliarAvatarMaskData.shared { mask.frame = avatar.bounds; mask.path = data.path(progress: progress.mask); avatar.layer.mask = mask } else { avatar.layer.mask = nil }
            avatar.alpha = reduceMotion || reduceTransparency ? 1 - progress.mask : 1
            titleLabel.bounds = .init(x: 0, y: 0, width: max(80, container.bounds.width - 32 - 188 * titleProgress) / scale, height: titleHeight)
            titleLabel.center = .init(x: container.bounds.midX, y: max(navigationY, titleY)); titleLabel.transform = .init(scaleX: scale, y: scale)
            let bioHeight: CGFloat = (bio.font?.lineHeight ?? 17) * 2
            let bioY: CGFloat = origin.y + 120 + titleHeight
            bio.frame = CGRect(x: 24, y: bioY, width: container.bounds.width - 48, height: bioHeight)
            bio.alpha = max(0, 1 - titleProgress * 2)
            fade.alpha = reduceTransparency ? 0 : progress.fade
            CATransaction.commit()
            if !reduceMotion && !reduceTransparency && progress.mask > 0 {
                if animator == nil {
                    let value = UIViewPropertyAnimator(duration: 1, curve: .linear)
                    value.addAnimations { [weak self] in self?.blur.effect = UIBlurEffect(style: .dark) }; animator = value
                }
                animator?.fractionComplete = min(0.99, progress.blur)
            } else { animator?.stopAnimation(true); animator = nil; blur.effect = nil }
        }
    }
}
private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont { fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: pointSize) } ?? self }
}
