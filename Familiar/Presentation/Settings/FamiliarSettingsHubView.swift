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

    let initialSettings: FamiliarSettings
    let initialRoute: FamiliarSettingsRoute?
    let registry: FamiliarToolRegistry
    let searchService: FamiliarWebSearchService
    let pythonPackageSourceSettings: FamiliarPythonPackageSourceSettingsStore
    let workspaceStore: FamiliarWorkspaceStore
    let workspaceID: FamiliarWorkScope?
    let shellRuntimeStatus: FamiliarShellRuntimeStatus
    let onSaveSettings: (FamiliarSettings) -> Void

    /// Scaled so the row icon container grows with the label beside it. A fixed 28pt box
    /// next to text that scales would leave the glyph visually detached at larger sizes.
    @ScaledMetric(relativeTo: .body) private var rowIconSize: CGFloat = FamiliarIconSize.standard
    @ScaledMetric(relativeTo: .body) private var rowIconContainer: CGFloat = FamiliarControlSize.compactVisual

    @State private var settings: FamiliarSettings
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
                Section(String(localized: "settings.hub.models")) {
                    settingsLink(.modelService, title: String(localized: "settings.hub.model_service"),
                                 subtitle: "\(settings.selectedProvider.displayName) · \(settings.selectedModel.displayName)",
                                 symbol: "key.horizontal.fill", color: FamiliarTheme.accent)
                    settingsLink(.modelGroups, title: String(localized: "group.title"), subtitle: String(localized: "group.detail"), symbol: "square.stack", color: .blue)
                }
                Section(String(localized: "settings.hub.personalization")) {
                    settingsLink(.soul, title: String(localized: "settings.hub.soul"), subtitle: String(localized: "settings.hub.soul.detail"), symbol: "sparkles", color: .pink)
                    settingsLink(.memory, title: String(localized: "settings.memory.title"),
                                 subtitle: settings.isAutomaticMemoryEnabled ? String(localized: "settings.hub.memory.detail") : String(localized: "settings.memory.detail.off"),
                                 symbol: "brain", color: .pink)
                    settingsLink(.voice, title: String(localized: "voice.title"), subtitle: String(localized: "voice.providers"), symbol: "waveform", color: .blue)
                }
                Section(String(localized: "settings.hub.capabilities")) {
                    settingsLink(.searchService, title: String(localized: "settings.search.title"),
                                 subtitle: FamiliarSearchProviderCatalog.descriptor(for: searchService.settingsStore.selectedProviderID)?.displayName ?? "DuckDuckGo",
                                 symbol: "magnifyingglass", color: .blue)
                    settingsLink(.skills, title: String(localized: "settings.skills.title"), subtitle: String(localized: "settings.skills.detail"), symbol: "wand.and.stars", color: .purple)
                    settingsLink(.mcp, title: String(localized: "mcp.title"), subtitle: String(localized: "mcp.settings.detail"), symbol: "wrench.and.screwdriver", color: .blue)
                    settingsLink(.tools, title: String(localized: "settings.hub.tools"), subtitle: String(localized: "settings.hub.tools.detail"), symbol: "puzzlepiece.extension.fill", color: .blue)
                    settingsLink(.executionBudget, title: String(localized: "settings.budget.title"), subtitle: executionBudgetSubtitle, symbol: "gauge.with.needle", color: .purple)
                    settingsLink(.shellRuntime, title: String(localized: "settings.shell.title"), subtitle: String(localized: "settings.shell.detail"), symbol: "shippingbox", color: .gray)
                    settingsLink(.pythonPackageSource, title: String(localized: "settings.python_source.title"), subtitle: pythonPackageSourceSettings.selectedSource.displayName, symbol: "shippingbox.fill", color: .orange)
                }
                Section(String(localized: "settings.hub.interface")) {
                    settingsLink(.appearance, title: String(localized: "settings.hub.appearance"), subtitle: FamiliarAppearancePreference.current.localizedTitle, symbol: "paintbrush.fill", color: .indigo)
                }
                Section(String(localized: "settings.privacy.title")) {
                    settingsLink(.permissions, title: String(localized: "settings.hub.permissions"), subtitle: String(localized: "settings.hub.permissions.detail"), symbol: "hand.raised.fill", color: .orange)
                    settingsLink(.authorizations, title: String(localized: "settings.hub.authorizations"), subtitle: String(localized: "settings.hub.authorizations.detail"), symbol: "checkmark.shield.fill", color: .green)
                    settingsLink(.appLock, title: String(localized: "lock.setting"), subtitle: String(localized: "lock.footer"), symbol: "lock", color: .blue)
                    settingsLink(.storage, title: String(localized: "settings.hub.storage"), subtitle: String(localized: "settings.hub.storage.detail"), symbol: "internaldrive.fill", color: .blue)
                    settingsLink(.dataHandling, title: String(localized: "settings.privacy.data_handling"), subtitle: String(localized: "settings.hub.privacy.detail"), symbol: "hand.raised.square.fill", color: .cyan)
                }
                Section(String(localized: "settings.hub.support")) {
                    settingsLink(.about, title: String(localized: "settings.hub.about"), subtitle: appVersion, symbol: "info.circle.fill", color: .indigo)
                }
                Section(String(localized: "settings.developer", defaultValue: "Developer")) {
                    settingsLink(.runHistory, title: String(localized: "settings.hub.run_history"), subtitle: String(localized: "settings.hub.run_history.detail"), symbol: "clock.arrow.circlepath", color: .gray)
                    settingsLink(.diagnostics, title: String(localized: "settings.diagnostics.title"), subtitle: String(localized: "settings.diagnostics.detail"), symbol: "stethoscope", color: .teal)
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
                    .font(.system(size: rowIconSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: rowIconContainer, height: rowIconContainer)
                    .background(
                        color.gradient,
                        in: RoundedRectangle(cornerRadius: FamiliarRadius.compact, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                    HStack(spacing: FamiliarSpacing.small) {
                        Text(title).font(FamiliarTypography.body)
                        if let badge {
                            Text(badge)
                                .font(FamiliarTypography.caption.weight(.semibold))
                                .foregroundStyle(FamiliarTheme.accent)
                        }
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(FamiliarTypography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
        }
        .accessibilityIdentifier("settings.route.\(route.rawValue)")
        .accessibilityLabel(title)
        .accessibilityValue(badge ?? subtitle)
    }

    @ViewBuilder
    private func destination(_ route: FamiliarSettingsRoute) -> some View {
        switch route {
        case .modelGroups:
            FamiliarModelGroupsView(settings: settings) { value in
                settings = value; onSaveSettings(value)
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
                settings = updated
                onSaveSettings(updated)
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
