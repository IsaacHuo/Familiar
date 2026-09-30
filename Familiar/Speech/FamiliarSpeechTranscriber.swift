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
    private var remoteRecorder: AVAudioRecorder?
    private var remoteConfiguration: FamiliarVoiceConfiguration?
    private var remoteTask: Task<Void, Never>?
    private var remoteURL: URL?

    public func toggle(onTranscription: @escaping (String) -> Void) async {
        if remoteRecorder != nil {
            finishRemoteRecording()
        } else if isListening {
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

        if let configuration = FamiliarVoiceStore.selected(input: true) {
            await startRemote(configuration, sessionID: sessionID)
            return
        }
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
        remoteTask?.cancel(); remoteTask = nil
        remoteRecorder?.stop(); remoteRecorder = nil
        if let remoteURL { try? FileManager.default.removeItem(at: remoteURL) }
        remoteURL = nil; remoteConfiguration = nil
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

    private func startRemote(_ configuration: FamiliarVoiceConfiguration, sessionID: UUID) async {
        let permissionGranted = await requestMicrophonePermission()
        guard activeSessionID == sessionID else { return }
        guard permissionGranted else { await fail(with: .microphone); return }
        do {
            let provider = try FamiliarVoiceFactory.make(configuration)
            guard provider.supportsVoiceInput else { throw FamiliarVoiceProviderError.unsupported(configuration.name) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech-" + UUID().uuidString + ".wav")
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            guard recorder.record() else { throw FamiliarSpeechError.start }
            remoteURL = url; remoteRecorder = recorder; remoteConfiguration = configuration
            isListening = true
        } catch { errorMessage = error.localizedDescription; await stopListening(resetState: true) }
    }

    private func finishRemoteRecording() {
        guard let url = remoteURL, let config = remoteConfiguration, let sessionID = activeSessionID else { return }
        remoteRecorder?.stop(); remoteRecorder = nil
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        remoteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: url)
                if self.activeSessionID == sessionID {
                    self.remoteURL = nil; self.remoteConfiguration = nil; self.isListening = false; self.remoteTask = nil
                }
            }
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= 25_000_000 else { throw FamiliarVoiceProviderError.unsupported("Audio too large") }
                let provider = try FamiliarVoiceFactory.make(config)
                let model = config.inputModel.isEmpty ? nil : config.inputModel
                let result = try await provider.transcribe(.init(audioData: data, model: model, language: Locale.current.identifier, resolvedModel: model.map { FamiliarModelDescriptor(id: $0) }))
                try Task.checkCancellation()
                guard self.activeSessionID == sessionID else { return }
                self.latestTranscript = result.text
                self.onTranscription?(result.text)
            } catch is CancellationError { }
            catch { if self.activeSessionID == sessionID { self.errorMessage = error.localizedDescription } }
        }
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
        remoteTask?.cancel()
        remoteRecorder?.stop()
        if let remoteURL { try? FileManager.default.removeItem(at: remoteURL) }
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
