import AVFoundation
import Contacts
import CoreBluetooth
import CoreLocation
import EventKit
import HealthKit
import MusicKit
import Photos
import Speech
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum FamiliarSettingsRoute: String, Hashable {
    case modelService
    case searchService
    case pythonPackageSource
    case appearance
    case tools
    case shellRuntime
    case authorizations
    case skills
    case soul
    case storage
    case permissions
    case runHistory
    case privacy
    case about
}

struct FamiliarSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let initialSettings: FamiliarSettings
    let initialRoute: FamiliarSettingsRoute?
    let registry: FamiliarToolRegistry
    let searchService: FamiliarWebSearchService
    let pythonPackageSourceSettings: FamiliarPythonPackageSourceSettingsStore
    let workspaceStore: FamiliarWorkspaceStore
    let workspaceID: FamiliarWorkspaceID?
    let shellRuntimeStatus: FamiliarShellRuntimeStatus
    let onSaveSettings: (FamiliarSettings) -> Void

    @State private var settings: FamiliarSettings
    @State private var path: [FamiliarSettingsRoute]

    init(
        initialSettings: FamiliarSettings,
        initialRoute: FamiliarSettingsRoute? = nil,
        registry: FamiliarToolRegistry,
        searchService: FamiliarWebSearchService,
        pythonPackageSourceSettings: FamiliarPythonPackageSourceSettingsStore,
        workspaceStore: FamiliarWorkspaceStore,
        workspaceID: FamiliarWorkspaceID?,
        shellRuntimeStatus: FamiliarShellRuntimeStatus,
        onSaveSettings: @escaping (FamiliarSettings) -> Void
    ) {
        self.initialSettings = initialSettings
        self.initialRoute = initialRoute
        self.registry = registry
        self.searchService = searchService
        self.pythonPackageSourceSettings = pythonPackageSourceSettings
        self.workspaceStore = workspaceStore
        self.workspaceID = workspaceID
        self.shellRuntimeStatus = shellRuntimeStatus
        self.onSaveSettings = onSaveSettings
        _settings = State(initialValue: initialSettings)
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section(String(localized: "settings.hub.models", defaultValue: "Models")) {
                    settingsLink(
                        .modelService,
                        title: String(localized: "settings.hub.model_service", defaultValue: "Model Service"),
                        subtitle: "\(settings.selectedProvider.displayName) · \(settings.selectedModel.displayName)",
                        symbol: "key.horizontal.fill",
                        color: FamiliarTheme.accent
                    )
                }

                Section(String(localized: "settings.hub.agent", defaultValue: "Agent")) {
                    settingsLink(
                        .searchService,
                        title: String(localized: "settings.search.title", defaultValue: "Web Search"),
                        subtitle: FamiliarSearchProviderCatalog.descriptor(
                            for: searchService.settingsStore.selectedProviderID
                        )?.displayName ?? "DuckDuckGo",
                        symbol: "magnifyingglass",
                        color: .blue
                    )
                    settingsLink(
                        .tools,
                        title: String(localized: "settings.hub.tools", defaultValue: "Tools"),
                        subtitle: String(localized: "settings.hub.tools.detail", defaultValue: "Capabilities registered with the Agent Runtime"),
                        symbol: "puzzlepiece.extension.fill",
                        color: .blue
                    )
                    settingsLink(
                        .shellRuntime,
                        title: String(localized: "settings.shell.title", defaultValue: "Shell Runtime"),
                        subtitle: String(localized: "settings.shell.detail", defaultValue: "Alpine Linux in the current Familiar Workspace"),
                        symbol: "terminal.fill",
                        color: .gray
                    )
                    settingsLink(
                        .pythonPackageSource,
                        title: String(localized: "settings.python_source.title", defaultValue: "Python Package Source"),
                        subtitle: pythonPackageSourceSettings.selectedSource.displayName,
                        symbol: "shippingbox.fill",
                        color: .orange
                    )
                    settingsLink(
                        .authorizations,
                        title: String(localized: "settings.hub.authorizations", defaultValue: "Authorizations"),
                        subtitle: String(localized: "settings.hub.authorizations.detail", defaultValue: "Review remembered Agent actions"),
                        symbol: "checkmark.shield.fill",
                        color: .green
                    )
                    settingsLink(
                        .skills,
                        title: String(localized: "settings.skills.title", defaultValue: "Skills"),
                        subtitle: String(localized: "settings.skills.detail", defaultValue: "Instruction-only guidance available from the composer"),
                        symbol: "wand.and.stars",
                        color: .purple
                    )
                    settingsLink(
                        .soul,
                        title: String(localized: "settings.hub.soul", defaultValue: "Soul"),
                        subtitle: String(localized: "settings.hub.soul.detail", defaultValue: "Personality and response style"),
                        symbol: "sparkles",
                        color: .pink
                    )
                }

                Section(String(localized: "settings.hub.app", defaultValue: "App")) {
                    settingsLink(
                        .appearance,
                        title: String(localized: "settings.hub.appearance", defaultValue: "Appearance"),
                        subtitle: FamiliarAppearancePreference.current.localizedTitle,
                        symbol: "paintbrush.fill",
                        color: .indigo
                    )
                    settingsLink(
                        .storage,
                        title: String(localized: "settings.hub.storage", defaultValue: "Local Storage"),
                        subtitle: String(localized: "settings.hub.storage.detail", defaultValue: "Conversations and attachments on this iPhone"),
                        symbol: "internaldrive.fill",
                        color: .blue
                    )
                    settingsLink(
                        .permissions,
                        title: String(localized: "settings.hub.permissions", defaultValue: "Permissions"),
                        subtitle: String(localized: "settings.hub.permissions.detail", defaultValue: "Review access managed by iOS"),
                        symbol: "hand.raised.fill",
                        color: .orange
                    )
                    settingsLink(
                        .runHistory,
                        title: String(localized: "settings.hub.run_history", defaultValue: "Run History"),
                        subtitle: String(localized: "settings.hub.run_history.detail", defaultValue: "Local Agent activity"),
                        symbol: "clock.arrow.circlepath",
                        color: .gray
                    )
                }

                Section(String(localized: "settings.hub.support", defaultValue: "Privacy & Support")) {
                    settingsLink(
                        .privacy,
                        title: String(localized: "settings.privacy.title"),
                        subtitle: String(localized: "settings.hub.privacy.detail", defaultValue: "How Familiar handles your data"),
                        symbol: "hand.raised.square.fill",
                        color: .cyan
                    )
                    settingsLink(
                        .about,
                        title: String(localized: "settings.hub.about", defaultValue: "About Familiar"),
                        subtitle: appVersion,
                        symbol: "info.circle.fill",
                        color: .indigo
                    )
                }
            }
            .navigationTitle(String(localized: "drawer.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done", defaultValue: "Done")) {
                        onSaveSettings(settings)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .navigationDestination(for: FamiliarSettingsRoute.self, destination: destination)
        }
        .tint(FamiliarTheme.accent)
    }

    private func settingsLink(
        _ route: FamiliarSettingsRoute,
        title: String,
        subtitle: String,
        symbol: String,
        color: Color,
        badge: String? = nil
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: FamiliarSpacing.medium) {
                Image(systemName: symbol)
                    .font(.system(size: FamiliarIconSize.standard, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(
                        width: FamiliarControlSize.compactVisual,
                        height: FamiliarControlSize.compactVisual
                    )
                    .background(
                        color.gradient,
                        in: RoundedRectangle(cornerRadius: FamiliarRadius.compact, style: .continuous)
                    )

                HStack(spacing: FamiliarSpacing.small) {
                    Text(title)
                        .font(FamiliarTypography.body)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(FamiliarTheme.accent)
                            .padding(.horizontal, FamiliarSpacing.small)
                            .padding(.vertical, FamiliarSpacing.xSmall)
                            .background(FamiliarTheme.accent.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .accessibilityValue(badge ?? subtitle)
    }

    @ViewBuilder
    private func destination(_ route: FamiliarSettingsRoute) -> some View {
        switch route {
        case .modelService:
            FamiliarModelServiceSettingsView(
                initialSettings: settings,
                onSaveSettings: { value in
                    settings = value
                    onSaveSettings(value)
                }
            )
        case .searchService:
            FamiliarSearchSettingsView(searchService: searchService)
        case .pythonPackageSource:
            FamiliarPythonPackageSourceSettingsView(store: pythonPackageSourceSettings)
        case .appearance:
            FamiliarAppearanceSettingsView()
        case .tools:
            FamiliarToolsSettingsView(registry: registry)
        case .shellRuntime:
            FamiliarShellRuntimeSettingsView(
                store: workspaceStore,
                workspaceID: workspaceID,
                runtimeStatus: shellRuntimeStatus
            )
        case .authorizations:
            FamiliarAuthorizationSettingsView()
        case .skills:
            FamiliarSkillsSettingsView()
        case .soul:
            FamiliarSoulSettingsView(systemPrompt: $settings.systemPrompt)
        case .storage:
            FamiliarStorageSettingsView()
        case .permissions:
            FamiliarPermissionsSettingsView()
        case .runHistory:
            FamiliarRunHistoryView()
        case .privacy:
            FamiliarPrivacySettingsView()
        case .about:
            FamiliarAboutView()
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return String(format: String(localized: "settings.about.version", defaultValue: "Version %@ (%@)"), version, build)
    }
}

private struct FamiliarPythonPackageSourceSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let store: FamiliarPythonPackageSourceSettingsStore
    @State private var selectedSourceID: String

    init(store: FamiliarPythonPackageSourceSettingsStore) {
        self.store = store
        _selectedSourceID = State(initialValue: store.selectedSource.id)
    }

    var body: some View {
        Form {
            Section {
                Picker(
                    String(localized: "settings.python_source.picker", defaultValue: "Package Source"),
                    selection: $selectedSourceID
                ) {
                    ForEach(FamiliarPythonPackageSource.all) { source in
                        Text(source.displayName).tag(source.id)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text(String(localized: "settings.python_source.footer", defaultValue: "environment_prepare uses only the selected HTTPS source. The approval card and environment receipt record the exact index URL."))
            }

            Section(String(localized: "settings.python_source.selected", defaultValue: "Selected Source")) {
                LabeledContent(
                    String(localized: "settings.python_source.index_url", defaultValue: "Index URL"),
                    value: selectedSource.indexURL.absoluteString
                )
                Link(
                    String(localized: "settings.python_source.website", defaultValue: "Source website and help"),
                    destination: selectedSource.websiteURL
                )
            }

            Section {
                Text(String(localized: "settings.python_source.security", defaultValue: "Changing the source affects future environment preparations only. Existing Project environments remain pinned to their recorded lock and source."))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(String(localized: "settings.python_source.title", defaultValue: "Python Package Source"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.save")) {
                    store.save(selectedSourceID: selectedSourceID)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private var selectedSource: FamiliarPythonPackageSource {
        FamiliarPythonPackageSource.resolved(selectedSourceID)
    }
}

private struct FamiliarShellRuntimeSettingsView: View {
    let store: FamiliarWorkspaceStore
    let workspaceID: FamiliarWorkspaceID?
    let runtimeStatus: FamiliarShellRuntimeStatus

    @State private var networkEnabled = false
    @State private var errorMessage: String?
    @State private var asksToResetRuntime = false

    var body: some View {
        Form {
            Section(String(localized: "settings.shell.status", defaultValue: "Runtime Status")) {
                LabeledContent(
                    String(localized: "settings.shell.title", defaultValue: "Shell Runtime"),
                    value: runtimeStatusLabel
                )
                LabeledContent(
                    String(localized: "settings.shell.rootfs", defaultValue: "Root filesystem"),
                    value: "Alpine 3.24.0 · arm64"
                )
                LabeledContent(
                    String(localized: "settings.shell.storage", defaultValue: "Bundled storage"),
                    value: bundledRuntimeSize
                )
            }

            Section {
                Toggle(
                    String(localized: "settings.shell.network", defaultValue: "Allow public internet in this Workspace"),
                    isOn: Binding(
                        get: { networkEnabled },
                        set: { enabled in saveNetworkEnabled(enabled) }
                    )
                )
                .disabled(workspaceID == nil || !runtimeStatus.isReady)
            } footer: {
                Text(String(localized: "settings.shell.network.footer", defaultValue: "Off by default. Shell never receives model API keys, Keychain data, cookies, or access to local-network services."))
            }

            Section(String(localized: "settings.shell.limits", defaultValue: "Limits")) {
                Text(String(localized: "settings.shell.limits.detail", defaultValue: "180 seconds · 16 processes · 1 MB output · 500 MB Workspace"))
                    .foregroundStyle(.secondary)
            }

            Section {
                Link(String(localized: "settings.shell.source", defaultValue: "iSH Source Code"), destination: URL(string: "https://github.com/OpenMinis/ish-arm64/tree/54ca185b77f170e12fd353fcd7443232f6cb73fd")!)
                Link(String(localized: "settings.shell.license", defaultValue: "GNU GPLv3 License"), destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            }

            Section {
                if case .failed = runtimeStatus.phase {
                    Button(String(localized: "settings.shell.retry", defaultValue: "Retry Runtime Preparation")) {
                        runtimeStatus.retry()
                    }
                }
                Button(
                    runtimeStatus.resetScheduled
                        ? String(localized: "settings.shell.reset_scheduled", defaultValue: "Runtime reset scheduled")
                        : String(localized: "settings.shell.reset", defaultValue: "Reset Runtime on Next Launch"),
                    role: .destructive
                ) {
                    asksToResetRuntime = true
                }
                .disabled(runtimeStatus.resetScheduled)
            } footer: {
                Text(String(localized: "settings.shell.reset.footer", defaultValue: "The installed Alpine filesystem will be replaced from the verified bundled image the next time Familiar launches."))
            }
        }
        .navigationTitle(String(localized: "settings.shell.title", defaultValue: "Shell Runtime"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workspaceID) {
            guard let workspaceID else {
                networkEnabled = false
                return
            }
            do {
                networkEnabled = try store.shellSettings(in: workspaceID).networkEnabled
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert(String(localized: "settings.shell.title", defaultValue: "Shell Runtime"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            String(localized: "settings.shell.reset.confirm", defaultValue: "Reset the Shell Runtime on next launch?"),
            isPresented: $asksToResetRuntime,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.shell.reset", defaultValue: "Reset Runtime on Next Launch"), role: .destructive) {
                runtimeStatus.scheduleReset()
            }
        }
    }

    private var runtimeStatusLabel: String {
        switch runtimeStatus.phase {
        case .unavailable:
            String(localized: "settings.shell.unavailable", defaultValue: "Runtime assets are not available in this build")
        case .preparing:
            String(localized: "settings.shell.preparing", defaultValue: "Preparing")
        case .ready:
            String(localized: "settings.shell.ready", defaultValue: "Ready")
        case .failed(let message):
            String(format: String(localized: "settings.shell.failed", defaultValue: "Failed: %@"), message)
        }
    }

    private var bundledRuntimeSize: String {
        guard let archive = Bundle.main.url(
            forResource: "alpine-3.24.0-aarch64-fakefs",
            withExtension: "tar.gz"
        ), let bytes = try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return String(localized: "settings.shell.unavailable", defaultValue: "Unavailable")
        }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func saveNetworkEnabled(_ enabled: Bool) {
        guard let workspaceID else { return }
        do {
            try store.setShellNetworkEnabled(enabled, in: workspaceID)
            networkEnabled = enabled
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FamiliarSkillsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamiliarSkill.installedAt, order: .reverse) private var skills: [FamiliarSkill]
    @State private var creating = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if skills.isEmpty {
                    ContentUnavailableView(
                        String(localized: "settings.skills.empty", defaultValue: "No installed skills"),
                        systemImage: "wand.and.stars",
                        description: Text(String(localized: "settings.skills.empty.detail", defaultValue: "Create an instruction-only Skill, then call it from the composer."))
                    )
                }
                ForEach(skills) { skill in
                    NavigationLink {
                        FamiliarSkillEditorView(skill: skill) { document in
                            _ = try FamiliarSkillService().install(document, in: modelContext)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.name)
                            Text("\(skill.stableID) · \(skill.version)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint(String(localized: "settings.skills.edit.hint", defaultValue: "Opens this Skill for viewing and editing"))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            do {
                                try FamiliarSkillService().uninstall(skill, in: modelContext)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            Label(String(localized: "settings.skills.delete", defaultValue: "Delete"), systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text(String(localized: "settings.skills.footer", defaultValue: "Skills contain instruction-only guidance. They cannot grant permissions or authorize actions."))
            }
        }
        .navigationTitle(String(localized: "settings.skills.title", defaultValue: "Skills"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "settings.skills.add", defaultValue: "Add Skill"))
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                FamiliarSkillEditorView(skill: nil, showsCancelButton: true) { document in
                    guard !skills.contains(where: { $0.stableID == document.id }) else {
                        throw FamiliarSkillServiceError.alreadyInstalled
                    }
                    _ = try FamiliarSkillService().install(document, in: modelContext)
                }
            }
        }
        .alert(String(localized: "settings.skills.title", defaultValue: "Skills"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok")) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct FamiliarSkillEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let skill: FamiliarSkill?
    let showsCancelButton: Bool
    let onSave: (FamiliarSkillDocument) throws -> Void
    private let preservedAllowedTools: [String]
    private let preservedExamples: [String]

    @State private var name: String
    @State private var identifier: String
    @State private var descriptionText: String
    @State private var instructions: String
    @State private var errorMessage: String?

    init(
        skill: FamiliarSkill?,
        showsCancelButton: Bool = false,
        onSave: @escaping (FamiliarSkillDocument) throws -> Void
    ) {
        self.skill = skill
        self.showsCancelButton = showsCancelButton
        self.onSave = onSave
        preservedAllowedTools = Self.decode([String].self, from: skill?.allowedToolsJSON) ?? []
        preservedExamples = Self.decode([String].self, from: skill?.examplesJSON) ?? []
        _name = State(initialValue: skill?.name ?? "")
        _identifier = State(initialValue: skill?.stableID ?? "")
        _descriptionText = State(initialValue: skill?.descriptionText ?? "")
        _instructions = State(initialValue: skill?.instructions ?? String(
            localized: "settings.skills.create.instructions_template",
            defaultValue: "Goal:\n- Describe what this Skill should help accomplish.\n\nRules:\n- Add requirements the response must follow.\n\nOutput:\n- Describe the expected format and style."
        ))
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "settings.skills.name", defaultValue: "Name"), text: $name)
                if let skill {
                    LabeledContent(
                        String(localized: "settings.skills.identifier", defaultValue: "Identifier"),
                        value: "/\(skill.stableID)"
                    )
                } else {
                    TextField(
                        String(localized: "settings.skills.identifier", defaultValue: "Identifier"),
                        text: $identifier,
                        prompt: Text(generatedIdentifier.isEmpty ? "my-skill" : generatedIdentifier)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                TextField(
                    String(localized: "settings.skills.description", defaultValue: "Description"),
                    text: $descriptionText,
                    axis: .vertical
                )
                .lineLimit(2...4)
            } footer: {
                if skill == nil {
                    Text(String(
                        format: String(localized: "settings.skills.create.identifier_hint", defaultValue: "Slash command: /%@"),
                        resolvedIdentifier.isEmpty ? "my-skill" : resolvedIdentifier
                    ))
                }
            }

            Section(String(localized: "settings.skills.instructions", defaultValue: "Instructions")) {
                TextEditor(text: $instructions)
                    .frame(minHeight: 220)
            }

            Section {
                Text(skill == nil
                     ? String(localized: "settings.skills.create.no_tools", defaultValue: "New Skills contain instructions only and start with no tool access.")
                     : String(localized: "settings.skills.edit.preserved", defaultValue: "The identifier, tool scope, and examples stay unchanged when you edit this Skill."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(skill == nil
                         ? String(localized: "settings.skills.create.title", defaultValue: "New Skill")
                         : String(localized: "settings.skills.edit.title", defaultValue: "Edit Skill"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancelButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(skill == nil
                       ? String(localized: "common.create", defaultValue: "Create")
                       : String(localized: "common.save")) {
                    save()
                }
                .fontWeight(.semibold)
                .disabled(!canSave)
            }
        }
        .alert(skill == nil
               ? String(localized: "settings.skills.create.title", defaultValue: "New Skill")
               : String(localized: "settings.skills.edit.title", defaultValue: "Edit Skill"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok")) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var generatedIdentifier: String {
        normalizedIdentifier(name)
    }

    private var resolvedIdentifier: String {
        if let skill { return skill.stableID }
        let explicit = normalizedIdentifier(identifier)
        return explicit.isEmpty ? generatedIdentifier : explicit
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !resolvedIdentifier.isEmpty
            && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let document = FamiliarSkillDocument(
            format: "familiar.skill",
            formatVersion: 1,
            id: resolvedIdentifier,
            version: skill?.version ?? "1.0.0",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
            allowedTools: preservedAllowedTools,
            examples: preservedExamples
        )
        do {
            let data = try JSONEncoder().encode(document)
            let validated = try FamiliarSkillDocumentParser.parse(data: data, toolIDs: Set(preservedAllowedTools))
            try onSave(validated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedIdentifier(_ value: String) -> String {
        value.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .joined(separator: "-")
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from value: String?) -> Value? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

private struct FamiliarAuthorizationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamiliarAuthorizationRuleRecord.createdAt, order: .reverse) private var records: [FamiliarAuthorizationRuleRecord]

    private var activeRecords: [FamiliarAuthorizationRuleRecord] {
        records.filter { $0.revokedAt == nil && $0.expiresAt > Date() && $0.duration != .once }
    }

    var body: some View {
        List {
            if activeRecords.isEmpty {
                ContentUnavailableView(
                    String(localized: "settings.authorizations.empty", defaultValue: "No remembered authorizations"),
                    systemImage: "checkmark.shield"
                )
            } else {
                Section {
                    ForEach(activeRecords) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.capabilityID)
                                .font(.body.weight(.medium))
                            Text(record.targetKey)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(record.duration == .session
                                 ? String(localized: "authorization.session", defaultValue: "This Session")
                                 : String(localized: "authorization.always", defaultValue: "Always Allow"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .swipeActions {
                            Button(String(localized: "settings.authorizations.revoke", defaultValue: "Revoke"), role: .destructive) {
                                record.revokedAt = Date()
                                try? modelContext.save()
                            }
                        }
                    }
                } footer: {
                    Text(String(localized: "settings.authorizations.footer", defaultValue: "Authorizations are scoped to a project, tool, and target. Destructive actions still require confirmation."))
                }

                Section {
                    Button(String(localized: "settings.authorizations.revoke_all", defaultValue: "Revoke All"), role: .destructive) {
                        let now = Date()
                        activeRecords.forEach { $0.revokedAt = now }
                        try? modelContext.save()
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.hub.authorizations", defaultValue: "Authorizations"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FamiliarSoulSettingsView: View {
    @Binding var systemPrompt: String

    var body: some View {
        Form {
            Section {
                TextEditor(text: $systemPrompt)
                    .frame(minHeight: 260)
                    .accessibilityLabel(String(localized: "settings.soul.editor", defaultValue: "Personality prompt"))
            } header: {
                Text(String(localized: "settings.soul.personality", defaultValue: "Personality"))
            } footer: {
                Text(String(localized: "settings.soul.footer", defaultValue: "This changes Familiar's tone and response style. Tool permissions and safety rules remain enforced by the app."))
            }

            Section {
                HStack {
                    Text(String(localized: "settings.soul.characters", defaultValue: "Characters"))
                    Spacer()
                    Text("\(min(systemPrompt.count, 3_000)) / 3,000")
                        .foregroundStyle(.secondary)
                }
                Button(String(localized: "settings.soul.restore", defaultValue: "Restore Familiar Default"), role: .destructive) {
                    systemPrompt = FamiliarSettings.defaultValue.systemPrompt
                }
            }
        }
        .onChange(of: systemPrompt) { _, value in
            if value.count > 3_000 { systemPrompt = String(value.prefix(3_000)) }
        }
        .navigationTitle(String(localized: "settings.hub.soul", defaultValue: "Soul"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FamiliarToolsSettingsView: View {
    private struct Entry: Identifiable, Sendable {
        let manifest: FamiliarToolManifest
        let availability: FamiliarCapabilityAvailability
        var id: String { manifest.name }
    }

    let registry: FamiliarToolRegistry
    @State private var entries: [Entry] = []

    var body: some View {
        List {
            Section {
                ForEach(entries) { entry in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.manifest.title)
                            Text("\(executionClassLabel(entry.manifest.executionClass)) · \(availabilityLabel(entry.availability))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: FamiliarToolPresentation.symbol(for: entry.manifest.name))
                    }
                }
            } header: {
                Text(String(localized: "settings.tools.registered", defaultValue: "Registered Tools"))
            } footer: {
                Text(String(localized: "settings.tools.registered.footer", defaultValue: "This read-only list shows each registered tool's execution class and current system-capability availability."))
            }
        }
        .navigationTitle(String(localized: "settings.hub.tools", defaultValue: "Tools"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let tools = await registry.snapshot()
            var values: [Entry] = []
            for tool in tools {
                values.append(Entry(
                    manifest: tool,
                    availability: await registry.availability(for: tool)
                ))
            }
            entries = values
        }
    }

    private func executionClassLabel(_ value: FamiliarToolExecutionClass) -> String {
        switch value {
        case .native: String(localized: "settings.tools.class.native", defaultValue: "Native")
        case .specializedLocal: String(localized: "settings.tools.class.specialized", defaultValue: "Specialized Local")
        case .shell: String(localized: "settings.tools.class.shell", defaultValue: "Shell")
        }
    }

    private func availabilityLabel(_ value: FamiliarCapabilityAvailability) -> String {
        switch value {
        case .available: String(localized: "settings.tools.availability.available", defaultValue: "Available")
        case .requestable: String(localized: "settings.tools.availability.requestable", defaultValue: "Permission Required")
        case .unavailable: String(localized: "settings.tools.availability.unavailable", defaultValue: "Unavailable")
        }
    }
}

nonisolated enum FamiliarToolPresentation {
    static func symbol(for name: String) -> String {
        switch name {
        case "current_date_time": "clock"
        case "app_information": "info.circle"
        case "web_search": "magnifyingglass"
        case "web_fetch": "globe"
        case "calendar_events": "calendar"
        case "create_calendar_event": "calendar.badge.plus"
        case "reminders": "checklist"
        case "create_reminder": "checkmark.circle"
        default: "wrench.and.screwdriver"
        }
    }
}

private struct FamiliarStorageSettingsView: View {
    @Query private var conversations: [FamiliarConversation]
    @Query private var messages: [FamiliarMessage]
    @Query private var attachments: [FamiliarAttachment]

    var body: some View {
        List {
            Section(String(localized: "settings.storage.overview", defaultValue: "Overview")) {
                storageRow(String(localized: "settings.storage.conversations", defaultValue: "Conversations"), value: conversations.count, symbol: "bubble.left.and.bubble.right")
                storageRow(String(localized: "settings.storage.messages", defaultValue: "Messages"), value: messages.count, symbol: "text.bubble")
                HStack {
                    Label(String(localized: "settings.storage.attachments", defaultValue: "Attachments"), systemImage: "doc")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: attachmentBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text(String(localized: "settings.storage.local.detail", defaultValue: "Conversation history and imported document copies stay in Familiar's private storage on this iPhone. Familiar does not use CloudKit or iCloud sync."))
            }
        }
        .navigationTitle(String(localized: "settings.hub.storage", defaultValue: "Local Storage"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var attachmentBytes: Int64 { attachments.reduce(0) { $0 + $1.byteSize } }

    private func storageRow(_ title: String, value: Int, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value.formatted()).foregroundStyle(.secondary)
        }
    }
}

private struct FamiliarPermissionsSettingsView: View {
    @Environment(\.openURL) private var openURL
    @State private var notificationState: FamiliarNotificationAuthorizationState = .unknown
    @State private var notificationsEnabled = FamiliarNotificationPreference.isEnabled
    @State private var isUpdatingNotifications = false
    @State private var healthRequestState: FamiliarHealthReadScope.RequestState = .notRequested

    var body: some View {
        List {
            Section {
                Toggle(
                    String(localized: "settings.notifications.run_terminal"),
                    isOn: Binding(
                        get: { notificationsEnabled },
                        set: { enabled in Task { await updateNotifications(enabled) } }
                    )
                )
                .disabled(isUpdatingNotifications)
                permissionRow(String(localized: "settings.permissions.calendar", defaultValue: "Calendar"), symbol: "calendar", status: eventStatus(.event))
                permissionRow(String(localized: "settings.permissions.reminders", defaultValue: "Reminders"), symbol: "checklist", status: eventStatus(.reminder))
                permissionRow(String(localized: "settings.permissions.contacts", defaultValue: "Contacts"), symbol: "person.crop.circle", status: contactsStatus)
                permissionRow(String(localized: "settings.permissions.location", defaultValue: "Location"), symbol: "location", status: locationStatus)
                permissionRow(String(localized: "settings.permissions.photos_add", defaultValue: "Add to Photos"), symbol: "photo.badge.plus", status: photoAddStatus)
                permissionRow(String(localized: "settings.permissions.photos_read", defaultValue: "Read Photo Metadata"), symbol: "photo.on.rectangle", status: photoReadStatus)
                permissionRow(String(localized: "settings.permissions.health", defaultValue: "Health Activity"), symbol: "heart.text.square", status: healthStatus)
                permissionRow(String(localized: "settings.permissions.music", defaultValue: "Apple Music"), symbol: "music.note", status: musicStatus)
                permissionRow(String(localized: "settings.permissions.bluetooth", defaultValue: "Bluetooth"), symbol: "dot.radiowaves.left.and.right", status: bluetoothStatus)
                permissionRow(String(localized: "settings.permissions.camera", defaultValue: "Camera"), symbol: "camera", status: mediaStatus(AVCaptureDevice.authorizationStatus(for: .video)))
                permissionRow(String(localized: "settings.permissions.microphone", defaultValue: "Microphone"), symbol: "mic", status: mediaStatus(AVCaptureDevice.authorizationStatus(for: .audio)))
                permissionRow(String(localized: "settings.permissions.speech", defaultValue: "Speech Recognition"), symbol: "waveform", status: speechStatus)
                permissionRow(String(localized: "settings.notifications.title"), symbol: "bell", status: notificationStatus)
            } footer: {
                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                    Text(String(localized: "settings.permissions.footer", defaultValue: "Familiar asks for access only when you use the related feature. Permissions are controlled by iOS."))
                    Text(String(localized: "settings.permissions.health_footer", defaultValue: "HealthKit never tells apps whether you denied a read request, so Familiar can only show whether it has asked. Missing values are never reported as zero."))
                }
            }

            Section {
                Button(String(localized: "settings.permissions.open", defaultValue: "Open Familiar in iOS Settings")) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            }
        }
        .navigationTitle(String(localized: "settings.hub.permissions", defaultValue: "Permissions"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            notificationState = await FamiliarNotificationService.authorizationState()
            notificationsEnabled = FamiliarNotificationPreference.isEnabled && notificationState == .enabled
            healthRequestState = await FamiliarHealthReadScope.requestState()
        }
    }

    private func permissionRow(_ title: String, symbol: String, status: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(status).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func eventStatus(_ entity: EKEntityType) -> String {
        authorizationTitle(EKEventStore.authorizationStatus(for: entity).rawValue)
    }

    private func mediaStatus(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var speechStatus: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var notificationStatus: String {
        switch notificationState {
        case .enabled: allowed
        case .denied: denied
        case .notDetermined, .unknown: notRequested
        }
    }

    private var contactsStatus: String {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var locationStatus: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    /// HealthKit deliberately hides read denials, so the only honest states are
    /// "requested" and "not requested". Never render `allowed` here.
    private var healthStatus: String {
        switch healthRequestState {
        case .unavailable: String(localized: "settings.permissions.unsupported", defaultValue: "Not Supported")
        case .notRequested: notRequested
        case .requested: String(localized: "settings.permissions.requested", defaultValue: "Requested")
        }
    }

    private var musicStatus: String {
        switch MusicAuthorization.currentStatus {
        case .authorized: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var bluetoothStatus: String {
        switch CBManager.authorization {
        case .allowedAlways: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var photoReadStatus: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: allowed
        case .limited: String(localized: "settings.permissions.limited", defaultValue: "Limited")
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private var photoAddStatus: String {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: allowed
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        @unknown default: restricted
        }
    }

    private func updateNotifications(_ enabled: Bool) async {
        guard !isUpdatingNotifications else { return }
        isUpdatingNotifications = true
        defer { isUpdatingNotifications = false }
        do {
            notificationState = try await FamiliarNotificationService.setEnabled(enabled)
            notificationsEnabled = enabled && notificationState == .enabled
        } catch {
            notificationsEnabled = false
        }
    }

    private func authorizationTitle(_ rawValue: Int) -> String {
        switch EKAuthorizationStatus(rawValue: rawValue) {
        case .fullAccess, .authorized: allowed
        case .writeOnly: String(localized: "settings.permissions.write_only", defaultValue: "Write Only")
        case .denied: denied
        case .restricted: restricted
        case .notDetermined: notRequested
        case nil: restricted
        @unknown default: restricted
        }
    }

    private var allowed: String { String(localized: "settings.permissions.allowed", defaultValue: "Allowed") }
    private var denied: String { String(localized: "settings.permissions.denied", defaultValue: "Denied") }
    private var restricted: String { String(localized: "settings.permissions.restricted", defaultValue: "Restricted") }
    private var notRequested: String { String(localized: "settings.permissions.not_requested", defaultValue: "Not Requested") }
}

private struct FamiliarRunHistoryView: View {
    @Query(sort: \FamiliarAgentRun.startedAt, order: .reverse) private var runs: [FamiliarAgentRun]

    var body: some View {
        Group {
            if runs.isEmpty {
                ContentUnavailableView(
                    String(localized: "settings.runs.empty.title", defaultValue: "No runs yet"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(String(localized: "settings.runs.empty.detail", defaultValue: "Completed and failed Agent runs will appear here."))
                )
            } else {
                List(runs) { run in
                    NavigationLink {
                        FamiliarRunDetailView(run: run)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(run.conversation?.title ?? String(localized: "conversation.new"))
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Text(runStatus(run)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(run.startedAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.hub.run_history", defaultValue: "Run History"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runStatus(_ run: FamiliarAgentRun) -> String {
        switch run.status {
        case .running: String(localized: "settings.runs.running", defaultValue: "Running")
        case .completed: String(localized: "settings.runs.completed", defaultValue: "Completed")
        case .cancelled: String(localized: "settings.runs.cancelled", defaultValue: "Cancelled")
        case .failed: String(localized: "settings.runs.failed", defaultValue: "Failed")
        }
    }
}

private struct FamiliarRunDetailView: View {
    let run: FamiliarAgentRun
    @Query private var activities: [FamiliarActivityRecord]

    init(run: FamiliarAgentRun) {
        self.run = run
        let runtimeID = run.runtimeID
        _activities = Query(
            filter: #Predicate<FamiliarActivityRecord> { $0.runtimeID == runtimeID },
            sort: \FamiliarActivityRecord.sequence
        )
    }

    var body: some View {
        List {
            Section {
                LabeledContent(String(localized: "settings.runs.started", defaultValue: "Started")) {
                    Text(run.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                }
                if let finishedAt = run.finishedAt {
                    LabeledContent(String(localized: "settings.runs.finished", defaultValue: "Finished")) {
                        Text(finishedAt, format: .dateTime.year().month().day().hour().minute().second())
                    }
                }
                if let reason = run.finishReason, !reason.isEmpty {
                    LabeledContent(String(localized: "settings.runs.result", defaultValue: "Result"), value: reason)
                }
            }

            Section(String(localized: "settings.runs.activities", defaultValue: "Activities")) {
                let visibleActivities = activities.filter { $0.kind != .assistantTurn }
                if visibleActivities.isEmpty {
                    Text(String(localized: "settings.runs.no_activities", defaultValue: "No persisted activities"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleActivities) { activity in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.summary).font(.headline)
                            if let detail = activity.detail, !detail.isEmpty {
                                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle(run.conversation?.title ?? String(localized: "settings.hub.run_history", defaultValue: "Run History"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FamiliarPrivacySettingsView: View {
    var body: some View {
        List {
            Section {
                Label(String(localized: "settings.privacy.no_account"), systemImage: "person.crop.circle.badge.xmark")
                Label(String(localized: "settings.privacy.permission_tools"), systemImage: "hand.raised")
                Label(String(localized: "settings.privacy.native_private_data", defaultValue: "Contacts, one-time location, and clipboard data are used only by explicitly requested tools"), systemImage: "iphone.and.arrow.forward")
                Label(String(localized: "settings.privacy.local_history"), systemImage: "internaldrive")
                Label(String(localized: "settings.privacy.local_documents"), systemImage: "doc.text.magnifyingglass")
                Label(String(localized: "settings.privacy.remote_images"), systemImage: "photo.badge.exclamationmark")
                Label(String(localized: "settings.privacy.web_tools"), systemImage: "network")
            }
        }
        .navigationTitle(String(localized: "settings.privacy.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FamiliarAboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    appIconView
                    Text(String(localized: "app.name")).font(.title2.bold())
                    Text(version).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                Link(String(localized: "settings.about.privacy", defaultValue: "Privacy Policy"), destination: URL(string: "https://isaachuo.github.io/familiar/privacy/")!)
                Link(String(localized: "settings.about.support", defaultValue: "Support"), destination: URL(string: "https://isaachuo.github.io/familiar/support/")!)
                Link(String(localized: "settings.about.feedback", defaultValue: "Report an Issue"), destination: URL(string: "https://github.com/IsaacHuo/familiar/issues")!)
                Link(String(localized: "settings.about.source", defaultValue: "Source Code"), destination: URL(string: "https://github.com/IsaacHuo/Familiar")!)
            }

            Section {
                NavigationLink(String(localized: "settings.about.notices", defaultValue: "Third-Party Notices")) {
                    ScrollView {
                        Text(thirdPartyNotices)
                            .font(.footnote.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(String(localized: "settings.about.notices", defaultValue: "Third-Party Notices"))
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .navigationTitle(String(localized: "settings.hub.about", defaultValue: "About Familiar"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var appIconView: some View {
        if let appIcon {
            Image(uiImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(FamiliarTheme.accent)
                .frame(width: 72, height: 72)
                .background(FamiliarTheme.brandGlow, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var appIcon: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String]
        else { return UIImage(named: "AppIcon") }

        for filename in files.reversed() {
            if let image = UIImage(named: filename) { return image }
            let resource = filename as NSString
            if let path = Bundle.main.path(
                forResource: resource.deletingPathExtension,
                ofType: resource.pathExtension.isEmpty ? "png" : resource.pathExtension
            ), let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return UIImage(named: "AppIcon")
    }

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return String(format: String(localized: "settings.about.version", defaultValue: "Version %@ (%@)"), version, build)
    }

    private var thirdPartyNotices: String {
        let names = ["ThirdPartyNotices", "ThirdPartyNotices-iSH", "AnyDocRustDependencies", "GPL-3.0", "ISH_LICENSE_IOS", "ISHSourceOffer"]
        let values = names.compactMap { name -> String? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return values.isEmpty
            ? String(localized: "settings.about.notices.unavailable", defaultValue: "Notices are unavailable.")
            : values.joined(separator: "\n\n\n")
    }
}
