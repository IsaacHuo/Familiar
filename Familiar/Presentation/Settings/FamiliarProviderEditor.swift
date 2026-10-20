import SwiftUI

struct FamiliarProviderEditor: View {
    @Environment(\.dismiss) private var dismiss
    let provider: FamiliarProviderDescriptor
    let isCurrent: Bool
    let onSelect: (FamiliarProviderDescriptor, String) -> Void
    @State private var name: String
    @State private var baseURL: String
    @State private var apiKey = ""
    @State private var models: [FamiliarModelDescriptor]
    @State private var modelID: String
    @State private var newModelID = ""
    private enum Operation { case discovering, verifying, signingIn }
    @State private var operation: Operation?
    @State private var verifiedIdentity: FamiliarProviderVerificationIdentity?
    private var busy: Bool { operation != nil }
    private var verified: Bool { verifiedIdentity != nil && verifiedIdentity == currentIdentity }
    private var currentIdentity: FamiliarProviderVerificationIdentity? {
        guard let descriptor = try? descriptor() else { return nil }
        return try? .init(descriptor: descriptor, modelID: modelID, credential: effectiveKey)
    }
    @State private var errorMessage: String?
    @State private var exported: URL?
    @State private var confirmsDelete = false
    @State private var showsLogin = false
    @State private var loginRevision = 0

    init(provider: FamiliarProviderDescriptor, isCurrent: Bool, selectedModelID: String? = nil, onSelect: @escaping (FamiliarProviderDescriptor, String) -> Void) {
        self.provider = provider
        self.isCurrent = isCurrent
        self.onSelect = onSelect
        _name = State(initialValue: provider.localizedName)
        _baseURL = State(initialValue: provider.baseURL.absoluteString)
        _models = State(initialValue: provider.curatedModels)
        _modelID = State(initialValue: selectedModelID ?? provider.curatedModels.first?.id ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "settings.provider")) {
                    TextField(String(localized: "provider.name"), text: $name)
                    TextField(String(localized: "provider.endpoint"), text: $baseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    LabeledContent(String(localized: "provider.protocol"), value: provider.protocolKind.rawValue)
                    if provider.oauthKind == nil {
                    SecureField(String(localized: FamiliarKeychainStore.isConfigured(for: provider.id) ? "settings.api_key.replace_placeholder" : "settings.api_key.missing"), text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if provider.baseURL.host == "openrouter.ai" {
                            Button(String(localized: "oauth.sign_in")) { browserLogin("openrouter") }
                        }
                    } else {
                        Button(String(localized: "oauth.sign_in")) {
                            if provider.oauthKind == "kimi" { showsLogin = true }
                            else { browserLogin("codex") }
                        }
                        if FamiliarOAuthCredentialStore.load(instanceID: provider.id) != nil {
                            Label(String(localized: "oauth.signed_in"), systemImage: "checkmark.seal")
                            Button(String(localized: "oauth.sign_out"), role: .destructive) {
                                do { try FamiliarKeychainStore.delete(for: "oauth." + provider.id); loginRevision += 1 }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }
                    }
                }
                .id(loginRevision)
                Section(String(localized: "settings.model")) {
                    ForEach(models) { model in
                        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
                            Button { modelID = model.id } label: {
                                HStack {
                                    Text(model.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if modelID == model.id { Image(systemName: "checkmark") }
                                }
                            }
                            Toggle(String(localized: "provider.tools"), isOn: capabilityBinding(model.id, images: false))
                            Toggle(String(localized: "provider.images"), isOn: capabilityBinding(model.id, images: true))
                        }.padding(.vertical, FamiliarSpacing.xSmall)
                    }
                    .onDelete { offsets in
                        models.remove(atOffsets: offsets)
                        if !models.contains(where: { $0.id == modelID }) { modelID = models.first?.id ?? "" }
                    }
                    HStack {
                        TextField(String(localized: "provider.model_id"), text: $newModelID).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button(String(localized: "common.add")) { addModel() }.disabled(newModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button(String(localized: "settings.model.refresh")) { discover() }.disabled(busy || effectiveKey.isEmpty)
                }
                Section {
                    Button(String(localized: "settings.api_key.verify")) { validate() }.disabled(busy || effectiveKey.isEmpty || modelID.isEmpty)
                    if let operation {
                        ProgressView(String(localized: operation == .discovering ? "settings.provider.discovering" : operation == .verifying ? "settings.provider.verifying" : "settings.provider.signing_in"))
                    }
                    if verified {
                        Label(String(localized: "settings.api_key.verified") + " · " + (models.first { $0.id == modelID }?.displayName ?? modelID), systemImage: "checkmark.seal")
                    }
                    Button(String(localized: "provider.use")) { save(select: true) }.disabled(busy || modelID.isEmpty)
                    Button(String(localized: "provider.export")) { export() }.disabled(busy)
                    if let exported { ShareLink(item: exported) }
                    Button(String(localized: "common.delete"), role: .destructive) { confirmsDelete = true }.disabled(isCurrent || provider.id == "deepseek")
                } footer: { Text(String(localized: "provider.export.footer")) }
            }
            .disabled(busy)
            .navigationTitle(String(localized: "settings.provider"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "common.save")) { save(select: false) }.disabled(busy) }
            }
            .sheet(isPresented: $showsLogin, onDismiss: { loginRevision += 1 }) {
                FamiliarKimiLoginView(instanceID: provider.id)
            }
            .interactiveDismissDisabled(busy)
            .onChange(of: currentIdentity) { old, new in if old != new { verifiedIdentity = nil } }
            .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .confirmationDialog(String(localized: "common.delete"), isPresented: $confirmsDelete) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    do { try FamiliarProviderInstanceStore.remove(provider.id); dismiss() }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        }
    }

    private var effectiveKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FamiliarKeychainStore.load(for: provider.id) ?? FamiliarOAuthCredentialStore.load(instanceID: provider.id)?.accessToken ?? "" : apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func descriptor() throws -> FamiliarProviderDescriptor {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw FamiliarProviderConnectionError.invalidResponse }
        let value = provider.instance(id: provider.id, name: name, url: url, models: models)
        try FamiliarProviderInstanceStore.validate(value)
        return value
    }
    private func addModel() {
        let id = newModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !models.contains(where: { $0.id == id }) { models.append(.init(id: id)) }
        modelID = id; newModelID = ""
    }
    private func capabilityBinding(_ id: String, images: Bool) -> Binding<Bool> {
        Binding(get: {
            let capability = models.first(where: { $0.id == id })?.capabilities
            return images ? capability?.supportsImages == true : capability?.supportsTools == true
        }, set: { enabled in
            guard let index = models.firstIndex(where: { $0.id == id }) else { return }
            let model = models[index]
            models[index] = .init(id: model.id, displayName: model.displayName, capabilities: .init(
                supportsTools: images ? model.capabilities.supportsTools : enabled,
                supportsImages: images ? enabled : model.capabilities.supportsImages,
                supportsDocuments: true,
                maximumInputCharacters: model.capabilities.maximumInputCharacters
            ))
        })
    }
    private func browserLogin(_ kind: String) {
        operation = .signingIn
        verifiedIdentity = nil
        Task { @MainActor in
            defer { operation = nil }
            do {
                try await FamiliarBrowserOAuth.shared.login(kind: kind, instanceID: provider.id)
                apiKey = ""
                loginRevision += 1
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }
    private func discover() {
        do {
            let value = try descriptor(); let key = effectiveKey; operation = .discovering
            Task { @MainActor in
                defer { operation = nil }
                do {
                    let found = try await FamiliarModelCatalogService.models(for: value, apiKey: key)
                    let existing = Set(models.map(\.id))
                    models += found.filter { !existing.contains($0.id) }
                    if modelID.isEmpty { modelID = models.first?.id ?? "" }
                } catch { errorMessage = error.localizedDescription }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    private func validate() {
        do {
            let value = try descriptor(); let key = effectiveKey; let selected = modelID
            verifiedIdentity = nil
            let identity = try FamiliarProviderVerificationIdentity(descriptor: value, modelID: selected, credential: key)
            operation = .verifying
            Task { @MainActor in
                defer { operation = nil }
                do {
                    try await FamiliarProviderConnectionValidator.validate(descriptor: value, modelID: selected, apiKey: key)
                    if currentIdentity == identity { verifiedIdentity = identity }
                }
                catch { errorMessage = error.localizedDescription }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    private func save(select: Bool) {
        do {
            let value = try descriptor()
            try FamiliarProviderInstanceStore.save(value)
            if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try FamiliarKeychainStore.save(apiKey, for: provider.id) }
            if select { onSelect(value, modelID) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
    private func export() {
        do {
            let value = try descriptor()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Familiar-provider-\(UUID().uuidString).json")
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            exported = url
        } catch { errorMessage = error.localizedDescription }
    }
}

