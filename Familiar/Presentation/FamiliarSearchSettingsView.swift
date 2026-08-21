import SwiftUI

struct FamiliarSearchSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let searchService: FamiliarWebSearchService

    @State private var providerID: String
    @State private var apiKey = ""
    @State private var hasAPIKey: Bool
    @State private var isValidating = false
    @State private var validationSucceeded = false
    @State private var errorMessage: String?

    init(searchService: FamiliarWebSearchService) {
        self.searchService = searchService
        let providerID = searchService.settingsStore.selectedProviderID
        _providerID = State(initialValue: providerID)
        _hasAPIKey = State(initialValue: FamiliarSearchKeychainStore.isConfigured(for: providerID))
    }

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "settings.search.provider", defaultValue: "Search Provider"), selection: $providerID) {
                    ForEach(FamiliarSearchProviderCatalog.all) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .onChange(of: providerID) { _, newValue in
                    apiKey = ""
                    hasAPIKey = FamiliarSearchKeychainStore.isConfigured(for: newValue)
                    validationSucceeded = false
                }
            } footer: {
                Text(String(localized: "settings.search.routing", defaultValue: "web_search uses only the selected provider. A failure is returned directly and never falls back to another provider."))
            }

            if descriptor.requiresAPIKey {
                Section {
                    SecureField(keyPlaceholder, text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: apiKey) { _, _ in validationSucceeded = false }

                    HStack {
                        Label(keyStatusTitle, systemImage: keyStatusSymbol)
                            .foregroundStyle(keyStatusColor)
                        Spacer()
                        if hasAPIKey {
                            Button(String(localized: "common.delete"), role: .destructive) {
                                deleteKey()
                            }
                        }
                    }
                } header: {
                    Text(String(format: String(localized: "settings.api_key.title"), descriptor.displayName))
                } footer: {
                    Text(String(localized: "settings.search.key.footer", defaultValue: "This search key is stored in a separate Keychain service and is never shared with model providers."))
                }
            }

            Section {
                Button {
                    validateConnection()
                } label: {
                    HStack {
                        if isValidating { ProgressView() }
                        Text(String(localized: "settings.api_key.verify"))
                        Spacer()
                    }
                }
                .disabled(isValidating || (descriptor.requiresAPIKey && effectiveKey.isEmpty))
            } footer: {
                Text(String(localized: "settings.search.validation.footer", defaultValue: "Validation sends one small test query to the selected search provider."))
            }

            Section(String(localized: "settings.search.privacy_cost", defaultValue: "Privacy and Cost")) {
                Label(
                    String(
                        format: String(localized: "settings.search.privacy", defaultValue: "Search queries are sent directly from this iPhone to %@. Search results may then be sent to your selected model provider as tool output."),
                        descriptor.displayName
                    ),
                    systemImage: "hand.raised"
                )
                Label(costDescription, systemImage: "creditcard")
                Link(
                    String(localized: "settings.search.provider_website", defaultValue: "Provider website and terms"),
                    destination: descriptor.websiteURL
                )
            }
        }
        .navigationTitle(String(localized: "settings.search.title", defaultValue: "Web Search"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .tint(FamiliarTheme.accent)
    }

    private var descriptor: FamiliarSearchProviderDescriptor {
        FamiliarSearchProviderCatalog.descriptor(for: providerID)
            ?? FamiliarSearchProviderCatalog.all[0]
    }

    private var effectiveKey: String {
        let entered = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return entered.isEmpty ? FamiliarSearchKeychainStore.load(for: providerID) ?? "" : entered
    }

    private var keyPlaceholder: String {
        hasAPIKey ? String(localized: "settings.api_key.replace_placeholder") : descriptor.apiKeyPlaceholder
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

    private var costDescription: String {
        if descriptor.requiresAPIKey {
            return String(
                format: String(localized: "settings.search.cost.paid", defaultValue: "%@ may charge your account according to its own plan, quota, and pricing."),
                descriptor.displayName
            )
        }
        return String(localized: "settings.search.cost.duckduckgo", defaultValue: "DuckDuckGo does not require an API key in Familiar. Its service terms still apply.")
    }

    private func save() {
        do {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if descriptor.requiresAPIKey, !key.isEmpty {
                try FamiliarSearchKeychainStore.save(key, for: providerID)
                hasAPIKey = true
                apiKey = ""
            }
            searchService.settingsStore.save(selectedProviderID: providerID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteKey() {
        do {
            try FamiliarSearchKeychainStore.delete(for: providerID)
            apiKey = ""
            hasAPIKey = false
            validationSucceeded = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func validateConnection() {
        isValidating = true
        Task {
            do {
                try await searchService.validateConnection(
                    providerID: providerID,
                    apiKey: descriptor.requiresAPIKey ? effectiveKey : nil
                )
                isValidating = false
                validationSucceeded = true
            } catch {
                isValidating = false
                validationSucceeded = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
