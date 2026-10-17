import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Ordinary conversations and Project work scopes", .serialized)
struct FamiliarWorkScopeTests {
    @Test("The same UUID in different owner kinds never shares bytes or references")
    func ownerKindsAreIsolated() throws {
        let id = UUID(), project = FamiliarWorkScope.project(id), chat = FamiliarWorkScope.conversation(id)
        #expect(project != chat)
        #expect(project.storageKey != chat.storageKey)
        #expect(FamiliarWorkScope(storageKey: chat.storageKey) == chat)
        #expect(FamiliarWorkScope(storageKey: "invalid") == nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarFileStore(rootURL: root), fileID = UUID()
        let first = try store.write(Data("Project data".utf8), scope: project, fileID: fileID, filename: "a.txt")
        let second = try store.write(Data("Chat data".utf8), scope: chat, fileID: fileID, filename: "a.txt")
        #expect(first.path != second.path)
        #expect(try store.read(relativePath: first.path) == Data("Project data".utf8))
        #expect(!store.isPath(first.path, inScope: chat, fileID: fileID))
    }

    @Test("An accepted ordinary Chat has no Project and preserves its provisional owner")
    @MainActor func ordinaryChatIdentity() throws {
        let container = try FamiliarTestStore.make(), context = container.mainContext
        let controller = FamiliarChatController(dependencies: .init())
        controller.startNewConversation(project: nil, in: context)
        let provisional = controller.currentScope
        #expect(try context.fetchCount(FetchDescriptor<FamiliarConversation>()) == 0)
        let chat = try #require(controller.createConversation(in: context))
        #expect(chat.project == nil)
        #expect(controller.currentScope == provisional)
        #expect(controller.currentScope == .conversation(chat.id))
        #expect(try context.fetchCount(FetchDescriptor<FamiliarProject>()) == 0)
        controller.startNewConversation(project: nil, in: context)
        #expect(controller.currentScope != provisional)
        #expect(try context.fetchCount(FetchDescriptor<FamiliarConversation>()) == 1)
    }

    @Test("Compiler and Memory admit only the current ordinary conversation")
    @MainActor func ordinaryContextIsolation() throws {
        let container = try FamiliarTestStore.make(), context = container.mainContext
        let chat = UUID(), other = UUID(), service = FamiliarMemoryService()
        let first = try service.insert(content: "Prefers short replies", scope: .conversation, projectID: nil,
            conversationID: chat, provenance: "user", creator: .user, in: context)
        _ = try service.insert(content: "Other private context", scope: .conversation, projectID: nil,
            conversationID: other, provenance: "user", creator: .user, in: context)
        let candidates = try service.candidates(query: "reply", projectID: nil, conversationID: chat, in: context)
        #expect(candidates.map(\.id) == [first.id])
        let scope = FamiliarWorkScope.conversation(chat)
        let a = fileSnapshot(scope), b = fileSnapshot(.conversation(other))
        let seed = FamiliarProjectContextSeed(projectID: nil, projectName: nil, conversationID: chat,
            projectInstruction: nil, resources: [], files: [a, b])
        let compiled = try FamiliarContextCompiler.assemble(seed: seed, settings: .defaultValue, messages: [], toolManifests: [])
        #expect(compiled.projectID == nil)
        #expect(compiled.workScope == scope)
        #expect(compiled.files.map(\.reference.scope) == [scope])
    }

    @Test("Business generation resets once and preserves preferences and new data on restart")
    @MainActor func generationResetIsOnceOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        for name in FamiliarBusinessDataGeneration.businessDirectories {
            let directory = root.appendingPathComponent("Familiar/" + name)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("old business bytes".utf8).write(to: directory.appendingPathComponent("old"))
        }
        let preference = root.appendingPathComponent("preferences.plist")
        try Data("provider-and-appearance".utf8).write(to: preference)
        try FamiliarBusinessDataGeneration.prepare(in: root)
        for name in FamiliarBusinessDataGeneration.businessDirectories {
            #expect(!fm.fileExists(atPath: root.appendingPathComponent("Familiar/" + name + "/old").path))
        }
        #expect(try String(contentsOf: preference, encoding: .utf8) == "provider-and-appearance")
        try FamiliarBusinessDataGeneration.finish(in: root)
        let path = root.appendingPathComponent("Familiar/Files/new.txt")
        try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("new data".utf8).write(to: path)
        try FamiliarBusinessDataGeneration.prepare(in: root)
        #expect(try String(contentsOf: path, encoding: .utf8) == "new data")
    }

    @Test("Deleting ordinary Chat deletes owned bytes; deleting Project Chat preserves Project Files")
    @MainActor func deletionOwnership() throws {
        let container = try FamiliarTestStore.make(), context = container.mainContext
        let ordinary = FamiliarConversation(title: "Ordinary"), project = FamiliarProject(name: "Work")
        let projectChat = FamiliarConversation(title: "Project chat", project: project)
        context.insert(ordinary); context.insert(project); context.insert(projectChat)
        let ordinaryFile = try saveFile(scope: .conversation(ordinary.id), chat: ordinary, context: context)
        let projectFile = try saveFile(scope: .project(project.id), chat: projectChat, context: context)
        let ordinaryPath = try #require(ordinaryFile.latestVersion?.storageRelativePath)
        let projectPath = try #require(projectFile.latestVersion?.storageRelativePath)
        defer { try? FamiliarFileStore().remove(scope: .project(project.id), fileID: projectFile.id) }
        let ordinaryURL = try #require(FamiliarFileStore().url(relativePath: ordinaryPath))
        let controller = FamiliarChatController(dependencies: .init())
        controller.delete([ordinary], in: context)
        #expect(!FileManager.default.fileExists(atPath: ordinaryURL.path))
        #expect(try context.fetchCount(FetchDescriptor<FamiliarFileRecord>()) == 1)
        controller.delete([projectChat], in: context)
        #expect(try context.fetchCount(FetchDescriptor<FamiliarFileRecord>()) == 1)
        #expect(try FamiliarFileStore().read(relativePath: projectPath) == Data("hello".utf8))
    }

    @Test("Moving Chat copies files, clears summary and authorization, and keeps historical references openable")
    @MainActor func movingChat() throws {
        let container = try FamiliarTestStore.make(), context = container.mainContext
        let chat = FamiliarConversation(title: "Move"), project = FamiliarProject(name: "Destination")
        context.insert(chat); context.insert(project)
        chat.contextSummary = "Old context"
        let old = try saveFile(scope: .conversation(chat.id), chat: chat, context: context)
        let snapshot = try #require(old.snapshot)
        let runtime = FamiliarAuthorizationRuntime(context: context, sessionID: "fixture")
        let manifest = FamiliarFileWriteTool(store: .init()).manifest
        try runtime.issueAuthorization(duration: .always, manifest: manifest, arguments: "{}",
            scope: .conversation(chat.id), targetKey: "file", evidence: "user")
        try FamiliarFileCatalogService().move(chat, to: project, in: context)
        #expect(chat.project?.id == project.id)
        #expect(chat.contextSummary == nil)
        #expect(try context.fetchCount(FetchDescriptor<FamiliarAuthorizationRuleRecord>()) == 0)
        let files = try FamiliarFileCatalogService().snapshots(scope: .project(project.id), in: context)
        #expect(files.count == 1)
        let presentation = FamiliarFilePresentation(snapshot: snapshot).resolved(in: context, scope: .project(project.id))
        #expect(try Data(contentsOf: presentation.validatedURL()) == Data("hello".utf8))
        try FamiliarFileCatalogService().move(chat, to: nil, in: context)
        #expect(chat.project == nil)
        let reopened = FamiliarFilePresentation(snapshot: snapshot).resolved(in: context, scope: .conversation(chat.id))
        #expect(try Data(contentsOf: reopened.validatedURL()) == Data("hello".utf8))
        FamiliarChatController(dependencies: .init()).delete([chat], in: context)
        if let file = files.first { try FamiliarFileCatalogService().delete(try #require(context.fetch(FetchDescriptor<FamiliarFileRecord>()).first { $0.id == file.reference.fileID }), in: context) }
    }

    @Test("Exact grants distinguish the same UUID across conversation and Project")
    @MainActor func authorizationScopeIsolation() async throws {
        let container = try FamiliarTestStore.make(), context = container.mainContext
        let runtime = FamiliarAuthorizationRuntime(context: context, sessionID: "session"), id = UUID()
        let manifest = FamiliarFileWriteTool(store: .init()).manifest
        try runtime.issueAuthorization(duration: .always, manifest: manifest, arguments: "{}", scope: .project(id), targetKey: "a", evidence: "user")
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest, arguments: "{}", scope: .project(id), targetKey: "a") == .always)
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest, arguments: "{}", scope: .conversation(id), targetKey: "a") == nil)
    }

    @Test("Local file writes execute without approval and supply a real byte undo")
    func localWriteAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = FamiliarFileWriteTool(store: .init(rootURL: root))
        let context = FamiliarToolContext(conversationID: UUID())
        let call = FamiliarToolCall(id: "write", name: "file_write", arguments: #"{"title":"Result","content":"hello","format":"markdown"}"#)
        let adapter = AnyFamiliarTool(tool)
        let assessment = try await adapter.preflight(arguments: call.arguments, context: context)
        guard case .action(let proposal) = try await adapter.execute(arguments: call.arguments, context: context) else { Issue.record("Missing action"); return }
        let evaluation = try await FamiliarExecutionPolicy().evaluate(manifest: tool.manifest, call: call, context: context,
            availability: .available, assessment: assessment, proposal: proposal, authorization: nil)
        #expect(evaluation.decision == .allow)
        #expect(evaluation.automatic)
        let commit = try await proposal.commit()
        let descriptor = try #require(commit.result.file)
        let path = try #require(FamiliarFileStore(rootURL: root).url(relativePath: descriptor.relativePath))
        #expect(FileManager.default.fileExists(atPath: path.path))
        let undo = try #require(commit.undo)
        _ = try await undo()
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    private func fileSnapshot(_ scope: FamiliarWorkScope) -> FamiliarFileSnapshot {
        .init(reference: .init(fileID: UUID(), versionID: UUID(), scope: scope), name: "File", origin: .upload,
            version: 1, filename: "a.txt", mimeType: "text/plain", byteSize: 1, contentHash: "x",
            storage: .init(kind: .file, relativePath: scope.filePrefix + "a.txt"), isProjectContext: false, updatedAt: Date())
    }

    @MainActor private func saveFile(scope: FamiliarWorkScope, chat: FamiliarConversation, context: ModelContext) throws -> FamiliarFileRecord {
        let id = UUID(), data = Data("hello".utf8)
        let bytes = try FamiliarFileStore().write(data, scope: scope, fileID: id, filename: "hello.txt")
        let file = FamiliarFileRecord(id: id, scope: scope, displayName: "Hello", origin: .generated, chatIDs: [chat.id])
        context.insert(file)
        context.insert(FamiliarFileVersionRecord(id: id, version: 1, filename: "hello.txt", mimeType: "text/plain",
            byteSize: Int64(data.count), contentHash: bytes.hash, extractedText: "hello", extractedTextHash: bytes.hash,
            storage: .init(kind: .file, relativePath: bytes.path), file: file))
        try context.save()
        return file
    }
}
