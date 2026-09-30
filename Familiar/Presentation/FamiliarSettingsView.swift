import SwiftUI
import UniformTypeIdentifiers

struct FamiliarModelServiceSettingsView: View {
    let initialSettings: FamiliarSettings
    let onSaveSettings: (FamiliarSettings) -> Void
    @State private var providers = FamiliarProviderCatalog.instances
    @State private var voiceProviders = FamiliarVoiceStore.load()
    @State private var destination: EditorDestination?
    @State private var importing = false
    @State private var errorMessage: String?

    private enum EditorDestination: Identifiable {
        case chooser
        case provider(FamiliarProviderDescriptor)
        case voice(FamiliarVoiceConfiguration)
        var id: String {
            switch self {
            case .chooser: "chooser"
            case .provider(let value): value.id
            case .voice(let value): value.id
            }
        }
    }

    var body: some View {
        List {
            Section(String(localized: "settings.provider")) {
                ForEach(providers) { provider in
                    Button { destination = .provider(provider) } label: {
                        HStack(spacing: FamiliarSpacing.medium) {
                            FamiliarProviderIcon(provider: provider)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider.displayName).foregroundStyle(.primary)
                                Text(provider.baseURL.host ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if initialSettings.providerID == provider.id { Image(systemName: "checkmark") }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.frame(minHeight: 44)
                    }
                }
                Button { destination = .chooser } label: { Label(String(localized: "provider.add"), systemImage: "plus") }
                Button { importing = true } label: { Label(String(localized: "provider.import"), systemImage: "square.and.arrow.down") }
            }
            Section(String(localized: "voice.providers")) {
                ForEach(voiceProviders) { voice in
                    Button(FamiliarVoiceStore.displayName(voice.name)) { destination = .voice(voice) }
                }
                NavigationLink(String(localized: "voice.title")) { FamiliarVoiceSettingsView() }
            }
        }
        .navigationTitle(String(localized: "settings.hub.model_service"))
        .sheet(item: $destination, onDismiss: reload) { item in
            switch item {
            case .chooser: chooser
            case .provider(let provider):
                FamiliarProviderEditor(provider: provider, isCurrent: initialSettings.providerID == provider.id, selectedModelID: initialSettings.providerID == provider.id ? initialSettings.modelID : nil) { descriptor, modelID in
                    var value = initialSettings
                    value.providerID = descriptor.id; value.modelID = modelID; value.modelRoutePolicy = .cloud
                    onSaveSettings(value)
                }
            case .voice(let voice): FamiliarVoiceProviderEditor(value: voice)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard data.count <= 2_000_000 else { throw FamiliarProviderConnectionError.invalidResponse }
                let imported = try JSONDecoder().decode(FamiliarProviderDescriptor.self, from: data).instance(id: UUID().uuidString)
                try FamiliarProviderInstanceStore.validate(imported)
                destination = .provider(imported)
            } catch { errorMessage = error.localizedDescription }
        }
        .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
    private var chooser: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FamiliarProviderCatalog.templates) { template in
                        Button { destination = .provider(template.instance(id: UUID().uuidString)) } label: {
                            HStack(spacing: 12) {
                                FamiliarProviderIcon(provider: template)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.localizedName).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(template.pickerSubtitle).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 6)
                        }
                    }
                } header: { Text(String(localized: "provider.choose")) }
                footer: { Text(String(localized: "provider.instances.footer")) }
                Section(String(localized: "voice.providers")) {
                    ForEach(FamiliarVoiceStore.templates, id: \.0) { vendor, name, endpoint in
                        Button { destination = .voice(.init(vendor: vendor, name: name, baseURL: endpoint)) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform").font(.title3).foregroundStyle(.blue)
                                    .frame(width: 36, height: 36).background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: FamiliarRadius.compact))
                                Text(FamiliarVoiceStore.displayName(name)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "provider.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { destination = nil } } }
        }
    }
    private func reload() { providers = FamiliarProviderCatalog.instances; voiceProviders = FamiliarVoiceStore.load() }
}

private struct FamiliarProviderIcon: View {
    let provider: FamiliarProviderDescriptor
    private var appearance: (String, Color) {
        switch provider.baseURL.host {
        case "openrouter.ai": return ("arrow.triangle.branch", .cyan)
        case "api.x.ai": return ("x.circle", .gray)
        case "api.moonshot.cn", "api.kimi.com": return ("moon.stars", .indigo)
        default:
            switch provider.protocolKind {
            case .anthropic: return ("sparkles", .purple)
            case .gemini: return ("diamond", .blue)
            case .openAIResponses: return ("arrow.triangle.2.circlepath", .mint)
            case .openAIChat: return ("circle.hexagongrid", .green)
            }
        }
    }
    var body: some View {
        Image(systemName: appearance.0).font(.system(size: FamiliarIconSize.prominent))
            .foregroundStyle(appearance.1).frame(width: 36, height: 36)
            .background(appearance.1.opacity(0.12), in: RoundedRectangle(cornerRadius: FamiliarRadius.compact))
            .accessibilityHidden(true)
    }
}

private struct FamiliarProviderEditor: View {
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
    @State private var busy = false
    @State private var verified = false
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
                        VStack(alignment: .leading, spacing: 8) {
                            Button { modelID = model.id } label: {
                                HStack {
                                    Text(model.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if modelID == model.id { Image(systemName: "checkmark") }
                                }
                            }
                            Toggle(String(localized: "provider.tools"), isOn: capabilityBinding(model.id, images: false))
                            Toggle(String(localized: "provider.images"), isOn: capabilityBinding(model.id, images: true))
                        }.padding(.vertical, 4)
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
                    if busy { ProgressView() }
                    if verified { Label(String(localized: "settings.api_key.verified"), systemImage: "checkmark.seal") }
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
            .onChange(of: apiKey) { _, _ in verified = false }
            .onChange(of: baseURL) { _, _ in verified = false }
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
        busy = true
        Task { @MainActor in
            defer { busy = false }
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
            let value = try descriptor(); let key = effectiveKey; busy = true
            Task { @MainActor in
                defer { busy = false }
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
            let value = try descriptor(); let key = effectiveKey; let selected = modelID; busy = true
            Task { @MainActor in
                defer { busy = false }
                do { try await FamiliarProviderConnectionValidator.validate(descriptor: value, modelID: selected, apiKey: key); verified = true }
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

nonisolated extension FamiliarProviderDescriptor {
    var pickerSubtitle: String {
        if oauthKind != nil { return String(localized: "provider.subtitle.login") }
        switch baseURL.host {
        case "openrouter.ai": return String(localized: "provider.subtitle.router")
        case "api.x.ai": return String(localized: "provider.subtitle.xai")
        case "api.moonshot.cn": return String(localized: "provider.subtitle.kimi")
        case "api.deepseek.com": return String(localized: "provider.subtitle.deepseek")
        default:
            switch protocolKind {
            case .anthropic: return String(localized: "provider.subtitle.anthropic")
            case .gemini: return String(localized: "provider.subtitle.gemini")
            case .openAIChat, .openAIResponses: return String(localized: "provider.subtitle.openai")
            }
        }
    }
    var localizedName: String {
        switch displayName {
        case "OpenAI / Compatible API": String(localized: "provider.openai")
        case "Anthropic / Compatible API": String(localized: "provider.anthropic")
        default: displayName
        }
    }
    func instance(id: String, name: String? = nil, url: URL? = nil, models: [FamiliarModelDescriptor]? = nil) -> Self {
        .init(id: id, displayName: name ?? displayName, protocolKind: protocolKind, baseURL: url ?? baseURL,
              chatPath: chatPath, modelsPath: modelsPath, authStyle: authStyle, additionalHeaders: additionalHeaders,
              curatedModels: models ?? curatedModels, openAIChat: openAIChat, isCustom: true, oauthKind: oauthKind)
    }
}
