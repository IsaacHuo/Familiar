import AppKit
import Observation
import SwiftUI

@main
struct FamiliarMacApp: App {
    @State private var state = FamiliarMacWorkspaceState()

    var body: some Scene {
        WindowGroup {
            FamiliarMacRootView(state: state)
                .frame(minWidth: 980, minHeight: 680)
                .alert("Familiar", isPresented: Binding(
                    get: { state.errorMessage != nil },
                    set: { if !$0 { state.errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(state.errorMessage ?? "")
                }
        }
        .commands {
            FamiliarMacCommands(state: state)
        }

        Settings {
            FamiliarMacSettingsView(state: state)
                .frame(width: 560, height: 430)
        }
    }
}

@MainActor
@Observable
final class FamiliarMacWorkspaceState {
    enum Selection: Hashable {
        case newChat
        case project(UUID)
        case conversation(UUID)
    }

    struct Project: Identifiable, Hashable {
        let id: UUID
        var name: String
        var summary: String
    }

    struct Conversation: Identifiable, Hashable {
        let id: UUID
        var title: String
        var projectID: UUID?
        var updatedAt: Date
    }

    enum RuntimeState: String {
        case stopped
        case starting
        case ready
        case running
        case failed
    }

    var selection: Selection? = .newChat
    var columnVisibility: NavigationSplitViewVisibility = .all
    var showsInspector = true
    var composerText = ""
    var projects: [Project] = []
    var conversations: [Conversation] = []
    var runtimeState: RuntimeState = .stopped
    var selectedRoute = "Cloud"
    var localModelState = "Not Installed"
    var workspaceFiles: [FamiliarWorkspaceEntry] = []
    var errorMessage: String?
    private let draftWorkspaceID = FamiliarWorkspaceID.conversation(UUID())
    private let workspaceStore = FamiliarWorkspaceStore()

    func newChat() {
        selection = .newChat
        composerText = ""
    }

    func send() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorMessage = "The macOS Agent Runtime is not connected to this UI shell yet. Your draft was kept."
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.importFiles(panel.urls) }
        }
    }

    func importFiles(_ urls: [URL]) {
        do {
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                _ = try workspaceStore.write(
                    data,
                    relativePath: "Files/\(url.lastPathComponent)",
                    in: currentWorkspaceID
                )
            }
            refreshWorkspaceFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshWorkspaceFiles() {
        do {
            workspaceFiles = try workspaceStore.entries(in: currentWorkspaceID)
                .filter { $0.relativePath.hasPrefix("Files/") }
        } catch {
            workspaceFiles = []
            errorMessage = error.localizedDescription
        }
    }

    private var currentWorkspaceID: FamiliarWorkspaceID {
        switch selection {
        case .project(let id): .project(id)
        case .conversation(let id): .conversation(id)
        case .newChat, .none: draftWorkspaceID
        }
    }
}

private struct FamiliarMacCommands: Commands {
    @Bindable var state: FamiliarMacWorkspaceState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { state.newChat() }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("View") {
            Button("Toggle Sidebar") {
                state.columnVisibility = state.columnVisibility == .detailOnly ? .all : .detailOnly
            }
            .keyboardShortcut("0", modifiers: .command)

            Button(state.showsInspector ? "Hide Inspector" : "Show Inspector") {
                state.showsInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

struct FamiliarMacRootView: View {
    @Bindable var state: FamiliarMacWorkspaceState

    var body: some View {
        NavigationSplitView(columnVisibility: $state.columnVisibility) {
            FamiliarMacSidebar(state: state)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 330)
        } detail: {
            FamiliarMacChatSurface(state: state)
                .inspector(isPresented: $state.showsInspector) {
                    FamiliarMacInspector(state: state)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    state.showsInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                Button {
                    state.newChat()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
            }
        }
        .onChange(of: state.selection) { _, _ in state.refreshWorkspaceFiles() }
        .task { state.refreshWorkspaceFiles() }
    }
}

private struct FamiliarMacSidebar: View {
    @Bindable var state: FamiliarMacWorkspaceState

    var body: some View {
        List(selection: $state.selection) {
            Section {
                Label("New Chat", systemImage: "square.and.pencil")
                    .tag(FamiliarMacWorkspaceState.Selection.newChat)
            }

            if !state.projects.isEmpty {
                Section("Projects") {
                    ForEach(state.projects) { project in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(project.name, systemImage: "folder")
                                .lineLimit(1)
                            if !project.summary.isEmpty {
                                Text(project.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(FamiliarMacWorkspaceState.Selection.project(project.id))
                    }
                }
            }

            Section("Recent") {
                if state.conversations.isEmpty {
                    ContentUnavailableView("No Conversations", systemImage: "bubble.left.and.bubble.right")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(state.conversations) { conversation in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conversation.title).lineLimit(1)
                            Text(conversation.updatedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(FamiliarMacWorkspaceState.Selection.conversation(conversation.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Familiar")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Circle()
                    .fill(runtimeColor)
                    .frame(width: 7, height: 7)
                Text("Runtime \(state.runtimeState.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                SettingsLink { Image(systemName: "gear") }
                    .buttonStyle(.plain)
            }
            .padding(10)
            .background(.bar)
        }
    }

    private var runtimeColor: Color {
        switch state.runtimeState {
        case .ready: .green
        case .running, .starting: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }
}

private struct FamiliarMacChatSurface: View {
    @Bindable var state: FamiliarMacWorkspaceState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Picker("Route", selection: $state.selectedRoute) {
                    Text("Local Only").tag("Local Only")
                    Text("Prefer Local").tag("Prefer Local")
                    Text("Cloud").tag("Cloud")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(.bar)

            Divider()

            ScrollView {
                ContentUnavailableView {
                    Label("Start a conversation", systemImage: "sparkles")
                } description: {
                    Text("Ask Familiar to reason locally, use native Mac tools, or work inside the current Linux Workspace.")
                }
                .frame(maxWidth: .infinity, minHeight: 420)
                .padding(32)
            }

            Divider()
            FamiliarMacComposer(state: state)
        }
        .navigationTitle(title)
    }

    private var title: String {
        switch state.selection {
        case .project(let id): state.projects.first(where: { $0.id == id })?.name ?? "Project"
        case .conversation(let id): state.conversations.first(where: { $0.id == id })?.title ?? "Conversation"
        case .newChat, .none: "New Chat"
        }
    }
}

private struct FamiliarMacComposer: View {
    @Bindable var state: FamiliarMacWorkspaceState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            TextEditor(text: $state.composerText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64, maxHeight: 180)
                .focused($focused)

            HStack {
                Button { state.chooseFiles() } label: { Label("Attach", systemImage: "paperclip") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                Spacer()
                Button {
                    state.send()
                    focused = true
                } label: {
                    Image(systemName: "arrow.up")
                        .fontWeight(.semibold)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(state.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
        .background(.regularMaterial)
    }
}

private struct FamiliarMacInspector: View {
    @Bindable var state: FamiliarMacWorkspaceState

    var body: some View {
        Form {
            Section("Context") {
                LabeledContent("Workspace", value: workspaceLabel)
                LabeledContent("Route", value: state.selectedRoute)
                LabeledContent("Local Model", value: state.localModelState)
            }
            Section("Runtime") {
                LabeledContent("State", value: state.runtimeState.rawValue.capitalized)
                LabeledContent("Network", value: "Disabled")
                LabeledContent("Mount", value: "Workspace only")
            }
            Section("Files") {
                if state.workspaceFiles.isEmpty {
                    ContentUnavailableView("No Imported Files", systemImage: "doc")
                } else {
                    ForEach(state.workspaceFiles, id: \.relativePath) { file in
                        LabeledContent(
                            URL(fileURLWithPath: file.relativePath).lastPathComponent,
                            value: ByteCountFormatter.string(
                                fromByteCount: file.byteSize,
                                countStyle: .file
                            )
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Inspector")
    }

    private var workspaceLabel: String {
        switch state.selection {
        case .project: "Project"
        case .conversation: "Conversation"
        case .newChat, .none: "Draft"
        }
    }
}

private struct FamiliarMacSettingsView: View {
    @Bindable var state: FamiliarMacWorkspaceState

    var body: some View {
        TabView {
            Form {
                LabeledContent("Model", value: "Qwen · Core AI")
                LabeledContent("Status", value: state.localModelState)
                Picker("Default route", selection: $state.selectedRoute) {
                    Text("Local Only").tag("Local Only")
                    Text("Prefer Local").tag("Prefer Local")
                    Text("Cloud").tag("Cloud")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Models", systemImage: "brain") }

            Form {
                LabeledContent("Runtime", value: "Apple Containerization")
                LabeledContent("Network", value: "Disabled")
                LabeledContent("Workspace access", value: "Current only")
                LabeledContent("Idle stop", value: "10 minutes")
            }
            .formStyle(.grouped)
            .tabItem { Label("Runtime", systemImage: "shippingbox") }
        }
        .padding(12)
    }
}
