import SwiftUI

struct FamiliarRootView: View {
    let dependencies: FamiliarAppDependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("familiar.onboarding.completed.v1") private var hasCompletedOnboarding = false
    @State private var pendingSystemEntry: FamiliarSystemEntryRequest?
    @State private var appIntentHandoff = FamiliarAppIntentHandoff.shared

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

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
        .onAppear { handlePendingAppIntent() }
        .onChange(of: appIntentHandoff.pendingRequest) { _, _ in handlePendingAppIntent() }
        .onOpenURL { url in
            guard let deepLink = FamiliarDeepLink(url: url) else { return }
            pendingSystemEntry = .deepLink(deepLink)
            setOnboardingCompleted(true)
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
