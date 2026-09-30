import Foundation

nonisolated struct FamiliarVoiceConfiguration: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var vendor: String
    var name: String
    var baseURL: String
    var inputModel: String = ""
    var outputModel: String = ""
    var voice: String = ""
}

nonisolated enum FamiliarVoiceStore {
    static let inputKey = "familiar.voice.input.v1"
    static let outputKey = "familiar.voice.output.v1"
    private static let key = "familiar.voice.providers.v1"
    static func load() -> [FamiliarVoiceConfiguration] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FamiliarVoiceConfiguration].self, from: data)) ?? []
    }
    @MainActor static func save(_ value: FamiliarVoiceConfiguration) throws {
        guard let url = URL(string: value.baseURL), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw FamiliarVoiceProviderError.parseError("Invalid endpoint") }
        var values = load().filter { $0.id != value.id }; values.append(value)
        UserDefaults.standard.set(try JSONEncoder().encode(values), forKey: key)
    }
    @MainActor static func remove(_ id: String) throws {
        try FamiliarKeychainStore.delete(for: "voice." + id)
        UserDefaults.standard.set(try JSONEncoder().encode(load().filter { $0.id != id }), forKey: key)
        for key in [inputKey, outputKey] where UserDefaults.standard.string(forKey: key) == id { UserDefaults.standard.removeObject(forKey: key) }
    }
    static func selected(input: Bool) -> FamiliarVoiceConfiguration? {
        let id = UserDefaults.standard.string(forKey: input ? inputKey : outputKey)
        return load().first { $0.id == id }
    }
    // Vendor endpoints match OpenMinis VoiceProviderTemplate at 4ef2900.
    static let templates: [(String, String, String)] = [
        ("elevenlabs", "ElevenLabs", "https://api.elevenlabs.io"),
        ("deepgram", "Deepgram", "https://api.deepgram.com"),
        ("azure", "Azure TTS", "https://eastasia.tts.speech.microsoft.com"),
        ("minimax", "MiniMax", "https://api.minimax.io"),
        ("alibaba", "Alibaba Bailian", "https://dashscope.aliyuncs.com/compatible-mode"),
        ("doubao", "Doubao", "https://openspeech.bytedance.com"),
        ("xunfei", "iFlytek", "https://iat-api.xfyun.cn"),
        ("mimo", "MiMo", "https://api.xiaomimimo.com"),
        ("openai", "OpenAI", "https://api.openai.com"),
        ("gemini", "Google Gemini", "https://generativelanguage.googleapis.com"),
        ("openrouter", "OpenRouter", "https://openrouter.ai/api")
    ]
    static func displayName(_ name: String) -> String {
        switch name {
        case "Alibaba Bailian": String(localized: "voice.alibaba")
        case "Doubao": String(localized: "voice.doubao")
        case "iFlytek": String(localized: "voice.xunfei")
        default: name
        }
    }
}

@MainActor enum FamiliarVoiceFactory {
    static func make(_ config: FamiliarVoiceConfiguration) throws -> FamiliarVoiceProvider {
        let key = FamiliarKeychainStore.load(for: "voice." + config.id)
        switch config.vendor {
        case "elevenlabs": return FamiliarElevenLabsVoiceProvider(providerId: config.id, baseURL: config.baseURL, apiKey: key)
        case "deepgram": return FamiliarDeepgramVoiceProvider(providerId: config.id, baseURL: config.baseURL, apiKey: key)
        case "azure": return FamiliarAzureTTSVoiceProvider(providerId: config.id, baseURL: config.baseURL, apiKey: key)
        case "minimax": return FamiliarMiniMaxVoiceProvider(providerId: config.id, baseURL: config.baseURL, apiKey: key)
        case "alibaba": return FamiliarAlibabaVoiceProvider(providerId: config.id, baseURL: config.baseURL, apiKey: key)
        case "doubao": return FamiliarDoubaoVoiceProvider(providerId: config.id, apiKey: key)
        case "xunfei":
            let parts = (key ?? "").split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { throw FamiliarVoiceProviderError.authError }
            return FamiliarXunfeiVoiceProvider(providerId: config.id, appId: parts[0], apiKey: parts[1], apiSecret: parts[2])
        case "mimo": return FamiliarMimoVoiceProvider(providerId: config.id, baseURL: config.baseURL, apiKey: key)
        case "gemini": return FamiliarGeminiVoiceProvider(providerId: config.id, baseURL: config.baseURL, apiKey: key)
        case "openrouter": return FamiliarOpenRouterVoiceProvider(providerId: config.id, baseURL: config.baseURL, apiKey: key)
        default: return FamiliarVoiceProvider(providerId: config.id, baseURL: config.baseURL, apiKey: key)
        }
    }
}
