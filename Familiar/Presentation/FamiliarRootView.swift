import CoreSpotlight
import SwiftUI

struct FamiliarRootView: View {
    let dependencies: FamiliarAppDependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("familiar.onboarding.completed.v1") private var hasCompletedOnboarding = false
    @AppStorage(FamiliarAppearancePreference.storageKey) private var appearance = FamiliarAppearancePreference.system.rawValue
    @State private var pendingSystemEntry: FamiliarSystemEntryRequest?
    @State private var appIntentHandoff = FamiliarAppIntentHandoff.shared

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            rootContent
        }
        .preferredColorScheme(FamiliarAppearancePreference(rawValue: appearance)?.colorScheme)
        .onAppear { handlePendingAppIntent() }
        .onChange(of: appIntentHandoff.pendingRequest) { _, _ in handlePendingAppIntent() }
        .onOpenURL { url in
            guard let deepLink = FamiliarDeepLink(url: url) else { return }
            pendingSystemEntry = .deepLink(deepLink)
            setOnboardingCompleted(true)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
            guard let deepLink = FamiliarSpotlightIndexer.deepLink(from: userActivity) else { return }
            pendingSystemEntry = .deepLink(deepLink)
            setOnboardingCompleted(true)
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
        if hasCompletedOnboarding {
            FamiliarChatView(
                dependencies: dependencies,
                onRestartOnboarding: { setOnboardingCompleted(false) },
                pendingSystemEntry: $pendingSystemEntry
            )
            .transition(.opacity)
        } else {
            FamiliarOnboardingView {
                setOnboardingCompleted(true)
            }
            .transition(.opacity)
        }
    }

    private func handlePendingAppIntent() {
        guard let request = appIntentHandoff.takePendingRequest() else { return }
        pendingSystemEntry = request
        setOnboardingCompleted(true)
    }

    private func setOnboardingCompleted(_ completed: Bool) {
        if reduceMotion {
            hasCompletedOnboarding = completed
        } else {
            withAnimation(.easeInOut(duration: 0.28)) {
                hasCompletedOnboarding = completed
            }
        }
    }
}
