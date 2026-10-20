import SwiftUI
import UIKit

/// Telegram ChatMessageTransitionNode.swift:321–334. Independent X/Y timing.
@MainActor enum FamiliarTelegramMotion {
    static let duration = 0.3
    static let horizontal = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    static let vertical = CAMediaTimingFunction(controlPoints: 0.19919473, 0.01064453, 0.27920937, 0.9102539)
    static let panel = Animation.spring(duration: 0.4)
}

@MainActor final class FamiliarSendPresentation {
    private struct Source {
        let scopeID: UUID
        let text: String
        let frame: CGRect
        let snapshot: UIView
        let date: TimeInterval
    }
    private var source: Source?
    private weak var window: UIWindow?
    private var committedID: UUID?
    private var flight: UIView?
    private var completion: (() -> Void)?
    private var expiry: Task<Void, Never>?
    private var generation = UUID()

    func capture(view: UIView?, text: String, scopeID: UUID?) {
        cancel()
        guard let view, let window = view.window, let scopeID, !UIAccessibility.isReduceMotionEnabled else { return }
        let frame = FamiliarViewGeometry.visibleRect(view, in: window)
        guard frame.width > 1, frame.height > 1, frame.height < window.bounds.height,
              let snapshot = window.resizableSnapshotView(from: frame, afterScreenUpdates: false, withCapInsets: .zero) else { return }
        self.window = window
        source = .init(scopeID: scopeID, text: text, frame: frame, snapshot: snapshot, date: ProcessInfo.processInfo.systemUptime)
        expiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.cancel()
        }
    }
    func commit(id: UUID, scopeID: UUID, text: String) {
        guard source?.scopeID == scopeID, source?.text == text else { cancel(); return }
        committedID = id
    }
    func present(id: UUID, target: UIView, hidden: @escaping (Bool) -> Void) {
        if UIAccessibility.isReduceMotionEnabled { cancel(); return }
        guard committedID == id, let source, let window, target.window === window,
              ProcessInfo.processInfo.systemUptime - source.date < 5 else { return }
        let rect = FamiliarViewGeometry.visibleRect(target, in: window)
        guard rect.intersects(window.bounds), rect.width > 1, rect.height > 1 else { return }
        committedID = nil; self.source = nil; expiry?.cancel()
        let token = UUID(); generation = token
        DispatchQueue.main.async { [weak self, weak target, weak window] in
            guard let self, let target, let window, target.window === window, self.generation == token else { return }
            hidden(true)
            let ghost = source.snapshot
            ghost.frame = rect; ghost.layer.cornerRadius = 18; ghost.clipsToBounds = true
            ghost.backgroundColor = .secondarySystemBackground
            window.addSubview(ghost); self.flight = ghost
            self.completion = { hidden(false) }
            let pairs: [(String, CGFloat, CGFloat, CAMediaTimingFunction)] = [
                ("position.x", source.frame.midX, rect.midX, FamiliarTelegramMotion.horizontal),
                ("position.y", source.frame.midY, rect.midY, FamiliarTelegramMotion.vertical),
                ("bounds.size.width", source.frame.width, rect.width, FamiliarTelegramMotion.horizontal),
                ("bounds.size.height", source.frame.height, rect.height, FamiliarTelegramMotion.vertical)
            ]
            for (key, start, end, curve) in pairs {
                let animation = CABasicAnimation(keyPath: key)
                animation.fromValue = start; animation.toValue = end
                animation.duration = FamiliarTelegramMotion.duration; animation.timingFunction = curve
                ghost.layer.add(animation, forKey: key)
            }
            self.expiry = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard let self, self.generation == token else { return }
                self.cancel()
            }
        }
    }
    func cancel() {
        generation = UUID(); source = nil; committedID = nil
        expiry?.cancel(); expiry = nil
        flight?.removeFromSuperview(); flight = nil
        let finish = completion; completion = nil; finish?()
    }
}

extension EnvironmentValues { @Entry var familiarSendPresentation: FamiliarSendPresentation? = nil }

struct FamiliarSentMessageModifier: ViewModifier {
    @Environment(\.familiarSendPresentation) private var presentation
    let id: UUID?
    @State private var hidden = false
    func body(content: Content) -> some View {
        content.opacity(hidden ? 0 : 1).background {
            if let id { Target(id: id, presentation: presentation, hidden: { hidden = $0 }) }
        }.onDisappear { if hidden { presentation?.cancel(); hidden = false } }
    }
    private struct Target: UIViewRepresentable {
        let id: UUID
        let presentation: FamiliarSendPresentation?
        let hidden: (Bool) -> Void
        func makeUIView(context: Context) -> Anchor { Anchor() }
        func updateUIView(_ view: Anchor, context: Context) {
            view.ready = { [weak view, weak presentation] in if let view { presentation?.present(id: id, target: view, hidden: hidden) } }
            view.setNeedsLayout()
        }
        final class Anchor: UIView {
            var ready: (() -> Void)?
            override func layoutSubviews() { super.layoutSubviews(); ready?() }
            override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { setNeedsLayout() } }
        }
    }
}


@MainActor enum FamiliarViewGeometry {
    static func visibleRect(_ view: UIView, in window: UIWindow) -> CGRect {
        var rect = view.convert(view.bounds, to: window).intersection(window.bounds)
        var ancestor = view.superview
        while let parent = ancestor {
            if parent.clipsToBounds { rect = rect.intersection(parent.convert(parent.bounds, to: window)) }
            ancestor = parent.superview
        }
        return rect
    }
}
