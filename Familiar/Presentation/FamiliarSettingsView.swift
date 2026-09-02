import SwiftUI

struct FamiliarModelServiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let initialSettings: FamiliarSettings
    let onSaveSettings: (FamiliarSettings) -> Void

    @State private var settings: FamiliarSettings
    @State private var configuration: FamiliarProviderConfiguration
    @State private var models: [FamiliarModelDescriptor]
    @State private var apiKey = ""
    @State private var hasAPIKey: Bool
    @State private var isValidating = false
    @State private var isRefreshingModels = false
    @State private var validationSucceeded = false
    @State private var errorMessage: String?

    init(
        initialSettings: FamiliarSettings,
        onSaveSettings: @escaping (FamiliarSettings) -> Void
    ) {
        self.initialSettings = initialSettings
        self.onSaveSettings = onSaveSettings
        _settings = State(initialValue: initialSettings)
        _configuration = State(initialValue: initialSettings.providerConfiguration)
        _models = State(initialValue: initialSettings.selectedProvider.curatedModels)
        _hasAPIKey = State(initialValue: FamiliarKeychainStore.isConfigured(for: initialSettings.providerID))
    }

    var body: some View {
        Form {
            providerSection
            modelSection
            keySection
        }
        .navigationTitle(String(localized: "settings.hub.model_service", defaultValue: "Model Service"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.save")) { save() }
                    .fontWeight(.semibold)
                    .disabled(currentDescriptor == nil || normalizedModelID.isEmpty)
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
        .tint(FamiliarTheme.accent)
    }

    private var providerSection: some View {
        Section {
            LabeledContent(String(localized: "settings.provider"), value: FamiliarProviderCatalog.deepSeek.displayName)
        } header: {
            Text(String(localized: "settings.provider"))
        } footer: {
            Text("DeepSeek 是 Familiar 1.0 唯一提供的模型服务。请求从这台 iPhone 直接发送，并使用你自己的 API Key。")
        }
    }

    private var modelSection: some View {
        Section {
            if !models.isEmpty {
                Picker(String(localized: "settings.model"), selection: $settings.modelID) {
                    ForEach(models) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
            }

            Button {
                refreshModels()
            } label: {
                HStack {
                    if isRefreshingModels { ProgressView() }
                    Text(String(localized: "settings.model.refresh"))
                    Spacer()
                }
            }
            .disabled(isRefreshingModels || effectiveKey.isEmpty || currentDescriptor?.modelsPath == nil)
        } header: {
            Text(String(localized: "settings.model"))
        } footer: {
            Text(currentDescriptor?.modelsPath == nil
                 ? String(localized: "settings.model.curated_footer")
                 : String(localized: "settings.model.refresh_footer"))
        }
    }

    private var keySection: some View {
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
            .disabled(isValidating || effectiveKey.isEmpty || currentDescriptor == nil || normalizedModelID.isEmpty)
        } header: {
            Text(String(format: String(localized: "settings.api_key.title"), providerDisplayName))
        } footer: {
            Text(String(format: String(localized: "settings.api_key.footer"), providerDisplayName))
        }
    }

    private var currentDescriptor: FamiliarProviderDescriptor? {
        FamiliarProviderCatalog.descriptor(for: settings.providerID, configuration: configuration)
    }

    private var providerDisplayName: String {
        currentDescriptor?.displayName
            ?? FamiliarProviderCatalog.deepSeek.displayName
    }

    private var normalizedModelID: String {
        settings.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveKey: String {
        let entered = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return entered.isEmpty ? FamiliarKeychainStore.load(for: settings.providerID) ?? "" : entered
    }

    private var keyPlaceholder: String {
        hasAPIKey
            ? String(localized: "settings.api_key.replace_placeholder")
            : currentDescriptor?.apiKeyPlaceholder ?? "sk-…"
    }

    private var keyStatusTitle: String {
        if validationSucceeded { return String(localized: "settings.api_key.verified") }
        return hasAPIKey ? String(localized: "settings.api_key.saved") : String(localized: "settings.api_key.missing")
    }

    private var keyStatusSymbol: String {
        validationSucceeded ? "checkmark.seal.fill" : (hasAPIKey ? "checkmark.circle.fill" : "exclamationmark.circle")
    }

    private var keyStatusColor: Color {
        validationSucceeded || hasAPIKey ? .green : .orange
    }

    private func settingsForSave() -> FamiliarSettings {
        var value = settings
        value.providerID = FamiliarProviderCatalog.deepSeek.id
        value.modelRoutePolicy = .cloud
        value.modelID = normalizedModelID
        value.providerConfigurations[value.providerID] = configuration
        return value
    }

    private func save() {
        let value = settingsForSave()
        guard let descriptor = value.resolvedProvider, !value.modelID.isEmpty else {
            errorMessage = String(localized: "error.provider.invalid_custom_configuration")
            return
        }
        let replacementKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacementKey.isEmpty else {
            onSaveSettings(value)
            dismiss()
            return
        }
        isValidating = true
        Task {
            do {
                try await FamiliarProviderConnectionValidator.validate(
                    descriptor: descriptor,
                    modelID: value.modelID,
                    apiKey: replacementKey
                )
                try FamiliarKeychainStore.save(replacementKey, for: value.providerID)
                hasAPIKey = true
                validationSucceeded = true
                isValidating = false
                onSaveSettings(value)
                dismiss()
            } catch {
                isValidating = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func validateCurrentKey() {
        guard let descriptor = currentDescriptor, !normalizedModelID.isEmpty else { return }
        let key = effectiveKey
        guard !key.isEmpty else { return }
        isValidating = true
        Task {
            do {
                try await FamiliarProviderConnectionValidator.validate(
                    descriptor: descriptor,
                    modelID: normalizedModelID,
                    apiKey: key
                )
                isValidating = false
                validationSucceeded = true
            } catch {
                isValidating = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshModels() {
        guard let descriptor = currentDescriptor else { return }
        let key = effectiveKey
        guard !key.isEmpty else { return }
        isRefreshingModels = true
        Task {
            do {
                let refreshed = try await FamiliarModelCatalogService.models(for: descriptor, apiKey: key)
                models = refreshed
                if !refreshed.contains(where: { $0.id == settings.modelID }),
                   let first = refreshed.first {
                    settings.modelID = first.id
                }
                isRefreshingModels = false
            } catch {
                isRefreshingModels = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearAPIKey() {
        do {
            try FamiliarKeychainStore.delete(for: settings.providerID)
            apiKey = ""
            hasAPIKey = false
            validationSucceeded = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
