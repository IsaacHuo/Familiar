import Foundation

nonisolated enum FamiliarWorkScope: Hashable, Codable, Sendable {
    case project(UUID)
    case conversation(UUID)

    var storageKey: String { directoryName }
    var filePrefix: String { "Scopes/\(directoryName)/" }

    init?(storageKey: String) {
        if storageKey.hasPrefix("project-"), let id = UUID(uuidString: String(storageKey.dropFirst(8))) { self = .project(id) }
        else if storageKey.hasPrefix("conversation-"), let id = UUID(uuidString: String(storageKey.dropFirst(13))) { self = .conversation(id) }
        else { return nil }
    }

    var projectID: UUID? { if case .project(let id) = self { id } else { nil } }
    var conversationID: UUID? { if case .conversation(let id) = self { id } else { nil } }

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
    let scope: FamiliarWorkScope
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
    let scope: FamiliarWorkScope
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
