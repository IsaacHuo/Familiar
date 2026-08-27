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
    let clipboard: FamiliarClipboardService
    let searchService: FamiliarWebSearchService
    let workspaceStore: FamiliarWorkspaceStore
    let visionProcessor = FamiliarVisionProcessor()
    let sessionID = UUID().uuidString

    init() {
        eventKit = FamiliarEventKitService()
        contacts = FamiliarContactsService()
        location = FamiliarLocationService()
        clipboard = FamiliarClipboardService()
        let web = FamiliarWebContentService()
        searchService = FamiliarWebSearchService()
        workspaceStore = FamiliarWorkspaceStore()
        confirmationCoordinator = FamiliarToolConfirmationCoordinator()
        clarificationCoordinator = FamiliarClarificationCoordinator()
        modelEscalationCoordinator = FamiliarModelEscalationCoordinator()
        policy = FamiliarExecutionPolicy()
        undoStore = FamiliarUndoStore()
        do {
            registry = try FamiliarToolRegistry(
                tools: [
                    AnyFamiliarTool(FamiliarCurrentDateTimeTool()),
                    AnyFamiliarTool(FamiliarAppInformationTool()),
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
                    AnyFamiliarTool(FamiliarArtifactWriteTool(store: FamiliarArtifactStore())),
                    AnyFamiliarTool(FamiliarArtifactEditTool(store: FamiliarArtifactStore())),
                    AnyFamiliarTool(FamiliarCalendarEventsTool(service: eventKit)),
                    AnyFamiliarTool(FamiliarCreateCalendarEventTool(service: eventKit)),
                    AnyFamiliarTool(FamiliarRemindersTool(service: eventKit)),
                    AnyFamiliarTool(FamiliarCreateReminderTool(service: eventKit))
                ],
                capabilities: FamiliarDeviceCapabilityProvider(
                    eventKit: eventKit,
                    contacts: contacts,
                    location: location
                )
            )
        } catch {
            preconditionFailure("无法创建工具注册表：\(error.localizedDescription)")
        }
    }

    func makeRuntime(
        for descriptor: FamiliarProviderDescriptor,
        apiKey: String,
        routePolicy: FamiliarModelRoutePolicy,
        authorizationRuntime: (any FamiliarAuthorizationServicing)? = nil
    ) -> FamiliarAgentLoop {
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
            authorizationRuntime: authorizationRuntime
        )
    }
}
