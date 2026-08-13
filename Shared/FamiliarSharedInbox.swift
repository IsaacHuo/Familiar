import Foundation

nonisolated struct FamiliarSharedInboxPayload: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        let storedName: String
        let originalName: String
        let byteSize: Int64
    }

    let id: UUID
    let createdAt: Date
    let text: String
    let files: [File]
}

nonisolated struct FamiliarSharedInboxItem: Equatable, Sendable {
    let payload: FamiliarSharedInboxPayload
    let directoryURL: URL

    var fileURLs: [URL] {
        payload.files.map { directoryURL.appendingPathComponent($0.storedName, isDirectory: false) }
    }
}

nonisolated enum FamiliarSharedInboxError: LocalizedError, Sendable {
    case containerUnavailable
    case noContent
    case tooManyFiles
    case fileTooLarge
    case sourceUnavailable
    case invalidPayload
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            String(localized: "share.error.container_unavailable", defaultValue: "Familiar’s shared inbox is unavailable.")
        case .noContent:
            String(localized: "share.error.no_content", defaultValue: "There is no text or file to share.")
        case .tooManyFiles:
            String(localized: "share.error.too_many_files", defaultValue: "You can share up to 3 files at a time.")
        case .fileTooLarge:
            String(localized: "share.error.file_too_large", defaultValue: "Each shared file must be 25 MiB or smaller.")
        case .sourceUnavailable:
            String(localized: "share.error.source_unavailable", defaultValue: "A shared file is no longer available.")
        case .invalidPayload:
            String(localized: "share.error.invalid_payload", defaultValue: "The shared item is invalid.")
        case .writeFailed:
            String(localized: "share.error.write_failed", defaultValue: "The shared item could not be saved.")
        }
    }
}

nonisolated enum FamiliarSharedInbox {
    static let appGroupIdentifier = "group.com.isaachuo.familiar"
    static let maximumTextCharacters = 20_000
    static let maximumFiles = 3
    static let maximumFileBytes: Int64 = 25 * 1024 * 1024

    private static let inboxDirectoryName = "ShareInbox"
    private static let manifestName = "manifest.json"
    private static var fileManager: FileManager { FileManager.default }

    @discardableResult
    static func enqueue(text: String, fileURLs: [URL]) throws -> UUID {
        guard let rootURL = sharedRootURL() else {
            throw FamiliarSharedInboxError.containerUnavailable
        }
        return try enqueue(text: text, fileURLs: fileURLs, rootURL: rootURL)
    }

    static func pendingItems() throws -> [FamiliarSharedInboxItem] {
        guard let rootURL = sharedRootURL() else { return [] }
        return try pendingItems(rootURL: rootURL)
    }

    static func remove(_ item: FamiliarSharedInboxItem) {
        try? fileManager.removeItem(at: item.directoryURL)
    }

    @discardableResult
    static func enqueue(text: String, fileURLs: [URL], rootURL: URL) throws -> UUID {
        guard fileURLs.count <= maximumFiles else { throw FamiliarSharedInboxError.tooManyFiles }
        let boundedText = String(text.prefix(maximumTextCharacters))
        guard !boundedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !fileURLs.isEmpty else {
            throw FamiliarSharedInboxError.noContent
        }

        let id = UUID()
        let inboxURL = rootURL.appendingPathComponent(inboxDirectoryName, isDirectory: true)
        let stagingURL = inboxURL.appendingPathComponent(".\(id.uuidString).staging", isDirectory: true)
        let destinationURL = inboxURL.appendingPathComponent(id.uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

            var storedFiles: [FamiliarSharedInboxPayload.File] = []
            for sourceURL in fileURLs {
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    throw FamiliarSharedInboxError.sourceUnavailable
                }
                let size = try fileSize(of: sourceURL)
                guard size <= maximumFileBytes else { throw FamiliarSharedInboxError.fileTooLarge }
                let originalName = sanitizedFilename(sourceURL.lastPathComponent)
                let storedName = UUID().uuidString + "-" + originalName
                let storedURL = stagingURL.appendingPathComponent(storedName, isDirectory: false)
                try fileManager.copyItem(at: sourceURL, to: storedURL)
                guard try fileSize(of: storedURL) == size else { throw FamiliarSharedInboxError.writeFailed }
                storedFiles.append(.init(storedName: storedName, originalName: originalName, byteSize: size))
            }

            let payload = FamiliarSharedInboxPayload(
                id: id,
                createdAt: Date(),
                text: boundedText,
                files: storedFiles
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: stagingURL.appendingPathComponent(manifestName), options: .atomic)
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
            return id
        } catch let error as FamiliarSharedInboxError {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw FamiliarSharedInboxError.writeFailed
        }
    }

    static func pendingItems(rootURL: URL) throws -> [FamiliarSharedInboxItem] {
        let inboxURL = rootURL.appendingPathComponent(inboxDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: inboxURL.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        return try directories.compactMap { directoryURL in
            do {
                let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true else { return nil }
                guard values.isSymbolicLink != true else { throw FamiliarSharedInboxError.invalidPayload }
                let manifestURL = directoryURL.appendingPathComponent(manifestName, isDirectory: false)
                guard let data = try? Data(contentsOf: manifestURL),
                      let payload = try? JSONDecoder().decode(FamiliarSharedInboxPayload.self, from: data),
                      payload.id.uuidString == directoryURL.lastPathComponent,
                      payload.files.count <= maximumFiles,
                      payload.text.count <= maximumTextCharacters,
                      payload.files.allSatisfy({ isSafeStoredName($0.storedName) })
                else { throw FamiliarSharedInboxError.invalidPayload }

                for (file, url) in zip(payload.files, payload.files.map({ directoryURL.appendingPathComponent($0.storedName) })) {
                    guard file.byteSize <= maximumFileBytes,
                          fileManager.fileExists(atPath: url.path),
                          try fileSize(of: url) == file.byteSize
                    else { throw FamiliarSharedInboxError.invalidPayload }
                }
                return FamiliarSharedInboxItem(payload: payload, directoryURL: directoryURL)
            } catch {
                try? fileManager.removeItem(at: directoryURL)
                throw FamiliarSharedInboxError.invalidPayload
            }
        }
        .sorted { $0.payload.createdAt < $1.payload.createdAt }
    }

    private static func sharedRootURL() -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    private static func fileSize(of url: URL) throws -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize
        else { throw FamiliarSharedInboxError.sourceUnavailable }
        return Int64(size)
    }

    private static func sanitizedFilename(_ filename: String) -> String {
        let base = URL(fileURLWithPath: filename).lastPathComponent
        let cleaned = base.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            if value < 32 || value == 127 || scalar == "/" || scalar == "\\" { return "_" }
            return Character(String(scalar))
        }
        let result = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return String((result.isEmpty ? "Shared File" : result).prefix(180))
    }

    private static func isSafeStoredName(_ name: String) -> Bool {
        !name.isEmpty
            && name == URL(fileURLWithPath: name).lastPathComponent
            && !name.contains("/")
            && !name.contains("\\")
            && name != "."
            && name != ".."
    }
}
