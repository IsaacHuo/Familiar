import SwiftUI
import UIKit

struct FamiliarModelServiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    let initialSettings: FamiliarSettings
    let onSaveSettings: (FamiliarSettings) -> Void
    let onRestartOnboarding: () -> Void

    @State private var settings: FamiliarSettings
    @State private var configuration: FamiliarProviderConfiguration
    @State private var models: [FamiliarModelDescriptor]
    @State private var apiKey = ""
    @State private var hasAPIKey: Bool
    @State private var isValidating = false
    @State private var isRefreshingModels = false
    @State private var validationSucceeded = false
    @State private var errorMessage: String?
    @State private var configuredProviderIDs: Set<String>
    @State private var asksToRestartOnboarding = false
    @State private var runNotificationsEnabled: Bool
    @State private var notificationAuthorization: FamiliarNotificationAuthorizationState = .unknown
    @State private var isUpdatingNotifications = false

    init(
        initialSettings: FamiliarSettings,
        onSaveSettings: @escaping (FamiliarSettings) -> Void,
        onRestartOnboarding: @escaping () -> Void
    ) {
        self.initialSettings = initialSettings
        self.onSaveSettings = onSaveSettings
        self.onRestartOnboarding = onRestartOnboarding
        _settings = State(initialValue: initialSettings)
        _configuration = State(initialValue: initialSettings.providerConfiguration)
        _models = State(initialValue: initialSettings.selectedProvider.curatedModels)
        _hasAPIKey = State(initialValue: FamiliarKeychainStore.isConfigured(for: initialSettings.providerID))
        _configuredProviderIDs = State(initialValue: FamiliarKeychainStore.configuredProviderIDs(
            in: FamiliarProviderCatalog.allProviderIDs
        ))
        _runNotificationsEnabled = State(initialValue: FamiliarNotificationPreference.isEnabled)
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
        .task { await refreshNotificationAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotificationAuthorization() }
        }
    }

    private var providerSection: some View {
        Section {
            Picker(String(localized: "settings.provider"), selection: $settings.providerID) {
                ForEach(providerChoices, id: \.id) { provider in
                    Text(provider.displayName).tag(provider.id)
                }
            }
            .onChange(of: settings.providerID) { oldID, newID in
                switchProvider(from: oldID, to: newID)
            }

            if settings.providerID == "openai" {
                TextField(String(localized: "settings.openai.organization"), text: $configuration.organizationID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(String(localized: "settings.openai.project"), text: $configuration.projectID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if settings.providerID == "qwen" {
                Picker(String(localized: "settings.qwen.region"), selection: $configuration.region) {
                    Text(String(localized: "settings.qwen.region.china")).tag(FamiliarProviderRegion.china)
                    Text(String(localized: "settings.qwen.region.international")).tag(FamiliarProviderRegion.international)
                }
            }

            if settings.providerID == FamiliarProviderCatalog.customProviderID {
                TextField(String(localized: "settings.custom.name"), text: $configuration.displayName)
                TextField("https://example.com/v1", text: $configuration.baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                TextField(String(localized: "settings.custom.models_path"), text: $configuration.modelsPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            HStack {
                Text(String(localized: "settings.provider"))
                Spacer()
                Text(String(
                    format: String(localized: "settings.provider.configured_count"),
                    configuredProviderIDs.count
                ))
                .textCase(nil)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(
                    format: String(localized: "settings.provider.configured_count.accessibility"),
                    configuredProviderIDs.count
                ))
            }
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

            TextField(String(localized: "settings.model.manual"), text: $settings.modelID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

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

    private var responseSection: some View {
        Section {
            TextEditor(text: $settings.systemPrompt)
                .frame(minHeight: 120)
        } header: {
            Text(String(localized: "settings.response_preferences"))
        } footer: {
            Text(String(localized: "settings.system_prompt.footer"))
        }
    }

    private var privacySection: some View {
        Section(String(localized: "settings.privacy.title")) {
            Label(String(localized: "settings.privacy.no_account"), systemImage: "person.crop.circle.badge.xmark")
            Label(String(localized: "settings.privacy.permission_tools"), systemImage: "hand.raised")
            Label(String(localized: "settings.privacy.local_history"), systemImage: "internaldrive")
            Label(String(localized: "settings.privacy.local_documents"), systemImage: "doc.text.magnifyingglass")
            Label(String(localized: "settings.privacy.remote_images"), systemImage: "photo.badge.exclamationmark")
            Label(String(localized: "settings.privacy.web_tools"), systemImage: "network")
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle(
                String(localized: "settings.notifications.run_terminal"),
                isOn: Binding(
                    get: { runNotificationsEnabled },
                    set: { enabled in
                        Task { await updateRunNotifications(enabled) }
                    }
                )
            )
            .disabled(isUpdatingNotifications)

            if notificationAuthorization == .denied,
               let settingsURL = URL(string: UIApplication.openNotificationSettingsURLString) {
                Button(String(localized: "settings.notifications.open_settings")) {
                    openURL(settingsURL)
                }
            }
        } header: {
            Text(String(localized: "settings.notifications.title"))
        } footer: {
            Text(notificationFooter)
        }
    }

    private var onboardingSection: some View {
        Section {
            Button(String(localized: "settings.onboarding.restart")) {
                asksToRestartOnboarding = true
            }
        } footer: {
            Text(String(localized: "settings.onboarding.restart.footer"))
        }
    }

    private var brandHeader: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(FamiliarTheme.accent.opacity(0.14))
                    Text("F")
                        .font(.title2.bold())
                        .foregroundStyle(FamiliarTheme.accent)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "settings.profile.name"))
                        .font(.headline)
                    Text(String(localized: "settings.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var providerChoices: [FamiliarProviderDescriptor] {
        FamiliarProviderCatalog.builtIn + [customChoice]
    }

    private var customChoice: FamiliarProviderDescriptor {
        FamiliarProviderCatalog.descriptor(
            for: FamiliarProviderCatalog.customProviderID,
            configuration: configurationForCustomChoice
        ) ?? FamiliarProviderDescriptor(
            id: FamiliarProviderCatalog.customProviderID,
            displayName: String(localized: "settings.custom.provider"),
            protocolKind: .openAIChat,
            baseURL: URL(string: "https://example.com/v1")!,
            chatPath: "/chat/completions",
            modelsPath: nil,
            authStyle: .bearer,
            additionalHeaders: [:],
            curatedModels: [],
            openAIChat: .init(),
            isCustom: true
        )
    }

    private var configurationForCustomChoice: FamiliarProviderConfiguration {
        if settings.providerID == FamiliarProviderCatalog.customProviderID { return configuration }
        return settings.providerConfigurations[FamiliarProviderCatalog.customProviderID] ?? .empty
    }

    private var currentDescriptor: FamiliarProviderDescriptor? {
        FamiliarProviderCatalog.descriptor(for: settings.providerID, configuration: configuration)
    }

    private var providerDisplayName: String {
        currentDescriptor?.displayName
            ?? FamiliarProviderCatalog.builtIn.first(where: { $0.id == settings.providerID })?.displayName
            ?? String(localized: "settings.custom.provider")
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

    private var notificationFooter: String {
        switch notificationAuthorization {
        case .denied:
            String(localized: "settings.notifications.denied_footer")
        case .unknown, .notDetermined, .enabled:
            String(localized: "settings.notifications.footer")
        }
    }

    private func switchProvider(from oldID: String, to newID: String) {
        settings.providerConfigurations[oldID] = configuration
        configuration = settings.providerConfigurations[newID] ?? .empty
        let descriptor = FamiliarProviderCatalog.descriptor(for: newID, configuration: configuration)
        models = descriptor?.curatedModels ?? []
        settings.modelID = newID == FamiliarProviderCatalog.customProviderID
            ? ""
            : descriptor?.defaultModel.id ?? ""
        apiKey = ""
        hasAPIKey = configuredProviderIDs.contains(newID)
        validationSucceeded = false
    }

    private func settingsForSave() -> FamiliarSettings {
        var value = settings
        value.modelID = normalizedModelID
        value.providerConfigurations[value.providerID] = configuration
        return value
    }

    private func save() {
        do {
            let value = settingsForSave()
            guard value.resolvedProvider != nil, !value.modelID.isEmpty else {
                errorMessage = String(localized: "error.provider.invalid_custom_configuration")
                return
            }
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                try FamiliarKeychainStore.save(trimmedKey, for: value.providerID)
                configuredProviderIDs.insert(value.providerID)
            }
            onSaveSettings(value)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
                if settings.modelID.isEmpty, let first = refreshed.first { settings.modelID = first.id }
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
            configuredProviderIDs.remove(settings.providerID)
            validationSucceeded = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshNotificationAuthorization() async {
        let state = await FamiliarNotificationService.authorizationState()
        notificationAuthorization = state
        if state != .enabled {
            FamiliarNotificationPreference.setEnabled(false)
            runNotificationsEnabled = false
        } else {
            runNotificationsEnabled = FamiliarNotificationPreference.isEnabled
        }
    }

    private func updateRunNotifications(_ enabled: Bool) async {
        guard !isUpdatingNotifications else { return }
        isUpdatingNotifications = true
        defer { isUpdatingNotifications = false }
        do {
            notificationAuthorization = try await FamiliarNotificationService.setEnabled(enabled)
            runNotificationsEnabled = enabled && notificationAuthorization == .enabled
        } catch {
            runNotificationsEnabled = false
            errorMessage = String(
                format: String(localized: "settings.notifications.error"),
                error.localizedDescription
            )
        }
    }
}
