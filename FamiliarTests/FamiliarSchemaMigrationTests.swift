import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar schema migration")
struct FamiliarSchemaMigrationTests {
    @Test("A populated disk-backed V1 store migrates to V4 without data loss")
    @MainActor
    func populatedV1StoreReopensThroughMigrationPlan() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("FamiliarSchemaMigrationTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = root.appendingPathComponent(FamiliarModelContainer.storeFilename)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let conversationID = UUID()
        let messageID = UUID()
        let attachmentID = UUID()
        let sourceID = UUID()
        let switchID = UUID()
        let runID = UUID()
        let stepID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        try autoreleasepool {
            let schema = Schema(versionedSchema: FamiliarSchemaV1.self)
            let configuration = ModelConfiguration(
                FamiliarModelContainer.storeName,
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let conversation = FamiliarSchemaV1.FamiliarConversation(
                id: conversationID,
                title: "Migrated conversation",
                createdAt: timestamp,
                updatedAt: timestamp,
                currentProviderID: "provider.current",
                currentModelID: "model.current"
            )
            let message = FamiliarSchemaV1.FamiliarMessage(
                id: messageID,
                role: .assistant,
                content: "Preserved message",
                createdAt: timestamp,
                sequence: 7,
                providerID: "provider.message",
                modelID: "model.message",
                conversation: conversation
            )
            let attachment = FamiliarSchemaV1.FamiliarAttachment(
                id: attachmentID,
                kind: .document,
                filename: "fixture.pdf",
                mimeType: "application/pdf",
                relativePath: "Messages/fixture/fixture.pdf",
                extractedText: "Preserved attachment text",
                byteSize: 42,
                extractionEngine: "fixture",
                extractionVersion: "1",
                detectedFormat: "pdf",
                usedOCR: true,
                createdAt: timestamp,
                message: message
            )
            let source = FamiliarSchemaV1.FamiliarSourceRecord(
                id: sourceID,
                sourceID: "source.fixture",
                kind: .fetchedPage,
                title: "Preserved source",
                urlString: "https://example.com/source",
                siteName: "Example",
                snippet: "Source snippet",
                sequence: 3,
                retrievedAt: timestamp,
                message: message
            )
            let modelSwitch = FamiliarSchemaV1.FamiliarModelSwitchRecord(
                id: switchID,
                previousProviderID: "provider.previous",
                previousModelID: "model.previous",
                currentProviderID: "provider.current",
                currentModelID: "model.current",
                sequence: 5,
                createdAt: timestamp,
                conversation: conversation
            )
            let run = FamiliarSchemaV1.FamiliarAgentRun(
                id: runID,
                runtimeID: "runtime.fixture",
                status: .completed,
                startedAt: timestamp,
                conversation: conversation
            )
            run.finishedAt = timestamp.addingTimeInterval(10)
            run.finishReason = "completed"
            run.responseMessageID = messageID
            let step = FamiliarSchemaV1.FamiliarAgentStep(
                id: stepID,
                type: .tool,
                eventSequence: 9,
                timelineSequence: 4,
                toolCallID: "call.fixture",
                toolName: "fixture_tool",
                summary: "Preserved step",
                detail: "Step detail",
                confirmation: .confirmed,
                status: .succeeded,
                startedAt: timestamp,
                finishedAt: timestamp.addingTimeInterval(5),
                artifactIdentifier: "artifact.fixture",
                run: run
            )

            container.mainContext.insert(conversation)
            container.mainContext.insert(message)
            container.mainContext.insert(attachment)
            container.mainContext.insert(source)
            container.mainContext.insert(modelSwitch)
            container.mainContext.insert(run)
            container.mainContext.insert(step)
            try container.mainContext.save()
        }

        #expect(fileManager.fileExists(atPath: storeURL.path))

        let container = try FamiliarModelContainer.make(at: storeURL)
        let conversation = try #require(container.mainContext.fetch(FetchDescriptor<FamiliarConversation>()).first)
        let message = try #require(container.mainContext.fetch(FetchDescriptor<FamiliarMessage>()).first)
        let attachment = try #require(container.mainContext.fetch(FetchDescriptor<FamiliarAttachment>()).first)
        let source = try #require(container.mainContext.fetch(FetchDescriptor<FamiliarSourceRecord>()).first)
        let modelSwitch = try #require(container.mainContext.fetch(FetchDescriptor<FamiliarModelSwitchRecord>()).first)
        let run = try #require(container.mainContext.fetch(FetchDescriptor<FamiliarAgentRun>()).first)
        let step = try #require(container.mainContext.fetch(FetchDescriptor<FamiliarAgentStep>()).first)

        #expect(conversation.id == conversationID)
        #expect(conversation.title == "Migrated conversation")
        #expect(conversation.messages.map(\.id) == [messageID])
        #expect(conversation.modelSwitchRecords.map(\.id) == [switchID])
        #expect(conversation.agentRuns.map(\.id) == [runID])
        #expect(conversation.project == nil)
        #expect(message.content == "Preserved message")
        #expect(message.conversation?.id == conversationID)
        #expect(message.attachments.map(\.id) == [attachmentID])
        #expect(message.sources.map(\.id) == [sourceID])
        #expect(attachment.extractedText == "Preserved attachment text")
        #expect(attachment.message?.id == messageID)
        #expect(attachment.resourceVersion == nil)
        #expect(source.sourceID == "source.fixture")
        #expect(source.message?.id == messageID)
        #expect(modelSwitch.conversation?.id == conversationID)
        #expect(run.runtimeID == "runtime.fixture")
        #expect(run.conversation?.id == conversationID)
        #expect(run.project == nil)
        #expect(run.steps.map(\.id) == [stepID])
        #expect(step.run?.id == runID)
        #expect(container.migrationPlan != nil)
    }

    @Test("The shared in-memory helper uses the current versioned schema")
    @MainActor
    func inMemoryHelperUsesVersionedSchema() throws {
        let container = try FamiliarTestStore.make()

        #expect(container.schema.version == FamiliarSchemaV6.versionIdentifier)
        #expect(container.migrationPlan != nil)
        #expect(Set(container.schema.entities.map(\.name)) == [
            "FamiliarConversation",
            "FamiliarMessage",
            "FamiliarSourceRecord",
            "FamiliarAttachment",
            "FamiliarModelSwitchRecord",
            "FamiliarAgentRun",
            "FamiliarAgentStep",
            "FamiliarProject",
            "FamiliarProjectInstruction",
            "FamiliarResource",
            "FamiliarResourceVersion",
            "FamiliarContextSnapshotRecord",
            "FamiliarContextResourceReference"
             ,"FamiliarArtifact",
             "FamiliarCapabilitySnapshotRecord",
             "FamiliarAuthorizationGrantRecord",
             "FamiliarRunResumeCursorRecord",
             "FamiliarToolInvocationRecord"
        ])
    }

    @Test("A populated disk-backed V2 store migrates to V3 and preserves optional relationships")
    @MainActor
    func populatedV2StoreMigratesToV3() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("FamiliarV2ToV3MigrationTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = root.appendingPathComponent(FamiliarModelContainer.storeFilename)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let projectID = UUID()
        let conversationID = UUID()
        let attachmentID = UUID()

        try autoreleasepool {
            let schema = Schema(versionedSchema: FamiliarSchemaV2.self)
            let configuration = ModelConfiguration(FamiliarModelContainer.storeName, schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let project = FamiliarSchemaV2.FamiliarProject(id: projectID, name: "V2 Project")
            let conversation = FamiliarSchemaV2.FamiliarConversation(id: conversationID, title: "V2 Chat", project: project)
            let message = FamiliarSchemaV2.FamiliarMessage(role: .user, content: "preserved", sequence: 0, conversation: conversation)
            let attachment = FamiliarSchemaV2.FamiliarAttachment(
                id: attachmentID,
                kind: .document,
                filename: "v2.txt",
                mimeType: "text/plain",
                relativePath: "Messages/v2/v2.txt",
                extractedText: "V2 attachment",
                byteSize: 13,
                extractionEngine: "fixture",
                extractionVersion: "2",
                detectedFormat: "txt",
                usedOCR: false,
                message: message
            )
            container.mainContext.insert(project)
            container.mainContext.insert(conversation)
            container.mainContext.insert(message)
            container.mainContext.insert(attachment)
            try container.mainContext.save()
        }

        let container = try FamiliarModelContainer.make(at: storeURL)
        let project = try #require(container.mainContext.fetch(FetchDescriptor<FamiliarProject>()).first)
        let conversation = try #require(container.mainContext.fetch(FetchDescriptor<FamiliarConversation>()).first)
        let attachment = try #require(container.mainContext.fetch(FetchDescriptor<FamiliarAttachment>()).first)
        #expect(project.id == projectID)
        #expect(project.resources.isEmpty)
        #expect(conversation.id == conversationID)
        #expect(conversation.project?.id == projectID)
        #expect(attachment.id == attachmentID)
        #expect(attachment.extractedText == "V2 attachment")
        #expect(attachment.resourceVersion == nil)
        #expect(try container.mainContext.fetch(FetchDescriptor<FamiliarContextSnapshotRecord>()).isEmpty)
    }

    @Test("A lightweight migration can add an optional relationship")
    @MainActor
    func optionalRelationshipMigration() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("FamiliarRelationshipMigrationTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = root.appendingPathComponent("RelationshipFixture.store")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let itemID = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: OptionalRelationshipFixtureV1.self)
            let configuration = ModelConfiguration("RelationshipFixture", schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.insert(OptionalRelationshipFixtureV1.Item(id: itemID, title: "Preserved"))
            try container.mainContext.save()
        }

        let schema = Schema(versionedSchema: OptionalRelationshipFixtureV2.self)
        let configuration = ModelConfiguration("RelationshipFixture", schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: OptionalRelationshipFixtureMigrationPlan.self,
            configurations: [configuration]
        )
        let item = try #require(container.mainContext.fetch(
            FetchDescriptor<OptionalRelationshipFixtureV2.Item>()
        ).first)

        #expect(item.id == itemID)
        #expect(item.title == "Preserved")
        #expect(item.folder == nil)
    }

    @Test("Opening a corrupt current store throws without deleting it")
    @MainActor
    func corruptStoreFailureIsObservableAndNonDestructive() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("FamiliarCorruptStoreTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = root.appendingPathComponent(FamiliarModelContainer.storeFilename)
        let corruptData = Data("not a SQLite store".utf8)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try corruptData.write(to: storeURL)
        defer { try? fileManager.removeItem(at: root) }

        #expect(throws: Error.self) {
            try FamiliarModelContainer.make(at: storeURL)
        }
        #expect(fileManager.fileExists(atPath: storeURL.path))
        #expect(try Data(contentsOf: storeURL) == corruptData)
    }
}

private enum OptionalRelationshipFixtureV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Item.self] }

    @Model
    final class Item {
        @Attribute(.unique) var id: UUID
        var title: String

        init(id: UUID, title: String) {
            self.id = id
            self.title = title
        }
    }
}

private enum OptionalRelationshipFixtureV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Item.self, Folder.self] }

    @Model
    final class Item {
        @Attribute(.unique) var id: UUID
        var title: String
        var folder: Folder?

        init(id: UUID, title: String, folder: Folder? = nil) {
            self.id = id
            self.title = title
            self.folder = folder
        }
    }

    @Model
    final class Folder {
        @Attribute(.unique) var id: UUID

        @Relationship(deleteRule: .nullify, inverse: \Item.folder)
        var items: [Item]

        init(id: UUID = UUID()) {
            self.id = id
            items = []
        }
    }
}

private enum OptionalRelationshipFixtureMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OptionalRelationshipFixtureV1.self, OptionalRelationshipFixtureV2.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: OptionalRelationshipFixtureV1.self, toVersion: OptionalRelationshipFixtureV2.self)]
    }
}
