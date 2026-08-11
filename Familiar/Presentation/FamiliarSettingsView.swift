import SwiftUI

struct FamiliarSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let initialSettings: FamiliarSettings
    let onSaveSettings: (FamiliarSettings) -> Void

    @State private var settings: FamiliarSettings
    @State private var apiKey = ""
    @State private var hasAPIKey: Bool
    @State private var isValidating = false
    @State private var validationSucceeded = false
    @State private var errorMessage: String?

    init(
        initialSettings: FamiliarSettings,
        onSaveSettings: @escaping (FamiliarSettings) -> Void
    ) {
        self.initialSettings = initialSettings
        self.onSaveSettings = onSaveSettings
        _settings = State(initialValue: initialSettings)
        _hasAPIKey = State(initialValue: FamiliarKeychainStore.isConfigured(for: initialSettings.provider))
    }

    var body: some View {
        NavigationStack {
            Form {
                brandHeader

                Section(String(localized: "settings.provider")) {
                    Picker(String(localized: "settings.provider"), selection: $settings.provider) {
                        ForEach(FamiliarProvider.allCases) { provider in
                            Label(provider.title, systemImage: provider == .deepSeek ? "bolt.fill" : "hare.fill")
                                .tag(provider)
                        }
                    }
                    .onChange(of: settings.provider) { _, provider in
                        switchProvider(to: provider)
                    }

                    Picker(String(localized: "settings.model"), selection: $settings.modelID) {
                        ForEach(settings.provider.models) { model in
                            Text(model.title).tag(model.id)
                        }
                    }
                }

                Section {
                    SecureField(keyPlaceholder, text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) { _, _ in validationSucceeded = false }

                    HStack(spacing: 10) {
                        Label(keyStatusTitle, systemImage: keyStatusSymbol)
                            .foregroundStyle(keyStatusColor)
                        Spacer()
                        if hasAPIKey {
                            Button(String(localized: "common.clear"), role: .destructive) {
                                clearAPIKey()
                            }
                        }
                    }

                    Button {
                        validateCurrentKey()
                    } label: {
                        HStack {
                            if isValidating { ProgressView() }
                            Text(String(localized: "settings.api_key.verify"))
                            Spacer()
                        }
                    }
                    .disabled(isValidating || effectiveKey.isEmpty)
                } header: {
                    Text(String(format: String(localized: "settings.api_key.title"), settings.provider.title))
                } footer: {
                    Text(String(format: String(localized: "settings.api_key.footer"), settings.provider.title))
                }

                Section {
                    TextEditor(text: $settings.systemPrompt)
                        .frame(minHeight: 120)
                } header: {
                    Text(String(localized: "settings.response_preferences"))
                } footer: {
                    Text(String(localized: "settings.system_prompt.footer"))
                }

                Section(String(localized: "settings.privacy.title")) {
                    Label(String(localized: "settings.privacy.no_account"), systemImage: "person.crop.circle.badge.xmark")
                    Label(String(localized: "settings.privacy.no_other_apps"), systemImage: "hand.raised")
                    Label(String(localized: "settings.privacy.local_history"), systemImage: "internaldrive")
                }
            }
            .navigationTitle(String(localized: "drawer.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) { save() }
                        .fontWeight(.semibold)
                }
            }
            .alert(String(localized: "settings.error.title"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? String(localized: "error.unknown"))
            }
        }
        .tint(FamiliarTheme.accent)
    }

    private var brandHeader: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(FamiliarTheme.brandGlow)
                    Image(systemName: "sparkles")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(FamiliarTheme.accent)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "app.name"))
                        .font(.headline)
                    Text(String(localized: "settings.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var effectiveKey: String {
        let entered = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entered.isEmpty { return entered }
        return FamiliarKeychainStore.load(for: settings.provider) ?? ""
    }

    private var keyPlaceholder: String {
        hasAPIKey
            ? String(localized: "settings.api_key.replace_placeholder")
            : settings.provider.apiKeyPlaceholder
    }

    private var keyStatusTitle: String {
        if validationSucceeded { return String(localized: "settings.api_key.verified") }
        return hasAPIKey
            ? String(localized: "settings.api_key.saved")
            : String(localized: "settings.api_key.missing")
    }

    private var keyStatusSymbol: String {
        validationSucceeded ? "checkmark.seal.fill" : (hasAPIKey ? "checkmark.circle.fill" : "exclamationmark.circle")
    }

    private var keyStatusColor: Color {
        validationSucceeded || hasAPIKey ? .green : .orange
    }

    private func save() {
        do {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                try FamiliarKeychainStore.save(trimmedKey, for: settings.provider)
                hasAPIKey = true
            }
            onSaveSettings(settings)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func validateCurrentKey() {
        let key = effectiveKey
        guard !key.isEmpty else { return }
        isValidating = true
        Task {
            do {
                try await FamiliarProviderConnectionValidator.validate(provider: settings.provider, apiKey: key)
                isValidating = false
                validationSucceeded = true
            } catch {
                isValidating = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func switchProvider(to provider: FamiliarProvider) {
        apiKey = ""
        hasAPIKey = FamiliarKeychainStore.isConfigured(for: provider)
        validationSucceeded = false
        settings.modelID = provider.defaultModelID
    }

    private func clearAPIKey() {
        do {
            try FamiliarKeychainStore.delete(for: settings.provider)
            apiKey = ""
            hasAPIKey = false
            validationSucceeded = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
