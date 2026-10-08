import Foundation

/// Shared byte access for Tools and native Files UI; storage implementations never reach Domain.
nonisolated enum FamiliarFileByteReader {
    static func url(for snapshot: FamiliarFileSnapshot) -> URL? {
        let prefix = "Projects/\(snapshot.reference.projectID.uuidString)/"
        if snapshot.storage.kind != .attachment || snapshot.storage.relativePath.hasPrefix("Projects/") {
            guard snapshot.storage.relativePath.hasPrefix(prefix) else { return nil }
        }
        let url: URL?
        switch snapshot.storage.kind {
        case .attachment: url = FamiliarAttachmentStore.url(for: snapshot.storage.relativePath)
        case .resource: url = FamiliarProjectResourceStore().url(for: snapshot.storage.relativePath)
        case .file: url = FamiliarFileStore().url(relativePath: snapshot.storage.relativePath)
        case .managed:
            url = try? FamiliarFilePath.confined(snapshot.storage.relativePath, to: FamiliarManagedFileStore().rootURL)
        }
        guard let url, let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return url
    }

    static func read(_ snapshot: FamiliarFileSnapshot, projectID: UUID) throws -> Data {
        guard snapshot.reference.projectID == projectID else { throw FamiliarFileError.invalidPath }
        guard let url = url(for: snapshot) else { throw FamiliarFileError.missingFile }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard snapshot.contentHash.isEmpty || FamiliarHash.sha256(data) == snapshot.contentHash else { throw FamiliarFileError.contentMismatch }
        return data
    }
}
