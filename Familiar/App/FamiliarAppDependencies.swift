import Foundation

@MainActor
struct FamiliarAppDependencies {
    let registry: FamiliarToolRegistry
    let policy: FamiliarExecutionPolicy
    let confirmationCoordinator: FamiliarToolConfirmationCoordinator
    let undoStore: FamiliarUndoStore

    init() {
        let eventKit = FamiliarEventKitService()
        let web = FamiliarWebContentService()
        confirmationCoordinator = FamiliarToolConfirmationCoordinator()
        policy = FamiliarExecutionPolicy()
        undoStore = FamiliarUndoStore()
        do {
            registry = try FamiliarToolRegistry(
                tools: [
                    AnyFamiliarTool(FamiliarCurrentDateTimeTool()),
                    AnyFamiliarTool(FamiliarAppInformationTool()),
                    AnyFamiliarTool(FamiliarWebSearchTool(service: web)),
                    AnyFamiliarTool(FamiliarWebFetchTool(service: web)),
                    AnyFamiliarTool(FamiliarArtifactWriteTool(store: FamiliarArtifactStore())),
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

    func makeRuntime(for descriptor: FamiliarProviderDescriptor) -> FamiliarAgentLoop {
        FamiliarAgentLoop(
            provider: FamiliarProviderFactory.makeProvider(for: descriptor),
            registry: registry,
            policy: policy,
            confirmationCoordinator: confirmationCoordinator,
            undoStore: undoStore
        )
    }
}
