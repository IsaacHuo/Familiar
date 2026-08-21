import Foundation

@MainActor
struct FamiliarAppDependencies {
    let registry: FamiliarToolRegistry
    let policy: FamiliarExecutionPolicy
    let confirmationCoordinator: FamiliarToolConfirmationCoordinator
    let clarificationCoordinator: FamiliarClarificationCoordinator
    let undoStore: FamiliarUndoStore
    let eventKit: FamiliarEventKitService
    let searchService: FamiliarWebSearchService
    let visionProcessor = FamiliarVisionProcessor()
    let localVision = FamiliarLocalVisionModelManager.shared
    let sessionID = UUID().uuidString

    init() {
        eventKit = FamiliarEventKitService()
        let web = FamiliarWebContentService()
        searchService = FamiliarWebSearchService()
        confirmationCoordinator = FamiliarToolConfirmationCoordinator()
        clarificationCoordinator = FamiliarClarificationCoordinator()
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
                capabilities: eventKit
            )
        } catch {
            preconditionFailure("无法创建工具注册表：\(error.localizedDescription)")
        }
    }

    func makeRuntime(for descriptor: FamiliarProviderDescriptor, authorizationRuntime: (any FamiliarAuthorizationServicing)? = nil) -> FamiliarAgentLoop {
        FamiliarAgentLoop(
            provider: FamiliarProviderFactory.makeProvider(for: descriptor),
            registry: registry,
            policy: policy,
            confirmationCoordinator: confirmationCoordinator,
            clarificationCoordinator: clarificationCoordinator,
            undoStore: undoStore,
            authorizationRuntime: authorizationRuntime
        )
    }
}
