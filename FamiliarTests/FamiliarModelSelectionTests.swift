import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Effective models and default delivery", .serialized)
struct FamiliarModelSelectionTests {
    @Test("Project selection drives both the displayed choice and frozen request")
    @MainActor
    func effectiveProjectSelection() throws {
        let container = try FamiliarTestStore.make(name: "EffectiveProjectModel")
        let project = FamiliarProject(name: "Models")
        container.mainContext.insert(project)
        let controller = FamiliarChatController(dependencies: .init())
        controller.settings = .defaultValue
        controller.selectedProjectID = project.id
        let provider = try #require(FamiliarProviderCatalog.builtIn.first { $0.curatedModels.count > 1 })
        let first = provider.curatedModels[0]
        let second = provider.curatedModels[1]
        controller.settings.providerID = provider.id
        controller.settings.modelID = first.id
        try FamiliarProjectService().updateModelOverride(project, modelID: second.id, providerID: provider.id, in: container.mainContext)
        let effective = controller.effectiveSettings(for: project)
        #expect(effective.selectedModel.id == second.id)
        let snapshot = try FamiliarContextCompiler.assemble(seed: .init(projectID: project.id, projectName: project.name,
            conversationID: UUID(), projectInstruction: nil, resources: []), settings: effective, messages: [], toolManifests: [])
        #expect(snapshot.modelID == effective.selectedModel.id)
        #expect(snapshot.providerID == effective.selectedProvider.id)
        controller.selectModel(providerID: provider.id, modelID: second.id, in: container.mainContext)
        #expect(controller.settings.modelID == first.id)
        #expect(project.modelIDOverride == second.id)
        controller.selectModel(providerID: provider.id, modelID: first.id, in: container.mainContext)
        #expect(project.modelIDOverride == first.id)
        #expect(controller.effectiveSettings(for: project).modelID == first.id)
        #expect(controller.settings.modelID == first.id)
        controller.followDefaultModel(in: container.mainContext)
        #expect(project.modelIDOverride == nil)
        #expect(project.providerIDOverride == nil)
        #expect(controller.effectiveSettings(for: project) == controller.settings)
    }

    @Test("Opening old history does not replace the user's default model with past execution metadata")
    @MainActor
    func historyDoesNotSelectOldModel() throws {
        let container = try FamiliarTestStore.make(name: "ModelHistorySelection")
        let project = FamiliarProject(name: "History")
        let chat = FamiliarConversation(currentProviderID: "historical-member", currentModelID: "historical-model", project: project)
        container.mainContext.insert(project)
        container.mainContext.insert(chat)
        try container.mainContext.save()
        let controller = FamiliarChatController(dependencies: .init())
        controller.settings = .defaultValue
        let baseline = controller.settings
        controller.select(chat.id, in: container.mainContext)
        #expect(controller.settings == baseline)
        #expect(controller.effectiveSettings(for: project) == baseline)
        project.modelIDOverride = "removed-model"
        project.providerIDOverride = "removed-provider"
        #expect(controller.effectiveSettings(for: project) == baseline)
    }

    @Test("Requested selection and actual member attempts remain distinct; missing usage stays unknown")
    @MainActor
    func modelAndUsagePersistence() throws {
        let container = try FamiliarTestStore.make(name: "ModelUsagePersistence")
        let context = container.mainContext
        let chat = FamiliarConversation()
        context.insert(chat)
        try context.save()
        var settings = FamiliarSettings.defaultValue
        settings.modelID = "requested-group-model"
        let snapshot = try FamiliarContextCompiler.assemble(seed: .init(projectID: nil, projectName: nil,
            conversationID: chat.id, projectInstruction: nil, resources: []), settings: settings, messages: [], toolManifests: [])
        let recorder = FamiliarRunPersistenceRecorder()
        recorder.ensureRun(runtimeID: "models", snapshot: snapshot, startedAt: Date(), context: context)
        let first = FamiliarModelReference(providerID: "member-a", modelID: "model-a")
        let fallback = FamiliarModelReference(providerID: "member-b", modelID: "model-b")
        try recorder.recordModelSelection(first, runtimeID: "models", context: context)
        try recorder.recordModelSelection(fallback, runtimeID: "models", context: context)
        try recorder.recordUsage(.init(inputTokens: nil, outputTokens: 9, cachedInputTokens: 0), runtimeID: "models", context: context)
        let run = try #require(chat.agentRuns.first)
        #expect(run.contextSnapshot?.modelID == "requested-group-model")
        let requests = try JSONDecoder().decode([FamiliarModelReference].self, from: Data((run.modelRequestsJSON ?? "").utf8))
        #expect(requests == [first, fallback])
        #expect(run.inputTokenCount == nil)
        #expect(run.outputTokenCount == 9)
        #expect(run.cachedInputTokenCount == 0)
        try recorder.recordUsage(.init(inputTokens: 4, outputTokens: 5, cachedInputTokens: nil), runtimeID: "models", context: context)
        #expect(run.inputTokenCount == 4)
        #expect(run.outputTokenCount == 14)
        #expect(run.cachedInputTokenCount == 0)
        run.modelRequestsJSON = "damaged"
        try context.save()
        #expect(throws: DecodingError.self) { try recorder.recordModelSelection(first, runtimeID: "models", context: context) }
        #expect(run.modelRequestsJSON == "damaged")
    }

    @Test("Group and member adapter report one member selection, not a duplicate identity")
    func groupSelectionIsNotDuplicated() async throws {
        let provider = FamiliarGroupModelProvider(providerID: "group", members: [
            .init(provider: FamiliarSelectionFixtureProvider(), modelID: "member-model")
        ], strategy: "fallback", fallbackOnAnyError: false, sessionID: "chat")
        var selections: [FamiliarModelReference] = []
        for try await event in provider.stream(request: .init(model: "group", messages: [.user("Hi")], tools: [])) {
            if case .providerSelection(let providerID, let modelID) = event {
                selections.append(.init(providerID: providerID, modelID: modelID))
            }
        }
        #expect(selections == [.init(providerID: "member", modelID: "member-model")])
    }

    @Test("Automatic compaction retains every model selection and usage report in the same Run")
    func compactionMetadataIsRetained() async throws {
        let registry = try FamiliarToolRegistry(tools: [])
        let maximum = FamiliarSettings.defaultValue.selectedModel.capabilities.maximumInputCharacters
        let old = FamiliarMessageSnapshot(id: UUID(), role: .user, content: String(repeating: "h", count: maximum * 2),
            createdAt: Date(), sequence: 0, providerID: nil, modelID: nil, attachments: [])
        let pending = FamiliarMessageSnapshot(id: UUID(), role: .user, content: "Continue", createdAt: Date(), sequence: 1,
            providerID: nil, modelID: nil, attachments: [])
        let snapshot = try familiarTestContextSnapshot(messages: [old, pending])
        let loop = FamiliarAgentLoop(provider: FamiliarSelectionFixtureProvider(), registry: registry, policy: .init(),
            confirmationCoordinator: .init(), undoStore: .init())
        var events: [FamiliarRuntimeEvent] = []
        for try await event in loop.stream(contextSnapshot: snapshot) { events.append(event) }
        #expect(events.contains { if case .runPhaseChanged(.compactingContext) = $0.payload { true } else { false } })
        let selections = events.filter { if case .modelSelected = $0.payload { true } else { false } }
        let usage = events.compactMap { if case .usage(let value) = $0.payload { value } else { nil } }
        #expect(selections.count >= 2)
        #expect(usage.count == selections.count)
        #expect(usage.allSatisfy { $0.inputTokens == 4 && $0.outputTokens == 5 })
        #expect(Set(events.map(\.runID)).count == 1)
    }

    @Test("Default delivery scopes allow text output but exclude advanced execution")
    @MainActor
    func defaultOutputScope() throws {
        let container = try FamiliarTestStore.make(name: "DefaultOutputScope")
        let service = FamiliarProjectService()
        let project = try service.create(name: "Text outputs", in: container.mainContext)
        let names = ["file_write", "file_edit", "file_read", "file_publish", "workspace_write", "shell_execute", "environment_prepare"]
        let manifests = names.map { FamiliarToolManifest(name: $0, title: $0, description: "Fixture", parameters: .object([:]), effect: .read, risk: .low) }
        let defaults = try service.filterCapabilities(manifests, projectID: project.id, in: container.mainContext)
        #expect(Set(defaults.map(\.name)) == ["file_write", "file_edit", "file_read"])
        try service.setCapability("shell_execute", enabled: true, allCapabilities: manifests, projectID: project.id, in: container.mainContext)
        let enabled = try service.filterCapabilities(manifests, projectID: project.id, in: container.mainContext)
        #expect(enabled.map(\.name).contains("shell_execute"))
        #expect(!enabled.map(\.name).contains("file_publish"))
    }

    @Test("Text output cannot accept a complex format before approval or file writes", arguments: [FamiliarFileFormat.docx, .pdf, .xlsx])
    func unsupportedTextFormats(format: FamiliarFileFormat) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TextFormat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = FamiliarFileWriteTool(store: .init(rootURL: root))
        await #expect(throws: FamiliarFileError.self) {
            _ = try await tool.execute(.init(title: "Output", content: "Body", format: format), context: .init(runID: "run", toolCallID: "call", projectID: UUID()))
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("A default text output creates actual Markdown bytes after the action is approved")
    func defaultMarkdownBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DefaultMarkdown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarFileStore(rootURL: root)
        let result = try await FamiliarFileWriteTool(store: store).execute(.init(title: "Report", content: "# Body", format: nil),
            context: .init(runID: "run", toolCallID: "call", projectID: UUID()))
        guard case .action(let proposal) = result else { Issue.record("Expected approval proposal"); return }
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let committed = try await proposal.commit()
        let descriptor = try #require(committed.result.file)
        #expect(descriptor.format == .markdown)
        #expect(try store.read(relativePath: descriptor.relativePath) == Data("# Body".utf8))
    }
}

private nonisolated struct FamiliarSelectionFixtureProvider: FamiliarModelProvider {
    let providerID = "member"
    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.providerSelection(providerID: providerID, modelID: request.model))
            continuation.yield(.textDelta("A concise answer or summary."))
            continuation.yield(.usage(.init(inputTokens: 4, outputTokens: 5, cachedInputTokens: nil)))
            continuation.yield(.completed(.stop))
            continuation.finish()
        }
    }
}
