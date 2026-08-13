import SwiftUI

struct FamiliarRootView: View {
    let dependencies: FamiliarAppDependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("familiar.onboarding.completed.v1") private var hasCompletedOnboarding = false
    @State private var pendingDeepLink: FamiliarDeepLink?

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            if hasCompletedOnboarding {
                FamiliarChatView(
                    dependencies: dependencies,
                    onRestartOnboarding: { setOnboardingCompleted(false) },
                    pendingDeepLink: $pendingDeepLink
                )
                    .transition(.opacity)
            } else {
                FamiliarOnboardingView {
                    setOnboardingCompleted(true)
                }
                .transition(.opacity)
            }
        }
        .onOpenURL { url in
            guard let deepLink = FamiliarDeepLink(url: url) else { return }
            pendingDeepLink = deepLink
            setOnboardingCompleted(true)
        }
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
