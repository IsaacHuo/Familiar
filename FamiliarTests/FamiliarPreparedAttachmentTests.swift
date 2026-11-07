import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Prepared attachment integrity")
struct FamiliarPreparedAttachmentTests {
    private func fixture() async throws -> (URL, FamiliarAttachmentDraft, Data) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data("ORIGINAL".utf8), input = root.appendingPathComponent("input.txt")
        try data.write(to: input)
        let draft = try await FamiliarAttachmentStore.importDocument(from: input)
        return (root, draft, data)
    }

    @Test("A source changed after context preparation cannot commit mismatched bytes")
    func changedSource() async throws {
        let (root, draft, original) = try await fixture()
        defer {
            FamiliarAttachmentStore.remove(relativePath: draft.relativePath)
            try? FileManager.default.removeItem(at: root)
        }
        let source = try #require(FamiliarAttachmentStore.url(for: draft.relativePath))
        try Data("MODIFIED".utf8).write(to: source)
        let messageID = UUID(), scope = FamiliarWorkScope.conversation(UUID())
        let hashes = FamiliarAttachmentHashes(content: FamiliarHash.sha256(original), extractedText: FamiliarHash.sha256(draft.extractedText))
        await #expect(throws: FamiliarAttachmentStoreError.self) {
            _ = try await FamiliarAttachmentStore.prepareCommittedCopies(of: [draft], messageID: messageID,
                scope: scope, expectedHashes: [draft.id: hashes])
        }
        let path = FamiliarAttachmentStore.committedRelativePath(of: draft, messageID: messageID, scope: scope)
        let destinationExists = FamiliarAttachmentStore.url(for: path).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        #expect(!destinationExists)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("A prepared Project receipt cannot be used by a Conversation with the same UUID")
    @MainActor func typedScopeReceipt() async throws {
        let (root, draft, original) = try await fixture()
        var preparedPaths: [String] = []
        defer {
            FamiliarAttachmentStore.remove(relativePaths: [draft.relativePath] + preparedPaths)
            try? FileManager.default.removeItem(at: root)
        }
        let container = try FamiliarTestStore.make(), context = container.mainContext
        let chat = FamiliarConversation(), messageID = UUID()
        let hashes = FamiliarAttachmentHashes(content: FamiliarHash.sha256(original), extractedText: FamiliarHash.sha256(draft.extractedText))
        let prepared = try await FamiliarAttachmentStore.prepareCommittedCopies(of: [draft], messageID: messageID,
            scope: .project(chat.id), expectedHashes: [draft.id: hashes])
        preparedPaths = prepared.paths
        let message = FamiliarMessage(id: messageID, role: .user, content: "Fixture", sequence: 0, conversation: chat)
        let attachment = FamiliarAttachment(id: draft.id, kind: draft.kind, filename: draft.filename,
            mimeType: draft.mimeType, relativePath: prepared.paths[0], extractedText: draft.extractedText,
            byteSize: draft.byteSize, extractionEngine: draft.extractionEngine, extractionVersion: draft.extractionVersion,
            detectedFormat: draft.detectedFormat, usedOCR: draft.usedOCR, message: message)
        context.insert(chat); context.insert(message); context.insert(attachment)
        try context.save()
        #expect(throws: FamiliarFileError.self) {
            try FamiliarFileCatalogService().stageUploads([attachment], in: context, prepared: prepared)
        }
        #expect(try context.fetchCount(FetchDescriptor<FamiliarFileRecord>()) == 0)
    }
}
