import SwiftUI
import QuickLook
import AVFoundation
import Observation

@MainActor @Observable
final class FamiliarReplySpeechPlayer: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var audioPlayer: AVAudioPlayer?
    private var speechTask: Task<Void, Never>?
    private var playbackID = UUID()
    var errorMessage: String?
    var isSpeaking = false
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard self?.currentUtterance.map(ObjectIdentifier.init) == identity else { return }
            self?.isSpeaking = false
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard self?.currentUtterance.map(ObjectIdentifier.init) == identity else { return }
            self?.isSpeaking = false
        }
    }
    func speak(_ text: String) {
        stop()
        let text = FamiliarVoiceTextSanitizer.sanitize(text)
        guard !text.isEmpty else { return }
        if let configuration = FamiliarVoiceStore.selected(input: false) {
            let id = playbackID
            isSpeaking = true
            speechTask = Task { @MainActor [weak self] in
                do {
                    let provider = try FamiliarVoiceFactory.make(configuration)
                    let data = try await provider.synthesize(.init(input: text, model: configuration.outputModel.isEmpty ? nil : configuration.outputModel, voice: configuration.voice.isEmpty ? nil : configuration.voice))
                    try Task.checkCancellation()
                    guard let self, self.playbackID == id else { return }
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                    try AVAudioSession.sharedInstance().setActive(true)
                    let player = try AVAudioPlayer(data: data)
                    player.delegate = self
                    self.audioPlayer = player
                    guard player.play() else { throw FamiliarVoiceProviderError.noAudioData }
                } catch is CancellationError { }
                catch { if let self, self.playbackID == id { self.errorMessage = error.localizedDescription; self.isSpeaking = false } }
            }
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
        currentUtterance = utterance
        synthesizer.speak(utterance)
        isSpeaking = true
    }
    func stop() {
        playbackID = UUID()
        currentUtterance = nil
        speechTask?.cancel(); speechTask = nil
        audioPlayer?.stop(); audioPlayer = nil
        synthesizer.stopSpeaking(at: .immediate); isSpeaking = false
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard self?.audioPlayer.map(ObjectIdentifier.init) == identity else { return }
            self?.isSpeaking = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
