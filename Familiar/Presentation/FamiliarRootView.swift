import CoreSpotlight
import SwiftUI

struct FamiliarRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appLock = FamiliarAppLock()
    @State private var deferredEntry: FamiliarSystemEntryRequest?
    let dependencies: FamiliarAppDependencies
    @AppStorage(FamiliarAppearancePreference.storageKey) private var appearance = FamiliarAppearancePreference.system.rawValue
    @State private var pendingSystemEntry: FamiliarSystemEntryRequest?
    @State private var appIntentHandoff = FamiliarAppIntentHandoff.shared

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            rootContent
        }
        .background(FamiliarWindowSceneReader { appLock.attach($0) })
        .onChange(of: scenePhase) { _, phase in appLock.sceneChanged(phase) }
        .onChange(of: appLock.isLocked) { _, locked in
            if !locked {
                if let deferredEntry { pendingSystemEntry = deferredEntry; self.deferredEntry = nil }
                handlePendingAppIntent()
            }
        }
        .preferredColorScheme(FamiliarAppearancePreference(rawValue: appearance)?.colorScheme)
        .onAppear { handlePendingAppIntent() }
        .onChange(of: appIntentHandoff.pendingRequest) { _, _ in handlePendingAppIntent() }
        .onOpenURL { url in
            guard let deepLink = FamiliarDeepLink(url: url) else { return }
            if appLock.isLocked { deferredEntry = .deepLink(deepLink) }
            else { pendingSystemEntry = .deepLink(deepLink) }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
            guard let deepLink = FamiliarSpotlightIndexer.deepLink(from: userActivity) else { return }
            if appLock.isLocked { deferredEntry = .deepLink(deepLink) }
            else { pendingSystemEntry = .deepLink(deepLink) }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-familiar.visual-fixture") {
            NavigationStack { FamiliarAssistantTurnVisualFixture() }
        } else {
            standardContent
        }
#else
        standardContent
#endif
    }

    @ViewBuilder
    private var standardContent: some View {
        FamiliarChatView(
            dependencies: dependencies,
            pendingSystemEntry: $pendingSystemEntry
        )
    }

    private func handlePendingAppIntent() {
        guard !appLock.isLocked, let request = appIntentHandoff.takePendingRequest() else { return }
        pendingSystemEntry = request
    }
}
