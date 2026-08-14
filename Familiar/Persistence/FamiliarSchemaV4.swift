import Foundation
import SwiftData

enum FamiliarSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        FamiliarSchemaV3.models + [FamiliarArtifact.self]
    }

    @Model
    final class FamiliarArtifact {
        @Attribute(.unique) var id: UUID
        var projectID: UUID
        var identifier: String
        var title: String
        var formatRawValue: String
        var relativePath: String
        var byteSize: Int64
        var contentHash: String
        var sourceKindRawValue: String
        var sourceURLString: String?
        var sourceResourceID: UUID?
        var sourceResourceVersionID: UUID?
        var sourceCaptureID: String?
        var createdByRunID: String?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(), projectID: UUID, identifier: String, title: String,
            format: FamiliarArtifactFormat = .markdown, relativePath: String,
            byteSize: Int64, contentHash: String, source: FamiliarArtifactSource = .generated,
            sourceURLString: String? = nil, sourceResourceID: UUID? = nil,
            sourceResourceVersionID: UUID? = nil, sourceCaptureID: String? = nil,
            createdByRunID: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()
        ) {
            self.id = id; self.projectID = projectID; self.identifier = identifier; self.title = title
            formatRawValue = format.rawValue; self.relativePath = relativePath; self.byteSize = byteSize
            self.contentHash = contentHash; sourceKindRawValue = source.rawValue
            self.sourceURLString = sourceURLString; self.sourceResourceID = sourceResourceID
            self.sourceResourceVersionID = sourceResourceVersionID; self.sourceCaptureID = sourceCaptureID
            self.createdByRunID = createdByRunID; self.createdAt = createdAt; self.updatedAt = updatedAt
        }

        var format: FamiliarArtifactFormat { FamiliarArtifactFormat(rawValue: formatRawValue) ?? .markdown }
        var source: FamiliarArtifactSource { FamiliarArtifactSource(rawValue: sourceKindRawValue) ?? .generated }
    }
}

nonisolated enum FamiliarArtifactFormat: String, Codable, Sendable { case markdown, plainText }
nonisolated enum FamiliarArtifactSource: String, Codable, Sendable { case generated, webCapture, projectResource }
