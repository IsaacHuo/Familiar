import CryptoKit
import Foundation
import SwiftSoup
import SwiftData

nonisolated enum FamiliarFileError: LocalizedError, Sendable {
    case projectRequired, invalidIdentifier, missingFile, invalidPath, transactionFailed
    case emptyFile, unsupportedFormat, contentMismatch, validationFailed(String), fileTooLarge
    var errorDescription: String? {
        switch self {
        case .projectRequired: String(localized: "file.error.project_required")
        case .invalidIdentifier, .invalidPath: String(localized: "file.error.invalid_path")
        case .missingFile: String(localized: "file.error.missing")
        case .transactionFailed: String(localized: "file.error.failed")
        case .emptyFile: String(localized: "file.error.empty")
        case .unsupportedFormat: String(localized: "file.error.unsupported")
        case .contentMismatch: String(localized: "file.error.mismatch")
        case .validationFailed(let detail): String(format: String(localized: "file.error.validation"), detail)
        case .fileTooLarge: String(localized: "file.error.too_large")
        }
    }
}

nonisolated struct FamiliarValidationReceipt: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let validator: String
    let validatorVersion: String
    let format: FamiliarFileFormat
    let extractedTextHash: String
    let checks: [String]
    let validatedAt: Date
}

nonisolated struct FamiliarFileDescriptor: Sendable, Equatable {
    let id: UUID
    let identifier: String
    let projectID: UUID
    let title: String
    /// The file this one replaces, if any. Tools are `nonisolated` and cannot query
    /// the store, so they name the predecessor and the service resolves its lineage and
    /// the next version number. `nil` means a first version that starts its own lineage.
    let supersedesFileID: UUID?
    let format: FamiliarFileFormat
    let relativePath: String
    let byteSize: Int64
    let contentHash: String
    let source: FamiliarFileSource
    let sourceURLString: String?
    let sourceResourceID: UUID?
    let sourceResourceVersionID: UUID?
    let sourceCaptureID: String?
    let createdByRunID: String?
    let utiIdentifier: String?
    let mimeType: String?
    let validationReceipt: FamiliarValidationReceipt?

    init(
        id: UUID,
        identifier: String,
        projectID: UUID,
        title: String,
        supersedesFileID: UUID? = nil,
        format: FamiliarFileFormat,
        relativePath: String,
        byteSize: Int64,
        contentHash: String,
        source: FamiliarFileSource,
        sourceURLString: String?,
        sourceResourceID: UUID?,
        sourceResourceVersionID: UUID?,
        sourceCaptureID: String?,
        createdByRunID: String?,
        utiIdentifier: String? = nil,
        mimeType: String? = nil,
        validationReceipt: FamiliarValidationReceipt? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.projectID = projectID
        self.title = title
        self.supersedesFileID = supersedesFileID
        self.format = format
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.contentHash = contentHash
        self.source = source
        self.sourceURLString = sourceURLString
        self.sourceResourceID = sourceResourceID
        self.sourceResourceVersionID = sourceResourceVersionID
        self.sourceCaptureID = sourceCaptureID
        self.createdByRunID = createdByRunID
        self.utiIdentifier = utiIdentifier
        self.mimeType = mimeType
        self.validationReceipt = validationReceipt
    }
}

nonisolated struct FamiliarStagedFileDirectory: Sendable {
    let originalURL: URL
    let stagedURL: URL
}

nonisolated struct FamiliarFileStore: @unchecked Sendable {
    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Familiar/Artifacts", isDirectory: true)
    }

    func write(_ data: Data, projectID: UUID, fileID: UUID, filename: String) throws -> (path: String, hash: String) {
        let safeName = sanitized(filename)
        let relative = "Projects/\(projectID.uuidString)/Artifacts/\(fileID.uuidString)/\(safeName)"
        let destination = try validate(relative)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                                         attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temporary, options: .atomic)
            try fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporary.path)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: temporary, to: destination)
            return (relative, FamiliarHash.sha256(data))
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw FamiliarFileError.transactionFailed
        }
    }

    func importFile(
        at source: URL,
        projectID: UUID,
        fileID: UUID,
        filename: String,
        maximumBytes: Int64
    ) throws -> (path: String, hash: String, byteSize: Int64) {
        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else {
            throw FamiliarFileError.invalidPath
        }
        let byteSize = Int64(sourceValues.fileSize ?? 0)
        guard byteSize > 0 else { throw FamiliarFileError.emptyFile }
        guard byteSize <= maximumBytes else { throw FamiliarFileError.fileTooLarge }
        let safeName = sanitized(filename)
        let relative = "Projects/\(projectID.uuidString)/Artifacts/\(fileID.uuidString)/\(safeName)"
        let destination = try validate(relative)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: temporary.path, contents: nil) else {
            throw FamiliarFileError.transactionFailed
        }
        do {
            let input = try FileHandle(forReadingFrom: source)
            let output = try FileHandle(forWritingTo: temporary)
            defer {
                try? input.close()
                try? output.close()
            }
            var hasher = SHA256()
            var copied: Int64 = 0
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                copied += Int64(chunk.count)
                guard copied <= maximumBytes else { throw FamiliarFileError.fileTooLarge }
                hasher.update(data: chunk)
                try output.write(contentsOf: chunk)
            }
            guard copied == byteSize else { throw FamiliarFileError.transactionFailed }
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: temporary.path
            )
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: temporary, to: destination)
            return (
                relative,
                hasher.finalize().map { String(format: "%02x", $0) }.joined(),
                copied
            )
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    func read(relativePath: String) throws -> Data {
        let url = try validate(relativePath)
        guard isRegular(url) else { throw FamiliarFileError.missingFile }
        return try Data(contentsOf: url)
    }

    func url(relativePath: String) -> URL? { guard let url = try? validate(relativePath), isRegular(url) else { return nil }; return url }

    func isPath(_ relativePath: String, inProject projectID: UUID, fileID: UUID) -> Bool {
        relativePath.hasPrefix("Projects/\(projectID.uuidString)/Artifacts/\(fileID.uuidString)/")
    }

    func remove(projectID: UUID, fileID: UUID) throws {
        let url = try validate("Projects/\(projectID.uuidString)/Artifacts/\(fileID.uuidString)")
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func editableFile(projectID: UUID, identifier: String) throws -> (id: UUID, filename: String, relativePath: String, data: Data) {
        let prefix = identifier.hasPrefix("file_") ? "file_" : "artifact_"
        guard identifier.hasPrefix(prefix),
              let fileID = UUID(uuidString: String(identifier.dropFirst(prefix.count)))
        else { throw FamiliarFileError.invalidIdentifier }
        let directory = try validate("Projects/\(projectID.uuidString)/Artifacts/\(fileID.uuidString)")
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path),
              let filename = names.first(where: { isRegular(directory.appendingPathComponent($0)) })
        else { throw FamiliarFileError.missingFile }
        let relativePath = "Projects/\(projectID.uuidString)/Artifacts/\(fileID.uuidString)/\(filename)"
        return (fileID, filename, relativePath, try read(relativePath: relativePath))
    }

    func stageProjectDirectory(projectID: UUID) throws -> FamiliarStagedFileDirectory? {
        let originalURL = try validate("Projects/\(projectID.uuidString)")
        guard fileManager.fileExists(atPath: originalURL.path) else { return nil }
        let trash = rootURL.appendingPathComponent("Trash", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        let stagedURL = trash.appendingPathComponent("\(projectID.uuidString)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.moveItem(at: originalURL, to: stagedURL)
        return FamiliarStagedFileDirectory(originalURL: originalURL, stagedURL: stagedURL)
    }

    func stageFileDirectory(projectID: UUID, fileID: UUID) throws -> FamiliarStagedFileDirectory {
        let original = try validate("Projects/\(projectID.uuidString)/Artifacts/\(fileID.uuidString)")
        guard fileManager.fileExists(atPath: original.path) else { throw FamiliarFileError.missingFile }
        let trash = rootURL.appendingPathComponent("Trash", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        let staged = trash.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.moveItem(at: original, to: staged)
        return .init(originalURL: original, stagedURL: staged)
    }

    func restore(_ staged: FamiliarStagedFileDirectory) throws {
        try fileManager.createDirectory(at: staged.originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: staged.stagedURL, to: staged.originalURL)
    }

    func discard(_ staged: FamiliarStagedFileDirectory) throws {
        if fileManager.fileExists(atPath: staged.stagedURL.path) {
            try fileManager.removeItem(at: staged.stagedURL)
        }
    }

    func rename(relativePath: String, projectID: UUID, fileID: UUID, filename: String) throws -> String {
        let oldURL = try validate(relativePath)
        let newRelative = "Projects/\(projectID.uuidString)/Artifacts/\(fileID.uuidString)/\(sanitized(filename))"
        let newURL = try validate(newRelative)
        try fileManager.moveItem(at: oldURL, to: newURL)
        return newRelative
    }

    private func validate(_ relative: String) throws -> URL {
        try FamiliarFilePath.confined(relative, to: rootURL)
    }

    private func isRegular(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
    private func sanitized(_ value: String) -> String { let base = URL(fileURLWithPath: value).lastPathComponent; return base.isEmpty || base == "." || base == ".." ? "file.md" : String(base.prefix(240)) }

}

@MainActor
struct FamiliarFileService {
    let store: FamiliarFileStore

    init(store: FamiliarFileStore = FamiliarFileStore()) { self.store = store }

    func persist(_ descriptor: FamiliarFileDescriptor, in context: ModelContext) throws {
        let descriptorID = descriptor.id
        if let existing = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.id == descriptorID })).first {
            guard existing.projectID == descriptor.projectID, existing.contentHash == descriptor.contentHash,
                  existing.relativePath == descriptor.relativePath, existing.byteSize == descriptor.byteSize,
                  existing.formatRawValue == descriptor.format.rawValue else { throw FamiliarFileError.contentMismatch }
            return
        }
        let file: FamiliarFileRecord
        if let id = descriptor.supersedesFileID {
            guard let predecessor = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.id == id })).first,
                  let owner = predecessor.file, owner.projectID == descriptor.projectID else { throw FamiliarFileError.missingFile }
            file = owner
        } else {
            file = FamiliarFileRecord(id: descriptor.id, projectID: descriptor.projectID, displayName: descriptor.title,
                origin: descriptor.source == .webCapture ? .webCapture : .generated)
            context.insert(file)
        }
        let version = max(file.lastVersionNumber, file.versions.map(\.version).max() ?? 0) + 1
        let fields = ["title": descriptor.title, "format": descriptor.format.rawValue, "source": descriptor.source.rawValue,
            "sourceResourceID": descriptor.sourceResourceID?.uuidString ?? "", "sourceResourceVersionID": descriptor.sourceResourceVersionID?.uuidString ?? "",
            "sourceCaptureID": descriptor.sourceCaptureID ?? "", "utiIdentifier": descriptor.utiIdentifier ?? "",
            "validationReceipt": try descriptor.validationReceipt.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) } ?? ""]
        let provenance = String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)
        let row = FamiliarFileVersionRecord(id: descriptor.id, version: version,
            filename: URL(fileURLWithPath: descriptor.relativePath).lastPathComponent,
            mimeType: descriptor.mimeType ?? descriptor.format.mimeType, byteSize: descriptor.byteSize,
            contentHash: descriptor.contentHash, extractedText: "", extractedTextHash: "",
            storage: .init(kind: .file, relativePath: descriptor.relativePath), sourceURLString: descriptor.sourceURLString,
            provenanceJSON: provenance, createdByRunID: descriptor.createdByRunID, file: file)
        context.insert(row)
        file.displayName = descriptor.title
        file.updatedAt = row.createdAt
        if let runID = descriptor.createdByRunID,
           let chatID = try context.fetch(FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.runtimeID == runID })).first?.conversation?.id,
           !file.chatIDs.contains(chatID) { file.chatIDs += [chatID] }
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    func storedFile(id: UUID, in context: ModelContext) -> FamiliarStoredFileVersion? {
        (try? context.fetch(FetchDescriptor<FamiliarStoredFileVersion>(predicate: #Predicate { $0.id == id })))?.first
    }

    /// One past the highest version already stored in that lineage, so a revision never
    /// reuses a number even if an earlier version was deleted.
    func nextVersion(inLineage lineageID: UUID, in context: ModelContext) -> Int {
        if let file = try? context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.id == lineageID })).first {
            return file.lastVersionNumber + 1
        }
        let existing = (try? context.fetch(FetchDescriptor<FamiliarStoredFileVersion>(
            predicate: #Predicate { $0.fileID == lineageID }
        ))) ?? []
        return (existing.map(\.version).max() ?? 0) + 1
    }

    /// The current version of a logical deliverable. Older versions stay on disk and in
    /// the store, so previewing or exporting a superseded version still works.
    func latestVersion(inLineage lineageID: UUID, in context: ModelContext) -> FamiliarStoredFileVersion? {
        let existing = (try? context.fetch(FetchDescriptor<FamiliarStoredFileVersion>(
            predicate: #Predicate { $0.fileID == lineageID }
        ))) ?? []
        return existing.max { $0.version < $1.version }
    }

    func delete(_ file: FamiliarStoredFileVersion, in context: ModelContext) throws {
        let staged = try store.stageFileDirectory(projectID: file.projectID, fileID: file.id)
        do {
            try FamiliarFileCatalogService().stageRemoval(versionID: file.id, in: context)
            context.delete(file)
            try context.save()
        } catch {
            context.rollback()
            do { try store.restore(staged) }
            catch { throw FamiliarFileError.validationFailed("File deletion rollback failed: \(error.localizedDescription)") }
            throw error
        }
        try? store.discard(staged)
    }

    func removeProjectFiles(projectID: UUID, in context: ModelContext) throws {
        let files = try context.fetch(FetchDescriptor<FamiliarStoredFileVersion>(
            predicate: #Predicate { $0.projectID == projectID }
        ))
        for file in files {
            try store.remove(projectID: projectID, fileID: file.id)
            try FamiliarFileCatalogService().stageRemoval(versionID: file.id, in: context)
            context.delete(file)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func read(_ file: FamiliarStoredFileVersion) throws -> Data {
        guard store.isPath(file.relativePath, inProject: file.projectID, fileID: file.id) else { throw FamiliarFileError.invalidPath }
        return try store.read(relativePath: file.relativePath)
    }

    func rename(_ file: FamiliarStoredFileVersion, to title: String, in context: ModelContext) throws {
        guard store.isPath(file.relativePath, inProject: file.projectID, fileID: file.id) else { throw FamiliarFileError.invalidPath }
        let fileID = file.lineageID
        if let record = try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.id == fileID })).first {
            record.displayName = title
            record.updatedAt = Date()
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    func exportURL(for file: FamiliarStoredFileVersion) -> URL? {
        guard store.isPath(file.relativePath, inProject: file.projectID, fileID: file.id) else { return nil }
        return store.url(relativePath: file.relativePath)
    }
}

nonisolated enum FamiliarFileValidator {
    static let maximumFileBytes: Int64 = 128 * 1_024 * 1_024

    static func validate(
        fileURL: URL,
        format: FamiliarFileFormat,
        requiredText: [String] = [],
        now: Date = Date()
    ) throws -> FamiliarValidationReceipt {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw FamiliarFileError.invalidPath }
        let byteSize = Int64(values.fileSize ?? 0)
        guard byteSize > 0 else { throw FamiliarFileError.emptyFile }
        guard byteSize <= maximumFileBytes else { throw FamiliarFileError.fileTooLarge }
        guard fileURL.pathExtension.lowercased() == format.filenameExtension else {
            throw FamiliarFileError.contentMismatch
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let extracted: String
        let validator: String
        let validatorVersion: String
        var checks = ["regular-file", "non-empty", "extension-matches"]
        switch format {
        case .docx, .xlsx:
            guard data.count >= 4, data[0] == 0x50, data[1] == 0x4B else {
                throw FamiliarFileError.contentMismatch
            }
            let conversion = try FamiliarAnyDocService.convert(data: data, filename: fileURL.lastPathComponent)
            extracted = conversion.markdown
            validator = FamiliarAnyDocService.engineName
            validatorVersion = conversion.engineVersion
            checks += ["zip-signature", "office-package-readable", "extracted-text-non-empty"]
        case .pdf:
            guard data.starts(with: Data("%PDF".utf8)) else { throw FamiliarFileError.contentMismatch }
            let conversion = try FamiliarAnyDocService.convert(data: data, filename: fileURL.lastPathComponent)
            extracted = conversion.markdown
            validator = FamiliarAnyDocService.engineName
            validatorVersion = conversion.engineVersion
            checks += ["pdf-signature", "pdf-readable", "extracted-text-non-empty"]
        case .html:
            guard let source = String(data: data, encoding: .utf8) else { throw FamiliarFileError.contentMismatch }
            let document = try SwiftSoup.parse(source)
            extracted = try document.text()
            validator = "SwiftSoup"
            validatorVersion = "2.13.7"
            checks += ["utf8", "html-parseable", "extracted-text-non-empty"]
        case .markdown, .plainText:
            guard let source = String(data: data, encoding: .utf8) else { throw FamiliarFileError.contentMismatch }
            extracted = source
            validator = "FamiliarTextValidator"
            validatorVersion = "1"
            checks += ["utf8", "text-non-empty"]
        }
        let normalized = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw FamiliarFileError.validationFailed("未提取到可检查的正文。") }
        let required = Array(Set(requiredText.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }))
        guard required.count <= 16 else { throw FamiliarFileError.validationFailed("Too many required content checks.") }
        for term in required where normalized.localizedCaseInsensitiveContains(term) == false {
            throw FamiliarFileError.validationFailed("缺少必需内容：\(term)")
        }
        if !required.isEmpty { checks.append("required-content") }
        return FamiliarValidationReceipt(
            schemaVersion: FamiliarValidationReceipt.currentSchemaVersion,
            validator: validator,
            validatorVersion: validatorVersion,
            format: format,
            extractedTextHash: FamiliarHash.sha256(normalized),
            checks: checks,
            validatedAt: now
        )
    }
}
