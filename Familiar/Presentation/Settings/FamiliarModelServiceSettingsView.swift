import SwiftUI
import UniformTypeIdentifiers

struct FamiliarModelServiceSettingsView: View {
    let initialSettings: FamiliarSettings
    let onSaveSettings: (FamiliarSettings) -> Void
    @State private var providers = FamiliarProviderCatalog.instances
    @State private var destination: EditorDestination?
    @State private var importing = false
    @State private var errorMessage: String?

    private enum EditorDestination: Identifiable {
        case chooser
        case provider(FamiliarProviderDescriptor)
        var id: String {
            switch self {
            case .chooser: "chooser"
            case .provider(let value): value.id
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
                            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                                Text(provider.displayName).foregroundStyle(.primary)
                                Text(provider.baseURL.host ?? "").font(FamiliarTypography.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if initialSettings.providerID == provider.id { Image(systemName: "checkmark") }
                            Image(systemName: "chevron.right").font(FamiliarTypography.caption).foregroundStyle(.tertiary)
                        }.frame(minHeight: 44)
                    }
                }
                Button { destination = .chooser } label: { Text(String(localized: "provider.add")) }
                Button { importing = true } label: { Text(String(localized: "provider.import")) }
            }
        }
        .navigationTitle(String(localized: "settings.hub.model_service"))
        .sheet(item: $destination, onDismiss: reload) { item in
            switch item {
            case .chooser: chooser
            case .provider(let provider):
                FamiliarProviderEditor(provider: provider, isCurrent: initialSettings.providerID == provider.id, selectedModelID: initialSettings.providerID == provider.id ? initialSettings.modelID : nil) { descriptor, modelID in
                    var value = initialSettings
                    value.providerID = descriptor.id; value.modelID = modelID
                    onSaveSettings(value)
                }
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
                            HStack(spacing: FamiliarSpacing.medium) {
                                FamiliarProviderIcon(provider: template)
                                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                                    Text(template.localizedName).font(FamiliarTypography.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(template.pickerSubtitle).font(FamiliarTypography.secondary).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(FamiliarTypography.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, FamiliarSpacing.small)
                        }
                    }
                } header: { Text(String(localized: "provider.choose")) }
                footer: { Text(String(localized: "provider.instances.footer")) }
            }
            .navigationTitle(String(localized: "provider.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { destination = nil } } }
        }
    }
    private func reload() { providers = FamiliarProviderCatalog.instances }
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
