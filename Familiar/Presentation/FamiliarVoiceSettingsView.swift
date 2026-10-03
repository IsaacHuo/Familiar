import SwiftUI

struct FamiliarVoiceSettingsView: View {
    @AppStorage(FamiliarVoiceStore.inputKey) private var input = ""
    @AppStorage(FamiliarVoiceStore.outputKey) private var output = ""
    @State private var providers = FamiliarVoiceStore.load()
    @State private var editor: FamiliarVoiceConfiguration?
    @State private var errorMessage: String?
    var body: some View {
        List {
            Section {
                Picker(String(localized: "voice.input"), selection: $input) {
                    Text(String(localized: "voice.system")).tag("")
                    ForEach(providers.filter { (try? FamiliarVoiceFactory.make($0).supportsVoiceInput) == true }) { Text(FamiliarVoiceStore.displayName($0.name)).tag($0.id) }
                }
                Picker(String(localized: "voice.output"), selection: $output) {
                    Text(String(localized: "voice.system")).tag("")
                    ForEach(providers.filter { (try? FamiliarVoiceFactory.make($0).supportsVoiceOutput) == true }) { Text(FamiliarVoiceStore.displayName($0.name)).tag($0.id) }
                }
            } footer: { Text(String(localized: "voice.remote.footer")) }
            Section(String(localized: "voice.providers")) {
                ForEach(providers) { value in
                    Button(FamiliarVoiceStore.displayName(value.name)) { editor = value }
                }
                .onDelete { offsets in
                    do {
                        for index in offsets { try FamiliarVoiceStore.remove(providers[index].id) }
                        providers = FamiliarVoiceStore.load()
                    } catch { errorMessage = error.localizedDescription }
                }
                Menu {
                    ForEach(FamiliarVoiceStore.templates, id: \.0) { vendor, name, endpoint in
                        Button(FamiliarVoiceStore.displayName(name)) { editor = .init(vendor: vendor, name: name, baseURL: endpoint) }
                    }
                } label: { Label(String(localized: "voice.add"), systemImage: "plus") }
            }
        }
        .navigationTitle(String(localized: "voice.title"))
        .sheet(item: $editor, onDismiss: { providers = FamiliarVoiceStore.load() }) { value in FamiliarVoiceProviderEditor(value: value) }
        .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
}

struct FamiliarVoiceProviderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var value: FamiliarVoiceConfiguration
    @State private var key = ""
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "provider.name"), text: $value.name)
                TextField(String(localized: "provider.endpoint"), text: $value.baseURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(String(localized: "settings.api_key.replace_placeholder"), text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                if value.vendor == "xunfei" { Text("App ID;API Key;API Secret").font(FamiliarTypography.caption) }
                Section(String(localized: "settings.model")) {
                    TextField(String(localized: "voice.input_model"), text: $value.inputModel)
                    TextField(String(localized: "voice.output_model"), text: $value.outputModel)
                    TextField(String(localized: "voice.voice_id"), text: $value.voice)
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .navigationTitle(String(localized: "voice.providers"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "common.save")) {
                    do {
                        try FamiliarVoiceStore.save(value)
                        if !key.isEmpty { try FamiliarKeychainStore.save(key, for: "voice." + value.id) }
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }.disabled(value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }
}
