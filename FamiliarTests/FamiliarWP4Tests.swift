import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar WP4")
struct FamiliarWP4Tests {
    @Test("Resource store validates paths, hashes copies, resolves versions, and rejects symlinks")
    func resourceStoreSafety() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("FamiliarResourceStore-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source.txt")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("resource body".utf8).write(to: source)
        defer { try? fileManager.removeItem(at: root) }
        let store = FamiliarProjectResourceStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let projectID = UUID()
        let resourceID = UUID()
        let versionID = UUID()

        #expect(store.isSafeRelativePath("Projects/p/Resources/r/Versions/1-v/file.txt"))
        #expect(!store.isSafeRelativePath("../file.txt"))
        #expect(!store.isSafeRelativePath("/private/file.txt"))
        #expect(!store.isSafeRelativePath("Projects//file.txt"))
        let copied = try store.copyVersion(from: source, projectID: projectID, resourceID: resourceID, version: 1, versionID: versionID, filename: "file.txt")
        #expect(copied.relativePath == "Projects/\(projectID.uuidString)/Resources/\(resourceID.uuidString)/Versions/1-\(versionID.uuidString)/file.txt")
        #expect(copied.byteSize == 13)
        #expect(copied.contentHash == "8c15f7b99b143b43c0c49d4250a8ba35e32168a9196085e0bf6e089147983cad")
        #expect(store.url(for: copied.relativePath) != nil)
        try store.removeVersion(relativePath: copied.relativePath)
        #expect(store.url(for: copied.relativePath) == nil)

        let restored = try store.copyVersion(from: source, projectID: projectID, resourceID: resourceID, version: 1, versionID: UUID(), filename: "restore.txt")
        let stagedValue = try store.stageProjectDirectory(projectID: projectID)
        let staged = try #require(stagedValue)
        #expect(store.url(for: restored.relativePath) == nil)
        try store.restore(staged)
        #expect(store.url(for: restored.relativePath) != nil)

        let malicious = store.rootURL.appendingPathComponent("Projects/link", isDirectory: true)
        try fileManager.createDirectory(at: malicious.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: malicious, withDestinationURL: root)
        #expect(store.url(for: "Projects/link/source.txt") == nil)
    }

    @Test("Resource store accepts a real ancestor symlink but still rejects an internal symlink")
    func ancestorSymlinkIsAllowed() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("FamiliarAncestorSymlink-\(UUID().uuidString)", isDirectory: true)
        let realTarget = root.appendingPathComponent("real", isDirectory: true)
        let linked = root.appendingPathComponent("linked", isDirectory: true)
        try fileManager.createDirectory(at: realTarget, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createSymbolicLink(at: linked, withDestinationURL: realTarget)

        let store = FamiliarProjectResourceStore(rootURL: linked.appendingPathComponent("store", isDirectory: true))
        let source = realTarget.appendingPathComponent("source.txt")
        try Data("body".utf8).write(to: source)
        let copied = try store.copyVersion(
            from: source,
            projectID: UUID(),
            resourceID: UUID(),
            version: 1,
            versionID: UUID(),
            filename: "source.txt"
        )
        #expect(store.url(for: copied.relativePath) != nil)

        let internalLink = store.rootURL.appendingPathComponent("Projects/link", isDirectory: true)
        try fileManager.createDirectory(at: internalLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: internalLink, withDestinationURL: realTarget)
        #expect(store.url(for: "Projects/link/source.txt") == nil)
    }

    @Test("All registered tool names match the provider function name pattern")
    func toolNamesMatchProviderPattern() async throws {
        let registry = try FamiliarToolRegistry(tools: [
            AnyFamiliarTool(FamiliarResourceListTool()),
            AnyFamiliarTool(FamiliarResourceReadTool()),
            AnyFamiliarTool(FamiliarResourceSearchTool())
        ])
        let pattern = /^[a-zA-Z0-9_-]+$/
        for manifest in await registry.snapshot() {
            #expect(manifest.name.wholeMatch(of: pattern) != nil, "工具名 \(manifest.name) 不符合 Provider 函数名约束")
        }
    }

    @Test("Context assembler separates ordinary and project data and freezes deterministic context")
    func contextAssembler() throws {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = resource(id: firstID, name: "B.txt", text: "second")
        let second = resource(id: secondID, name: "A.txt", text: "first")
        let conversationID = UUID()
        let ordinary = try FamiliarProjectContextAssembler.assemble(
            seed: .init(projectID: nil, projectName: nil, conversationID: conversationID, projectInstruction: nil, resources: [first]),
            settings: .defaultValue,
            messages: [],
            toolManifests: []
        )
        #expect(ordinary.resources.isEmpty)
        #expect(ordinary.providerMessages.count == 1)

        let manifest = FamiliarToolManifest(name: "z_tool", title: "Z", description: "fixture", parameters: .init(type: .object), effect: .read, risk: .low, requirements: [])
        let project = try FamiliarProjectContextAssembler.assemble(
            seed: .init(projectID: UUID(), projectName: "P", conversationID: conversationID, projectInstruction: "Frozen instruction", resources: [first, second]),
            settings: .defaultValue,
            messages: [],
            toolManifests: [manifest]
        )
        #expect(project.resources.map(\.filename) == ["A.txt", "B.txt"])
        #expect(project.providerMessages.compactMap(\.networkText).joined(separator: "\n").contains("Frozen instruction"))
        #expect(project.providerMessages.compactMap(\.networkText).joined(separator: "\n").contains("first"))
        #expect(project.exposedToolNames == ["z_tool"])
        #expect(project.initialInputCharacters == FamiliarProjectContextAssembler.inputCharacterCount(messages: project.providerMessages, manifests: project.toolManifests))
        #expect(!project.providerMessages.compactMap(\.networkText).joined().contains("changed later"))
    }

    @Test("Assembler rejects the complete initial project context when oversized")
    func oversizedProjectContext() throws {
        var settings = FamiliarSettings.defaultValue
        settings.modelID = settings.selectedProvider.curatedModels.first(where: { $0.capabilities.maximumInputCharacters <= 60_000 })?.id ?? settings.modelID
        let huge = resource(id: UUID(), name: "huge.txt", text: String(repeating: "x", count: 400_000))
        #expect(throws: FamiliarAgentError.self) {
            _ = try FamiliarProjectContextAssembler.assemble(
                seed: .init(projectID: UUID(), projectName: "P", conversationID: UUID(), projectInstruction: nil, resources: [huge]),
                settings: settings,
                messages: [],
                toolManifests: []
            )
        }
    }

    @Test("One resource belongs to a project and survives message deletion across two chats")
    @MainActor
    func sharedResourceSurvivesMessages() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let project = FamiliarProject(name: "Shared")
        let resource = FamiliarResource(displayName: "shared.txt", project: project)
        let version = FamiliarResourceVersion(version: 1, source: .importedFile, filename: "shared.txt", mimeType: "text/plain", originalRelativePath: "Projects/p/resource", byteSize: 6, contentHash: "file", extractedText: "shared", extractedTextHash: "text", extractionEngine: "fixture", extractionVersion: "1", detectedFormat: "txt", usedOCR: false, resource: resource)
        let first = FamiliarConversation(project: project)
        let second = FamiliarConversation(project: project)
        let message = FamiliarMessage(role: .user, content: "delete me", sequence: 0, conversation: first)
        context.insert(project)
        context.insert(resource)
        context.insert(version)
        context.insert(first)
        context.insert(second)
        context.insert(message)
        try context.save()
        context.delete(message)
        try context.save()

        #expect(project.conversations.count == 2)
        #expect(project.resources.map(\.id) == [resource.id])
        #expect(try context.fetch(FetchDescriptor<FamiliarResourceVersion>()).count == 1)
    }

    @Test("Project deletion detaches chats and runs and removes resource metadata and files")
    @MainActor
    func projectDeletionRemovesResources() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("FamiliarProjectDelete-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source.txt")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("delete me".utf8).write(to: source)
        defer { try? fileManager.removeItem(at: root) }
        let store = FamiliarProjectResourceStore(rootURL: root.appendingPathComponent("store", isDirectory: true))
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let project = FamiliarProject(name: "Delete")
        let conversation = FamiliarConversation(project: project)
        let run = FamiliarAgentRun(runtimeID: "historical", status: .completed, conversation: conversation, project: project)
        let resource = FamiliarResource(displayName: "source.txt", project: project)
        let stored = try store.copyVersion(from: source, projectID: project.id, resourceID: resource.id, version: 1, versionID: UUID(), filename: "source.txt")
        let version = FamiliarResourceVersion(version: 1, source: .importedFile, filename: "source.txt", mimeType: "text/plain", originalRelativePath: stored.relativePath, byteSize: stored.byteSize, contentHash: stored.contentHash, extractedText: "delete me", extractedTextHash: "text", extractionEngine: "fixture", extractionVersion: "1", detectedFormat: "txt", usedOCR: false, resource: resource)
        context.insert(project)
        context.insert(conversation)
        context.insert(run)
        context.insert(resource)
        context.insert(version)
        try context.save()

        try FamiliarProjectService(resourceStore: store).permanentlyDelete(project, in: context)
        #expect(try context.fetch(FetchDescriptor<FamiliarProject>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarResource>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarResourceVersion>()).isEmpty)
        #expect(try #require(context.fetch(FetchDescriptor<FamiliarConversation>()).first).project == nil)
        #expect(try #require(context.fetch(FetchDescriptor<FamiliarAgentRun>()).first).project == nil)
        #expect(store.url(for: stored.relativePath) == nil)
    }

    @Test("Run records persist immutable resource references without full extracted text")
    @MainActor
    func snapshotRecordPersistence() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let conversation = FamiliarConversation()
        context.insert(conversation)
        try context.save()
        let contextResource = resource(id: UUID(), name: "ref.txt", text: "private full text")
        let snapshot = try FamiliarProjectContextAssembler.assemble(
            seed: .init(projectID: UUID(), projectName: "P", conversationID: conversation.id, projectInstruction: "Instruction", resources: [contextResource]),
            settings: .defaultValue,
            messages: [],
            toolManifests: []
        )
        let recorder = FamiliarRunPersistenceRecorder()
        recorder.ensureRun(runtimeID: "failed-run", snapshot: snapshot, startedAt: Date(), context: context)
        recorder.finishRun(runtimeID: "failed-run", outcome: .init(status: .failed, failureKind: .unknown, message: "fixture"), eventSequence: 1, at: Date(), context: context)
        let cancelledSnapshot = try FamiliarProjectContextAssembler.assemble(
            seed: .init(projectID: UUID(), projectName: "P", conversationID: conversation.id, projectInstruction: "Instruction", resources: [contextResource]),
            settings: .defaultValue,
            messages: [],
            toolManifests: []
        )
        recorder.ensureRun(runtimeID: "cancelled-run", snapshot: cancelledSnapshot, startedAt: Date(), context: context)
        recorder.finishRun(runtimeID: "cancelled-run", outcome: .cancelled(message: "fixture"), eventSequence: 1, at: Date(), context: context)
        let record = try #require(context.fetch(FetchDescriptor<FamiliarContextSnapshotRecord>()).first { $0.id == snapshot.id })
        let reference = try #require(record.resourceReferences.first)
        #expect(record.run?.status == .failed)
        #expect(reference.contentHash == contextResource.contentHash)
        #expect(reference.extractedTextHash == contextResource.extractedTextHash)
        #expect(!record.exposedToolNamesJSON.contains("private full text"))
        #expect(Set(try context.fetch(FetchDescriptor<FamiliarAgentRun>()).map(\.status)) == [.failed, .cancelled])
    }

    private func resource(id: UUID, name: String, text: String) -> FamiliarContextResource {
        FamiliarContextResource(
            resourceID: id,
            resourceVersionID: UUID(),
            version: 1,
            displayName: name,
            filename: name,
            mimeType: "text/plain",
            contentHash: "file-\(id.uuidString)",
            extractedText: text,
            extractedTextHash: FamiliarProjectResourceService.sha256(text)
        )
    }
}
