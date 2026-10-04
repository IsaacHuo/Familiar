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
    private var audioSessionTransition: Task<Void, Error>?
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
            await finishRemoteRecording()
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
        guard activeSessionID == nil else { return }
        let sessionID = UUID()
        isListening = true
        await stopListening(resetState: false, nextSessionID: sessionID)
        guard activeSessionID == sessionID else { return }
        self.onTranscription = onTranscription
        latestTranscript = ""
        errorMessage = nil

        if let configuration = FamiliarVoiceStore.selected(input: true) {
            await startRemote(configuration, sessionID: sessionID)
            return
        }
        guard let recognizer = makeRecognizer() else {
            await fail(with: .unavailable)
            return
        }

        let authorization = await requestSpeechAuthorization()
        guard activeSessionID == sessionID else { return }
        guard authorization == .authorized else {
            await fail(with: .permission)
            return
        }
        let permissionGranted = await requestMicrophonePermission()
        guard activeSessionID == sessionID else { return }
        guard permissionGranted else {
            await fail(with: .microphone)
            return
        }

        do {
            guard activeSessionID == sessionID else { return }
            try await changeAudioSession(active: true, duckOthers: true)
            guard activeSessionID == sessionID else { return }

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
            guard activeSessionID == sessionID else { return }
            await fail(with: .start)
        }
    }

    private func stopListening(resetState: Bool, nextSessionID: UUID? = nil) async {
        activeSessionID = nextSessionID
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
        try? await changeAudioSession(active: false)
    }

    private func changeAudioSession(active: Bool, duckOthers: Bool = false) async throws {
        let previous = audioSessionTransition
        let session = audioSession
        // Finish each hardware transition before the next one. Cancelling a UI
        // request must not let its late activation overtake the queued stop.
        let transition = Task {
            _ = await previous?.result
            try await Self.changeAudioSession(session, active: active, duckOthers: duckOthers)
        }
        audioSessionTransition = transition
        try await transition.value
    }

    @concurrent
    private static func changeAudioSession(_ session: AVAudioSession, active: Bool, duckOthers: Bool) async throws {
        if active {
            try session.setCategory(.record, mode: .measurement, options: duckOthers ? [.duckOthers] : [])
        }
        if #available(iOS 27.0, *) {
            let succeeded: Bool
            if active {
                succeeded = try await session.activate(options: [])
            } else {
                succeeded = try await session.deactivate(options: [.notifyOthersOnDeactivation])
            }
            guard succeeded else { throw FamiliarSpeechError.start }
        } else {
            try session.setActive(active, options: active ? [] : [.notifyOthersOnDeactivation])
        }
    }

    private func startRemote(_ configuration: FamiliarVoiceConfiguration, sessionID: UUID) async {
        let permissionGranted = await requestMicrophonePermission()
        guard activeSessionID == sessionID else { return }
        guard permissionGranted else { await fail(with: .microphone); return }
        do {
            let provider = try FamiliarVoiceFactory.make(configuration)
            guard provider.supportsVoiceInput else { throw FamiliarVoiceProviderError.unsupported(configuration.name) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech-" + UUID().uuidString + ".wav")
            try await changeAudioSession(active: true)
            guard activeSessionID == sessionID else { return }
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            guard recorder.record() else { throw FamiliarSpeechError.start }
            remoteURL = url; remoteRecorder = recorder; remoteConfiguration = configuration
            isListening = true
        } catch {
            guard activeSessionID == sessionID else { return }
            errorMessage = error.localizedDescription
            await stopListening(resetState: true)
        }
    }

    private func finishRemoteRecording() async {
        guard let url = remoteURL, let config = remoteConfiguration, let sessionID = activeSessionID else { return }
        remoteRecorder?.stop(); remoteRecorder = nil
        try? await changeAudioSession(active: false)
        guard activeSessionID == sessionID else { return }
        remoteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: url)
                if self.activeSessionID == sessionID {
                    self.activeSessionID = nil
                    self.onTranscription = nil
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
