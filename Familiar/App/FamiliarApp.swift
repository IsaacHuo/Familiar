import Foundation
import SwiftData
import SwiftUI

@main
struct FamiliarApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                FamiliarConversation.self,
                FamiliarMessage.self,
                FamiliarAttachment.self,
                FamiliarModelSwitchRecord.self,
                FamiliarToolRunRecord.self
            ])
            modelContainer = try Self.makeModelContainer(schema: schema)
        } catch {
            fatalError("Familiar 本地会话数据库初始化失败：\(error.localizedDescription)")
        }
    }

    private static func makeModelContainer(schema: Schema) throws -> ModelContainer {
        let fileManager = FileManager.default
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let persistenceURL = applicationSupportURL
            .appendingPathComponent("Familiar", isDirectory: true)
            .appendingPathComponent("Persistence", isDirectory: true)
        try fileManager.createDirectory(at: persistenceURL, withIntermediateDirectories: true)

        let storeURL = persistenceURL.appendingPathComponent("FamiliarAgentV1.store")
        let isCreatingCurrentStore = !fileManager.fileExists(atPath: storeURL.path)
        let configuration = ModelConfiguration(
            "FamiliarAgentV1",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])

        if isCreatingCurrentStore {
            removeLegacyDevelopmentStore(in: applicationSupportURL, fileManager: fileManager)
        }
        return container
    }

    private static func removeLegacyDevelopmentStore(
        in applicationSupportURL: URL,
        fileManager: FileManager
    ) {
        let legacyStoreURL = applicationSupportURL.appendingPathComponent("default.store")
        let legacyStoreFiles = [
            legacyStoreURL,
            URL(fileURLWithPath: legacyStoreURL.path + "-shm"),
            URL(fileURLWithPath: legacyStoreURL.path + "-wal")
        ]
        let hadLegacyStore = legacyStoreFiles.contains {
            fileManager.fileExists(atPath: $0.path)
        }
        guard hadLegacyStore else { return }

        for url in legacyStoreFiles {
            try? fileManager.removeItem(at: url)
        }
        let legacyAttachmentsURL = applicationSupportURL
            .appendingPathComponent("Familiar", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        try? fileManager.removeItem(at: legacyAttachmentsURL)
    }

    var body: some Scene {
        WindowGroup {
            FamiliarRootView()
                .tint(FamiliarTheme.accent)
        }
        .modelContainer(modelContainer)
    }
}
