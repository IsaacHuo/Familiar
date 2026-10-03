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

struct FamiliarChatFilesView: View {
    @Environment(\.dismiss) private var dismiss
    let store: FamiliarWorkspaceStore
    let workspaceIDs: [FamiliarWorkspaceID]
    let attachments: [FamiliarAttachmentSnapshot]
    @State private var files: [File] = []
    @State private var preview: URL?
    @State private var errorMessage: String?
    @State private var query = ""
    @State private var temporaryDirectory: URL?

    private struct File: Identifiable {
        let id: String
        let name: String
        let byteSize: Int64
        let workspace: FamiliarWorkspaceID?
        let relativePath: String
    }

    var body: some View {
        NavigationStack {
            List(files.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { file in
                Button { open(file) } label: {
                    HStack(spacing: FamiliarSpacing.medium) {
                        Image(systemName: "doc").frame(width: 24)
                        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                            Text(file.name).foregroundStyle(.primary)
                            Text(ByteCountFormatter.string(fromByteCount: file.byteSize, countStyle: .file)).font(FamiliarTypography.caption).foregroundStyle(.secondary)
                        }
                    }.frame(minHeight: 44)
                }
            }
            .overlay { if files.isEmpty { ContentUnavailableView(String(localized: "resource.empty"), systemImage: "folder") } }
            .searchable(text: $query)
            .navigationTitle(String(localized: "chat.files"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "common.done")) { dismiss() } } }
            .quickLookPreview($preview)
            .task { load() }
            .onDisappear {
                if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
            }
            .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }
    private func load() {
        do {
            files = try workspaceIDs.flatMap { workspace in
                try store.entries(in: workspace).map { entry in
                    File(id: workspace.directoryName + "/" + entry.relativePath, name: entry.relativePath, byteSize: entry.byteSize, workspace: workspace, relativePath: entry.relativePath)
                }
            }
            var seen = Set<String>()
            files += attachments.filter { seen.insert($0.relativePath).inserted }.map {
                File(id: $0.relativePath, name: $0.filename, byteSize: $0.byteSize, workspace: nil, relativePath: $0.relativePath)
            }
        } catch { errorMessage = error.localizedDescription }
    }
    private func open(_ file: File) {
        do {
            if let workspace = file.workspace {
                let data = try store.read(relativePath: file.relativePath, in: workspace)
                let directory: URL
                if let temporaryDirectory { directory = temporaryDirectory }
                else {
                    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    temporaryDirectory = directory
                }
                let url = directory.appendingPathComponent(URL(fileURLWithPath: file.name).lastPathComponent)
                try data.write(to: url, options: .atomic)
                preview = url
            } else { preview = FamiliarAttachmentStore.url(for: file.relativePath) }
        } catch { errorMessage = error.localizedDescription }
    }
}
