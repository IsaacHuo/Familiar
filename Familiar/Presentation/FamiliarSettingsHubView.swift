import AVFoundation
import EventKit
import Speech
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum FamiliarSettingsRoute: String, Hashable {
    case modelService
    case localVision
    case appearance
    case tools
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
    let onSaveSettings: (FamiliarSettings) -> Void
    let onRestartOnboarding: () -> Void

    @State private var settings: FamiliarSettings
    @State private var path: [FamiliarSettingsRoute]

    init(
        initialSettings: FamiliarSettings,
        initialRoute: FamiliarSettingsRoute? = nil,
        registry: FamiliarToolRegistry,
        onSaveSettings: @escaping (FamiliarSettings) -> Void,
        onRestartOnboarding: @escaping () -> Void
    ) {
        self.initialSettings = initialSettings
        self.initialRoute = initialRoute
        self.registry = registry
        self.onSaveSettings = onSaveSettings
        self.onRestartOnboarding = onRestartOnboarding
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
                    settingsLink(
                        .localVision,
                        title: String(localized: "settings.local_vision.title", defaultValue: "Local Vision"),
                        subtitle: String(localized: "settings.local_vision.detail", defaultValue: "FastVLM 0.5B model and device benchmark"),
                        symbol: "eye.fill",
                        color: .teal
                    )
                }

                Section(String(localized: "settings.hub.agent", defaultValue: "Agent")) {
                    settingsLink(
                        .tools,
                        title: String(localized: "settings.hub.tools", defaultValue: "Tools"),
                        subtitle: String(localized: "settings.hub.tools.detail", defaultValue: "Capabilities registered with the Agent Runtime"),
                        symbol: "puzzlepiece.extension.fill",
                        color: .blue
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
                        subtitle: String(localized: "settings.skills.detail", defaultValue: "Installed instruction-only project guidance"),
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
                    Button(String(localized: "settings.onboarding.restart")) {
                        onRestartOnboarding()
                    }
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

                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
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
                    Text(subtitle)
                        .font(FamiliarTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, FamiliarSpacing.xSmall)
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
                },
                onRestartOnboarding: onRestartOnboarding
            )
        case .localVision:
            FamiliarLocalVisionSettingsView()
        case .appearance:
            FamiliarAppearanceSettingsView()
        case .tools:
            FamiliarToolsSettingsView(registry: registry)
        case .authorizations:
            FamiliarAuthorizationSettingsView()
        case .skills:
            FamiliarSkillsSettingsView(registry: registry)
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

private struct FamiliarSkillsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    let registry: FamiliarToolRegistry
    @Query(sort: \FamiliarSkill.installedAt, order: .reverse) private var skills: [FamiliarSkill]
    @State private var importing = false
    @State private var pending: FamiliarSkillDocument?
    @State private var errorMessage: String?
    @State private var knownToolNames: Set<String> = []

    var body: some View {
        List {
            Section {
                if skills.isEmpty {
                    ContentUnavailableView(
                        String(localized: "settings.skills.empty", defaultValue: "No installed skills"),
                        systemImage: "wand.and.stars",
                        description: Text(String(localized: "settings.skills.empty.detail", defaultValue: "Import an instruction-only JSON skill, then enable it for a project."))
                    )
                }
                ForEach(skills) { skill in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.name)
                        Text("\(skill.stableID) · \(skill.version)").font(.caption).foregroundStyle(.secondary)
                    }
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
            Section {
                Button { importing = true } label: { Label(String(localized: "settings.skills.import", defaultValue: "Import Skill JSON"), systemImage: "square.and.arrow.down") }
                    .disabled(knownToolNames.isEmpty)
            }
        }
        .navigationTitle(String(localized: "settings.skills.title", defaultValue: "Skills"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                pending = try FamiliarSkillDocumentParser.parse(
                    data: Data(contentsOf: url),
                    toolIDs: knownToolNames
                )
            } catch { errorMessage = error.localizedDescription }
        }
        .sheet(item: $pending) { document in
            NavigationStack {
                List {
                    Section {
                        LabeledContent(String(localized: "settings.skills.name", defaultValue: "Name"), value: document.name)
                        LabeledContent(String(localized: "settings.skills.version", defaultValue: "Version"), value: document.version)
                        LabeledContent(String(localized: "settings.skills.identifier", defaultValue: "Identifier"), value: document.id)
                    }
                    if !document.description.isEmpty {
                        Section(String(localized: "settings.skills.description", defaultValue: "Description")) {
                            Text(document.description)
                        }
                    }
                    Section(String(localized: "settings.skills.instructions", defaultValue: "Instructions")) {
                        Text(document.instructions)
                            .textSelection(.enabled)
                    }
                    Section(String(localized: "settings.skills.allowed_tools", defaultValue: "Allowed Tools")) {
                        Text(document.allowedTools.isEmpty
                             ? String(localized: "settings.skills.no_tools", defaultValue: "No tools")
                             : document.allowedTools.joined(separator: ", "))
                            .textSelection(.enabled)
                    }
                }
                .navigationTitle(String(localized: "settings.skills.preview.title", defaultValue: "Preview Skill"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.cancel")) { pending = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(skills.contains(where: { $0.stableID == document.id })
                               ? String(localized: "settings.skills.update", defaultValue: "Update")
                               : String(localized: "settings.skills.install", defaultValue: "Install")) {
                            do {
                                _ = try FamiliarSkillService().install(document, in: modelContext)
                                pending = nil
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .alert(String(localized: "settings.skills.title", defaultValue: "Skills"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok")) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            knownToolNames = Set(await registry.snapshot().map(\.name))
        }
    }
}

private struct FamiliarLocalVisionSettingsView: View {
    @State private var manager = FamiliarLocalVisionModelManager.shared

    var body: some View {
        List {
            Section {
                LabeledContent(String(localized: "settings.local_vision.model", defaultValue: "Model"), value: "FastVLM-0.5B")
                LabeledContent(String(localized: "settings.local_vision.download", defaultValue: "Download"), value: ByteCountFormatter.string(fromByteCount: FamiliarLocalVisionModelManager.archiveSize, countStyle: .file))
                LabeledContent(String(localized: "settings.local_vision.status", defaultValue: "Status"), value: statusText)
                if manager.state == .downloading {
                    ProgressView(value: manager.progress)
                }
                if let duration = manager.lastBenchmarkDuration {
                    LabeledContent(String(localized: "settings.local_vision.benchmark", defaultValue: "Last benchmark"), value: duration.formatted(.number.precision(.fractionLength(1))) + " s")
                }
            } footer: {
                Text(String(localized: "settings.local_vision.license", defaultValue: "Apple FastVLM model weights are licensed only for non-commercial research and academic development. The model runs on this device."))
            }

            Section {
                switch manager.state {
                case .notInstalled, .failed:
                    Button(String(localized: "settings.local_vision.install", defaultValue: "Download and Install")) { manager.install() }
                case .unavailable:
                    Button(String(localized: "settings.local_vision.run_benchmark", defaultValue: "Run Device Benchmark")) {
                        Task {
                            manager.markInstalledForRetry()
                            await manager.benchmark()
                        }
                    }
                    Button(String(localized: "settings.local_vision.delete", defaultValue: "Delete Model"), role: .destructive) {
                        Task { await manager.deleteModel() }
                    }
                case .downloading:
                    Button(String(localized: "settings.local_vision.pause", defaultValue: "Pause Download")) { manager.cancelInstall() }
                    Button(String(localized: "common.cancel"), role: .destructive) { manager.discardDownload() }
                case .paused:
                    Button(String(localized: "settings.local_vision.resume", defaultValue: "Resume Download")) { manager.install() }
                    Button(String(localized: "common.cancel"), role: .destructive) { manager.discardDownload() }
                case .installing:
                    ProgressView()
                case .installed:
                    Button(String(localized: "settings.local_vision.run_benchmark", defaultValue: "Run Device Benchmark")) {
                        Task { await manager.benchmark() }
                    }
                    Button(String(localized: "settings.local_vision.delete", defaultValue: "Delete Model"), role: .destructive) {
                        Task { await manager.deleteModel() }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.local_vision.title", defaultValue: "Local Vision"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        switch manager.state {
        case .notInstalled: String(localized: "settings.local_vision.not_installed", defaultValue: "Not installed")
        case .downloading: String(localized: "settings.local_vision.downloading", defaultValue: "Downloading")
        case .paused: String(localized: "settings.local_vision.paused", defaultValue: "Paused")
        case .installing: String(localized: "settings.local_vision.installing", defaultValue: "Installing")
        case .installed: String(localized: "settings.local_vision.installed", defaultValue: "Installed")
        case .unavailable(let reason), .failed(let reason): reason
        }
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
    let registry: FamiliarToolRegistry
    @State private var tools: [FamiliarToolManifest] = []

    var body: some View {
        List {
            Section {
                ForEach(tools, id: \.name) { tool in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.title)
                            Text(tool.name)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: FamiliarToolPresentation.symbol(for: tool.name))
                    }
                }
            } header: {
                Text(String(localized: "settings.tools.registered", defaultValue: "Registered Tools"))
            } footer: {
                Text(String(localized: "settings.tools.registered.footer", defaultValue: "This read-only list reflects the tools registered with Familiar's Agent Runtime. Availability is checked only when a run uses a tool."))
            }
        }
        .navigationTitle(String(localized: "settings.hub.tools", defaultValue: "Tools"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            tools = await registry.snapshot()
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
                permissionRow(String(localized: "settings.permissions.camera", defaultValue: "Camera"), symbol: "camera", status: mediaStatus(AVCaptureDevice.authorizationStatus(for: .video)))
                permissionRow(String(localized: "settings.permissions.microphone", defaultValue: "Microphone"), symbol: "mic", status: mediaStatus(AVCaptureDevice.authorizationStatus(for: .audio)))
                permissionRow(String(localized: "settings.permissions.speech", defaultValue: "Speech Recognition"), symbol: "waveform", status: speechStatus)
                permissionRow(String(localized: "settings.notifications.title"), symbol: "bell", status: notificationStatus)
            } footer: {
                Text(String(localized: "settings.permissions.footer", defaultValue: "Familiar asks for access only when you use the related feature. Permissions are controlled by iOS."))
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

            Section(String(localized: "settings.runs.steps", defaultValue: "Steps")) {
                if run.steps.isEmpty {
                    Text(String(localized: "settings.runs.no_steps", defaultValue: "No persisted tool steps"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(run.steps.sorted { $0.timelineSequence < $1.timelineSequence }) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.summary).font(.headline)
                            if !step.detail.isEmpty {
                                Text(step.detail).font(.subheadline).foregroundStyle(.secondary)
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
                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(FamiliarTheme.accent)
                        .frame(width: 72, height: 72)
                        .background(FamiliarTheme.brandGlow, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return String(format: String(localized: "settings.about.version", defaultValue: "Version %@ (%@)"), version, build)
    }

    private var thirdPartyNotices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let value = try? String(contentsOf: url, encoding: .utf8)
        else { return String(localized: "settings.about.notices.unavailable", defaultValue: "Notices are unavailable.") }
        return value
    }
}
