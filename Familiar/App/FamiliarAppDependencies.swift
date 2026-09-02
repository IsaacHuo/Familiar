import Foundation

@MainActor
struct FamiliarAppDependencies {
    let registry: FamiliarToolRegistry
    let policy: FamiliarExecutionPolicy
    let confirmationCoordinator: FamiliarToolConfirmationCoordinator
    let clarificationCoordinator: FamiliarClarificationCoordinator
    let modelEscalationCoordinator: FamiliarModelEscalationCoordinator
    let undoStore: FamiliarUndoStore
    let eventKit: FamiliarEventKitService
    let contacts: FamiliarContactsService
    let location: FamiliarLocationService
    let map: FamiliarMapService
    let weather: FamiliarWeatherService
    let photoLibrary: FamiliarPhotoLibraryService
    let health: FamiliarHealthService
    let music: FamiliarMusicService
    let naturalLanguage: FamiliarNaturalLanguageService
    let bluetooth: FamiliarBluetoothService
    let alarm: FamiliarAlarmService
    let clipboard: FamiliarClipboardService
    let searchService: FamiliarWebSearchService
    let pythonPackageSourceSettings: FamiliarPythonPackageSourceSettingsStore
    let workspaceStore: FamiliarWorkspaceStore
    let shellRuntimeStatus: FamiliarShellRuntimeStatus
    let visionProcessor = FamiliarVisionProcessor()
    let sessionID = UUID().uuidString

    init() {
        eventKit = FamiliarEventKitService()
        contacts = FamiliarContactsService()
        location = FamiliarLocationService()
        map = FamiliarMapService()
        weather = FamiliarWeatherService()
        photoLibrary = FamiliarPhotoLibraryService()
        health = FamiliarHealthService()
        music = FamiliarMusicService()
        naturalLanguage = FamiliarNaturalLanguageService()
        bluetooth = FamiliarBluetoothService()
        alarm = FamiliarAlarmService()
        clipboard = FamiliarClipboardService()
        let web = FamiliarWebContentService()
        searchService = FamiliarWebSearchService()
        pythonPackageSourceSettings = FamiliarPythonPackageSourceSettingsStore()
        workspaceStore = FamiliarWorkspaceStore()
        confirmationCoordinator = FamiliarToolConfirmationCoordinator()
        clarificationCoordinator = FamiliarClarificationCoordinator()
        modelEscalationCoordinator = FamiliarModelEscalationCoordinator()
        policy = FamiliarExecutionPolicy()
        undoStore = FamiliarUndoStore()
        let outputResolver = FamiliarWorkspaceOutputResolver(store: workspaceStore)
        let shellRuntime = Self.makeShellRuntime(workspaceStore: workspaceStore)
        shellRuntimeStatus = FamiliarShellRuntimeStatus(
            phase: shellRuntime == nil ? .unavailable : .preparing
        )
        do {
            let tools: [AnyFamiliarTool] = [
                AnyFamiliarTool(FamiliarCurrentDateTimeTool()),
                AnyFamiliarTool(FamiliarAppInformationTool()),
                AnyFamiliarTool(FamiliarMapSearchTool(service: map)),
                AnyFamiliarTool(FamiliarWeatherForecastTool(service: weather)),
                AnyFamiliarTool(FamiliarWeatherHistoryTool(service: weather)),
                AnyFamiliarTool(FamiliarNaturalLanguageAnalyzeTool(service: naturalLanguage)),
                AnyFamiliarTool(FamiliarHealthActivitySummaryTool(service: health)),
                AnyFamiliarTool(FamiliarMusicCatalogSearchTool(service: music)),
                AnyFamiliarTool(FamiliarBluetoothScanTool(service: bluetooth)),
                AnyFamiliarTool(FamiliarScheduleNotificationTool()),
                AnyFamiliarTool(FamiliarAlarmScheduleTool(service: alarm)),
                AnyFamiliarTool(FamiliarAlarmCancelTool(service: alarm)),
                AnyFamiliarTool(FamiliarAlarmListTool(service: alarm)),
                AnyFamiliarTool(FamiliarWebSearchTool(service: searchService)),
                AnyFamiliarTool(FamiliarWebFetchTool(service: web)),
                AnyFamiliarTool(FamiliarResourceListTool()),
                AnyFamiliarTool(FamiliarResourceReadTool()),
                AnyFamiliarTool(FamiliarResourceSearchTool()),
                AnyFamiliarTool(FamiliarWorkspaceListTool(store: workspaceStore)),
                AnyFamiliarTool(FamiliarWorkspaceReadTool(store: workspaceStore)),
                AnyFamiliarTool(FamiliarWorkspaceSearchTool(store: workspaceStore)),
                AnyFamiliarTool(FamiliarWorkspaceWriteTool(store: workspaceStore)),
                AnyFamiliarTool(FamiliarWorkspaceImageListTool(store: workspaceStore)),
                AnyFamiliarTool(FamiliarPhotosSaveOutputTool(resolver: outputResolver, photos: photoLibrary)),
                AnyFamiliarTool(FamiliarPhotosRecentMetadataTool(photos: photoLibrary)),
                AnyFamiliarTool(FamiliarPrepareFileExportTool(resolver: outputResolver)),
                AnyFamiliarTool(FamiliarSpotlightSearchTool(indexer: .shared)),
                AnyFamiliarTool(FamiliarContactsSearchTool(service: contacts)),
                AnyFamiliarTool(FamiliarCurrentLocationTool(service: location)),
                AnyFamiliarTool(FamiliarClipboardReadTool(service: clipboard)),
                AnyFamiliarTool(FamiliarClipboardWriteTool(service: clipboard)),
                AnyFamiliarTool(FamiliarPrepareShareTool()),
                AnyFamiliarTool(FamiliarTaskPlanTool()),
                AnyFamiliarTool(FamiliarPresentRecommendationTool()),
                AnyFamiliarTool(FamiliarPresentInsightTool()),
                AnyFamiliarTool(FamiliarAskUserTool()),
                AnyFamiliarTool(FamiliarMemorySearchTool()),
                AnyFamiliarTool(FamiliarMemoryRememberTool()),
                AnyFamiliarTool(FamiliarSkillListTool()),
                AnyFamiliarTool(FamiliarSkillReadTool()),
                AnyFamiliarTool(FamiliarArtifactWriteTool(store: FamiliarArtifactStore())),
                AnyFamiliarTool(FamiliarArtifactEditTool(store: FamiliarArtifactStore())),
                AnyFamiliarTool(FamiliarArtifactReadTool(store: FamiliarArtifactStore())),
                AnyFamiliarTool(FamiliarArtifactPublishTool(workspaceStore: workspaceStore)),
                AnyFamiliarTool(FamiliarEnvironmentStatusTool(workspaceStore: workspaceStore)),
                AnyFamiliarTool(FamiliarCalendarEventsTool(service: eventKit)),
                AnyFamiliarTool(FamiliarCreateCalendarEventTool(service: eventKit)),
                AnyFamiliarTool(FamiliarUpdateCalendarEventTool(service: eventKit)),
                AnyFamiliarTool(FamiliarDeleteCalendarEventTool(service: eventKit)),
                AnyFamiliarTool(FamiliarRemindersTool(service: eventKit)),
                AnyFamiliarTool(FamiliarCreateReminderTool(service: eventKit)),
                AnyFamiliarTool(FamiliarUpdateReminderTool(service: eventKit)),
                AnyFamiliarTool(FamiliarDeleteReminderTool(service: eventKit))
            ]
            registry = try FamiliarToolRegistry(
                tools: tools,
                capabilities: FamiliarDeviceCapabilityProvider(
                    eventKit: eventKit,
                    contacts: contacts,
                    location: location,
                    photos: photoLibrary,
                    health: health,
                    music: music,
                    bluetooth: bluetooth,
                    alarm: alarm
                )
            )
        } catch {
            preconditionFailure("无法创建工具注册表：\(error.localizedDescription)")
        }
        if let shellRuntime {
            let registry = registry
            let status = shellRuntimeStatus
            let runtimeWorkspaceStore = workspaceStore
            let runtimePackageSourceSettings = pythonPackageSourceSettings
            let prepareRuntime: @MainActor @Sendable () -> Void = {
                Task {
                    do {
                        try await shellRuntime.executor.prepare()
                        try await registry.registerIfAbsent(AnyFamiliarTool(
                            FamiliarEnvironmentPrepareTool(
                                executor: shellRuntime.executor,
                                workspaceStore: runtimeWorkspaceStore,
                                packageSourceSettings: runtimePackageSourceSettings
                            )
                        ))
                        try await registry.registerIfAbsent(shellRuntime.tool)
                        status.markReady()
                    } catch {
                        status.markFailed(error.localizedDescription)
                    }
                }
            }
            status.configureRetry(prepareRuntime)
            prepareRuntime()
        }
    }

    private static func makeShellRuntime(
        workspaceStore: FamiliarWorkspaceStore
    ) -> (tool: AnyFamiliarTool, executor: FamiliarISHShellExecutor)? {
#if canImport(FamiliarISHRuntime)
        guard FamiliarRealISHBridge.isBundledRuntimeAvailable else { return nil }
        let bridge = FamiliarRealISHBridge()
        let executor = FamiliarISHShellExecutor(bridge: bridge, workspaceStore: workspaceStore)
        return (
            AnyFamiliarTool(FamiliarShellTool(executor: executor, workspaceStore: workspaceStore)),
            executor
        )
#else
        return nil
#endif
    }

    func makeRuntime(
        for descriptor: FamiliarProviderDescriptor,
        apiKey: String,
        routePolicy: FamiliarModelRoutePolicy,
        budget: FamiliarExecutionBudget = .defaultValue,
        authorizationRuntime: (any FamiliarAuthorizationServicing)? = nil
    ) -> FamiliarAgentLoop {
        let normalized = budget.normalized
        let cloudProvider = FamiliarProviderFactory.makeProvider(for: descriptor, apiKey: apiKey)
        let router = FamiliarModelRouter(
            policy: routePolicy,
            cloudProvider: cloudProvider,
            authorizeCloudEscalation: { request in
                await modelEscalationCoordinator.requestApproval(request)
            }
        )
        return FamiliarAgentLoop(
            provider: router,
            registry: registry,
            policy: policy,
            confirmationCoordinator: confirmationCoordinator,
            clarificationCoordinator: clarificationCoordinator,
            undoStore: undoStore,
            authorizationRuntime: authorizationRuntime,
            maximumIterations: normalized.maximumIterations,
            maximumToolCalls: normalized.maximumToolCalls,
            maximumDuration: normalized.maximumDuration
        )
    }
}
