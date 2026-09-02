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
    let environment: URL
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

nonisolated struct FamiliarWorkspaceUsage: Equatable, Sendable {
    let totalBytes: Int64
    let largestFileBytes: Int64
}

/// A per-command host view. Only this view is mounted into a shell runtime.
/// Inputs are immutable copies; Outputs are the workspace's durable output
/// directory; Work is unique to one task and is removed at terminal state.
nonisolated struct FamiliarWorkspaceTaskView: Equatable, Sendable {
    let taskID: UUID
    let workspaceID: FamiliarWorkspaceID
    let root: URL
    let files: URL
    let outputs: URL
    let work: URL
    let environment: URL
    let environmentIsPersistent: Bool
}

nonisolated enum FamiliarWorkspaceCheckpointScope: Sendable {
    case workspace
    case shellOutputs
}

nonisolated struct FamiliarWorkspaceCheckpoint: Sendable {
    let id: UUID
    let workspaceID: FamiliarWorkspaceID
    let rootURL: URL
    let createdAt: Date
    let scope: FamiliarWorkspaceCheckpointScope
}

nonisolated struct FamiliarStagedWorkspaceDirectory: Sendable {
    let workspaceID: FamiliarWorkspaceID
    let originalURL: URL
    let stagedURL: URL?
}

nonisolated enum FamiliarWorkspaceError: LocalizedError, Sendable {
    case invalidPath
    case symbolicLinkNotAllowed
    case missingFile
    case quotaExceeded(limit: Int64)
    case checkpointUnavailable
    case invalidTaskView

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
        case .invalidTaskView:
            "Shell task Workspace 视图无效。"
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
        let environment = runtime.appendingPathComponent("Environment", isDirectory: true)
        var directories = [root, metadata, files, outputs, runtime, work, tasks, checkpoints]
        if case .project = id { directories.append(environment) }
        for directory in directories {
            try ensureDirectory(directory)
        }
        return FamiliarWorkspacePaths(
            root: root,
            metadata: metadata,
            files: files,
            outputs: outputs,
            runtime: runtime,
            work: work,
            tasks: tasks,
            checkpoints: checkpoints,
            environment: environment
        )
    }

    func shellSettingsURL(in id: FamiliarWorkspaceID) throws -> URL {
        try prepare(id).metadata.appendingPathComponent("shell-settings.json", isDirectory: false)
    }

    func prepareShellTaskView(
        taskID: UUID,
        workspaceID: FamiliarWorkspaceID,
        resources: [FamiliarToolContext.Resource],
        attachments: [FamiliarToolContext.Attachment],
        useStagingEnvironment: Bool = false
    ) throws -> FamiliarWorkspaceTaskView {
        let paths = try prepare(workspaceID)
        let taskRoot = paths.tasks.appendingPathComponent(taskID.uuidString.lowercased(), isDirectory: true)
        guard isConfined(taskRoot, below: paths.tasks), !fileManager.fileExists(atPath: taskRoot.path) else {
            throw FamiliarWorkspaceError.invalidTaskView
        }
        let inputs = taskRoot.appendingPathComponent("Files", isDirectory: true)
        let work = taskRoot.appendingPathComponent("Work", isDirectory: true)
        let environmentIsPersistent: Bool
        let environment: URL
        switch workspaceID {
        case .project where !useStagingEnvironment:
            environmentIsPersistent = true
            environment = paths.environment
        case .project, .conversation:
            environmentIsPersistent = false
            environment = taskRoot.appendingPathComponent("Environment", isDirectory: true)
        }
        do {
            try ensureDirectory(inputs)
            try ensureDirectory(work)
            try ensureDirectory(environment)
            for resource in resources {
                let directory = inputs
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(resource.id.uuidString.lowercased(), isDirectory: true)
                try ensureDirectory(directory)
                let destination = directory.appendingPathComponent(safeFilename(resource.filename), isDirectory: false)
                try Data(resource.extractedText.utf8).write(to: destination, options: [.atomic])
                try protectFile(destination)
            }
            for attachment in attachments {
                let directory = inputs
                    .appendingPathComponent("Attachments", isDirectory: true)
                    .appendingPathComponent(attachment.id.uuidString.lowercased(), isDirectory: true)
                try ensureDirectory(directory)
                let destination = directory.appendingPathComponent(safeFilename(attachment.filename), isDirectory: false)
                if let source = FamiliarAttachmentStore.url(for: attachment.relativePath) {
                    guard !isSymbolicLink(source) else { throw FamiliarWorkspaceError.symbolicLinkNotAllowed }
                    let sourceSize = Int64(
                        try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    )
                    guard sourceSize == attachment.byteSize,
                          sourceSize <= FamiliarAttachmentStore.maximumSourceBytes
                    else { throw FamiliarWorkspaceError.invalidTaskView }
                    try fileManager.copyItem(at: source, to: destination)
                } else if attachment.kind != .image {
                    try Data(attachment.extractedText.utf8).write(to: destination, options: [.atomic])
                } else {
                    throw FamiliarWorkspaceError.missingFile
                }
                try protectFile(destination)
            }
            try makeTreeReadOnly(inputs)
        } catch {
            try? makeTreeWritable(taskRoot)
            try? fileManager.removeItem(at: taskRoot)
            throw error
        }
        return FamiliarWorkspaceTaskView(
            taskID: taskID,
            workspaceID: workspaceID,
            root: taskRoot,
            files: inputs,
            outputs: paths.outputs,
            work: work,
            environment: environment,
            environmentIsPersistent: environmentIsPersistent
        )
    }

    func removeShellTaskView(_ view: FamiliarWorkspaceTaskView) throws {
        let paths = try prepare(view.workspaceID)
        guard isConfined(view.root, below: paths.tasks),
              view.root.lastPathComponent == view.taskID.uuidString.lowercased()
        else { throw FamiliarWorkspaceError.invalidTaskView }
        guard fileManager.fileExists(atPath: view.root.path) else { return }
        try makeTreeWritable(view.root)
        try fileManager.removeItem(at: view.root)
    }

    func projectEnvironmentURL(_ projectID: UUID) throws -> URL {
        let paths = try prepare(.project(projectID))
        guard isConfined(paths.environment, below: paths.runtime),
              !isSymbolicLink(paths.environment)
        else { throw FamiliarWorkspaceError.invalidTaskView }
        return paths.environment
    }

    func commitProjectEnvironment(
        from view: FamiliarWorkspaceTaskView,
        projectID: UUID
    ) throws {
        guard view.workspaceID == .project(projectID),
              !view.environmentIsPersistent,
              isConfined(view.environment, below: view.root),
              !isSymbolicLink(view.environment)
        else { throw FamiliarWorkspaceError.invalidTaskView }
        try assertNoSymbolicLinks(below: view.environment)
        let paths = try prepare(.project(projectID))
        let backup = paths.runtime.appendingPathComponent(
            "Environment.backup-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        do {
            if fileManager.fileExists(atPath: paths.environment.path) {
                try fileManager.moveItem(at: paths.environment, to: backup)
            }
            try fileManager.moveItem(at: view.environment, to: paths.environment)
            if fileManager.fileExists(atPath: backup.path) {
                try fileManager.removeItem(at: backup)
            }
        } catch {
            if !fileManager.fileExists(atPath: paths.environment.path),
               fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: paths.environment)
            }
            throw error
        }
    }

    func removeWorkspace(_ id: FamiliarWorkspaceID) throws {
        let root = rootURL.appendingPathComponent(id.directoryName, isDirectory: true).standardizedFileURL
        guard isConfined(root, below: rootURL.standardizedFileURL) else {
            throw FamiliarWorkspaceError.invalidPath
        }
        guard fileManager.fileExists(atPath: root.path) else { return }
        guard !isSymbolicLink(root) else { throw FamiliarWorkspaceError.symbolicLinkNotAllowed }
        try makeTreeWritable(root)
        try fileManager.removeItem(at: root)
    }

    func stageWorkspace(_ id: FamiliarWorkspaceID) throws -> FamiliarStagedWorkspaceDirectory {
        let original = rootURL.appendingPathComponent(id.directoryName, isDirectory: true).standardizedFileURL
        guard isConfined(original, below: rootURL.standardizedFileURL) else {
            throw FamiliarWorkspaceError.invalidPath
        }
        guard fileManager.fileExists(atPath: original.path) else {
            return FamiliarStagedWorkspaceDirectory(workspaceID: id, originalURL: original, stagedURL: nil)
        }
        guard !isSymbolicLink(original) else { throw FamiliarWorkspaceError.symbolicLinkNotAllowed }
        let trash = rootURL.appendingPathComponent(".Trash", isDirectory: true)
        try ensureDirectory(trash)
        let staged = trash.appendingPathComponent(
            "\(id.directoryName)-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        guard isConfined(staged, below: trash), !fileManager.fileExists(atPath: staged.path) else {
            throw FamiliarWorkspaceError.invalidPath
        }
        try fileManager.moveItem(at: original, to: staged)
        return FamiliarStagedWorkspaceDirectory(workspaceID: id, originalURL: original, stagedURL: staged)
    }

    func restore(_ staged: FamiliarStagedWorkspaceDirectory) throws {
        guard let stagedURL = staged.stagedURL else { return }
        guard isConfined(stagedURL, below: rootURL.appendingPathComponent(".Trash", isDirectory: true)),
              !fileManager.fileExists(atPath: staged.originalURL.path),
              fileManager.fileExists(atPath: stagedURL.path),
              !isSymbolicLink(stagedURL)
        else { throw FamiliarWorkspaceError.invalidPath }
        try fileManager.moveItem(at: stagedURL, to: staged.originalURL)
    }

    func discard(_ staged: FamiliarStagedWorkspaceDirectory) throws {
        guard let stagedURL = staged.stagedURL else { return }
        guard isConfined(stagedURL, below: rootURL.appendingPathComponent(".Trash", isDirectory: true)) else {
            throw FamiliarWorkspaceError.invalidPath
        }
        guard fileManager.fileExists(atPath: stagedURL.path) else { return }
        guard !isSymbolicLink(stagedURL) else { throw FamiliarWorkspaceError.symbolicLinkNotAllowed }
        try makeTreeWritable(stagedURL)
        try fileManager.removeItem(at: stagedURL)
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

    func shellWritableUsage(for view: FamiliarWorkspaceTaskView) throws -> FamiliarWorkspaceUsage {
        let paths = try prepare(view.workspaceID)
        guard view.outputs.standardizedFileURL == paths.outputs.standardizedFileURL,
              isConfined(view.root, below: paths.tasks),
              view.root.lastPathComponent == view.taskID.uuidString.lowercased(),
              isConfined(view.work, below: view.root),
              !isSymbolicLink(view.outputs),
              !isSymbolicLink(view.work)
        else { throw FamiliarWorkspaceError.invalidTaskView }

        var totalBytes: Int64 = 0
        var largestFileBytes: Int64 = 0
        let roots = view.environmentIsPersistent
            ? [view.outputs, view.work]
            : [view.outputs, view.work, view.environment]
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: []
            ) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                ) else { continue }
                if values.isSymbolicLink == true {
                    throw FamiliarWorkspaceError.symbolicLinkNotAllowed
                }
                guard values.isRegularFile == true else { continue }
                let byteSize = Int64(values.fileSize ?? 0)
                totalBytes += byteSize
                largestFileBytes = max(largestFileBytes, byteSize)
            }
        }
        return FamiliarWorkspaceUsage(totalBytes: totalBytes, largestFileBytes: largestFileBytes)
    }

    func createCheckpoint(
        for id: FamiliarWorkspaceID,
        checkpointID: UUID = UUID(),
        now: Date = Date()
    ) throws -> FamiliarWorkspaceCheckpoint {
        let paths = try prepare(id)
        for root in [paths.files, paths.outputs, paths.work] {
            try assertNoSymbolicLinks(below: root)
        }
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
            createdAt: now,
            scope: .workspace
        )
    }

    func createShellCheckpoint(
        for id: FamiliarWorkspaceID,
        checkpointID: UUID = UUID(),
        now: Date = Date()
    ) throws -> FamiliarWorkspaceCheckpoint {
        let paths = try prepare(id)
        try assertNoSymbolicLinks(below: paths.outputs)
        let checkpointRoot = paths.checkpoints.appendingPathComponent(
            checkpointID.uuidString.lowercased(),
            isDirectory: true
        )
        guard isConfined(checkpointRoot, below: paths.checkpoints),
              !fileManager.fileExists(atPath: checkpointRoot.path)
        else { throw FamiliarWorkspaceError.checkpointUnavailable }
        try ensureDirectory(checkpointRoot)
        try fileManager.copyItem(
            at: paths.outputs,
            to: checkpointRoot.appendingPathComponent("Outputs", isDirectory: true)
        )
        return FamiliarWorkspaceCheckpoint(
            id: checkpointID,
            workspaceID: id,
            rootURL: checkpointRoot,
            createdAt: now,
            scope: .shellOutputs
        )
    }

    func diff(
        from checkpoint: FamiliarWorkspaceCheckpoint
    ) throws -> FamiliarWorkspaceDiff {
        let currentPaths = try prepare(checkpoint.workspaceID)
        guard fileManager.fileExists(atPath: checkpoint.rootURL.path) else {
            throw FamiliarWorkspaceError.checkpointUnavailable
        }
        let currentRoots: [URL]
        let previousRoots: [URL]
        switch checkpoint.scope {
        case .workspace:
            currentRoots = [currentPaths.files, currentPaths.outputs, currentPaths.work]
            previousRoots = ["Files", "Outputs", "Work"].map {
                checkpoint.rootURL.appendingPathComponent($0, isDirectory: true)
            }
        case .shellOutputs:
            currentRoots = [currentPaths.outputs]
            previousRoots = [checkpoint.rootURL.appendingPathComponent("Outputs", isDirectory: true)]
        }
        let current = try snapshotMap(roots: currentRoots, base: currentPaths.root)
        let previous = try snapshotMap(roots: previousRoots, base: checkpoint.rootURL)
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
        let destinations: [(URL, String)] = switch checkpoint.scope {
        case .workspace: [(paths.files, "Files"), (paths.outputs, "Outputs"), (paths.work, "Work")]
        case .shellOutputs: [(paths.outputs, "Outputs")]
        }
        for (destination, name) in destinations {
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
        for component in components {
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
            options: []
        ) else { return [] }
        var result: [FamiliarWorkspaceEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw FamiliarWorkspaceError.symbolicLinkNotAllowed
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
            contentHash: FamiliarHash.sha256(data)
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

    private func ensureDirectory(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            guard !isSymbolicLink(url),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { throw FamiliarWorkspaceError.symbolicLinkNotAllowed }
            return
        }
        let parent = url.deletingLastPathComponent()
        if parent.path != url.path, parent.path.hasPrefix(rootURL.standardizedFileURL.path),
           fileManager.fileExists(atPath: parent.path), isSymbolicLink(parent) {
            throw FamiliarWorkspaceError.symbolicLinkNotAllowed
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: directoryAttributes)
    }

    private func isConfined(_ url: URL, below directory: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        let root = directory.standardizedFileURL.path
        return candidate.hasPrefix(root + "/")
    }

    private func safeFilename(_ value: String) -> String {
        let candidate = URL(fileURLWithPath: value).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty || candidate == "." || candidate == ".." ? "file" : candidate
    }

    private func protectFile(_ url: URL) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o444]
#if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
#endif
        try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
    }

    private func makeTreeReadOnly(_ root: URL) throws {
        if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw FamiliarWorkspaceError.symbolicLinkNotAllowed }
                try fileManager.setAttributes(
                    [.posixPermissions: values.isDirectory == true ? 0o555 : 0o444],
                    ofItemAtPath: url.path
                )
            }
        }
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
    }

    private func makeTreeWritable(_ root: URL) throws {
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for case let url as URL in enumerator {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                try? fileManager.setAttributes([.posixPermissions: isDirectory ? 0o700 : 0o600], ofItemAtPath: url.path)
            }
        }
    }

    private func assertNoSymbolicLinks(below directory: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return }
        for case let url as URL in enumerator {
            if isSymbolicLink(url) { throw FamiliarWorkspaceError.symbolicLinkNotAllowed }
        }
    }

    private var directoryAttributes: [FileAttributeKey: Any] {
#if os(iOS)
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
#else
        [:]
#endif
    }
}
