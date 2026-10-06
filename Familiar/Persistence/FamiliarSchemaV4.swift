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
        /// Groups the successive versions of one logical deliverable. Each version is its
        /// own row and its own directory, because the store keys files by artifact ID and
        /// overwriting in place would destroy the previous version's bytes.
        var lineageID: UUID
        var version: Int
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
        var utiIdentifier: String?
        var mimeType: String?
        var validationReceiptJSON: String?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(), projectID: UUID, identifier: String, title: String,
            lineageID: UUID? = nil, version: Int = 1,
            format: FamiliarFileFormat = .markdown, relativePath: String,
            byteSize: Int64, contentHash: String, source: FamiliarFileSource = .generated,
            sourceURLString: String? = nil, sourceResourceID: UUID? = nil,
            sourceResourceVersionID: UUID? = nil, sourceCaptureID: String? = nil,
            createdByRunID: String? = nil, utiIdentifier: String? = nil, mimeType: String? = nil,
            validationReceiptJSON: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()
        ) {
            self.id = id; self.projectID = projectID; self.identifier = identifier; self.title = title
            // Defaults to this row's own id: a first version is the origin of its lineage,
            // so an artifact created without an explicit lineage is still well-formed.
            self.lineageID = lineageID ?? id; self.version = version
            formatRawValue = format.rawValue; self.relativePath = relativePath; self.byteSize = byteSize
            self.contentHash = contentHash; sourceKindRawValue = source.rawValue
            self.sourceURLString = sourceURLString; self.sourceResourceID = sourceResourceID
            self.sourceResourceVersionID = sourceResourceVersionID; self.sourceCaptureID = sourceCaptureID
            self.createdByRunID = createdByRunID; self.createdAt = createdAt; self.updatedAt = updatedAt
            self.utiIdentifier = utiIdentifier; self.mimeType = mimeType; self.validationReceiptJSON = validationReceiptJSON
        }

        var format: FamiliarFileFormat { FamiliarFileFormat(rawValue: formatRawValue) ?? .markdown }
        var source: FamiliarFileSource { FamiliarFileSource(rawValue: sourceKindRawValue) ?? .generated }
    }
}
