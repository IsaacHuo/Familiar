import CryptoKit
import Foundation
import SwiftSoup
import SwiftData

nonisolated enum FamiliarArtifactError: LocalizedError, Sendable {
    case projectRequired, invalidIdentifier, missingArtifact, invalidPath, transactionFailed
    case emptyFile, unsupportedFormat, contentMismatch, validationFailed(String), fileTooLarge
    var errorDescription: String? {
        switch self {
        case .projectRequired: "Artifact 只能写入项目。"
        case .invalidIdentifier, .invalidPath: "Artifact 路径无效。"
        case .missingArtifact: "Artifact 不存在。"
        case .transactionFailed: "Artifact 操作未完成。"
        case .emptyFile: "Artifact 文件为空。"
        case .unsupportedFormat: "Artifact 文件格式不受支持。"
        case .contentMismatch: "Artifact 扩展名与真实文件内容不匹配。"
        case .validationFailed(let detail): "Artifact 验证失败：\(detail)"
        case .fileTooLarge: "Artifact 文件超过允许大小。"
        }
    }
}

nonisolated struct FamiliarValidationReceipt: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let validator: String
    let validatorVersion: String
    let format: FamiliarArtifactFormat
    let extractedTextHash: String
    let checks: [String]
    let validatedAt: Date
}

nonisolated struct FamiliarArtifactDescriptor: Sendable, Equatable {
    let id: UUID
    let identifier: String
    let projectID: UUID
    let title: String
    /// The artifact this one replaces, if any. Tools are `nonisolated` and cannot query
    /// the store, so they name the predecessor and the service resolves its lineage and
    /// the next version number. `nil` means a first version that starts its own lineage.
    let supersedesArtifactID: UUID?
    let format: FamiliarArtifactFormat
    let relativePath: String
    let byteSize: Int64
    let contentHash: String
    let source: FamiliarArtifactSource
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
        supersedesArtifactID: UUID? = nil,
        format: FamiliarArtifactFormat,
        relativePath: String,
        byteSize: Int64,
        contentHash: String,
        source: FamiliarArtifactSource,
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
        self.supersedesArtifactID = supersedesArtifactID
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

nonisolated struct FamiliarStagedArtifactDirectory: Sendable {
    let originalURL: URL
    let stagedURL: URL
}

nonisolated struct FamiliarArtifactStore: @unchecked Sendable {
    let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Familiar/Artifacts", isDirectory: true)
    }

    func write(_ data: Data, projectID: UUID, artifactID: UUID, filename: String) throws -> (path: String, hash: String) {
        let safeName = sanitized(filename)
        let relative = "Projects/\(projectID.uuidString)/Artifacts/\(artifactID.uuidString)/\(safeName)"
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
            throw FamiliarArtifactError.transactionFailed
        }
    }

    func importFile(
        at source: URL,
        projectID: UUID,
        artifactID: UUID,
        filename: String,
        maximumBytes: Int64
    ) throws -> (path: String, hash: String, byteSize: Int64) {
        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else {
            throw FamiliarArtifactError.invalidPath
        }
        let byteSize = Int64(sourceValues.fileSize ?? 0)
        guard byteSize > 0 else { throw FamiliarArtifactError.emptyFile }
        guard byteSize <= maximumBytes else { throw FamiliarArtifactError.fileTooLarge }
        let safeName = sanitized(filename)
        let relative = "Projects/\(projectID.uuidString)/Artifacts/\(artifactID.uuidString)/\(safeName)"
        let destination = try validate(relative)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: temporary.path, contents: nil) else {
            throw FamiliarArtifactError.transactionFailed
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
                guard copied <= maximumBytes else { throw FamiliarArtifactError.fileTooLarge }
                hasher.update(data: chunk)
                try output.write(contentsOf: chunk)
            }
            guard copied == byteSize else { throw FamiliarArtifactError.transactionFailed }
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
        guard isRegular(url) else { throw FamiliarArtifactError.missingArtifact }
        return try Data(contentsOf: url)
    }

    func url(relativePath: String) -> URL? { guard let url = try? validate(relativePath), isRegular(url) else { return nil }; return url }

    func isPath(_ relativePath: String, inProject projectID: UUID, artifactID: UUID) -> Bool {
        relativePath.hasPrefix("Projects/\(projectID.uuidString)/Artifacts/\(artifactID.uuidString)/")
    }

    func remove(projectID: UUID, artifactID: UUID) throws {
        let url = try validate("Projects/\(projectID.uuidString)/Artifacts/\(artifactID.uuidString)")
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func editableArtifact(projectID: UUID, identifier: String) throws -> (id: UUID, filename: String, relativePath: String, data: Data) {
        guard identifier.hasPrefix("artifact_"),
              let artifactID = UUID(uuidString: String(identifier.dropFirst("artifact_".count)))
        else { throw FamiliarArtifactError.invalidIdentifier }
        let directory = try validate("Projects/\(projectID.uuidString)/Artifacts/\(artifactID.uuidString)")
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path),
              let filename = names.first(where: { isRegular(directory.appendingPathComponent($0)) })
        else { throw FamiliarArtifactError.missingArtifact }
        let relativePath = "Projects/\(projectID.uuidString)/Artifacts/\(artifactID.uuidString)/\(filename)"
        return (artifactID, filename, relativePath, try read(relativePath: relativePath))
    }

    func stageProjectDirectory(projectID: UUID) throws -> FamiliarStagedArtifactDirectory? {
        let originalURL = try validate("Projects/\(projectID.uuidString)")
        guard fileManager.fileExists(atPath: originalURL.path) else { return nil }
        let trash = rootURL.appendingPathComponent("Trash", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        let stagedURL = trash.appendingPathComponent("\(projectID.uuidString)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.moveItem(at: originalURL, to: stagedURL)
        return FamiliarStagedArtifactDirectory(originalURL: originalURL, stagedURL: stagedURL)
    }

    func restore(_ staged: FamiliarStagedArtifactDirectory) throws {
        try fileManager.createDirectory(at: staged.originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: staged.stagedURL, to: staged.originalURL)
    }

    func discard(_ staged: FamiliarStagedArtifactDirectory) throws {
        if fileManager.fileExists(atPath: staged.stagedURL.path) {
            try fileManager.removeItem(at: staged.stagedURL)
        }
    }

    func rename(relativePath: String, projectID: UUID, artifactID: UUID, filename: String) throws -> String {
        let oldURL = try validate(relativePath)
        let newRelative = "Projects/\(projectID.uuidString)/Artifacts/\(artifactID.uuidString)/\(sanitized(filename))"
        let newURL = try validate(newRelative)
        try fileManager.moveItem(at: oldURL, to: newURL)
        return newRelative
    }

    private func validate(_ relative: String) throws -> URL {
        let normalized = relative.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !normalized.isEmpty, !normalized.hasPrefix("/"), !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { throw FamiliarArtifactError.invalidPath }
        let url = rootURL.appendingPathComponent(normalized).standardizedFileURL
        guard url.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else { throw FamiliarArtifactError.invalidPath }
        return url
    }

    private func isRegular(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
    private func sanitized(_ value: String) -> String { let base = URL(fileURLWithPath: value).lastPathComponent; return base.isEmpty || base == "." || base == ".." ? "artifact.md" : String(base.prefix(240)) }

}

@MainActor
struct FamiliarArtifactService {
    let store: FamiliarArtifactStore

    init(store: FamiliarArtifactStore = FamiliarArtifactStore()) { self.store = store }

    func persist(_ descriptor: FamiliarArtifactDescriptor, in context: ModelContext) throws {
        let descriptorID = descriptor.id
        let existing = try context.fetch(FetchDescriptor<FamiliarArtifact>(predicate: #Predicate { $0.id == descriptorID })).first
        if let existing {
            existing.title = descriptor.title
            existing.formatRawValue = descriptor.format.rawValue
            existing.relativePath = descriptor.relativePath
            existing.byteSize = descriptor.byteSize
            existing.contentHash = descriptor.contentHash
            existing.utiIdentifier = descriptor.utiIdentifier
            existing.mimeType = descriptor.mimeType
            existing.validationReceiptJSON = descriptor.validationReceipt.flatMap {
                try? String(decoding: JSONEncoder().encode($0), as: UTF8.self)
            }
            existing.updatedAt = Date()
            try context.save()
            return
        }
        // Lineage and version are resolved here rather than trusted from the descriptor:
        // the tools are nonisolated and cannot query the store, so a tool-supplied number
        // would collide as soon as two revisions of the same deliverable are published.
        let predecessor = descriptor.supersedesArtifactID.flatMap { storedArtifact(id: $0, in: context) }
        let lineageID = predecessor?.lineageID
        let version = lineageID.map { nextVersion(inLineage: $0, in: context) } ?? 1
        let artifact = FamiliarArtifact(id: descriptor.id, projectID: descriptor.projectID, identifier: descriptor.identifier,
            title: descriptor.title, lineageID: lineageID, version: version,
            format: descriptor.format, relativePath: descriptor.relativePath,
            byteSize: descriptor.byteSize, contentHash: descriptor.contentHash, source: descriptor.source,
            sourceURLString: descriptor.sourceURLString, sourceResourceID: descriptor.sourceResourceID,
            sourceResourceVersionID: descriptor.sourceResourceVersionID, sourceCaptureID: descriptor.sourceCaptureID,
            createdByRunID: descriptor.createdByRunID, utiIdentifier: descriptor.utiIdentifier,
            mimeType: descriptor.mimeType, validationReceiptJSON: descriptor.validationReceipt.flatMap {
                try? String(decoding: JSONEncoder().encode($0), as: UTF8.self)
            })
        context.insert(artifact)
        do { try context.save() } catch { context.rollback(); try? store.remove(projectID: descriptor.projectID, artifactID: descriptor.id); throw error }
    }

    func storedArtifact(id: UUID, in context: ModelContext) -> FamiliarArtifact? {
        (try? context.fetch(FetchDescriptor<FamiliarArtifact>(predicate: #Predicate { $0.id == id })))?.first
    }

    /// One past the highest version already stored in that lineage, so a revision never
    /// reuses a number even if an earlier version was deleted.
    func nextVersion(inLineage lineageID: UUID, in context: ModelContext) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<FamiliarArtifact>(
            predicate: #Predicate { $0.lineageID == lineageID }
        ))) ?? []
        return (existing.map(\.version).max() ?? 0) + 1
    }

    /// The current version of a logical deliverable. Older versions stay on disk and in
    /// the store, so previewing or exporting a superseded version still works.
    func latestVersion(inLineage lineageID: UUID, in context: ModelContext) -> FamiliarArtifact? {
        let existing = (try? context.fetch(FetchDescriptor<FamiliarArtifact>(
            predicate: #Predicate { $0.lineageID == lineageID }
        ))) ?? []
        return existing.max { $0.version < $1.version }
    }

    func delete(_ artifact: FamiliarArtifact, in context: ModelContext) throws {
        context.delete(artifact)
        do { try context.save(); try store.remove(projectID: artifact.projectID, artifactID: artifact.id) }
        catch { context.rollback(); throw error }
    }

    func removeProjectArtifacts(projectID: UUID, in context: ModelContext) throws {
        let artifacts = try context.fetch(FetchDescriptor<FamiliarArtifact>(
            predicate: #Predicate { $0.projectID == projectID }
        ))
        for artifact in artifacts {
            try store.remove(projectID: projectID, artifactID: artifact.id)
            context.delete(artifact)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func read(_ artifact: FamiliarArtifact) throws -> Data {
        guard store.isPath(artifact.relativePath, inProject: artifact.projectID, artifactID: artifact.id) else { throw FamiliarArtifactError.invalidPath }
        return try store.read(relativePath: artifact.relativePath)
    }

    func rename(_ artifact: FamiliarArtifact, to title: String, in context: ModelContext) throws {
        guard store.isPath(artifact.relativePath, inProject: artifact.projectID, artifactID: artifact.id) else { throw FamiliarArtifactError.invalidPath }
        let formatSuffix = "." + artifact.format.filenameExtension
        let path = try store.rename(relativePath: artifact.relativePath, projectID: artifact.projectID, artifactID: artifact.id, filename: title + formatSuffix)
        let oldPath = artifact.relativePath
        artifact.title = title
        artifact.relativePath = path
        artifact.updatedAt = Date()
        do { try context.save() }
        catch {
            context.rollback()
            _ = try? store.rename(relativePath: path, projectID: artifact.projectID, artifactID: artifact.id, filename: URL(fileURLWithPath: oldPath).lastPathComponent)
            throw error
        }
    }

    func exportURL(for artifact: FamiliarArtifact) -> URL? {
        guard store.isPath(artifact.relativePath, inProject: artifact.projectID, artifactID: artifact.id) else { return nil }
        return store.url(relativePath: artifact.relativePath)
    }
}

nonisolated enum FamiliarArtifactValidator {
    static let maximumArtifactBytes: Int64 = 128 * 1_024 * 1_024

    static func validate(
        fileURL: URL,
        format: FamiliarArtifactFormat,
        requiredText: [String] = [],
        now: Date = Date()
    ) throws -> FamiliarValidationReceipt {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw FamiliarArtifactError.invalidPath }
        let byteSize = Int64(values.fileSize ?? 0)
        guard byteSize > 0 else { throw FamiliarArtifactError.emptyFile }
        guard byteSize <= maximumArtifactBytes else { throw FamiliarArtifactError.fileTooLarge }
        guard fileURL.pathExtension.lowercased() == format.filenameExtension else {
            throw FamiliarArtifactError.contentMismatch
        }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let extracted: String
        let validator: String
        let validatorVersion: String
        var checks = ["regular-file", "non-empty", "extension-matches"]
        switch format {
        case .docx, .xlsx:
            guard data.count >= 4, data[0] == 0x50, data[1] == 0x4B else {
                throw FamiliarArtifactError.contentMismatch
            }
            let conversion = try FamiliarAnyDocService.convert(data: data, filename: fileURL.lastPathComponent)
            extracted = conversion.markdown
            validator = FamiliarAnyDocService.engineName
            validatorVersion = conversion.engineVersion
            checks += ["zip-signature", "office-package-readable", "extracted-text-non-empty"]
        case .pdf:
            guard data.starts(with: Data("%PDF".utf8)) else { throw FamiliarArtifactError.contentMismatch }
            let conversion = try FamiliarAnyDocService.convert(data: data, filename: fileURL.lastPathComponent)
            extracted = conversion.markdown
            validator = FamiliarAnyDocService.engineName
            validatorVersion = conversion.engineVersion
            checks += ["pdf-signature", "pdf-readable", "extracted-text-non-empty"]
        case .html:
            guard let source = String(data: data, encoding: .utf8) else { throw FamiliarArtifactError.contentMismatch }
            let document = try SwiftSoup.parse(source)
            extracted = try document.text()
            validator = "SwiftSoup"
            validatorVersion = "2.13.7"
            checks += ["utf8", "html-parseable", "extracted-text-non-empty"]
        case .markdown, .plainText:
            guard let source = String(data: data, encoding: .utf8) else { throw FamiliarArtifactError.contentMismatch }
            extracted = source
            validator = "FamiliarTextValidator"
            validatorVersion = "1"
            checks += ["utf8", "text-non-empty"]
        }
        let normalized = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw FamiliarArtifactError.validationFailed("未提取到可检查的正文。") }
        let required = Array(Set(requiredText.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).prefix(16)
        for term in required where normalized.localizedCaseInsensitiveContains(term) == false {
            throw FamiliarArtifactError.validationFailed("缺少必需内容：\(term)")
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
