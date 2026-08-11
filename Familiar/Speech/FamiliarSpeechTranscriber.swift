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
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onTranscription: ((String) -> Void)?
    private var activationID: UUID?
    private var recognitionID: UUID?
    private var hasInputTap = false

    public func toggle(onTranscription: @escaping (String) -> Void) {
        if isListening {
            stop()
        } else {
            start(onTranscription: onTranscription)
        }
    }

    public func stop() {
        activationID = nil
        guard isListening || recognitionTask != nil || recognitionRequest != nil else {
            onTranscription = nil
            return
        }
        finishListening()
    }

    isolated deinit {
        audioEngine.stop()
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    private func start(onTranscription: @escaping (String) -> Void) {
        stop()
        self.onTranscription = onTranscription
        latestTranscript = ""
        errorMessage = nil
        let activationID = UUID()
        self.activationID = activationID

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self, self.activationID == activationID else { return }
                guard status == .authorized else {
                    self.fail(with: .permission)
                    return
                }

                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    Task { @MainActor [weak self] in
                        guard let self, self.activationID == activationID else { return }
                        guard granted else {
                            self.fail(with: .microphone)
                            return
                        }
                        self.beginRecognition(activationID: activationID)
                    }
                }
            }
        }
    }

    private func beginRecognition(activationID: UUID) {
        guard self.activationID == activationID else { return }
        let locale = Locale.current
        speechRecognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            fail(with: .unavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                throw FamiliarSpeechError.start
            }

            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            hasInputTap = true
            let recognitionID = UUID()
            self.recognitionID = recognitionID

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                guard self?.recognitionID == recognitionID else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if let result {
                        let transcript = result.bestTranscription.formattedString
                        self.latestTranscript = transcript
                        self.onTranscription?(transcript)

                        if result.isFinal {
                            self.finishListening()
                            return
                        }
                    }

                    if error != nil {
                        self.fail(with: .start)
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            fail(with: .start)
        }
    }

    private func finishListening() {
        activationID = nil
        recognitionID = nil
        audioEngine.stop()
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        onTranscription = nil

        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(with error: FamiliarSpeechError) {
        errorMessage = error.localizedDescription
        finishListening()
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
