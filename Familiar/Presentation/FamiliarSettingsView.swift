import SwiftUI

struct FamiliarSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let initialSettings: FamiliarSettings
    let onSaveSettings: (FamiliarSettings) -> Void

    @State private var settings: FamiliarSettings
    @State private var apiKey = ""
    @State private var hasAPIKey = FamiliarKeychainStore.isConfigured
    @State private var errorMessage: String?

    init(
        initialSettings: FamiliarSettings,
        onSaveSettings: @escaping (FamiliarSettings) -> Void
    ) {
        self.initialSettings = initialSettings
        self.onSaveSettings = onSaveSettings
        _settings = State(initialValue: initialSettings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(hasAPIKey ? "已配置；输入新值可替换" : "sk-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        Label(hasAPIKey ? "已保存在此设备" : "尚未配置", systemImage: hasAPIKey ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(hasAPIKey ? .green : .orange)
                        Spacer()
                        if hasAPIKey {
                            Button("清除", role: .destructive) { clearAPIKey() }
                        }
                    }
                } header: {
                    Text("DeepSeek API Key")
                } footer: {
                    Text("API Key 只保存在当前设备的 Keychain。聊天请求从设备直接发送到 DeepSeek；Familiar 没有账号和后端数据库。")
                }

                Section("模型") {
                    Picker("回答模型", selection: $settings.model) {
                        ForEach(FamiliarModel.allCases) { model in
                            VStack(alignment: .leading) {
                                Text(model.title)
                                Text(model.detail)
                            }
                            .tag(model)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    TextEditor(text: $settings.systemPrompt)
                        .frame(minHeight: 120)
                } header: {
                    Text("回答偏好")
                } footer: {
                    Text("系统提示最多使用前 3,000 个字符，仅影响后续问题。")
                }

                Section("数据边界") {
                    Label("无登录、无账号", systemImage: "person.crop.circle.badge.xmark")
                    Label("不读取教务或其他 App 数据", systemImage: "hand.raised")
                    Label("会话历史仅保存在本机", systemImage: "internaldrive")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .alert("设置失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func save() {
        do {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                try FamiliarKeychainStore.save(trimmedKey)
                hasAPIKey = true
            }
            onSaveSettings(settings)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAPIKey() {
        do {
            try FamiliarKeychainStore.delete()
            apiKey = ""
            hasAPIKey = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
