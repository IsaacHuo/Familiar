import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
public final class FamiliarSpeechTranscriber: ObservableObject {
    @Published public private(set) var isListening = false
    @Published public private(set) var latestTranscript = ""
    @Published public var errorMessage: String?

    public init() {}

    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onTranscription: ((String) -> Void)?
    private var activeSessionID: UUID?

    public func toggle(onTranscription: @escaping (String) -> Void) async {
        if isListening {
            await stop()
        } else {
            await start(onTranscription: onTranscription)
        }
    }

    public func stop() async {
        await stopListening(resetState: true)
    }

    private func start(onTranscription: @escaping (String) -> Void) async {
        await stopListening(resetState: false)
        self.onTranscription = onTranscription
        latestTranscript = ""
        errorMessage = nil
        let sessionID = UUID()
        activeSessionID = sessionID

        guard let recognizer = makeRecognizer() else {
            await fail(with: .unavailable)
            return
        }

        guard await requestSpeechAuthorization() == .authorized else {
            await fail(with: .permission)
            return
        }
        guard await requestMicrophonePermission() else {
            await fail(with: .microphone)
            return
        }

        do {
            guard activeSessionID == sessionID else { return }
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            guard activeSessionID == sessionID else {
                await stopListening(resetState: false)
                return
            }

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.activeSessionID == sessionID else { return }

                    if let result {
                        let transcript = result.bestTranscription.formattedString
                        self.latestTranscript = transcript
                        self.onTranscription?(transcript)

                        if result.isFinal {
                            await self.stopListening(resetState: true)
                        }
                    } else if error != nil {
                        await self.fail(with: .start)
                    }
                }
            }
            isListening = true
        } catch {
            await fail(with: .start)
        }
    }

    private func stopListening(resetState: Bool) async {
        activeSessionID = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if resetState {
            isListening = false
            onTranscription = nil
        }
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(with error: FamiliarSpeechError) async {
        errorMessage = error.localizedDescription
        await stopListening(resetState: true)
    }

    private func makeRecognizer() -> SFSpeechRecognizer? {
        let locales = [Locale.current, Locale(identifier: "zh-CN"), Locale(identifier: "en-US")]
        for locale in locales {
            if let recognizer = SFSpeechRecognizer(locale: locale),
               recognizer.isAvailable,
               recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        return nil
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    isolated deinit {
        if audioEngine.isRunning { audioEngine.stop() }
        task?.cancel()
    }
}

enum FamiliarSpeechError: LocalizedError {
    case unavailable
    case permission
    case microphone
    case start

    var errorDescription: String? {
        switch self {
        case .unavailable:
            NSLocalizedString("speech.error.unavailable", comment: "Speech recognition is unavailable")
        case .permission:
            NSLocalizedString("speech.error.permission", comment: "Speech recognition permission was denied")
        case .microphone:
            NSLocalizedString("speech.error.microphone", comment: "Microphone permission was denied")
        case .start:
            NSLocalizedString("speech.error.start", comment: "Speech recognition could not be started")
        }
    }
}
