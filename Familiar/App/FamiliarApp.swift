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
                    .transformEnvironment(\.dynamicTypeSize) { value in
                        if FamiliarChatTestScenario.accessibilityEnabled { value = .accessibility3 }
                    }
            } else {
                FamiliarStoreRecoveryView(diagnostic: storeError ?? "未知错误")
                    .tint(FamiliarTheme.accent)
            }
        }
    }

    private static func makeModelContainer() throws -> ModelContainer {
#if DEBUG && targetEnvironment(simulator)
        if FamiliarChatTestScenario.isEnabled {
            if let id = FamiliarChatTestScenario.persistentStoreID {
                let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Familiar/Verification/UITests/" + id, isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                return try FamiliarModelContainer.make(at: root.appendingPathComponent("Functional.store"), configurationName: "FunctionalUI")
            }
            return try FamiliarModelContainer.makeInMemory(name: "PresentationTests")
        }
#endif
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let didReset = try FamiliarBusinessDataGeneration.prepare(in: support, fileManager: fileManager)
        let persistence = support.appendingPathComponent("Familiar/Persistence", isDirectory: true)
        try fileManager.createDirectory(at: persistence, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let storeURL = persistence.appendingPathComponent(FamiliarModelContainer.storeFilename)
        let container = try FamiliarModelContainer.make(at: storeURL)
        if didReset {
            try FamiliarSharedInbox.removeAll()
            try FamiliarBusinessDataGeneration.finish(in: support, fileManager: fileManager)
            Task { await FamiliarSpotlightIndexer.shared.replaceConversations([]) }
        }
        return container
    }

    static func resetStore() throws {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try resetStore(in: support, fileManager: fileManager)
        try FamiliarSharedInbox.removeAll()
    }

    static func resetStore(in support: URL, fileManager: FileManager = .default) throws {
        try FamiliarBusinessDataGeneration.reset(in: support, fileManager: fileManager)
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
        .confirmationDialog("重建会删除本地 Project、Chat、Files 和执行记录，但会保留钥匙串中的 API Key。", isPresented: $asksToRebuild, titleVisibility: .visible) {
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
