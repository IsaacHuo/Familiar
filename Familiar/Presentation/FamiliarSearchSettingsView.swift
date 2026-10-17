import Observation
import SwiftUI

/// iOS Settings-style commit model: every change is persisted immediately.
/// Provider selection saves on change; the key saves on submit, on focus loss,
/// before verification and when the page disappears.
struct FamiliarSearchSettingsView: View {
    @State private var state: FamiliarSearchSettingsState
    @FocusState private var isKeyFocused: Bool

    init(searchService: FamiliarWebSearchService) {
        _state = State(initialValue: FamiliarSearchSettingsState(service: searchService))
    }

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                Picker(String(localized: "settings.search.provider", defaultValue: "Search Provider"),
                       selection: Binding(get: { state.providerID }, set: { state.selectProvider($0) })) {
                    ForEach(FamiliarSearchProviderCatalog.releaseVisible) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
            } footer: {
                Text(String(localized: "settings.search.routing.v2", defaultValue: "If the selected service is unreachable, DuckDuckGo answers instead and the result says so. Key, quota and rate-limit problems are reported directly."))
            }

            if descriptor.requiresAPIKey {
                Section {
                    SecureField(keyPlaceholder, text: $state.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .submitLabel(.done)
                        .focused($isKeyFocused)
                        .onSubmit { state.saveKey() }
                        .onChange(of: isKeyFocused) { _, focused in if !focused { state.saveKey() } }

                    HStack {
                        Label(keyStatusTitle, systemImage: keyStatusSymbol)
                            .foregroundStyle(keyStatusColor)
                        Spacer()
                        if state.keyState.key != nil {
                            Button(String(localized: "common.delete"), role: .destructive) { state.deleteKey() }
                        }
                    }
                } header: {
                    Text(String(format: String(localized: "settings.api_key.title"), descriptor.displayName))
                } footer: {
                    if state.keyState == .missing && state.normalizedEntry.isEmpty {
                        Text(String(format: String(localized: "settings.search.key.required", defaultValue: "%@ needs an API key. Until one is added, searches fail."), descriptor.displayName))
                            .foregroundStyle(FamiliarTheme.warning)
                    } else {
                        Text(String(localized: "settings.search.key.footer", defaultValue: "This search key is stored in a separate Keychain service and is never shared with model providers."))
                    }
                }
            }

            Section {
                Button {
                    state.startValidation()
                } label: {
                    HStack {
                        Text(String(localized: "settings.api_key.verify"))
                        Spacer()
                        if state.isValidating { ProgressView() }
                    }
                }
                .disabled(state.isValidating || (descriptor.requiresAPIKey && state.effectiveKey.isEmpty))
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
        .onDisappear { state.leave() }
        .alert(String(localized: "settings.error.title"), isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? String(localized: "error.unknown"))
        }
        .tint(FamiliarTheme.accent)
    }

    private var descriptor: FamiliarSearchProviderDescriptor {
        FamiliarSearchProviderCatalog.descriptor(for: state.providerID)
            ?? FamiliarSearchProviderCatalog.releaseVisible[0]
    }

    private var keyPlaceholder: String {
        state.keyState.key != nil ? String(localized: "settings.api_key.replace_placeholder") : descriptor.apiKeyPlaceholder
    }

    private var keyStatusTitle: String {
        if state.validationSucceeded { return String(localized: "settings.api_key.verified") }
        switch state.keyState {
        case .found: return String(localized: "settings.api_key.saved")
        case .missing: return String(localized: "settings.api_key.missing")
        case .locked: return String(localized: "settings.search.key.locked", defaultValue: "Unavailable until the device is unlocked")
        case .failed(let status): return String(format: String(localized: "settings.search.key.failed", defaultValue: "Keychain error %d"), Int(status))
        }
    }

    private var keyStatusSymbol: String {
        if state.validationSucceeded { return "checkmark.seal.fill" }
        return state.keyState.key != nil ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var keyStatusColor: Color {
        state.validationSucceeded || state.keyState.key != nil ? FamiliarTheme.success : FamiliarTheme.warning
    }

    private var costDescription: String {
        if descriptor.requiresAPIKey {
            return String(
                format: String(localized: "settings.search.cost.paid", defaultValue: "%@ may charge your account according to its own plan, quota, and pricing."),
                descriptor.displayName
            )
        }
        return String(
            format: String(localized: "settings.search.cost.no_key", defaultValue: "%@ does not require an API key in Familiar. Its service terms still apply."),
            descriptor.displayName
        )
    }

}

/// Owns one settings editor. Validation is tied to a saved credential revision,
/// so focus changes, provider switches and stale replies cannot relabel a key.
@MainActor @Observable
final class FamiliarSearchSettingsState {
    private(set) var providerID: String
    var apiKey = "" {
        didSet { if apiKey != oldValue { invalidateValidation() } }
    }
    private(set) var keyState: FamiliarSearchKeyLookup
    private(set) var isValidating = false
    private(set) var validationSucceeded = false
    var errorMessage: String?

    private let settings: FamiliarSearchSettingsStore
    private let keys: any FamiliarSearchAPIKeyManaging
    private let validate: @Sendable (String, String?) async throws -> Void
    private var validationID: UUID?
    private var validationTask: Task<Void, Never>?

    convenience init(service: FamiliarWebSearchService) {
        self.init(settings: service.settingsStore, keys: FamiliarSearchKeychainAPIKeyStore()) {
            try await service.validateConnection(providerID: $0, apiKey: $1)
        }
    }

    init(settings: FamiliarSearchSettingsStore, keys: any FamiliarSearchAPIKeyManaging,
         validate: @escaping @Sendable (String, String?) async throws -> Void) {
        self.settings = settings
        self.keys = keys
        self.validate = validate
        let selectedProvider = settings.selectedProviderID
        providerID = selectedProvider
        keyState = keys.lookup(for: selectedProvider)
    }

    var normalizedEntry: String { FamiliarSearchKeychainStore.normalized(apiKey) }
    var effectiveKey: String { normalizedEntry.isEmpty ? keyState.key ?? "" : normalizedEntry }

    func selectProvider(_ id: String) {
        guard id != providerID, saveKey() else { return }
        invalidateValidation()
        providerID = FamiliarSearchProviderCatalog.resolvedProviderID(id)
        settings.save(selectedProviderID: providerID)
        apiKey = ""
        keyState = keys.lookup(for: providerID)
    }

    @discardableResult func saveKey() -> Bool {
        let key = normalizedEntry
        guard FamiliarSearchProviderCatalog.descriptor(for: providerID)?.requiresAPIKey == true,
              !key.isEmpty else { return true }
        do {
            try keys.save(key, for: providerID)
            keyState = keys.lookup(for: providerID)
            guard keyState.key == key else { throw FamiliarWebError.searchKeyLocked }
            apiKey = ""
            return true
        } catch {
            invalidateValidation()
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteKey() {
        invalidateValidation()
        do {
            try keys.delete(for: providerID)
            apiKey = ""
            keyState = keys.lookup(for: providerID)
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult func startValidation() -> Task<Void, Never>? {
        invalidateValidation()
        guard saveKey() else { return nil }
        let provider = providerID
        let requiresKey = FamiliarSearchProviderCatalog.descriptor(for: provider)?.requiresAPIKey == true
        let key = requiresKey ? keyState.key : nil
        guard !requiresKey || key != nil else {
            errorMessage = FamiliarWebError.missingSearchAPIKey(provider).localizedDescription
            return nil
        }
        let id = UUID()
        validationID = id
        isValidating = true
        validationTask = Task { [weak self, validate] in
            do {
                try await validate(provider, key)
                guard let self, self.validationID == id, !Task.isCancelled else { return }
                // Re-read the saved value; verification never makes an unsaved key look valid.
                let current = self.keys.lookup(for: provider)
                self.keyState = current
                self.isValidating = false
                self.validationSucceeded = key == nil || current.key == key
            } catch {
                guard let self, self.validationID == id, !Task.isCancelled else { return }
                self.isValidating = false
                self.errorMessage = error.localizedDescription
            }
        }
        return validationTask
    }

    func leave() {
        _ = saveKey()
        invalidateValidation()
    }

    private func invalidateValidation() {
        validationTask?.cancel()
        validationTask = nil
        validationID = nil
        validationSucceeded = false
        isValidating = false
    }
}
