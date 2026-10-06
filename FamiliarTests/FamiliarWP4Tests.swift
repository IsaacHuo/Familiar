import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar WP4")
struct FamiliarWP4Tests {
    private let fixtureProjectID = UUID()
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
            AnyFamiliarTool(FamiliarFileListTool()),
            AnyFamiliarTool(FamiliarFileReadTool()),
            AnyFamiliarTool(FamiliarFileSearchTool())
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
        let ordinary = try FamiliarContextCompiler.assemble(
            seed: .init(projectID: nil, projectName: nil, conversationID: conversationID, projectInstruction: nil, resources: [first]),
            settings: .defaultValue,
            messages: [],
            toolManifests: []
        )
        #expect(ordinary.resources.isEmpty)
        #expect(ordinary.providerMessages.count == 1)

        let manifest = FamiliarToolManifest(name: "z_tool", title: "Z", description: "fixture", parameters: .init(type: .object), effect: .read, risk: .low, requirements: [])
        let project = try FamiliarContextCompiler.assemble(
            seed: .init(projectID: fixtureProjectID, projectName: "P", conversationID: conversationID, projectInstruction: "Frozen instruction", resources: [first, second]),
            settings: .defaultValue,
            messages: [],
            toolManifests: [manifest]
        )
        #expect(project.resources.map(\.filename) == ["A.txt", "B.txt"])
        #expect(project.providerMessages.compactMap(\.networkText).joined(separator: "\n").contains("Frozen instruction"))
        #expect(project.providerMessages.compactMap(\.networkText).joined(separator: "\n").contains("first"))
        #expect(project.allowedToolNames == ["z_tool"])
        #expect(project.initialInputCharacters == FamiliarContextCompiler.inputCharacterCount(messages: project.providerMessages, manifests: project.toolManifests))
        #expect(!project.providerMessages.compactMap(\.networkText).joined().contains("changed later"))
    }

    @Test("Compiler retains a read reference when a Project file body exceeds the budget")
    func oversizedProjectContext() throws {
        var settings = FamiliarSettings.defaultValue
        settings.modelID = settings.selectedProvider.curatedModels.first(where: { $0.capabilities.maximumInputCharacters <= 60_000 })?.id ?? settings.modelID
        let huge = resource(id: UUID(), name: "huge.txt", text: String(repeating: "x", count: 400_000))
        let snapshot = try FamiliarContextCompiler.assemble(
            seed: .init(projectID: fixtureProjectID, projectName: "P", conversationID: UUID(), projectInstruction: nil, resources: [huge]),
            settings: settings, messages: [], toolManifests: [])
        #expect(!snapshot.providerMessages.compactMap(\.networkText).joined().contains(huge.extractedText))
        #expect(snapshot.providerMessages.compactMap(\.networkText).joined().contains("omitted:"))

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
        let snapshot = try FamiliarContextCompiler.assemble(
            seed: .init(projectID: fixtureProjectID, projectName: "P", conversationID: conversation.id, projectInstruction: "Instruction", resources: [contextResource]),
            settings: .defaultValue,
            messages: [],
            toolManifests: []
        )
        let recorder = FamiliarRunPersistenceRecorder()
        recorder.ensureRun(runtimeID: "failed-run", snapshot: snapshot, startedAt: Date(), context: context)
        recorder.finishRun(runtimeID: "failed-run", outcome: .init(status: .failed, failureKind: .unknown, message: "fixture"), eventSequence: 1, at: Date(), context: context)
        let cancelledSnapshot = try FamiliarContextCompiler.assemble(
            seed: .init(projectID: fixtureProjectID, projectName: "P", conversationID: conversation.id, projectInstruction: "Instruction", resources: [contextResource]),
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

    @Test("Compiler excludes foreign Project files and Memory before prompt admission")
    func compilerScopeIsolation() throws {
        let foreign = UUID(), chatID = UUID()
        let resource = FamiliarContextResource(resourceID: UUID(), resourceVersionID: UUID(), version: 1,
            displayName: "foreign.txt", filename: "foreign.txt", mimeType: "text/plain", contentHash: "foreign",
            extractedText: "FOREIGN FILE", extractedTextHash: "foreign", projectID: foreign)
        let snapshot = try FamiliarContextCompiler.assemble(seed: .init(projectID: fixtureProjectID, projectName: "P",
            conversationID: chatID, projectInstruction: nil, resources: [resource], memories: [
                .init(id: UUID(), scope: .project, content: "FOREIGN MEMORY", provenance: "user", confidence: 1, projectID: foreign),
                .init(id: UUID(), scope: .global, content: "GLOBAL FACT", provenance: "user", confidence: 1)
            ]), settings: .defaultValue, messages: [], toolManifests: [])
        let prompt = snapshot.providerMessages.compactMap(\.networkText).joined()
        #expect(!prompt.contains("FOREIGN"))
        #expect(prompt.contains("GLOBAL FACT"))
        #expect(snapshot.resources.isEmpty)
    }

    @Test("Compaction preserves the submitted turn and complete assistant/result pairs")
    func compactionKeepsCurrentInput() throws {
        let call = FamiliarToolCall(id: "read", name: "file_read", arguments: "{}")
        let messages: [FamiliarProviderMessage] = [.system("rules"), .user(String(repeating: "old", count: 12_000)),
            .user("CURRENT INPUT MUST SURVIVE"), .assistant(nil, toolCalls: [call]),
            .tool(String(repeating: "result", count: 4_000), toolCallID: call.id, name: call.name)]
        let selection = try #require(FamiliarContextCompiler.compaction(messages: messages,
            protectedPrefixMessageCount: 1, maximumInputCharacters: 40_000, protectedTurnIndex: 2))
        #expect(!selection.entries.contains { $0.networkText == "CURRENT INPUT MUST SURVIVE" })
        let compacted = selection.replacing(with: "Earlier work summary")
        #expect(compacted[try #require(selection.currentTurnIndex)].networkText == "CURRENT INPUT MUST SURVIVE")
        let resultIndex = try #require(compacted.firstIndex { $0.role == .tool })
        #expect(compacted[resultIndex - 1].toolCalls.first?.id == call.id)
    }

    @Test("Write facts survive transcript replacement and loaded tools do not remain exposed")
    func runFactsSurviveCompaction() async throws {
        let state = FamiliarRunState()
        let manifest = FamiliarFileReadTool().manifest
        await state.expose([manifest])
        await state.expose([])
        let call = FamiliarToolCall(id: "write", name: "file_write", arguments: "{}")
        await state.record(call: call, status: .attempted)
        await state.record(call: call, status: .uncertain, detail: "tool_commit_unconfirmed")
        let facts = await state.snapshot()
        #expect(facts.discoveredTools == ["file_read"])
        #expect(facts.exposedTools.isEmpty)
        let input = try familiarTestContextSnapshot(projectID: fixtureProjectID)
        let compiled = try FamiliarContextCompiler.compileRequest(input: input, transcript: [.system("rules"), .user("Continue")],
            facts: facts, manifests: [], toolsWithheld: true)
        #expect(compiled.manifest.stateSummary.contains("uncertain"))
        #expect(compiled.manifest.stateSummary.contains("tool_commit_unconfirmed"))
        #expect(compiled.request.tools.isEmpty)
        #expect(input.providerMessages.count == 1)
        #expect(compiled.manifest.inputSnapshotID == input.id)
    }

    @Test("Only exact immutable FileVersions reuse bounded reads with original observation time")
    func fileReadReuse() async throws {
        let state = FamiliarRunState(), versionID = UUID()
        let file = FamiliarFileSnapshot(reference: .init(fileID: UUID(), versionID: versionID, projectID: fixtureProjectID),
            name: "same.txt", origin: .upload, version: 1, filename: "same.txt", mimeType: "text/plain", byteSize: 4,
            contentHash: "hash", storage: .init(kind: .attachment, relativePath: "frozen"), isProjectContext: false, updatedAt: Date())
        let call = FamiliarToolCall(id: "read", name: "file_read", arguments: "{\"identifier\":\"file_\(versionID)\"}")
        let key = try #require(await state.fileReadKey(call: call, available: [file]))
        let result = FamiliarToolExecutionResult(envelope: try .init(model: ["text": "body"],
            presentation: .document(.init(summary: "Read", title: "same.txt", text: "body"))))
        let observed = Date(timeIntervalSince1970: 100)
        await state.cacheRead(result, key: key, observedAt: observed)
        #expect(await state.cachedRead(key)?.observedAt == observed)
        #expect(await state.fileReadKey(call: call, available: []) == nil)
        #expect(await state.fileReadKey(call: .init(id: "web", name: "web_fetch", arguments: call.arguments), available: [file]) == nil)
    }

    @Test("Per-request audit stores references and facts without Project file bodies")
    @MainActor
    func compilationAudit() async throws {
        let container = try FamiliarTestStore.make(name: "CompilationAudit")
        let context = container.mainContext
        let conversation = FamiliarConversation()
        context.insert(conversation); try context.save()
        let input = try FamiliarContextCompiler.assemble(seed: .init(projectID: fixtureProjectID, projectName: "P",
            conversationID: conversation.id, projectInstruction: nil, resources: [resource(id: UUID(), name: "ref.txt", text: "PRIVATE FILE BODY")]),
            settings: .defaultValue, messages: [], toolManifests: [])
        let recorder = FamiliarRunPersistenceRecorder(), state = FamiliarRunState()
        recorder.ensureRun(runtimeID: "audit", snapshot: input, startedAt: Date(), context: context)
        let compiled = try FamiliarContextCompiler.compileRequest(input: input, transcript: input.providerMessages,
            facts: await state.snapshot(), manifests: [], toolsWithheld: false)
        try recorder.recordCompilation(compiled.manifest, runtimeID: "audit", context: context)
        try recorder.recordCompilation(compiled.manifest, runtimeID: "audit", context: context)
        let records = try context.fetch(FetchDescriptor<FamiliarActivityRecord>())
        #expect(records.count == 1)
        let json = try #require(records.first?.detail)
        #expect(!json.contains("PRIVATE FILE BODY"))
        let audit = try JSONDecoder().decode(FamiliarContextCompilation.self, from: Data(json.utf8))
        #expect(audit.inputSnapshotID == input.id)
        #expect(audit.characterCount == FamiliarContextCompiler.inputCharacterCount(messages: compiled.request.messages, manifests: []))
        #expect(audit.references.first?.hash == input.resources.first?.contentHash)
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
            extractedTextHash: FamiliarHash.sha256(text), projectID: fixtureProjectID
        )
    }
}
