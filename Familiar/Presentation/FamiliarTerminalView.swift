#if os(iOS)
import SwiftUI
import SwiftData
import WebKit

@MainActor @Observable
final class FamiliarTerminalController {
    let projectID: UUID
    let workspaceStore: FamiliarWorkspaceStore
    private let bridge = FamiliarRealISHBridge()
    private var task: Task<Void, Never>?
    private var inputTask: Task<Void, Never>?
    private var taskID: UUID?
    private(set) var generation = UUID()
    private(set) var active = false
    private(set) var status = String(localized: "terminal.idle", defaultValue: "Not started")
    private(set) var chunks: [Data] = []
    private(set) var outputBytes = 0
    private(set) var outputText = ""
    private var outputTail = Data()
    var networkEnabled = false
    var columns = 80
    var rows = 24

    init(projectID: UUID, workspaceStore: FamiliarWorkspaceStore) {
        self.projectID = projectID; self.workspaceStore = workspaceStore
    }

    func start(files: [FamiliarFileSnapshot]) {
        guard !active else { return }
        let id = UUID(), token = UUID()
        generation = token; taskID = id; active = true
        chunks = []; outputBytes = 0; outputText = ""; outputTail = Data()
        status = String(localized: "terminal.preparing", defaultValue: "Preparing Linux…")
        let store = workspaceStore, scope = FamiliarWorkspaceID.project(projectID)
        let network: FamiliarShellNetworkPolicy = networkEnabled ? .publicInternet : .disabled
        task = Task {
            var view: FamiliarWorkspaceTaskView?
            var watchdog: Task<Void, Never>?
            defer {
                watchdog?.cancel()
                if generation == token { active = false; taskID = nil }
            }
            do {
                let prepared = try await Task.detached {
                    try store.prepareShellTaskView(taskID: id, workspaceID: scope, resources: [], files: files, attachments: [])
                }.value
                view = prepared
                try Task.checkCancellation()
                let paths = try store.prepare(scope)
                let home = paths.work.appendingPathComponent("TerminalHome", isDirectory: true)
                let temporary = prepared.work.appendingPathComponent("Tmp", isDirectory: true)
                // Reject a user-created link before mounting a host directory.
                try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                guard (try home.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
                      home.resolvingSymlinksInPath().path.hasPrefix(paths.root.resolvingSymlinksInPath().path + "/") else {
                    throw FamiliarWorkspaceError.symbolicLinkNotAllowed
                }
                let mounts: [FamiliarISHMount] = [
                    .init(hostURL: prepared.files, guestPath: "/workspace/files", writable: false),
                    .init(hostURL: prepared.outputs, guestPath: "/workspace/outputs", writable: true),
                    .init(hostURL: prepared.work, guestPath: "/workspace/work", writable: true),
                    .init(hostURL: prepared.environment, guestPath: "/workspace/env", writable: true),
                    .init(hostURL: home, guestPath: "/root", writable: true),
                    .init(hostURL: temporary, guestPath: "/tmp", writable: true)
                ]
                watchdog = Task {
                    let deadline = ContinuousClock.now.advanced(by: .seconds(180))
                    do {
                        while !Task.isCancelled {
                            try await Task.sleep(for: .seconds(1))
                            let usage = try await Task.detached { try store.shellWritableUsage(for: prepared) }.value
                            let total = try await Task.detached { try store.workspaceSize(scope) }.value
                            if ContinuousClock.now >= deadline || total + usage.totalBytes > store.quotaBytes || usage.largestFileBytes > 128 * 1_024 * 1_024 {
                                status = String(localized: "terminal.limit", defaultValue: "Stopped: session time or storage limit reached")
                                await bridge.closeTerminal(taskID: id)
                                break
                            }
                        }
                    } catch {
                        if !Task.isCancelled { status = error.localizedDescription; await bridge.closeTerminal(taskID: id) }
                    }
                }
                for try await event in bridge.openTerminal(taskID: id, workspaceID: scope, mounts: mounts,
                    command: "exec /bin/sh -i", networkPolicy: network, columns: columns, rows: rows) {
                    guard generation == token else { break }
                    switch event {
                    case .started: status = String(localized: "terminal.running", defaultValue: "Running")
                    case .output(let bytes):
                        guard outputBytes + bytes.count <= 1_024 * 1_024 else {
                            status = String(localized: "terminal.output_limit", defaultValue: "Stopped: output limit reached")
                            await bridge.closeTerminal(taskID: id); continue
                        }
                        chunks.append(bytes); outputBytes += bytes.count
                        outputTail.append(bytes)
                        outputTail = Data(outputTail.suffix(8192))
                        outputText = String(decoding: outputTail, as: UTF8.self)
                    case .exited(let code): status = String(format: String(localized: "terminal.exited", defaultValue: "Exited (%d)"), code)
                    case .cancelled:
                        if status == String(localized: "terminal.running", defaultValue: "Running") {
                            status = String(localized: "terminal.stopped", defaultValue: "Stopped")
                        }
                    case .failed(let detail): status = detail
                    }
                }
                // Retain failed cleanup evidence; never remove a still-mounted task view.
                if await bridge.isIdle(), let view { try store.removeShellTaskView(view) }
            } catch {
                await bridge.closeTerminal(taskID: id)
                status = error is CancellationError ? String(localized: "terminal.stopped", defaultValue: "Stopped") : error.localizedDescription
                if await bridge.isIdle(), let view { try? store.removeShellTaskView(view) }
            }
        }
    }

    func send(_ data: Data) {
        guard active, let id = taskID else { return }
        let previous = inputTask
        inputTask = Task {
            await previous?.value
            guard !Task.isCancelled, taskID == id else { return }
            do { try await bridge.sendTerminalInput(taskID: id, data: data) }
            catch { status = error.localizedDescription }
        }
    }
    func resize(columns: Int, rows: Int) {
        self.columns = min(500, max(2, columns)); self.rows = min(300, max(2, rows))
        guard active, let id = taskID else { return }
        Task { try? await bridge.resizeTerminal(taskID: id, columns: self.columns, rows: self.rows) }
    }
    func stop() {
        inputTask?.cancel()
        task?.cancel()
        if let id = taskID { Task { await bridge.closeTerminal(taskID: id) } }
    }
}

struct FamiliarTerminalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: FamiliarTerminalController
    @State private var command = ""
    let projectID: UUID
    init(projectID: UUID, workspaceStore: FamiliarWorkspaceStore) {
        self.projectID = projectID
        _controller = State(initialValue: FamiliarTerminalController(projectID: projectID, workspaceStore: workspaceStore))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack {
                    Text(controller.status).font(.caption).accessibilityIdentifier("terminal.status")
                    Spacer()
                    Button(controller.active ? String(localized: "terminal.stop", defaultValue: "Stop") : String(localized: "terminal.start", defaultValue: "Start")) {
                        if controller.active { controller.stop() }
                        else {
                            do { controller.start(files: try FamiliarFileCatalogService().snapshots(projectID: projectID, in: context)) }
                            catch { controller.statusForFailure(error) }
                        }
                    }.accessibilityIdentifier("terminal.startStop")
                }.padding(.horizontal)
                if !controller.active {
                    Toggle(String(localized: "terminal.network", defaultValue: "Allow network for this session"), isOn: $controller.networkEnabled).padding(.horizontal)
                    Text(String(localized: "terminal.scope", defaultValue: "Current Project only · 3 minute foreground session · 512 MB memory · 16 processes. HOME is saved in this Project; temporary files are cleared. Commands can change Project files and have no automatic Undo."))
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }
                FamiliarTerminalWebView(controller: controller).accessibilityIdentifier("terminal.screen")
                Text(controller.outputText.split(separator: "\n").last.map(String.init) ?? "")
                    .font(.caption2.monospaced()).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                    .accessibilityIdentifier("terminal.output").accessibilityValue(controller.outputText)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach([("Esc", "\u{1b}"), ("Tab", "\t"), ("↑", "\u{1b}[A"), ("↓", "\u{1b}[B"), ("←", "\u{1b}[D"), ("→", "\u{1b}[C"), ("Ctrl-C", "\u{3}"), ("Ctrl-D", "\u{4}")], id: \.0) { label, value in
                            Button(label) { controller.send(Data(value.utf8)) }.buttonStyle(.bordered)
                        }
                    }.padding(.horizontal)
                }.disabled(!controller.active)
                HStack {
                    TextField(String(localized: "terminal.command", defaultValue: "Shell command"), text: $command)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().onSubmit(sendCommand)
                        .accessibilityIdentifier("terminal.command")
                    Button(String(localized: "terminal.send", defaultValue: "Send"), action: sendCommand)
                        .disabled(command.isEmpty || !controller.active).accessibilityIdentifier("terminal.send")
                }.padding(.horizontal).padding(.bottom, 8)
            }
            .navigationTitle(String(localized: "terminal.title", defaultValue: "Terminal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "common.done", defaultValue: "Done")) { controller.stop(); dismiss() } } }
            .onDisappear { controller.stop() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { controller.stop() } }
        }
    }
    private func sendCommand() {
        guard !command.isEmpty else { return }
        controller.send(Data((command + "\n").utf8)); command = ""
    }
}

private extension FamiliarTerminalController {
    func statusForFailure(_ error: Error) { status = error.localizedDescription }
}

private struct FamiliarTerminalWebView: UIViewRepresentable {
    let controller: FamiliarTerminalController
    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "terminal")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false; web.scrollView.isScrollEnabled = false
        context.coordinator.web = web
        if let directory = Bundle.main.url(forResource: "FamiliarTerminalRenderer", withExtension: nil),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent("terminal.html").path) {
            web.loadFileURL(directory.appendingPathComponent("terminal.html"), allowingReadAccessTo: directory)
        } else { controller.statusForFailure(FamiliarShellExecutorError.unavailable) }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) { context.coordinator.flush() }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "terminal")
        web.navigationDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let controller: FamiliarTerminalController
        weak var web: WKWebView?
        var ready = false
        var cursor = 0
        var generation: UUID?
        init(controller: FamiliarTerminalController) { self.controller = controller }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
                  let payload = message.body as? [String: Any], let kind = payload["kind"] as? String else { return }
            switch kind {
            case "ready": ready = true; flush()
            case "input":
                if let encoded = payload["value"] as? String, encoded.count <= 90_000, let bytes = Data(base64Encoded: encoded) { controller.send(bytes) }
            case "resize":
                if let size = payload["value"] as? [String: Int], let cols = size["cols"], let rows = size["rows"] { controller.resize(columns: cols, rows: rows) }
            default: break
            }
        }
        func flush() {
            guard ready else { return }
            if generation != controller.generation { generation = controller.generation; cursor = 0; web?.evaluateJavaScript("window.familiarTerminalWrite('G1tj')") }
            while cursor < controller.chunks.count {
                let encoded = controller.chunks[cursor].base64EncodedString()
                web?.evaluateJavaScript("window.familiarTerminalWrite('\(encoded)')")
                cursor += 1
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}
#endif
