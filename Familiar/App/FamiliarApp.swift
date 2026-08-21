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
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let persistence = support.appendingPathComponent("Familiar/Persistence", isDirectory: true)
        try fileManager.createDirectory(at: persistence, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let storeURL = persistence.appendingPathComponent(FamiliarModelContainer.storeFilename)
        let isNew = !fileManager.fileExists(atPath: storeURL.path)
        let container = try FamiliarModelContainer.make(at: storeURL)
        if isNew {
            removeStore(named: "FamiliarAgentV2", in: persistence, fileManager: fileManager)
            removeStore(named: "FamiliarAgentV1", in: persistence, fileManager: fileManager)
            removeStore(named: "default", in: support, fileManager: fileManager)
            for directory in ["Attachments", "ProjectResources", "Artifacts"] {
                try? fileManager.removeItem(
                    at: support.appendingPathComponent("Familiar/\(directory)", isDirectory: true)
                )
            }
        }
        return container
    }

    static func resetStore() throws {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try resetStore(in: support, fileManager: fileManager)
    }

    static func resetStore(in support: URL, fileManager: FileManager = .default) throws {
        let persistence = support.appendingPathComponent("Familiar/Persistence", isDirectory: true)
        removeStore(named: FamiliarModelContainer.storeName, in: persistence, fileManager: fileManager)
        let attachments = support.appendingPathComponent("Familiar/Attachments", isDirectory: true)
        if fileManager.fileExists(atPath: attachments.path) { try fileManager.removeItem(at: attachments) }
        let projectResources = support.appendingPathComponent("Familiar/ProjectResources", isDirectory: true)
        if fileManager.fileExists(atPath: projectResources.path) { try fileManager.removeItem(at: projectResources) }
        let artifacts = support.appendingPathComponent("Familiar/Artifacts", isDirectory: true)
        if fileManager.fileExists(atPath: artifacts.path) { try fileManager.removeItem(at: artifacts) }
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
        .confirmationDialog("重建会删除本地会话、附件、项目资料和产物，但会保留钥匙串中的 API Key。", isPresented: $asksToRebuild, titleVisibility: .visible) {
            Button("确认重建", role: .destructive) {
                do {
                    try FamiliarApp.resetStore()
                    resultMessage = "本地数据已清理。请重新启动 Familiar。"
                } catch {
                    resultMessage = "清理失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
