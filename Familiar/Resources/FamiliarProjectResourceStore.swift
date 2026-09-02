import Foundation

nonisolated enum FamiliarProjectResourceStoreError: LocalizedError, Sendable {
    case invalidRelativePath
    case sourceUnavailable
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .invalidRelativePath:
            String(localized: "resource.error.invalid_path")
        case .sourceUnavailable:
            String(localized: "resource.error.source_unavailable")
        case .copyFailed:
            String(localized: "resource.error.copy_failed")
        }
    }
}

nonisolated struct FamiliarStoredResourceFile: Equatable, Sendable {
    let relativePath: String
    let byteSize: Int64
    let contentHash: String
}

nonisolated struct FamiliarStagedResourceDirectory: Sendable {
    let originalURL: URL
    let stagedURL: URL
}

nonisolated struct FamiliarProjectResourceStore {
    let rootURL: URL
    private let fileManager: FileManager

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Familiar/ProjectResources", isDirectory: true)
    }

    func copyVersion(
        from sourceURL: URL,
        projectID: UUID,
        resourceID: UUID,
        version: Int,
        versionID: UUID,
        filename: String
    ) throws -> FamiliarStoredResourceFile {
        guard version > 0 else { throw FamiliarProjectResourceStoreError.invalidRelativePath }
        let safeFilename = sanitizedFilename(filename)
        let relativePath = "Projects/\(projectID.uuidString)/Resources/\(resourceID.uuidString)/Versions/\(version)-\(versionID.uuidString)/\(safeFilename)"
        let destination = try validatedURL(for: relativePath)
        let size = try regularFileSize(sourceURL)
        let sourceHash = try sha256(of: sourceURL)
        try createDirectory(destination.deletingLastPathComponent())
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
            try applyProtection(to: destination)
            guard try regularFileSize(destination) == size,
                  try sha256(of: destination) == sourceHash
            else { throw FamiliarProjectResourceStoreError.copyFailed }
        } catch let error as FamiliarProjectResourceStoreError {
            try? fileManager.removeItem(at: destination.deletingLastPathComponent())
            throw error
        } catch {
            try? fileManager.removeItem(at: destination.deletingLastPathComponent())
            throw FamiliarProjectResourceStoreError.copyFailed
        }
        return FamiliarStoredResourceFile(relativePath: relativePath, byteSize: size, contentHash: sourceHash)
    }

    func copyText(_ text: String, projectID: UUID, resourceID: UUID, version: Int, versionID: UUID, filename: String) throws -> FamiliarStoredResourceFile {
        try createDirectory(rootURL)
        let temporary = rootURL.appendingPathComponent(".text-\(UUID().uuidString)")
        try Data(text.utf8).write(to: temporary, options: .atomic)
        defer { try? fileManager.removeItem(at: temporary) }
        return try copyVersion(from: temporary, projectID: projectID, resourceID: resourceID, version: version, versionID: versionID, filename: filename)
    }

    func url(for relativePath: String) -> URL? {
        guard let url = try? validatedURL(for: relativePath),
              isRegularFileWithoutSymlinks(url)
        else { return nil }
        return url
    }

    func removeVersion(relativePath: String) throws {
        let fileURL = try validatedURL(for: relativePath)
        let versionDirectory = fileURL.deletingLastPathComponent()
        guard versionDirectory.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else {
            throw FamiliarProjectResourceStoreError.invalidRelativePath
        }
        if fileManager.fileExists(atPath: versionDirectory.path) {
            try fileManager.removeItem(at: versionDirectory)
        }
    }

    func removeResource(projectID: UUID, resourceID: UUID) throws {
        let relativePath = "Projects/\(projectID.uuidString)/Resources/\(resourceID.uuidString)"
        let url = try validatedURL(for: relativePath)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func stageProjectDirectory(projectID: UUID) throws -> FamiliarStagedResourceDirectory? {
        try stageDirectory(relativePath: "Projects/\(projectID.uuidString)", name: projectID.uuidString)
    }

    func stageResourceDirectory(projectID: UUID, resourceID: UUID) throws -> FamiliarStagedResourceDirectory? {
        try stageDirectory(
            relativePath: "Projects/\(projectID.uuidString)/Resources/\(resourceID.uuidString)",
            name: resourceID.uuidString
        )
    }

    private func stageDirectory(relativePath: String, name: String) throws -> FamiliarStagedResourceDirectory? {
        let originalURL = try validatedURL(for: relativePath)
        guard fileManager.fileExists(atPath: originalURL.path) else { return nil }
        guard !containsSymlink(from: rootURL, through: originalURL) else {
            throw FamiliarProjectResourceStoreError.invalidRelativePath
        }
        let trash = rootURL.appendingPathComponent("Trash", isDirectory: true)
        try createDirectory(trash)
        let stagedURL = trash.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.moveItem(at: originalURL, to: stagedURL)
        return FamiliarStagedResourceDirectory(originalURL: originalURL, stagedURL: stagedURL)
    }

    func restore(_ staged: FamiliarStagedResourceDirectory) throws {
        guard staged.stagedURL.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/Trash/") else {
            throw FamiliarProjectResourceStoreError.invalidRelativePath
        }
        try createDirectory(staged.originalURL.deletingLastPathComponent())
        try fileManager.moveItem(at: staged.stagedURL, to: staged.originalURL)
    }

    func discard(_ staged: FamiliarStagedResourceDirectory) throws {
        guard staged.stagedURL.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/Trash/") else {
            throw FamiliarProjectResourceStoreError.invalidRelativePath
        }
        if fileManager.fileExists(atPath: staged.stagedURL.path) {
            try fileManager.removeItem(at: staged.stagedURL)
        }
    }

    func isSafeRelativePath(_ relativePath: String) -> Bool {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        return !normalized.isEmpty
            && !normalized.hasPrefix("/")
            && !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    private func validatedURL(for relativePath: String) throws -> URL {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard isSafeRelativePath(normalized) else {
            throw FamiliarProjectResourceStoreError.invalidRelativePath
        }
        let url = rootURL.appendingPathComponent(normalized).standardizedFileURL
        guard url.path.hasPrefix(rootURL.standardizedFileURL.path + "/"),
              !containsSymlink(from: rootURL, through: url)
        else { throw FamiliarProjectResourceStoreError.invalidRelativePath }
        return url
    }

    private func createDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    private func applyProtection(to url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func regularFileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else {
            throw FamiliarProjectResourceStoreError.sourceUnavailable
        }
        return Int64(size)
    }

    private func isRegularFileWithoutSymlinks(_ url: URL) -> Bool {
        guard !containsSymlink(from: rootURL, through: url),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func containsSymlink(from root: URL, through target: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        guard targetComponents.starts(with: rootComponents) else { return true }
        var current = root.standardizedFileURL
        if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return true
        }
        for component in targetComponents.dropFirst(rootComponents.count) {
            current.appendPathComponent(component)
            guard fileManager.fileExists(atPath: current.path) else { continue }
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                return true
            }
        }
        return false
    }

    /// Delegates to the shared hasher but keeps this store's error contract: any
    /// read failure is reported as `sourceUnavailable`.
    private func sha256(of url: URL) throws -> String {
        do { return try FamiliarHash.sha256(contentsOf: url) }
        catch { throw FamiliarProjectResourceStoreError.sourceUnavailable }
    }

    private func sanitizedFilename(_ filename: String) -> String {
        let base = URL(fileURLWithPath: filename).lastPathComponent
        let filtered = base.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            return (value >= 32 && value != 47 && value != 92 && value != 127) ? Character(String(scalar)) : "_"
        }
        let value = String(filtered).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == "." || value == ".." ? "resource" : String(value.prefix(240))
    }
}
