import SwiftUI

struct FamiliarRootView: View {
    let dependencies: FamiliarAppDependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("familiar.onboarding.completed.v1") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            if hasCompletedOnboarding {
                FamiliarChatView(
                    dependencies: dependencies,
                    onRestartOnboarding: { setOnboardingCompleted(false) }
                )
                    .transition(.opacity)
            } else {
                FamiliarOnboardingView {
                    setOnboardingCompleted(true)
                }
                .transition(.opacity)
            }
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
