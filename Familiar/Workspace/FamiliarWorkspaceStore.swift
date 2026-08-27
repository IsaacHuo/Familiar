import CryptoKit
import Foundation

nonisolated enum FamiliarWorkspaceID: Hashable, Codable, Sendable {
    case project(UUID)
    case conversation(UUID)

    var rawID: UUID {
        switch self {
        case .project(let id), .conversation(let id): id
        }
    }

    var directoryName: String {
        switch self {
        case .project(let id): "project-\(id.uuidString.lowercased())"
        case .conversation(let id): "conversation-\(id.uuidString.lowercased())"
        }
    }
}

nonisolated struct FamiliarWorkspacePaths: Sendable {
    let root: URL
    let metadata: URL
    let files: URL
    let outputs: URL
    let runtime: URL
    let work: URL
    let tasks: URL
    let checkpoints: URL
}

nonisolated struct FamiliarWorkspaceEntry: Equatable, Sendable {
    let relativePath: String
    let byteSize: Int64
    let modifiedAt: Date?
    let contentHash: String
}

nonisolated struct FamiliarWorkspaceDiff: Equatable, Sendable {
    let added: [String]
    let modified: [String]
    let removed: [String]
}

nonisolated struct FamiliarWorkspaceCheckpoint: Sendable {
    let id: UUID
    let workspaceID: FamiliarWorkspaceID
    let rootURL: URL
    let createdAt: Date
}

nonisolated enum FamiliarWorkspaceError: LocalizedError, Sendable {
    case invalidPath
    case symbolicLinkNotAllowed
    case missingFile
    case quotaExceeded(limit: Int64)
    case checkpointUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            "Workspace 路径无效。"
        case .symbolicLinkNotAllowed:
            "Workspace 不允许通过符号链接访问文件。"
        case .missingFile:
            "Workspace 文件不存在。"
        case .quotaExceeded(let limit):
            "Workspace 已超过 \(limit) 字节的存储上限。"
        case .checkpointUnavailable:
            "Workspace checkpoint 不可用。"
        }
    }
}

nonisolated struct FamiliarWorkspaceStore: @unchecked Sendable {
    static let iOSQuotaBytes: Int64 = 500 * 1_024 * 1_024
    static let macOSQuotaBytes: Int64 = 10 * 1_024 * 1_024 * 1_024

    let rootURL: URL
    let quotaBytes: Int64
    private let fileManager: FileManager

    init(
        rootURL: URL? = nil,
        quotaBytes: Int64? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Familiar/Workspaces", isDirectory: true)
#if os(macOS)
        self.quotaBytes = quotaBytes ?? Self.macOSQuotaBytes
#else
        self.quotaBytes = quotaBytes ?? Self.iOSQuotaBytes
#endif
    }

    func prepare(_ id: FamiliarWorkspaceID) throws -> FamiliarWorkspacePaths {
        let root = rootURL.appendingPathComponent(id.directoryName, isDirectory: true)
        let metadata = root.appendingPathComponent("Metadata", isDirectory: true)
        let files = root.appendingPathComponent("Files", isDirectory: true)
        let outputs = root.appendingPathComponent("Outputs", isDirectory: true)
        let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
        let work = runtime.appendingPathComponent("Work", isDirectory: true)
        let tasks = runtime.appendingPathComponent("Tasks", isDirectory: true)
        let checkpoints = runtime.appendingPathComponent("Checkpoints", isDirectory: true)
        for directory in [metadata, files, outputs, work, tasks, checkpoints] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: directoryAttributes
            )
        }
        return FamiliarWorkspacePaths(
            root: root,
            metadata: metadata,
            files: files,
            outputs: outputs,
            runtime: runtime,
            work: work,
            tasks: tasks,
            checkpoints: checkpoints
        )
    }

    func read(relativePath: String, in id: FamiliarWorkspaceID) throws -> Data {
        let url = try validatedURL(relativePath: relativePath, in: id)
        guard isRegularFile(url) else { throw FamiliarWorkspaceError.missingFile }
        return try Data(contentsOf: url)
    }

    func contains(relativePath: String, in id: FamiliarWorkspaceID) throws -> Bool {
        let url = try validatedURL(relativePath: relativePath, in: id)
        return isRegularFile(url)
    }

    func remove(relativePath: String, in id: FamiliarWorkspaceID) throws {
        let url = try validatedURL(relativePath: relativePath, in: id)
        guard isRegularFile(url) else { throw FamiliarWorkspaceError.missingFile }
        try fileManager.removeItem(at: url)
    }

    @discardableResult
    func write(
        _ data: Data,
        relativePath: String,
        in id: FamiliarWorkspaceID
    ) throws -> FamiliarWorkspaceEntry {
        let url = try validatedURL(relativePath: relativePath, in: id)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: directoryAttributes
        )
        let currentSize = try workspaceSize(id)
        let previousSize = fileSize(url)
        guard currentSize - previousSize + Int64(data.count) <= quotaBytes else {
            throw FamiliarWorkspaceError.quotaExceeded(limit: quotaBytes)
        }
        try data.write(to: url, options: [.atomic])
#if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
#endif
        return try entry(for: url, workspaceRoot: try prepare(id).root)
    }

    func entries(in id: FamiliarWorkspaceID) throws -> [FamiliarWorkspaceEntry] {
        let paths = try prepare(id)
        return try [paths.files, paths.outputs, paths.work]
            .flatMap { try entries(below: $0, workspaceRoot: paths.root) }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    func workspaceSize(_ id: FamiliarWorkspaceID) throws -> Int64 {
        let paths = try prepare(id)
        return try [paths.files, paths.outputs, paths.work].reduce(into: 0) { total, directory in
            total += try entries(below: directory, workspaceRoot: paths.root).reduce(0) { $0 + $1.byteSize }
        }
    }

    func createCheckpoint(
        for id: FamiliarWorkspaceID,
        checkpointID: UUID = UUID(),
        now: Date = Date()
    ) throws -> FamiliarWorkspaceCheckpoint {
        let paths = try prepare(id)
        let checkpointRoot = paths.checkpoints.appendingPathComponent(
            checkpointID.uuidString.lowercased(),
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: checkpointRoot,
            withIntermediateDirectories: true,
            attributes: directoryAttributes
        )
        for (source, name) in [(paths.files, "Files"), (paths.outputs, "Outputs"), (paths.work, "Work")] {
            let destination = checkpointRoot.appendingPathComponent(name, isDirectory: true)
            try fileManager.copyItem(at: source, to: destination)
        }
        return FamiliarWorkspaceCheckpoint(
            id: checkpointID,
            workspaceID: id,
            rootURL: checkpointRoot,
            createdAt: now
        )
    }

    func diff(
        from checkpoint: FamiliarWorkspaceCheckpoint
    ) throws -> FamiliarWorkspaceDiff {
        let currentPaths = try prepare(checkpoint.workspaceID)
        guard fileManager.fileExists(atPath: checkpoint.rootURL.path) else {
            throw FamiliarWorkspaceError.checkpointUnavailable
        }
        let current = try snapshotMap(
            roots: [currentPaths.files, currentPaths.outputs, currentPaths.work],
            base: currentPaths.root
        )
        let previous = try snapshotMap(
            roots: [
                checkpoint.rootURL.appendingPathComponent("Files", isDirectory: true),
                checkpoint.rootURL.appendingPathComponent("Outputs", isDirectory: true),
                checkpoint.rootURL.appendingPathComponent("Work", isDirectory: true)
            ],
            base: checkpoint.rootURL
        )
        let currentKeys = Set(current.keys)
        let previousKeys = Set(previous.keys)
        return FamiliarWorkspaceDiff(
            added: currentKeys.subtracting(previousKeys).sorted(),
            modified: currentKeys.intersection(previousKeys).filter { current[$0] != previous[$0] }.sorted(),
            removed: previousKeys.subtracting(currentKeys).sorted()
        )
    }

    func restore(_ checkpoint: FamiliarWorkspaceCheckpoint) throws {
        let paths = try prepare(checkpoint.workspaceID)
        guard fileManager.fileExists(atPath: checkpoint.rootURL.path) else {
            throw FamiliarWorkspaceError.checkpointUnavailable
        }
        for (destination, name) in [(paths.files, "Files"), (paths.outputs, "Outputs"), (paths.work, "Work")] {
            let source = checkpoint.rootURL.appendingPathComponent(name, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path) else {
                throw FamiliarWorkspaceError.checkpointUnavailable
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    func removeCheckpoint(_ checkpoint: FamiliarWorkspaceCheckpoint) throws {
        guard checkpoint.rootURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else {
            throw FamiliarWorkspaceError.invalidPath
        }
        if fileManager.fileExists(atPath: checkpoint.rootURL.path) {
            try fileManager.removeItem(at: checkpoint.rootURL)
        }
    }

    private func validatedURL(
        relativePath: String,
        in id: FamiliarWorkspaceID
    ) throws -> URL {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              let first = components.first,
              ["Files", "Outputs", "Runtime"].contains(String(first))
        else {
            throw FamiliarWorkspaceError.invalidPath
        }
        if first == "Runtime", components.dropFirst().first != "Work" {
            throw FamiliarWorkspaceError.invalidPath
        }
        let root = try prepare(id).root.standardizedFileURL
        let url = root.appendingPathComponent(normalized).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else {
            throw FamiliarWorkspaceError.invalidPath
        }
        var cursor = root
        for component in components.dropLast() {
            cursor.appendPathComponent(String(component))
            guard !isSymbolicLink(cursor) else {
                throw FamiliarWorkspaceError.symbolicLinkNotAllowed
            }
        }
        return url
    }

    private func entries(
        below directory: URL,
        workspaceRoot: URL
    ) throws -> [FamiliarWorkspaceEntry] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [FamiliarWorkspaceEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            result.append(try entry(for: url, workspaceRoot: workspaceRoot))
        }
        return result
    }

    private func entry(for url: URL, workspaceRoot: URL) throws -> FamiliarWorkspaceEntry {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let relative = String(url.standardizedFileURL.path.dropFirst(workspaceRoot.standardizedFileURL.path.count + 1))
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return FamiliarWorkspaceEntry(
            relativePath: relative,
            byteSize: Int64(values.fileSize ?? data.count),
            modifiedAt: values.contentModificationDate,
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func snapshotMap(roots: [URL], base: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for root in roots where fileManager.fileExists(atPath: root.path) {
            for item in try entries(below: root, workspaceRoot: base) {
                result[item.relativePath] = item.contentHash
            }
        }
        return result
    }

    private func fileSize(_ url: URL) -> Int64 {
        guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return 0 }
        return Int64(value)
    }

    private func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private var directoryAttributes: [FileAttributeKey: Any] {
#if os(iOS)
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
#else
        [:]
#endif
    }
}
