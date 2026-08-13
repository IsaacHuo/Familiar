import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar baseline")
struct FamiliarBaselineTests {
    @Test("Provider catalog has stable unique identifiers")
    func providerCatalogIdentifiersAreUnique() {
        let identifiers = FamiliarProviderCatalog.builtIn.map(\.id)
        #expect(identifiers.count == 12)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(!identifiers.contains(FamiliarProviderCatalog.customProviderID))
    }

    @Test("Unknown models use the safe text-only capability fallback")
    func unknownModelsAreTextOnly() {
        let model = FamiliarProviderCatalog.deepSeek.model(for: "future-model")
        #expect(model.capabilities.supportsText)
        #expect(!model.capabilities.supportsTools)
        #expect(!model.capabilities.supportsImages)
        #expect(!model.capabilities.supportsDocuments)
    }

    @Test("Markdown newlines are normalized")
    func markdownNormalizesNewlines() {
        #expect(FamiliarMarkdownNormalizer.normalize("a\r\nb\rc") == "a\nb\nc")
    }

    @Test("Markdown CSP blocks automatic remote image requests")
    @MainActor func markdownRemoteImagePolicy() {
        let directives = Dictionary(
            uniqueKeysWithValues: FamiliarMarkdownHTML.contentSecurityPolicy
                .split(separator: ";")
                .compactMap { directive -> (String, [Substring])? in
                    let tokens = directive.split(whereSeparator: \.isWhitespace)
                    guard let name = tokens.first else { return nil }
                    return (String(name), Array(tokens.dropFirst()))
                }
        )

        #expect(directives["img-src"] == ["'self'", "data:"])
        #expect(directives["connect-src"] == ["'none'"])
        #expect(!FamiliarMarkdownHTML.baseDocument.contains("img-src https:"))
    }

    @Test("SSE fixtures preserve OpenAI, Anthropic and Gemini framing")
    func sseFixtures() {
        let openAI = FamiliarSSEParser.events(in: "data: {\"choices\":[]}\n\ndata: [DONE]\n\n")
        let anthropic = FamiliarSSEParser.events(in: "event: content_block_delta\ndata: {\"delta\":{\"text\":\"Hi\"}}\n\n")
        let gemini = FamiliarSSEParser.events(in: "data: {\"candidates\":[]}\n\n")
        #expect(openAI.map(\.data) == ["{\"choices\":[]}", "[DONE]"])
        #expect(anthropic.first?.name == "content_block_delta")
        #expect(gemini.first?.data == "{\"candidates\":[]}")
    }

    @Test("Attachment boundaries reject traversal")
    func attachmentBoundaries() {
        #expect(FamiliarAttachmentStore.maximumSourceBytes == 25 * 1024 * 1024)
        #expect(FamiliarAttachmentStore.isSafeRelativePath("Messages/id/file.pdf"))
        #expect(!FamiliarAttachmentStore.isSafeRelativePath("../secret"))
        #expect(!FamiliarAttachmentStore.isSafeRelativePath("/private/secret"))
        #expect(!FamiliarAttachmentStore.isSafeRelativePath("Messages//file.pdf"))
    }

    @Test("Execution policy confirms natural-language writes")
    func executionPolicy() {
        let manifest = FamiliarToolManifest(name: "write", title: "Write", description: "", parameters: .init(type: .object), effect: .reversibleWrite, risk: .low, requirements: [])
        let policy = FamiliarExecutionPolicy()
        #expect(policy.decide(manifest: manifest, availability: .available, idempotencyKey: "run:call") == .requestApproval)
        let token = FamiliarOneShotAuthorization(toolName: "write", idempotencyKey: "run:call", source: .appIntent)
        #expect(policy.decide(manifest: manifest, availability: .available, authorization: token, idempotencyKey: "run:call") == .execute)
    }

    @Test("V2 Run and Step persist in the in-memory store") @MainActor
    func runStepPersistence() throws {
        let container = try FamiliarTestStore.make()
        let conversation = FamiliarConversation()
        let run = FamiliarAgentRun(runtimeID: "run", status: .completed, conversation: conversation)
        run.finishedAt = Date(timeIntervalSince1970: 10)
        let step = FamiliarAgentStep(type: .tool, eventSequence: 3, timelineSequence: 1, toolCallID: "call", toolName: "tool", summary: "Tool", detail: "Done", confirmation: .confirmed, status: .succeeded, startedAt: .distantPast, finishedAt: .distantFuture, run: run)
        container.mainContext.insert(conversation)
        container.mainContext.insert(run)
        container.mainContext.insert(step)
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(FetchDescriptor<FamiliarAgentRun>()).first?.steps.count == 1)
    }

    @Test("Cancelling a run resolves a pending confirmation once")
    func confirmationCancellationIsIdempotent() async throws {
        let coordinator = FamiliarToolConfirmationCoordinator()
        let request = FamiliarToolConfirmationRequest(
            runID: "run",
            toolCallID: "call",
            toolName: "test",
            title: "Test"
        )
        let waiting = Task {
            try await coordinator.requestConfirmation(request)
        }

        while await coordinator.pendingRequests().isEmpty {
            await Task.yield()
        }
        #expect(await coordinator.cancel(runID: "run") == 1)
        #expect(try await waiting.value == .cancelled)
        #expect(
            await coordinator.resolve(requestID: request.id, decision: .confirmed)
                == .alreadyResolved(.cancelled)
        )
    }

    @Test("Store recovery removes only the current store and local attachments") @MainActor
    func storeRecovery() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let persistence = root.appendingPathComponent("Familiar/Persistence", isDirectory: true)
        let attachments = root.appendingPathComponent("Familiar/Attachments", isDirectory: true)
        try fileManager.createDirectory(at: persistence, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: attachments, withIntermediateDirectories: true)
        try Data("store".utf8).write(to: persistence.appendingPathComponent("FamiliarAgentV2.store"))
        try Data("wal".utf8).write(to: persistence.appendingPathComponent("FamiliarAgentV2.store-wal"))
        try Data("old".utf8).write(to: persistence.appendingPathComponent("FamiliarAgentV1.store"))
        try Data("attachment".utf8).write(to: attachments.appendingPathComponent("message.txt"))

        try FamiliarApp.resetV2Store(in: root, fileManager: fileManager)

        #expect(!fileManager.fileExists(atPath: persistence.appendingPathComponent("FamiliarAgentV2.store").path))
        #expect(!fileManager.fileExists(atPath: persistence.appendingPathComponent("FamiliarAgentV2.store-wal").path))
        #expect(fileManager.fileExists(atPath: persistence.appendingPathComponent("FamiliarAgentV1.store").path))
        #expect(!fileManager.fileExists(atPath: attachments.path))
    }
}
