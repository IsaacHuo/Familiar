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


struct FamiliarPythonPackageSourceSettingsView: View {
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

struct FamiliarShellRuntimeSettingsView: View {
    let store: FamiliarWorkspaceStore
    let workspaceID: FamiliarWorkScope?
    let runtimeStatus: FamiliarShellRuntimeStatus

    private let timeoutSettings = FamiliarShellTimeoutSettingsStore()

    @State private var networkEnabled = false
    @State private var timeoutSeconds = FamiliarShellLimits.iOS.defaultTimeout
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

            Section {
                Stepper(value: $timeoutSeconds, in: 10...FamiliarShellLimits.iOS.maximumTimeout, step: 10) {
                    LabeledContent(
                        String(localized: "settings.shell.timeout", defaultValue: "Command timeout"),
                        value: String(format: String(localized: "settings.shell.timeout.seconds", defaultValue: "%@ seconds"), NSNumber(value: Int(timeoutSeconds)))
                    )
                }
                Text(shellLimitsDetail)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "settings.shell.limits", defaultValue: "Limits"))
            } footer: {
                Text(String(localized: "settings.shell.timeout.footer", defaultValue: "This is both the default and the ceiling. The Agent may ask for less, never more."))
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
        .onChange(of: timeoutSeconds) { _, value in
            timeoutSettings.save(value, limits: FamiliarShellLimits.iOS)
        }
        .task {
            timeoutSeconds = timeoutSettings.timeout(limits: FamiliarShellLimits.iOS)
        }
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
        case .notPrepared:
            String(localized: "settings.shell.not_prepared", defaultValue: "Prepared when needed")
        case .unavailable:
            String(localized: "settings.shell.unavailable", defaultValue: "Runtime assets are not available in this build")
        case .preparing, .installing, .booting:
            String(localized: "settings.shell.preparing", defaultValue: "Preparing")
        case .ready, .running:
            String(localized: "settings.shell.ready", defaultValue: "Ready")
        case .failed(let message):
            String(format: String(localized: "settings.shell.failed", defaultValue: "Failed: %@"), message)
        }
    }

    /// Derived from `FamiliarShellLimits.iOS` rather than written as a literal: a
    /// hardcoded limits string silently drifts from what the executor enforces.
    private var shellLimitsDetail: String {
        let limits = FamiliarShellLimits.iOS
        return String(
            format: String(localized: "settings.shell.limits.detail", defaultValue: "%1$@ seconds · %2$@ processes · %3$@ output · %4$@ Workspace"),
            NSNumber(value: Int(limits.maximumTimeout)),
            NSNumber(value: limits.maximumProcessCount),
            ByteCountFormatter.string(fromByteCount: Int64(limits.maximumOutputBytes), countStyle: .file),
            ByteCountFormatter.string(fromByteCount: limits.maximumWorkspaceBytes, countStyle: .file)
        )
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

struct FamiliarSkillsSettingsView: View {
    @State private var importing = false
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
                        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                            Text(skill.name)
                            Text("\(skill.stableID) · \(skill.version)").font(FamiliarTypography.caption).foregroundStyle(.secondary)
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
                Menu {
                    Button(String(localized: "skills.create"), systemImage: "square.and.pencil") { creating = true }
                    Button(String(localized: "skills.import"), systemImage: "square.and.arrow.down") { importing = true }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel(String(localized: "settings.skills.add", defaultValue: "Add Skill"))
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, .zip, .plainText, .data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let store = FamiliarSkillPackageStore()
                let prepared = try store.prepare(url: url)
                let snapshot = try store.commit(prepared)
                try store.persistInstallation(snapshot, context: modelContext)
            } catch { errorMessage = error.localizedDescription }
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

struct FamiliarSkillEditorView: View {
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
                        format: String(localized: "settings.skills.create.identifier_hint", defaultValue: "Skill identifier: %@"),
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

/// `FamiliarExecutionBudget.normalized`, and a control that can express a value the
/// runtime silently rejects is a dead control.
struct FamiliarExecutionBudgetSettingsView: View {
    @Binding var budget: FamiliarExecutionBudget

    var body: some View {
        Form {
            Section {
                Stepper(value: $budget.maximumIterations, in: FamiliarExecutionBudget.iterationRange) {
                    LabeledContent(
                        String(localized: "settings.budget.iterations", defaultValue: "Maximum steps"),
                        value: "\(budget.maximumIterations)"
                    )
                }
                Stepper(value: $budget.maximumToolCalls, in: FamiliarExecutionBudget.toolCallRange, step: 4) {
                    LabeledContent(
                        String(localized: "settings.budget.tool_calls", defaultValue: "Maximum tool calls"),
                        value: "\(budget.maximumToolCalls)"
                    )
                }
                Stepper(value: $budget.maximumDuration, in: FamiliarExecutionBudget.durationRange, step: 60) {
                    LabeledContent(
                        String(localized: "settings.budget.duration", defaultValue: "Maximum run time"),
                        value: durationLabel
                    )
                }
            } header: {
                Text(String(localized: "settings.budget.title", defaultValue: "Execution Limits"))
            } footer: {
                Text(String(localized: "settings.budget.footer", defaultValue: "Applies to the next run. Reaching the tool-call limit does not fail the run: Familiar asks the model to answer from what it already has and states what it could not finish. Exceeding the run time fails the run with a real error."))
            }

            Section {
                Button(String(localized: "settings.budget.restore", defaultValue: "Restore Defaults"), role: .destructive) {
                    budget = .defaultValue
                }
                .disabled(budget == .defaultValue)
            }
        }
        .navigationTitle(String(localized: "settings.budget.title", defaultValue: "Execution Limits"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var durationLabel: String {
        let minutes = Int((budget.maximumDuration / 60).rounded())
        return String(
            format: String(localized: "settings.budget.duration.minutes", defaultValue: "%@ min"),
            NSNumber(value: minutes)
        )
    }

}

/// Shows why a capability cannot be used right now. Reuses `availabilityReport()` so the
/// reasons shown here are the same ones the model is told, rather than a parallel query
/// that could drift from the runtime's own view.
struct FamiliarDiagnosticsSettingsView: View {
    let registry: FamiliarToolRegistry
    let runtimeStatus: FamiliarShellRuntimeStatus

    @State private var unavailable: [FamiliarUnavailableTool] = []
    @State private var availableCount = 0

    var body: some View {
        List {
            Section {
                LabeledContent(
                    String(localized: "settings.shell.title", defaultValue: "Shell Runtime"),
                    value: runtimeLabel
                )
                LabeledContent(
                    String(localized: "settings.diagnostics.tools_available", defaultValue: "Tools available now"),
                    value: "\(availableCount)"
                )
            } header: {
                Text(String(localized: "settings.diagnostics.runtime", defaultValue: "Runtime"))
            } footer: {
                Text(String(localized: "settings.diagnostics.runtime.footer", defaultValue: "Reading the Project environment receipt never needs the Linux runtime, so it keeps working even when the runtime failed to prepare."))
            }

            if unavailable.isEmpty {
                Section {
                    ContentUnavailableView(
                        String(localized: "settings.diagnostics.all_available", defaultValue: "Every capability is available"),
                        systemImage: "checkmark.seal"
                    )
                }
            } else {
                Section {
                    ForEach(unavailable, id: \.name) { tool in
                        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                            Text(FamiliarToolPresentationName.title(for: tool.name))
                            Text(tool.reason)
                                .font(FamiliarTypography.caption)
                                .foregroundStyle(.secondary)
                            Text(tool.name)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text(String(format: String(localized: "settings.diagnostics.unavailable", defaultValue: "%@ unavailable"), NSNumber(value: unavailable.count)))
                } footer: {
                    Text(String(localized: "settings.diagnostics.unavailable.footer", defaultValue: "Familiar tells the model these capabilities are unavailable and why, so it reports what it cannot do instead of guessing another way."))
                }
            }
        }
        .navigationTitle(String(localized: "settings.diagnostics.title", defaultValue: "Diagnostics"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let report = await registry.availabilityReport()
            availableCount = report.manifests.count
            unavailable = report.unavailable
        }
    }

    private var runtimeLabel: String {
        switch runtimeStatus.phase {
        case .notPrepared:
            String(localized: "settings.shell.not_prepared", defaultValue: "Prepared when needed")
        case .unavailable:
            String(localized: "settings.shell.unavailable", defaultValue: "Unavailable")
        case .preparing, .installing, .booting:
            String(localized: "settings.shell.preparing", defaultValue: "Preparing")
        case .ready, .running:
            String(localized: "settings.shell.ready", defaultValue: "Ready")
        case .failed(let message):
            String(format: String(localized: "settings.shell.failed", defaultValue: "Failed: %@"), message)
        }
    }
}

struct FamiliarToolsSettingsView: View {
    struct Entry: Identifiable, Sendable {
        let manifest: FamiliarToolManifest
        let availability: FamiliarCapabilityAvailability
        var id: String { manifest.name }
    }

    let registry: FamiliarToolRegistry
    @State private var entries: [Entry] = []

    var body: some View {
        List {
            // Grouped by the same explicit table the Project Capabilities screen uses, so the
            // two screens cannot disagree about where a tool belongs.
            ForEach(orderedCategories, id: \.self) { category in
                let group = entries.filter { FamiliarToolGroup.group(for: $0.manifest.name) == category }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { entry in
                            Label {
                                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                                    Text(FamiliarToolPresentationName.title(for: entry.manifest.name))
                                    Text("\(executionClassLabel(entry.manifest.executionClass)) · \(availabilityLabel(entry.availability))")
                                        .font(FamiliarTypography.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: FamiliarToolPresentation.symbol(for: entry.manifest.name))
                            }
                        }
                    } header: {
                        Text(category.title)
                    } footer: {
                        // Only under the last group, so the explanation appears once rather
                        // than repeating under every category.
                        if category == orderedCategories.last {
                            Text(String(localized: "settings.tools.registered.footer", defaultValue: "This read-only list shows each registered tool's execution class and current system-capability availability."))
                        }
                    }
                }
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

    /// Categories that actually have tools, in the enum's declaration order. Deriving the
    /// order from the enum rather than from the registry keeps the screen from reshuffling
    /// between launches, and it also gives the footer a single stable last section.
    private var orderedCategories: [FamiliarToolGroup] {
        FamiliarToolGroup.allCases.filter { category in
            entries.contains { FamiliarToolGroup.group(for: $0.manifest.name) == category }
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
