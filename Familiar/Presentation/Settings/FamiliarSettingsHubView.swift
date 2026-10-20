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


nonisolated enum FamiliarSettingsRoute: String, Hashable, CaseIterable {
    case profile
    case mcp
    case voice
    case appLock
    case modelGroups
    case modelService
    case searchService
    case pythonPackageSource
    case appearance
    case tools
    case executionBudget
    case memory
    case diagnostics
    case shellRuntime
    case authorizations
    case skills
    case soul
    case storage
    case permissions
    case runHistory
    case dataHandling
    case about
}

struct FamiliarSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let isRootTab: Bool
    let initialSettings: FamiliarSettings
    let initialRoute: FamiliarSettingsRoute?
    let registry: FamiliarToolRegistry
    let searchService: FamiliarWebSearchService
    let pythonPackageSourceSettings: FamiliarPythonPackageSourceSettingsStore
    let workspaceStore: FamiliarWorkspaceStore
    let workspaceID: FamiliarWorkScope?
    let shellRuntimeStatus: FamiliarShellRuntimeStatus
    let onSaveSettings: (FamiliarSettings) -> FamiliarSettings

    @State private var settings: FamiliarSettings
    @State private var searchDestination: FamiliarSettingsRoute?
    @State private var searching = false
    @State private var editingProfile = false
    @State private var profileMotion = FamiliarProfileMotionAnchor()
    @AppStorage("familiar.local-profile") private var profileData = Data()
    @State private var path: [FamiliarSettingsRoute]

    init(
        initialSettings: FamiliarSettings,
        initialRoute: FamiliarSettingsRoute? = nil,
        registry: FamiliarToolRegistry,
        searchService: FamiliarWebSearchService,
        pythonPackageSourceSettings: FamiliarPythonPackageSourceSettingsStore,
        workspaceStore: FamiliarWorkspaceStore,
        workspaceID: FamiliarWorkScope?,
        shellRuntimeStatus: FamiliarShellRuntimeStatus,
        onSaveSettings: @escaping (FamiliarSettings) -> FamiliarSettings,
        isRootTab: Bool = false
    ) {
        self.isRootTab = isRootTab
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
                FamiliarLocalProfileSection(editing: $editingProfile, motionAnchor: profileMotion)
                ForEach(FamiliarSettingsCatalog.groups, id: \.self) { group in
                    Section {
                        ForEach(FamiliarSettingsCatalog.entries.filter { $0.groupKey == group && $0.route != .profile }) { entry in
                            entryLink(entry)
                        }
                    }.accessibilityLabel(String(localized: String.LocalizationValue(group)))
                }
            }
            .background { FamiliarProfileHeaderMotion(profile: .read(profileData), anchor: profileMotion).allowsHitTesting(false) }
            .listStyle(.insetGrouped)
            .listSectionSpacing(24)
            .environment(\.defaultMinListRowHeight, 44)
            .navigationTitle(isRootTab ? "" : String(localized: "drawer.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { searching = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel(String(localized: "settings.search.local"))
                        .accessibilityIdentifier("settings.search.open")
                    Button(String(localized: "common.edit")) { editingProfile = true }.disabled(searching)
                }
                if !isRootTab { ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done", defaultValue: "Done")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                } }
            }
            .navigationDestination(for: FamiliarSettingsRoute.self, destination: destination)
        }
        .sheet(isPresented: $searching, onDismiss: {
            if let route = searchDestination { searchDestination = nil; path.append(route) }
        }) {
            FamiliarSettingsSearchPage { route in searchDestination = route; searching = false }
        }
        .tint(FamiliarTheme.accent)
        .onChange(of: initialSettings) { _, value in if settings != value { settings = value } }
    }

    private func entryLink(_ entry: FamiliarSettingsEntry) -> some View {
        NavigationLink(value: entry.route) { FamiliarSettingsCatalogRow(entry: entry, status: status(entry.route)) }
            .listRowInsets(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
            .accessibilityIdentifier("settings.route." + entry.route.rawValue)
            .accessibilityLabel(entry.title).accessibilityValue(status(entry.route))
            .accessibilityHint(entry.detail)
    }

    private func status(_ route: FamiliarSettingsRoute) -> String {
        switch route {
        case .modelService: settings.selectedProvider.displayName + " · " + settings.selectedModel.displayName
        case .memory: String(localized: settings.isAutomaticMemoryEnabled ? "settings.state.on" : "settings.state.off")
        case .searchService: FamiliarSearchProviderCatalog.descriptor(for: searchService.settingsStore.selectedProviderID)?.displayName ?? "DuckDuckGo"
        case .pythonPackageSource: pythonPackageSourceSettings.selectedSource.displayName
        case .appearance: FamiliarAppearancePreference.current.localizedTitle
        case .executionBudget: executionBudgetSubtitle
        case .about: appVersion
        default: ""
        }
    }

    @ViewBuilder
    private func destination(_ route: FamiliarSettingsRoute) -> some View {
        switch route {
        case .profile: FamiliarLocalProfileDestination()
        case .modelGroups:
            FamiliarModelGroupsView(settings: settings) { value in
                settings = onSaveSettings(value)
            }
        case .appLock:
            FamiliarAppLockSettingsView()
        case .voice:
            FamiliarVoiceSettingsView()
        case .mcp:
            FamiliarMCPSettingsView()
        case .modelService:
            FamiliarModelServiceSettingsView(
                initialSettings: settings,
                onSaveSettings: { value in
                    settings = onSaveSettings(value)
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
        case .executionBudget:
            FamiliarExecutionBudgetSettingsView(budget: immediateBinding(\.executionBudget))
        case .memory:
            FamiliarMemorySettingsView(isAutomaticMemoryEnabled: immediateBinding(\.isAutomaticMemoryEnabled))
        case .diagnostics:
            FamiliarDiagnosticsSettingsView(
                registry: registry,
                runtimeStatus: shellRuntimeStatus
            )
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
            FamiliarSoulSettingsView(systemPrompt: immediateBinding(\.systemPrompt))
        case .storage:
            FamiliarStorageSettingsView()
        case .permissions:
            FamiliarPermissionsSettingsView()
        case .runHistory:
            FamiliarRunHistoryView()
        case .dataHandling:
            FamiliarPrivacySettingsView()
        case .about:
            FamiliarAboutView()
        }
    }

    /// Second-level editors apply immediately: every change persists through the
    /// same save path the Done button uses, so no edit depends on leaving the page.
    private func immediateBinding<Value>(_ keyPath: WritableKeyPath<FamiliarSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var updated = settings
                updated[keyPath: keyPath] = value
                settings = onSaveSettings(updated)
            }
        )
    }

    private var executionBudgetSubtitle: String {
        let budget = settings.executionBudget.normalized
        return String(
            format: String(localized: "settings.budget.detail", defaultValue: "%1$@ steps · %2$@ tool calls · %3$@ min"),
            NSNumber(value: budget.maximumIterations),
            NSNumber(value: budget.maximumToolCalls),
            NSNumber(value: Int((budget.maximumDuration / 60).rounded()))
        )
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return String(format: String(localized: "settings.about.version", defaultValue: "Version %@ (%@)"), version, build)
    }
}


private struct FamiliarSettingsSearchPage: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (FamiliarSettingsRoute) -> Void
    @State private var query = ""
    @State private var active = true

    var body: some View {
        NavigationStack {
            List {
                let results = FamiliarSettingsCatalog.entries.filter { $0.matches(query) }
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if results.isEmpty { ContentUnavailableView.search(text: query) }
                    ForEach(results) { entry in
                        Button { onSelect(entry.route) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                FamiliarSettingsCatalogRow(entry: entry, status: "")
                                Text(entry.path).font(.caption).foregroundStyle(.secondary)
                                if entry.detail != entry.title { Text(entry.detail).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.search." + entry.route.rawValue)
                    }
                }
            }
            .navigationTitle(String(localized: "settings.search.local"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $active,
                placement: .navigationBarDrawer(displayMode: .always), prompt: String(localized: "settings.search.local"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { FamiliarDismissButton() } }
        }
        .onChange(of: active) { _, value in if !value { dismiss() } }
    }
}
