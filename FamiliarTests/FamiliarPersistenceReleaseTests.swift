import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar release persistence", .serialized)
struct FamiliarPersistenceReleaseTests {
    @Test("Release V1 freezes the current 31 entity schema")
    @MainActor
    func releaseSchemaBaseline() {
        #expect(FamiliarReleaseSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(FamiliarReleaseSchemaV1.models.count == 31)
        #expect(FamiliarReleaseMigrationPlan.schemas.count == 1)
        #expect(FamiliarReleaseMigrationPlan.stages.isEmpty)
        #expect(FamiliarModelContainer.currentSchema.entities.count == 31)
        #expect(FamiliarStoreProfile.development.storeName == "FamiliarDevelopment")
        #expect(FamiliarStoreProfile.release.storeName == "Familiar")
    }

    @Test("A file-backed V1 store reopens with relationships intact")
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
