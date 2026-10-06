import Foundation

nonisolated enum FamiliarFileOrigin: String, Codable, Sendable {
    case upload, projectImport, webCapture, generated, shell
}

nonisolated enum FamiliarFileStorageKind: String, Codable, Sendable {
    case attachment, resource, file, managed
}

/// Identity is independent of paths, names and content hashes.
nonisolated struct FamiliarFileReference: Codable, Equatable, Hashable, Sendable {
    let fileID: UUID
    let versionID: UUID
    let projectID: UUID
}

nonisolated struct FamiliarFileStorageReference: Codable, Equatable, Sendable {
    let kind: FamiliarFileStorageKind
    let relativePath: String
}

nonisolated struct FamiliarFileSnapshot: Identifiable, Equatable, Sendable {
    var id: UUID { reference.fileID }
    let reference: FamiliarFileReference
    let name: String
    let origin: FamiliarFileOrigin
    let version: Int
    let filename: String
    let mimeType: String
    let byteSize: Int64
    let contentHash: String
    let storage: FamiliarFileStorageReference
    let isProjectContext: Bool
    let updatedAt: Date
}

/// A captured output awaiting the Run's persistence checkpoint, never a mutable guest path.
nonisolated struct FamiliarProducedFile: Equatable, Sendable {
    let versionID: UUID
    let projectID: UUID
    let originKey: String
    let filename: String
    let mimeType: String
    let byteSize: Int64
    let contentHash: String
    let storage: FamiliarFileStorageReference
    let createdByRunID: String?
    let toolCallID: String?
    let capturedAt: Date
}
