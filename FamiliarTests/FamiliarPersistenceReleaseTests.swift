import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar release persistence", .serialized)
struct FamiliarPersistenceReleaseTests {
    @Test("Files outlive Chat deletion and reads reject another Project before byte access")
    @MainActor
    func fileOwnership() throws {
        let container = try FamiliarModelContainer.makeInMemory(name: "FileOwnership")
        let context = container.mainContext
        let project = FamiliarProject(name: "Owner")
        let chat = FamiliarConversation(project: project)
        let file = FamiliarFileRecord(scope: .project(project.id), displayName: "File", origin: .upload, chatIDs: [chat.id])
        let version = FamiliarFileVersionRecord(version: 1, filename: "data.txt", mimeType: "text/plain", byteSize: 4,
            contentHash: "hash", extractedText: "text", extractedTextHash: "hash",
            storage: .init(kind: .attachment, relativePath: "Messages/missing/data.txt"), file: file)
        context.insert(project); context.insert(chat); context.insert(file); context.insert(version)
        try context.save()
        context.delete(chat)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<FamiliarFileRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>()).count == 1)
        #expect(throws: FamiliarFileError.self) {
            _ = try FamiliarFileCatalogService().read(.init(fileID: file.id, versionID: version.id, scope: .project(project.id)),
                inScope: .project(UUID()), context: context)
        }
    }

    @Test("Release uses the current work-scope schema")
    @MainActor
    func releaseSchemaBaseline() {
        #expect(FamiliarReleaseSchema.versionIdentifier == Schema.Version(5, 0, 0))
        #expect(FamiliarReleaseSchema.models.count == 39)
        #expect(FamiliarModelContainer.currentSchema.entities.count == 39)
        #expect(!FamiliarModelContainer.currentSchema.entities.contains { $0.name == "FamiliarArtifact" })
        #expect(!FamiliarModelContainer.currentSchema.entities.contains { $0.name == "FamiliarAuthorizationGrantRecord" })
        #expect(FamiliarStoreProfile.development.storeName == "FamiliarDevelopment")
        #expect(FamiliarStoreProfile.release.storeName == "Familiar")
    }

    @Test("Current schema persists immutable attachment evidence and EventKit inverse snapshots")
    @MainActor
    func v2NativeRecords() throws {
        let container = try FamiliarModelContainer.makeInMemory(name: "FamiliarCurrentNativeRecords")
        let context = container.mainContext
        let snapshotID = UUID()
        let attachmentID = UUID()
        context.insert(FamiliarContextAttachmentReference(
            contextSnapshotID: snapshotID,
            attachmentID: attachmentID,
            filename: "data.csv",
            mimeType: "text/csv",
            sourceRelativePath: "Messages/message/data.csv",
            byteSize: 12,
            contentHash: "content",
            extractedTextHash: "text"
        ))
        let descriptor = FamiliarEventKitUndoDescriptor(
            operation: .delete,
            kind: .reminders,
            calendarItemIdentifier: "reminder-1",
            snapshot: .reminder(.init(
                title: "Review",
                dueISO8601: nil,
                priority: 0,
                notes: nil,
                isCompleted: true,
                listIdentifier: "list-1"
            ))
        )
        context.insert(try FamiliarEventKitUndoMutationRecord(idempotencyKey: "run:call", descriptor: descriptor))
        try context.save()

        let attachment = try #require(context.fetch(FetchDescriptor<FamiliarContextAttachmentReference>()).first)
        #expect(attachment.contextSnapshotID == snapshotID)
        #expect(attachment.attachmentID == attachmentID)
        let mutation = try #require(context.fetch(FetchDescriptor<FamiliarEventKitUndoMutationRecord>()).first)
        #expect(mutation.operation == .delete)
        #expect(try mutation.descriptor().calendarItemIdentifier == "reminder-1")
    }

    @Test("A file-backed current store reopens with relationships intact")
    @MainActor
    func fileBackedReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarReleaseStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storeURL = root.appendingPathComponent("Familiar.store")
        let conversationID = UUID()
        let messageID = UUID()

        do {
            let container = try FamiliarModelContainer.make(at: storeURL, configurationName: "FamiliarReleaseTest")
            let context = container.mainContext
            let conversation = FamiliarConversation(id: conversationID, title: "Release")
            context.insert(conversation)
            context.insert(FamiliarMessage(id: messageID, role: .user, content: "Persisted", sequence: 0, conversation: conversation))
            try context.save()
        }

        do {
            let container = try FamiliarModelContainer.make(at: storeURL, configurationName: "FamiliarReleaseTest")
            let context = container.mainContext
            let conversations = try context.fetch(FetchDescriptor<FamiliarConversation>())
            let messages = try context.fetch(FetchDescriptor<FamiliarMessage>())
            let conversation = try #require(conversations.first { $0.id == conversationID })
            let message = try #require(messages.first { $0.id == messageID })
            #expect(conversation.title == "Release")
            #expect(message.content == "Persisted")
            #expect(message.conversation?.id == conversationID)
        }
    }

    @Test("Opening the release store never deletes development data")
    @MainActor
    func releaseDoesNotDeleteDevelopmentStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarSeparateStores-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let developmentURL = root.appendingPathComponent("FamiliarDevelopment.store")
        let sentinel = Data("development-data".utf8)
        try sentinel.write(to: developmentURL)

        _ = try FamiliarModelContainer.make(
            at: root.appendingPathComponent("Familiar.store"),
            configurationName: "FamiliarReleaseTest"
        )

        #expect(try Data(contentsOf: developmentURL) == sentinel)
    }

    @Test("A failed open leaves the exact store target in place")
    @MainActor
    func failedOpenDoesNotDeleteTarget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarInvalidStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let invalidStoreURL = root.appendingPathComponent("Familiar.store", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidStoreURL, withIntermediateDirectories: true)

        #expect(throws: Error.self) {
            _ = try FamiliarModelContainer.make(at: invalidStoreURL, configurationName: "FamiliarInvalidTest")
        }
        #expect(FileManager.default.fileExists(atPath: invalidStoreURL.path))
    }
}
