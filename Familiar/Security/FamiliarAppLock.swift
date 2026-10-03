// Adapted from OpenMinis SessionLockStore / AppLockOverlay at 4ef2900 (GPL-3.0).
// Familiar uses a scene-owned window so the shield also covers presented sheets.
import SwiftUI
import LocalAuthentication
import Observation

@MainActor @Observable
final class FamiliarAppLock {
    static let enabledKey = "familiar.app-lock.enabled.v1"
    private var window: UIWindow?
    private weak var scene: UIWindowScene?
    var isLocked = UserDefaults.standard.bool(forKey: enabledKey)
    var isAuthenticating = false
    var errorMessage: String?

    func attach(_ scene: UIWindowScene) {
        self.scene = scene
        if isLocked { show(); authenticate() }
    }
    func sceneChanged(_ phase: ScenePhase) {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else {
            isLocked = false; hide(); return
        }
        switch phase {
        case .background: isLocked = true; show()
        case .inactive: show()
        case .active:
            if isLocked { show(); authenticate() } else { hide() }
        @unknown default: break
        }
    }
    func authenticate() {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true; errorMessage = nil
        Task { @MainActor in
            defer { isAuthenticating = false }
            do {
                let context = LAContext()
                let allowed = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "lock.reason"))
                if allowed { isLocked = false; hide() }
            } catch { errorMessage = String(localized: "lock.failed") }
        }
    }
    private func show() {
        guard let scene, window == nil else { return }
        let shield = UIWindow(windowScene: scene)
        shield.frame = scene.coordinateSpace.bounds
        shield.windowLevel = .alert + 1
        shield.rootViewController = UIHostingController(rootView: FamiliarAppLockScreen(lock: self))
        shield.isHidden = false
        window = shield
    }
    private func hide() { window?.isHidden = true; window = nil }
}

private struct FamiliarAppLockScreen: View {
    let lock: FamiliarAppLock
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if lock.isLocked {
                VStack(spacing: FamiliarSpacing.section) {
                    Image(systemName: "lock.fill").font(.largeTitle)
                    Text(String(localized: "lock.title")).font(FamiliarTypography.screenTitle)
                    if let error = lock.errorMessage { Text(error).foregroundStyle(.secondary) }
                    Button(String(localized: "lock.unlock")) { lock.authenticate() }
                        .buttonStyle(.borderedProminent).disabled(lock.isAuthenticating)
                }.padding()
            }
        }
    }
}

struct FamiliarWindowSceneReader: UIViewRepresentable {
    let onScene: (UIWindowScene) -> Void
    func makeUIView(context: Context) -> Reader { Reader(onScene: onScene) }
    func updateUIView(_ uiView: Reader, context: Context) {}
    final class Reader: UIView {
        let onScene: (UIWindowScene) -> Void
        init(onScene: @escaping (UIWindowScene) -> Void) { self.onScene = onScene; super.init(frame: .zero); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { onScene(scene) }
        }
    }
}

struct FamiliarAppLockSettingsView: View {
    @AppStorage(FamiliarAppLock.enabledKey) private var enabled = false
    @State private var busy = false
    @State private var errorMessage: String?
    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "lock.setting"), isOn: Binding(get: { enabled }, set: { value in
                    busy = true
                    Task { @MainActor in
                        defer { busy = false }
                        do {
                            let context = LAContext()
                            let accepted = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "lock.reason"))
                            if accepted { enabled = value }
                        } catch { errorMessage = String(localized: "lock.failed") }
                    }
                })).disabled(busy)
            } footer: { Text(String(localized: "lock.footer")) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
        }
        .navigationTitle(String(localized: "lock.setting"))
    }
}
