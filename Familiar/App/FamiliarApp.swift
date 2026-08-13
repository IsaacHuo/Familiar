import Foundation
import SwiftData
import SwiftUI

@main
struct FamiliarApp: App {
    @UIApplicationDelegateAdaptor(FamiliarAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer?
    private let storeError: String?
    private let dependencies: FamiliarAppDependencies

    init() {
        dependencies = FamiliarAppDependencies()
        do {
            modelContainer = try Self.makeModelContainer()
            storeError = nil
        } catch {
            modelContainer = nil
            storeError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                FamiliarRootView(dependencies: dependencies)
                    .tint(FamiliarTheme.accent)
                    .modelContainer(modelContainer)
            } else {
                FamiliarStoreRecoveryView(diagnostic: storeError ?? "未知错误")
                    .tint(FamiliarTheme.accent)
            }
        }
    }

    private static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            FamiliarConversation.self,
            FamiliarMessage.self,
            FamiliarSourceRecord.self,
            FamiliarAttachment.self,
            FamiliarModelSwitchRecord.self,
            FamiliarAgentRun.self,
            FamiliarAgentStep.self
        ])
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let persistence = support.appendingPathComponent("Familiar/Persistence", isDirectory: true)
        try fileManager.createDirectory(at: persistence, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let storeURL = persistence.appendingPathComponent("FamiliarAgentV2.store")
        let isNew = !fileManager.fileExists(atPath: storeURL.path)
        let configuration = ModelConfiguration("FamiliarAgentV2", schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        if isNew {
            removeStore(named: "FamiliarAgentV1", in: persistence, fileManager: fileManager)
            removeStore(named: "default", in: support, fileManager: fileManager)
            let oldAttachments = support.appendingPathComponent("Familiar/Attachments", isDirectory: true)
            try? fileManager.removeItem(at: oldAttachments)
        }
        return container
    }

    static func resetV2Store() throws {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try resetV2Store(in: support, fileManager: fileManager)
    }

    static func resetV2Store(in support: URL, fileManager: FileManager = .default) throws {
        let persistence = support.appendingPathComponent("Familiar/Persistence", isDirectory: true)
        removeStore(named: "FamiliarAgentV2", in: persistence, fileManager: fileManager)
        let attachments = support.appendingPathComponent("Familiar/Attachments", isDirectory: true)
        guard fileManager.fileExists(atPath: attachments.path) else { return }
        try fileManager.removeItem(at: attachments)
    }

    private static func removeStore(named name: String, in directory: URL, fileManager: FileManager) {
        let base = directory.appendingPathComponent(name + ".store")
        for url in [base, URL(fileURLWithPath: base.path + "-shm"), URL(fileURLWithPath: base.path + "-wal")] {
            try? fileManager.removeItem(at: url)
        }
    }
}

private struct FamiliarStoreRecoveryView: View {
    let diagnostic: String
    @State private var asksToRebuild = false
    @State private var resultMessage: String?

    var body: some View {
        ContentUnavailableView {
            Label("无法打开本地数据", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(resultMessage ?? "Familiar 无法读取本地会话。诊断：\(String(diagnostic.prefix(240)))")
        } actions: {
            Button("重建本地数据", role: .destructive) { asksToRebuild = true }
                .disabled(resultMessage != nil)
        }
        .confirmationDialog("重建会删除本地会话与附件，但会保留钥匙串中的 API Key。", isPresented: $asksToRebuild, titleVisibility: .visible) {
            Button("确认重建", role: .destructive) {
                do {
                    try FamiliarApp.resetV2Store()
                    resultMessage = "本地数据已清理。请重新启动 Familiar。"
                } catch {
                    resultMessage = "清理失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
