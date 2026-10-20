import Foundation
import os
import SwiftData

nonisolated struct FamiliarStorageUsage: Sendable {
    var bytes: [String: Int64] = [:]
    var conversations = 0
    var messages = 0
    var files = 0
    var versions = 0
    var unreadableFiles = 0
    var total: Int64 { bytes.values.reduce(0, +) }
}

@ModelActor actor FamiliarStorageInventory {
    func measure(root: URL) throws -> FamiliarStorageUsage {
        var usage = try Self.scan(root: root)
        usage.conversations = try modelContext.fetchCount(FetchDescriptor<FamiliarConversation>())
        usage.messages = try modelContext.fetchCount(FetchDescriptor<FamiliarMessage>())
        usage.files = try modelContext.fetchCount(FetchDescriptor<FamiliarFileRecord>())
        usage.versions = try modelContext.fetchCount(FetchDescriptor<FamiliarFileVersionRecord>())
        return usage
    }

    nonisolated static func scan(root: URL) throws -> FamiliarStorageUsage {
        var usage = FamiliarStorageUsage(), identities = Set<AnyHashable>()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .fileResourceIdentifierKey]
        guard FileManager.default.fileExists(atPath: root.path) else { return usage }
        let failures = OSAllocatedUnfairLock(initialState: 0)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in
            failures.withLock { $0 += 1 }; return true
        }) else { throw CocoaError(.fileReadNoPermission) }
        let prefix = root.standardizedFileURL.path + "/"
        for case let url as URL in walker {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { usage.unreadableFiles += 1; continue }
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }
            if let identity = values.fileResourceIdentifier as? AnyHashable, !identities.insert(identity).inserted { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            let top = path.dropFirst(prefix.count).split(separator: "/").first.map(String.init) ?? ""
            let category: String
            switch top {
            case "Attachments": category = "settings.storage.attachments"
            case "Artifacts", "Files", "ProjectResources": category = "settings.storage.files"
            case "Workspaces": category = "settings.storage.workspaces"
            case "ShellRuntime": category = "settings.storage.runtime"
            case "Persistence": category = "settings.storage.database"
            default: category = "settings.storage.other"
            }
            guard let size = values.fileSize else { usage.unreadableFiles += 1; continue }
            usage.bytes[category, default: 0] += Int64(size)
        }
        usage.unreadableFiles += failures.withLock { $0 }
        return usage
    }
}

nonisolated enum FamiliarStorageMeasurement {
    static func load(container: ModelContainer) async throws -> FamiliarStorageUsage {
        let task = Task.detached(priority: .utility) {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Familiar", isDirectory: true)
            return try await FamiliarStorageInventory(modelContainer: container).measure(root: root)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
