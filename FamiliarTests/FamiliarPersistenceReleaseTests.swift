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
        let file = FamiliarFileRecord(projectID: project.id, displayName: "File", origin: .upload, chatIDs: [chat.id])
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
            _ = try FamiliarFileCatalogService().read(.init(fileID: file.id, versionID: version.id, projectID: project.id),
                inProject: UUID(), context: context)
        }
    }

    @Test("Release has a frozen 37-entity baseline and an additive Files migration")
    @MainActor
    func releaseSchemaBaseline() {
        #expect(FamiliarStoreSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(FamiliarStoreSchemaV1.models.count == 37)
        #expect(FamiliarReleaseSchema.versionIdentifier == Schema.Version(4, 0, 0))
        #expect(FamiliarReleaseSchema.models.count == 37)
        #expect(FamiliarModelContainer.currentSchema.entities.count == 37)
        #expect(FamiliarSchemaMigrationPlan.schemas.count == 4)
        #expect(FamiliarSchemaMigrationPlan.stages.count == 3)
        #expect(!FamiliarModelContainer.currentSchema.entities.contains { $0.name == "FamiliarArtifact" })
        #expect(!FamiliarModelContainer.currentSchema.entities.contains { $0.name == "FamiliarAuthorizationGrantRecord" })
        #expect(FamiliarStoreProfile.development.storeName == "FamiliarDevelopment")
        #expect(FamiliarStoreProfile.release.storeName == "Familiar")
    }

    @Test("Frozen definitions have the original entity and property names")
    @MainActor
    func frozenStorageShape() {
        let original = Schema(FamiliarModelSchema.legacyModels)
        let frozen = Schema(versionedSchema: FamiliarStoreSchemaV1.self)
        #expect(original.entities.map(\.name).sorted() == frozen.entities.map(\.name).sorted())
        for entity in original.entities {
            let counterpart = frozen.entities.first { $0.name == entity.name }
            #expect(entity.properties.map(\.name).sorted() == counterpart?.properties.map(\.name).sorted())
        }
    }

    @Test("The actual pre-migration store upgrades without moving bytes or losing audit and Undo")
    @MainActor
    func originalStoreUpgrade() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarUpgrade-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storeURL = root.appendingPathComponent("Familiar.store")
        let projectID = UUID(), chatID = UUID(), attachmentID = UUID(), resourceID = UUID(), versionID = UUID(), generatedID = UUID(), grantID = UUID()
        let fileBytes = root.appendingPathComponent("original.txt")
        try Data("original bytes".utf8).write(to: fileBytes)
        do {
            // This deliberately uses the shipped model types and the original unplanned container,
            // rather than constructing a fixture with the newly frozen namespace.
            let schema = Schema(FamiliarModelSchema.legacyModels)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Original", schema: schema, url: storeURL, cloudKitDatabase: .none)])
            let context = container.mainContext
            context.insert(FamiliarSchemaV5.FamiliarAuthorizationGrantRecord(id: grantID, userAction: "confirm", sourceRawValue: "builtIn",
                capabilityID: "artifact_write", capabilityVersion: "1", argumentsHash: "original-arguments", projectID: projectID,
                expiresAt: .distantFuture, singleUse: false, evidence: "Original audit", consumedAt: nil, stateRawValue: "issued"))
            let project = FamiliarProject(id: projectID, name: "Upgrade")
            let chat = FamiliarConversation(id: chatID, title: "Keep this chat", project: project)
            let message = FamiliarMessage(role: .user, content: "Keep this message", sequence: 0, conversation: chat)
            let resource = FamiliarResource(id: resourceID, displayName: "Reference", project: project)
            let version = FamiliarResourceVersion(id: versionID, version: 1, source: .importedFile,
                filename: "reference.txt", mimeType: "text/plain", originalRelativePath: "unchanged/reference.txt",
                byteSize: 13, contentHash: "original-hash", extractedText: "Reference text", extractedTextHash: "text-hash",
                extractionEngine: "plain", extractionVersion: "1", detectedFormat: "txt", usedOCR: false, resource: resource)
            context.insert(project); context.insert(chat); context.insert(message); context.insert(resource); context.insert(version)
            context.insert(FamiliarSchemaV4.FamiliarArtifact(id: generatedID, projectID: projectID,
                identifier: "artifact_" + generatedID.uuidString, title: "Old generated file", format: .markdown,
                relativePath: "Projects/\(projectID.uuidString)/Artifacts/\(generatedID.uuidString)/report.md",
                byteSize: 13, contentHash: "generated-hash", createdByRunID: "original-run"))
            context.insert(FamiliarAttachment(id: attachmentID, kind: .document, filename: "reference.txt", mimeType: "text/plain",
                relativePath: "unchanged/attachment.txt", extractedText: "Reference text", byteSize: 13,
                extractionEngine: "plain", extractionVersion: "1", detectedFormat: "txt", usedOCR: false,
                message: message, resourceVersion: version))
            context.insert(FamiliarToolInvocationRecord(idempotencyKey: "run:call", runtimeID: "run", toolCallID: "call",
                toolName: "calendar_create", argumentsHash: "exact", state: .committing))
            context.insert(FamiliarEventKitUndoRecord(idempotencyKey: "run:undo", runtimeID: "run", toolCallID: "undo",
                toolName: "calendar_create", kind: .events, calendarItemIdentifier: "native-event"))
            context.insert(FamiliarMemoryItem(scopeRawValue: "project", projectID: projectID, conversationID: nil,
                content: "Preserve memory", normalizedKey: "memory", provenance: "user", confidence: 1, createdByRawValue: "user"))
            try context.save()
        }
        for _ in 0..<2 {
            let container = try FamiliarModelContainer.make(at: storeURL, configurationName: "Upgraded")
            let context = container.mainContext
            let chat = try #require(context.fetch(FetchDescriptor<FamiliarConversation>()).first)
            #expect(chat.id == chatID && chat.project?.id == projectID)
            #expect(chat.messages.first?.content == "Keep this message")
            #expect(chat.messages.first?.attachments.first?.id == attachmentID)
            let archiveID = "legacy-grant:" + grantID.uuidString
            let archives = try context.fetch(FetchDescriptor<FamiliarActivityRecord>(predicate: #Predicate { $0.activityID == archiveID }))
            #expect(archives.count == 1)
            let archived = try JSONDecoder().decode(FamiliarArchivedGrant.self, from: Data(try #require(archives.first?.detail).utf8))
            #expect(archived.id == grantID && archived.evidence == "Original audit" && archived.capabilityID == "artifact_write")
            let files = try context.fetch(FetchDescriptor<FamiliarFileRecord>())
            #expect(files.count == 2) // Explicit attachment->Resource relationship shares a File; generation has its own identity.
            let file = try #require(files.first { $0.id == resourceID })
            #expect(file.id == resourceID && file.isProjectContext && file.chatIDs == [chatID])
            #expect(file.latestVersion?.id == versionID)
            #expect(file.latestVersion?.storageRelativePath == "unchanged/reference.txt")
            let generated = try #require(files.first { $0.id == generatedID })
            #expect(generated.latestVersion?.identifier == "file_" + generatedID.uuidString)
            #expect(generated.latestVersion?.contentHash == "generated-hash")
            #expect(generated.latestVersion?.createdByRunID == "original-run")
            #expect(try context.fetch(FetchDescriptor<FamiliarToolInvocationRecord>()).first?.state == .committing)
            #expect(try context.fetch(FetchDescriptor<FamiliarEventKitUndoRecord>()).first?.calendarItemIdentifier == "native-event")
            #expect(try context.fetch(FetchDescriptor<FamiliarMemoryItem>()).first?.content == "Preserve memory")
        }
        #expect(try Data(contentsOf: fileBytes) == Data("original bytes".utf8))
    }

    @Test("Same names do not merge Files and a repeated conversion does not duplicate versions")
    @MainActor
    func identityConversion() throws {
        let container = try FamiliarModelContainer.makeInMemory(name: "FilesIdentity")
        let context = container.mainContext
        let project = FamiliarProject(name: "Identity")
        let chat = FamiliarConversation(project: project)
        let message = FamiliarMessage(role: .user, content: "files", sequence: 0, conversation: chat)
        context.insert(project); context.insert(chat); context.insert(message)
        for _ in 0..<2 {
            context.insert(FamiliarAttachment(kind: .document, filename: "same.txt", mimeType: "text/plain",
                relativePath: UUID().uuidString + "/same.txt", extractedText: "same", byteSize: 4,
                extractionEngine: "plain", extractionVersion: "1", detectedFormat: "txt", usedOCR: false, message: message))
        }
        try context.save()
        try FamiliarFileMetadataMigration.convert(in: context)
        try FamiliarFileMetadataMigration.convert(in: context)
        let files = try context.fetch(FetchDescriptor<FamiliarFileRecord>())
        #expect(files.count == 2)
        #expect(files.allSatisfy { !$0.isProjectContext && $0.projectID == project.id && $0.versions.count == 1 })
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
