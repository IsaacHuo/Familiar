import Foundation
import SwiftData
import Testing
@testable import Familiar

private actor FamiliarProjectRequestCapture {
    private(set) var systemPrompt: String?

    func record(_ request: FamiliarModelRequest) {
        systemPrompt = request.messages.first?.networkText
    }
}

private struct FamiliarProjectCapturingProvider: FamiliarModelProvider {
    let providerID = "project-capture"
    let capture: FamiliarProjectRequestCapture

    func stream(request: FamiliarModelRequest, apiKey: String) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await capture.record(request)
                continuation.yield(.textDelta("Captured"))
                continuation.yield(.completed(.stop))
                continuation.finish()
            }
        }
    }
}

@Suite("Familiar projects")
struct FamiliarProjectTests {
    @Test("Project CRUD normalizes fields and empty instruction removes its row")
    @MainActor
    func projectCRUDAndNormalization() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let service = FamiliarProjectService()
        let project = try service.create(
            name: "  " + String(repeating: "N", count: 90) + "  ",
            summary: "  " + String(repeating: "S", count: 510) + "  ",
            in: context
        )

        #expect(project.name.count == 80)
        #expect(project.summary.count == 500)
        #expect(project.status == .active)

        try service.updateInstruction(
            project,
            text: "  " + String(repeating: "I", count: 8_010) + "  ",
            in: context
        )
        #expect(project.instruction?.text.count == 8_000)
        #expect(try context.fetch(FetchDescriptor<FamiliarProjectInstruction>()).count == 1)

        try service.update(project, name: "  Renamed  ", summary: "  Summary  ", in: context)
        #expect(project.name == "Renamed")
        #expect(project.summary == "Summary")

        try service.updateInstruction(project, text: " \n ", in: context)
        #expect(project.instruction == nil)
        #expect(try context.fetch(FetchDescriptor<FamiliarProjectInstruction>()).isEmpty)
    }

    @Test("Project names are unique regardless of case or surrounding whitespace")
    @MainActor
    func projectNamesAreUnique() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let service = FamiliarProjectService()
        let first = try service.create(name: "Research", in: context)
        let second = try service.create(name: "Writing", in: context)

        #expect(throws: FamiliarProjectServiceError.duplicateName) {
            try service.create(name: "  research  ", in: context)
        }
        #expect(throws: FamiliarProjectServiceError.duplicateName) {
            try service.update(second, name: "RESEARCH", summary: "", in: context)
        }
        #expect(first.name == "Research")
        #expect(second.name == "Writing")
        #expect(try context.fetch(FetchDescriptor<FamiliarProject>()).count == 2)
    }

    @Test("Archive is always available while permanent deletion only blocks running runs")
    @MainActor
    func archiveAndEmptyDelete() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let service = FamiliarProjectService()
        let project = try service.create(name: "Project", in: context)
        try service.updateInstruction(project, text: "Keep project context", in: context)
        let conversation = FamiliarConversation(project: project)
        let running = FamiliarAgentRun(runtimeID: "running", project: project)
        context.insert(conversation)
        context.insert(running)
        try context.save()
        try FamiliarPinService().pin(.project, targetID: project.id, in: context)

        try service.setArchived(true, for: project, in: context)
        #expect(project.status == .archived)
        try service.setArchived(false, for: project, in: context)
        #expect(project.status == .active)
        #expect(throws: FamiliarProjectServiceError.self) {
            try service.permanentlyDelete(project, in: context)
        }

        running.status = .completed
        try context.save()
        try service.permanentlyDelete(project, in: context)
        #expect(try context.fetch(FetchDescriptor<FamiliarProject>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarProjectInstruction>()).isEmpty)
        #expect(try #require(context.fetch(FetchDescriptor<FamiliarAgentRun>()).first).project == nil)
        #expect(try #require(context.fetch(FetchDescriptor<FamiliarConversation>()).first).project == nil)
        #expect(try context.fetch(FetchDescriptor<FamiliarPinnedItemRecord>()).isEmpty)
    }

    @Test("Ordinary and project chats preserve distinct ownership")
    @MainActor
    func conversationOwnership() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let project = try FamiliarProjectService().create(name: "Owned", in: context)
        let controller = FamiliarChatController(dependencies: FamiliarAppDependencies())

        let ordinary = try #require(controller.createConversation(in: context))
        #expect(ordinary.project == nil)
        let owned = try #require(controller.createConversation(project: project, in: context))
        #expect(owned.project?.id == project.id)
    }

    @Test("Starting a workspace chat stays transient and selecting history restores its scope")
    @MainActor
    func transientWorkspaceSelection() throws {
        let container = try FamiliarTestStore.make(name: "TransientWorkspace")
        let context = container.mainContext
        let project = try FamiliarProjectService().create(name: "Workspace", in: context)
        let controller = FamiliarChatController(dependencies: FamiliarAppDependencies())

        controller.startNewConversation(project: project, in: context)
        #expect(controller.selectedConversationID == nil)
        #expect(controller.selectedProjectID == project.id)
        #expect(try context.fetch(FetchDescriptor<FamiliarConversation>()).isEmpty)

        let conversation = try #require(controller.createConversation(project: project, in: context))
        controller.select(nil, in: context)
        #expect(controller.selectedProjectID == nil)
        controller.select(conversation.id, in: context)
        #expect(controller.selectedProjectID == project.id)
    }

    @Test("A Run snapshots its Project at start and keeps it after conversation detachment")
    @MainActor
    func runCapturesProjectAtStart() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let project = try FamiliarProjectService().create(name: "Captured", in: context)
        let conversation = FamiliarConversation(project: project)
        context.insert(conversation)
        try context.save()

        FamiliarRunPersistenceRecorder().ensureRun(
            runtimeID: "captured-run",
            snapshot: try FamiliarProjectContextAssembler.assemble(
                seed: .init(projectID: project.id, projectName: project.name, conversationID: conversation.id, projectInstruction: nil, resources: []),
                settings: .defaultValue,
                messages: [],
                toolManifests: []
            ),
            startedAt: Date(),
            context: context
        )
        let run = try #require(context.fetch(FetchDescriptor<FamiliarAgentRun>()).first)
        #expect(run.project?.id == project.id)

        conversation.project = nil
        try context.save()
        #expect(run.project?.id == project.id)
    }

    @Test("Deep links still locate conversations owned by a project")
    @MainActor
    func deepLinkLocatesProjectConversation() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let project = try FamiliarProjectService().create(name: "Linked", in: context)
        let conversation = FamiliarConversation(title: "Project chat", project: project)
        context.insert(conversation)
        try context.save()

        let all = try context.fetch(FetchDescriptor<FamiliarConversation>())
        let controller = FamiliarChatController(dependencies: FamiliarAppDependencies())
        #expect(controller.openDeepLink(.conversation(conversation.id), conversations: all, in: context))
        #expect(controller.selectedConversationID == conversation.id)
    }

    @Test("Deleting a project removes its artifact metadata and file")
    @MainActor
    func projectDeletionRemovesArtifacts() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("FamiliarArtifactDelete-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let project = try FamiliarProjectService().create(name: "Artifact owner", in: context)
        let store = FamiliarArtifactStore(rootURL: root)
        let artifactID = UUID()
        let stored = try store.write(Data("result".utf8), projectID: project.id, artifactID: artifactID, filename: "result.md")
        context.insert(FamiliarArtifact(
            id: artifactID,
            projectID: project.id,
            identifier: "artifact_fixture",
            title: "Result",
            relativePath: stored.path,
            byteSize: 6,
            contentHash: stored.hash,
            createdByRunID: nil
        ))
        try context.save()

        let resourceStore = FamiliarProjectResourceStore(rootURL: root.appendingPathComponent("Resources", isDirectory: true))
        try FamiliarProjectService(resourceStore: resourceStore, artifactStore: store).permanentlyDelete(project, in: context)

        #expect(try context.fetch(FetchDescriptor<FamiliarArtifact>()).isEmpty)
        #expect(!fileManager.fileExists(atPath: root.appendingPathComponent(stored.path).path))
    }

    @Test("Project instruction reaches the runtime without the personal prompt limit")
    func projectInstructionRuntimeInput() async throws {
        let capture = FamiliarProjectRequestCapture()
        let registry = try FamiliarToolRegistry(tools: [])
        let loop = FamiliarAgentLoop(
            provider: FamiliarProjectCapturingProvider(capture: capture),
            registry: registry,
            policy: FamiliarExecutionPolicy(),
            confirmationCoordinator: FamiliarToolConfirmationCoordinator(),
            undoStore: FamiliarUndoStore()
        )
        let instruction = String(repeating: "P", count: FamiliarProjectService.maximumInstructionLength)

        let snapshot = try familiarTestContextSnapshot(projectID: UUID(), projectInstruction: instruction)
        for try await _ in loop.stream(contextSnapshot: snapshot, apiKey: "key") {}

        let systemPrompt = try #require(await capture.systemPrompt)
        #expect(systemPrompt.contains(instruction))
    }
}
