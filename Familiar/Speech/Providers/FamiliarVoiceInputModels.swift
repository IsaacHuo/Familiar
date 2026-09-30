// Adapted from OpenMinis VoiceInputModels.swift at 4ef29002e88db1e20e462ec2ff46916e8a7dcb45.
// GPL-3.0; see Resources/ThirdParty/OpenMinis/LICENSE.
// Familiar changes: namespaced types, native model descriptor, ephemeral sessions, no payload logging.
import Foundation

// MARK: - Request / Response models
//
// Shared value types for the voice subsystem. `VoiceInput*` covers speech
// recognition (ASR); `VoiceOutput*` covers speech synthesis (TTS).

/// A speech-recognition (ASR) request: audio in, text out.
nonisolated struct FamiliarVoiceInputRequest: Sendable {
    /// 16 kHz mono WAV produced by the VAD (or any provider-acceptable audio).
    let audioData: Data
    let model: String?
    /// nil = let the provider auto-detect the spoken language.
    let language: String?
    let responseFormat: FamiliarVoiceInputFormat
    /// Optional biasing prompt to improve recognition of domain terms.
    let prompt: String?
    /// The resolved FamiliarModelDescriptor — allows the provider to detect whether this model
    /// uses dedicated ASR (Whisper API) or chat-based ASR (chat completions with
    /// audio input + constrained system prompt).
    let resolvedModel: FamiliarModelDescriptor?
    /// System (Apple) ASR only: force on-device (`true`) vs server/cloud (`false`).
    /// nil = provider default (prefer on-device when supported). Ignored by cloud
    /// ASR providers.
    let onDeviceRecognition: Bool?

    init(audioData: Data,
         model: String? = nil,
         language: String? = nil,
         responseFormat: FamiliarVoiceInputFormat = .json,
         prompt: String? = nil,
         resolvedModel: FamiliarModelDescriptor? = nil,
         onDeviceRecognition: Bool? = nil) {
        self.audioData = audioData
        self.model = model
        self.language = language
        self.responseFormat = responseFormat
        self.prompt = prompt
        self.resolvedModel = resolvedModel
        self.onDeviceRecognition = onDeviceRecognition
    }
}

nonisolated enum FamiliarVoiceInputFormat: String, Sendable {
    case json, text, srt, vtt
}

nonisolated struct FamiliarVoiceInputResponse: Sendable {
    let text: String
    let language: String?
    let duration: Double?
}

/// A speech-synthesis (TTS) request: text in, audio out.
nonisolated struct FamiliarVoiceOutputRequest: Sendable {
    let input: String
    let model: String?
    let voice: String?
    /// 0.25 ~ 4.0, nil = 1.0 (provider default).
    let speed: Float?
    let responseFormat: FamiliarVoiceOutputFormat

    init(input: String,
         model: String? = nil,
         voice: String? = nil,
         speed: Float? = nil,
         responseFormat: FamiliarVoiceOutputFormat = .mp3) {
        self.input = input
        self.model = model
        self.voice = voice
        self.speed = speed
        self.responseFormat = responseFormat
    }
}

nonisolated enum FamiliarVoiceOutputFormat: String, Sendable {
    case mp3, opus, wav, aac
}

// MARK: - Capability protocols

@MainActor protocol FamiliarVoiceInputCapable {
    func transcribe(_ request: FamiliarVoiceInputRequest) async throws -> FamiliarVoiceInputResponse
    var supportsVoiceInput: Bool { get }
}

@MainActor protocol FamiliarVoiceOutputCapable {
    func synthesize(_ request: FamiliarVoiceOutputRequest) async throws -> Data
    var supportsVoiceOutput: Bool { get }
}

/// A voice provider that can do both directions (ASR + TTS). The factory returns
/// this so the built-in `SystemVoiceProvider` (not a `FamiliarVoiceProvider` subclass) and
/// the cloud `FamiliarVoiceProvider` subclasses share one factory entry point.
typealias FamiliarVoiceProviderCapable = FamiliarVoiceInputCapable & FamiliarVoiceOutputCapable

// MARK: - Errors

nonisolated enum FamiliarVoiceProviderError: LocalizedError {
    case unsupported(String)
    case httpError(Int, Data?)
    case parseError(String)
    case authError
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .unsupported: return String(localized: "voice.error.unsupported")
        case .httpError(let code, let data): return String(format: String(localized: "voice.error.http"), code, data.map(FamiliarProviderHTTP.errorMessage(from:)) ?? "")
        case .parseError: return String(localized: "voice.error.response")
        case .authError: return String(localized: "voice.error.auth")
        case .noAudioData: return String(localized: "voice.error.empty")
        }
    }

    /// Best-effort extraction of an API error message from a JSON/text body.
    private static func serverMessage(from body: Data?) -> String? {
        guard let body, !body.isEmpty else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
            if let msg = obj["error"] as? String { return msg }
            if let msg = obj["message"] as? String { return msg }
        }
        if let text = String(data: body, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.count < 200 { return trimmed }
        }
        return nil
    }
}
