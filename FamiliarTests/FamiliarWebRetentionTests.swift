import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Explicit web retention")
@MainActor
struct FamiliarWebRetentionTests {
    @Test("A fetched page remains replayable Run evidence without creating Project resources")
    func evidenceOnly() throws {
        let fixture = try makeFetch()
        #expect(try fixture.container.mainContext.fetchCount(FetchDescriptor<FamiliarResource>()) == 0)
        #expect(fixture.project.resources.isEmpty)
        let reopened = ModelContext(fixture.container)
        let result = try #require(reopened.fetch(FetchDescriptor<FamiliarToolResultRecord>()).first)
        let envelope = try JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(result.envelopeJSON.utf8))
        let output = try JSONDecoder().decode(FamiliarWebFetchOutput.self, from: Data(envelope.modelContent.utf8))
        #expect(output.capture == fixture.output.capture)
        #expect(output.truncated)
        #expect(output.accessedAt == fixture.output.accessedAt)
    }

    @Test("Explicit save uses the stored capture, its owning Project and verifiable provenance")
    func explicitSave() throws {
        let fixture = try makeFetch()
        let context = fixture.container.mainContext
        let other = FamiliarProject(name: "Unrelated")
        context.insert(other)
        try context.save()
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarProjectResourceStore(rootURL: root)
        let resource = try FamiliarProjectResourceService(store: store).saveFetchedWebResult(
            runtimeID: fixture.runtimeID, toolCallID: "fetch", in: context)
        let version = try #require(resource.versions.first)
        #expect(resource.project?.id == fixture.project.id)
        #expect(other.resources.isEmpty)
        #expect(resource.displayName == fixture.output.title)
        #expect(version.source == .fetchedWeb)
        #expect(version.sourceURLString == fixture.output.finalURL)
        #expect(version.createdAt == fixture.output.accessedAt)
        #expect(version.extractedText == fixture.output.capture.resourceText)
        #expect(version.extractedText.contains("Truncated: true"))
        #expect(version.extractedText.contains(fixture.output.contentHash))
        let file = try #require(store.url(for: version.originalRelativePath))
        let bytes = try Data(contentsOf: file)
        #expect(bytes == Data(version.extractedText.utf8))
        #expect(FamiliarHash.sha256(bytes) == version.contentHash)
        #expect(FamiliarHash.sha256(version.extractedText) == version.extractedTextHash)
        // This reserved URL cannot supply the fixture body over HTTP. Successful
        // import must use the recorded bytes instead of another network fetch.
        #expect(version.extractedText.hasSuffix(fixture.output.text))
    }

    @Test("Repeated saves, including after reopening history, do not duplicate context")
    func repeatedSave() throws {
        let fixture = try makeFetch()
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FamiliarProjectResourceService(store: .init(rootURL: root))
        let first = try service.saveFetchedWebResult(runtimeID: fixture.runtimeID, toolCallID: "fetch", in: fixture.container.mainContext)
        let reopened = ModelContext(fixture.container)
        let second = try service.saveFetchedWebResult(runtimeID: fixture.runtimeID, toolCallID: "fetch", in: reopened)
        #expect(first.id == second.id)
        #expect(try reopened.fetchCount(FetchDescriptor<FamiliarResource>()) == 1)
        #expect(try reopened.fetchCount(FetchDescriptor<FamiliarResourceVersion>()) == 1)
    }

    @Test("Failed or cancelled fetches cannot be promoted even if a record contains a body", arguments: [FamiliarToolRunTerminalStatus.failed, .cancelled])
    func unsuccessfulFetch(status: FamiliarToolRunTerminalStatus) throws {
        let fixture = try makeFetch(status: status)
        let context = fixture.container.mainContext
        #expect(throws: FamiliarProjectResourceServiceError.self) {
            try FamiliarProjectResourceService().saveFetchedWebResult(runtimeID: fixture.runtimeID, toolCallID: "fetch", in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<FamiliarResource>()) == 0)
    }

    @Test("A non-web tool or an absent call cannot supply a captured page")
    func wrongToolOrCall() throws {
        let fixture = try makeFetch(toolName: "resource_read")
        let service = FamiliarProjectResourceService()
        let context = fixture.container.mainContext
        for call in ["fetch", "missing"] {
            #expect(throws: FamiliarProjectResourceServiceError.self) {
                try service.saveFetchedWebResult(runtimeID: fixture.runtimeID, toolCallID: call, in: context)
            }
        }
        #expect(try context.fetchCount(FetchDescriptor<FamiliarResource>()) == 0)
    }

    @Test("Hash damage and missing Project ownership reject saving without creating resources")
    func invalidCaptureAndOwnership() throws {
        let fixture = try makeFetch(contentHash: "damaged")
        let context = fixture.container.mainContext
        let service = FamiliarProjectResourceService()
        #expect(throws: FamiliarProjectResourceServiceError.self) {
            try service.saveFetchedWebResult(runtimeID: fixture.runtimeID, toolCallID: "fetch", in: context)
        }
        fixture.conversation.project = nil
        try context.save()
        #expect(throws: FamiliarProjectResourceServiceError.self) {
            try service.saveFetchedWebResult(runtimeID: fixture.runtimeID, toolCallID: "fetch", in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<FamiliarResource>()) == 0)
    }

    @Test("File creation failure leaves Project metadata and resources unchanged")
    func fileFailure() throws {
        let fixture = try makeFetch()
        let context = fixture.container.mainContext
        let previousUpdate = fixture.project.updatedAt
        let root = temporaryRoot()
        try Data("Blocks the resource directory".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FamiliarProjectResourceService(store: .init(rootURL: root))
        #expect(throws: (any Error).self) {
            try service.saveFetchedWebResult(runtimeID: fixture.runtimeID, toolCallID: "fetch", in: context)
        }
        #expect(fixture.project.updatedAt == previousUpdate)
        #expect(try context.fetchCount(FetchDescriptor<FamiliarResource>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FamiliarResourceVersion>()) == 0)
    }

    @Test("A duplicate save never reports success for a missing or damaged saved file")
    func damagedSavedFile() throws {
        let fixture = try makeFetch()
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarProjectResourceStore(rootURL: root)
        let service = FamiliarProjectResourceService(store: store)
        let context = fixture.container.mainContext
        let resource = try service.saveFetchedWebResult(runtimeID: fixture.runtimeID, toolCallID: "fetch", in: context)
        let version = try #require(resource.versions.first)
        let file = try #require(store.url(for: version.originalRelativePath))
        try Data("Changed bytes".utf8).write(to: file)
        #expect(throws: FamiliarProjectResourceStoreError.self) {
            try service.saveFetchedWebResult(runtimeID: fixture.runtimeID, toolCallID: "fetch", in: context)
        }
        try FileManager.default.removeItem(at: file)
        #expect(throws: FamiliarProjectResourceStoreError.self) {
            try service.saveFetchedWebResult(runtimeID: fixture.runtimeID, toolCallID: "fetch", in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<FamiliarResource>()) == 1)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WebRetention-\(UUID().uuidString)")
    }

    private func makeFetch(status: FamiliarToolRunTerminalStatus = .succeeded, toolName: String = "web_fetch",
                           contentHash: String? = nil) throws -> (container: ModelContainer, project: FamiliarProject,
                           conversation: FamiliarConversation, runtimeID: String, output: FamiliarWebFetchOutput) {
        let container = try FamiliarTestStore.make(name: "WebRetention-\(UUID().uuidString)")
        let context = container.mainContext
        let project = FamiliarProject(name: "Research")
        let conversation = FamiliarConversation(project: project)
        context.insert(project)
        context.insert(conversation)
        try context.save()
        let runtimeID = UUID().uuidString
        let snapshot = try FamiliarProjectContextAssembler.assemble(seed: .init(projectID: project.id,
            projectName: project.name, conversationID: conversation.id, projectInstruction: nil, resources: []),
            settings: .defaultValue, messages: [], toolManifests: [])
        let recorder = FamiliarRunPersistenceRecorder()
        recorder.ensureRun(runtimeID: runtimeID, snapshot: snapshot, startedAt: Date(timeIntervalSince1970: 1), context: context)
        let text = "Recorded content, including an incomplete page boundary."
        let output = FamiliarWebFetchOutput(sourceID: "src_fixture", finalURL: "https://example.invalid/page", title: "Recorded page",
            mimeType: "text/html", contentTrust: "untrusted_external_content", text: text, truncated: true,
            accessedAt: Date(timeIntervalSince1970: 10), contentHash: contentHash ?? FamiliarHash.sha256(text))
        let turnID = runtimeID + ":turn:0"
        let completion = FamiliarRuntimeActivityCompletion(runID: runtimeID, toolCallID: "fetch", toolName: toolName,
            effect: .read, assistantTurnID: turnID, detail: "Fetched", confirmation: .notRequired, status: status,
            startedAt: Date(timeIntervalSince1970: 5), finishedAt: Date(timeIntervalSince1970: 11), artifactIdentifier: nil,
            undoAvailable: false, automaticApprovalRequest: nil)
        try recorder.recordActivityCompleted(completion, eventSequence: 3, conversationID: conversation.id, context: context)
        let envelope = try FamiliarToolResultEnvelope(model: output, presentation: .document(.init(summary: "Fetched",
            title: output.title, text: output.text, mimeType: output.mimeType, url: output.finalURL, truncated: output.truncated)))
        let event = FamiliarToolResultProduced(runID: runtimeID, toolCallID: "fetch", toolName: toolName, effect: .read,
            assistantTurnID: turnID, envelope: envelope, sources: [], artifact: nil, producedAt: Date(timeIntervalSince1970: 11))
        #expect(try recorder.recordToolResult(event, eventSequence: 4, conversationID: conversation.id, context: context))
        return (container, project, conversation, runtimeID, output)
    }
}
