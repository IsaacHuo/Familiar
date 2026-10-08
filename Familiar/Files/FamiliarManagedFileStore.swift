import Foundation
import UniformTypeIdentifiers

/// Immutable bytes for Files produced by Shell and adopted from old workspace outputs.
nonisolated struct FamiliarManagedFileStore: Sendable {
    let rootURL: URL

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Familiar/Files", isDirectory: true)
    }

    func capture(_ data: Data, filename: String, projectID: UUID, originKey: String,
                 runID: String?, toolCallID: String?) throws -> FamiliarProducedFile {
        let id = UUID()
        let name = String(URL(fileURLWithPath: filename).lastPathComponent.prefix(240))
        guard !name.isEmpty, name != ".", name != ".." else { throw FamiliarFileError.invalidPath }
        let path = "Projects/\(projectID.uuidString)/Versions/\(id.uuidString)/\(name)"
        let destination = try FamiliarFilePath.confined(path, to: rootURL)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        do {
            try data.write(to: destination, options: [.atomic])
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        } catch { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()); throw error }
        return .init(versionID: id, projectID: projectID, originKey: originKey, filename: name,
            mimeType: UTType(filenameExtension: URL(fileURLWithPath: name).pathExtension)?.preferredMIMEType ?? "application/octet-stream",
            byteSize: Int64(data.count), contentHash: FamiliarHash.sha256(data),
            storage: .init(kind: .managed, relativePath: path), createdByRunID: runID,
            toolCallID: toolCallID, capturedAt: Date())
    }

    func remove(_ captured: FamiliarProducedFile) throws {
        let prefix = "Projects/\(captured.projectID.uuidString)/Versions/\(captured.versionID.uuidString)/"
        guard captured.storage.relativePath.hasPrefix(prefix), !captured.storage.relativePath.split(separator: "/").contains("..") else {
            throw FamiliarFileError.invalidPath
        }
        let directory = try FamiliarFilePath.confined(captured.storage.relativePath, to: rootURL).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func stageProjectDirectory(projectID: UUID) throws -> FamiliarStagedFileDirectory? {
        let original = try FamiliarFilePath.confined("Projects/\(projectID.uuidString)", to: rootURL)
        guard FileManager.default.fileExists(atPath: original.path) else { return nil }
        let backup = rootURL.appendingPathComponent(".deleted-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.moveItem(at: original, to: backup)
        return .init(originalURL: original, stagedURL: backup)
    }

    func restore(_ staged: FamiliarStagedFileDirectory) throws {
        try FileManager.default.moveItem(at: staged.stagedURL, to: staged.originalURL)
    }

    func discard(_ staged: FamiliarStagedFileDirectory) throws {
        try FileManager.default.removeItem(at: staged.stagedURL)
    }
}
