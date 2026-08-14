import CryptoKit
import Foundation
import SwiftData

nonisolated enum FamiliarArtifactError: LocalizedError, Sendable {
    case projectRequired, invalidIdentifier, missingArtifact, invalidPath, transactionFailed
    var errorDescription: String? {
        switch self {
        case .projectRequired: "Artifact 只能写入项目。"
        case .invalidIdentifier, .invalidPath: "Artifact 路径无效。"
        case .missingArtifact: "Artifact 不存在。"
        case .transactionFailed: "Artifact 操作未完成。"
        }
    }
}

nonisolated struct FamiliarArtifactDescriptor: Sendable, Equatable {
    let id: UUID
    let identifier: String
    let projectID: UUID
    let title: String
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
            return (relative, sha256(data))
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw FamiliarArtifactError.transactionFailed
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
    private func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

@MainActor
struct FamiliarArtifactService {
    let store: FamiliarArtifactStore

    init(store: FamiliarArtifactStore = FamiliarArtifactStore()) { self.store = store }

    func persist(_ descriptor: FamiliarArtifactDescriptor, in context: ModelContext) throws {
        let artifact = FamiliarArtifact(id: descriptor.id, projectID: descriptor.projectID, identifier: descriptor.identifier,
            title: descriptor.title, format: descriptor.format, relativePath: descriptor.relativePath,
            byteSize: descriptor.byteSize, contentHash: descriptor.contentHash, source: descriptor.source,
            sourceURLString: descriptor.sourceURLString, sourceResourceID: descriptor.sourceResourceID,
            sourceResourceVersionID: descriptor.sourceResourceVersionID, sourceCaptureID: descriptor.sourceCaptureID,
            createdByRunID: descriptor.createdByRunID)
        context.insert(artifact)
        do { try context.save() } catch { context.rollback(); try? store.remove(projectID: descriptor.projectID, artifactID: descriptor.id); throw error }
    }

    func delete(_ artifact: FamiliarArtifact, in context: ModelContext) throws {
        context.delete(artifact)
        do { try context.save(); try store.remove(projectID: artifact.projectID, artifactID: artifact.id) }
        catch { context.rollback(); throw error }
    }

    func read(_ artifact: FamiliarArtifact) throws -> Data {
        guard store.isPath(artifact.relativePath, inProject: artifact.projectID, artifactID: artifact.id) else { throw FamiliarArtifactError.invalidPath }
        return try store.read(relativePath: artifact.relativePath)
    }

    func rename(_ artifact: FamiliarArtifact, to title: String, in context: ModelContext) throws {
        guard store.isPath(artifact.relativePath, inProject: artifact.projectID, artifactID: artifact.id) else { throw FamiliarArtifactError.invalidPath }
        let formatSuffix = artifact.format == .markdown ? ".md" : ".txt"
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
