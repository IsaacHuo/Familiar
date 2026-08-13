import SwiftUI

struct FamiliarOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @State private var step = 0
    @State private var settings = FamiliarSettings.defaultValue
    @State private var configuration = FamiliarProviderConfiguration.empty
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @FocusState private var isKeyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                welcomePage.tag(0)
                providerPage.tag(1)
                readyPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? nil : .smooth, value: step)

            footer
        }
        .background { FamiliarTheme.brandGlow.ignoresSafeArea() }
        .alert(String(localized: "onboarding.validation_failed"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? String(localized: "error.unknown"))
        }
    }

    private var welcomePage: some View {
        OnboardingPage(
            symbol: "sparkles",
            title: String(localized: "onboarding.welcome.title"),
            subtitle: String(localized: "onboarding.welcome.subtitle")
        ) {
            VStack(spacing: 12) {
                OnboardingFeatureRow(symbol: "bubble.left.and.text.bubble.right", title: String(localized: "onboarding.feature.chat"))
                OnboardingFeatureRow(symbol: "key", title: String(localized: "onboarding.feature.byok"))
                OnboardingFeatureRow(symbol: "iphone", title: String(localized: "onboarding.feature.local"))
            }
        }
    }

    private var providerPage: some View {
        OnboardingPage(
            symbol: "key.horizontal",
            title: String(localized: "onboarding.provider.title"),
            subtitle: String(localized: "onboarding.provider.subtitle")
        ) {
            VStack(spacing: 14) {
                Picker(String(localized: "settings.provider"), selection: $settings.providerID) {
                    ForEach(FamiliarProviderCatalog.builtIn) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                    Text(String(localized: "settings.custom.provider"))
                        .tag(FamiliarProviderCatalog.customProviderID)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onChange(of: settings.providerID) { oldID, newID in
                    settings.providerConfigurations[oldID] = configuration
                    configuration = settings.providerConfigurations[newID] ?? .empty
                    settings.modelID = newID == FamiliarProviderCatalog.customProviderID
                        ? ""
                        : currentDescriptor?.defaultModel.id ?? ""
                    apiKey = ""
                }

                if settings.providerID == FamiliarProviderCatalog.customProviderID {
                    TextField(String(localized: "settings.custom.name"), text: $configuration.displayName)
                        .onboardingField()
                    TextField("https://example.com/v1", text: $configuration.baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .onboardingField()
                }

                SecureField(currentDescriptor?.apiKeyPlaceholder ?? "sk-…", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isKeyFocused)
                    .onboardingField()

                TextField(String(localized: "settings.model.manual"), text: $settings.modelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onboardingField()
            }
        }
    }

    private var readyPage: some View {
        OnboardingPage(
            symbol: "checkmark.seal",
            title: String(localized: "onboarding.ready.title"),
            subtitle: String(localized: "onboarding.ready.subtitle")
        ) {
            VStack(spacing: 12) {
                OnboardingFeatureRow(symbol: "lock.shield", title: String(localized: "onboarding.ready.keychain"))
                OnboardingFeatureRow(symbol: "internaldrive", title: String(localized: "onboarding.ready.history"))
                OnboardingFeatureRow(symbol: "hand.tap", title: String(localized: "onboarding.ready.permissions"))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? FamiliarTheme.accent : Color.secondary.opacity(0.22))
                        .frame(width: index == step ? 24 : 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                String(
                    format: String(localized: "onboarding.page_indicator"),
                    step + 1,
                    3
                )
            )

            Button(action: advance) {
                HStack(spacing: 8) {
                    if isValidating { ProgressView().tint(.white) }
                    Text(primaryButtonTitle).font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(FamiliarTheme.accent, in: Capsule())
            .disabled(isPrimaryDisabled)
            .opacity(isPrimaryDisabled ? 0.45 : 1)

            if step > 0 {
                Button(String(localized: "common.back")) { setStep(step - 1) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .disabled(isValidating)
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var currentDescriptor: FamiliarProviderDescriptor? {
        FamiliarProviderCatalog.descriptor(for: settings.providerID, configuration: configuration)
    }

    private var primaryButtonTitle: String {
        switch step {
        case 0: String(localized: "common.continue")
        case 1: String(localized: "onboarding.verify")
        default: String(localized: "onboarding.start")
        }
    }

    private var isPrimaryDisabled: Bool {
        isValidating
            || (step == 1 && (
                apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || settings.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || currentDescriptor == nil
            ))
    }

    private func advance() {
        switch step {
        case 0:
            setStep(1)
            isKeyFocused = true
        case 1:
            validateProvider()
        default:
            onComplete()
        }
    }

    private func setStep(_ newStep: Int) {
        if reduceMotion { step = newStep }
        else { withAnimation(.smooth) { step = newStep } }
    }

    private func validateProvider() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = settings.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let descriptor = currentDescriptor, !key.isEmpty, !modelID.isEmpty else { return }
        isKeyFocused = false
        isValidating = true

        Task {
            do {
                try await FamiliarProviderConnectionValidator.validate(
                    descriptor: descriptor,
                    modelID: modelID,
                    apiKey: key
                )
                settings.modelID = modelID
                settings.providerConfigurations[settings.providerID] = configuration
                try FamiliarKeychainStore.save(key, for: settings.providerID)
                try FamiliarSettingsStore.save(settings)
                isValidating = false
                setStep(2)
            } catch {
                isValidating = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private extension View {
    func onboardingField() -> some View {
        padding(.horizontal, 16)
            .frame(height: 52)
            .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct OnboardingPage<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    let content: Content

    init(symbol: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 48)
                ZStack {
                    Circle().fill(FamiliarTheme.brandGlow).frame(width: 112, height: 112)
                    Image(systemName: symbol)
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(FamiliarTheme.accent)
                }
                VStack(spacing: 10) {
                    Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                content.frame(maxWidth: 420)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct OnboardingFeatureRow: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FamiliarTheme.accent)
                .frame(width: 28)
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(FamiliarTheme.elevatedFill.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
