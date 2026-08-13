import SwiftUI

struct FamiliarRootView: View {
    let dependencies: FamiliarAppDependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("familiar.onboarding.completed.v1") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            if hasCompletedOnboarding {
                FamiliarChatView(dependencies: dependencies)
                    .transition(.opacity)
            } else {
                FamiliarOnboardingView {
                    if reduceMotion {
                        hasCompletedOnboarding = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            hasCompletedOnboarding = true
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}
