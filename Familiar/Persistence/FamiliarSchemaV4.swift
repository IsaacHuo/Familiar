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
        var utiIdentifier: String?
        var mimeType: String?
        var validationReceiptJSON: String?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(), projectID: UUID, identifier: String, title: String,
            format: FamiliarArtifactFormat = .markdown, relativePath: String,
            byteSize: Int64, contentHash: String, source: FamiliarArtifactSource = .generated,
            sourceURLString: String? = nil, sourceResourceID: UUID? = nil,
            sourceResourceVersionID: UUID? = nil, sourceCaptureID: String? = nil,
            createdByRunID: String? = nil, utiIdentifier: String? = nil, mimeType: String? = nil,
            validationReceiptJSON: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()
        ) {
            self.id = id; self.projectID = projectID; self.identifier = identifier; self.title = title
            formatRawValue = format.rawValue; self.relativePath = relativePath; self.byteSize = byteSize
            self.contentHash = contentHash; sourceKindRawValue = source.rawValue
            self.sourceURLString = sourceURLString; self.sourceResourceID = sourceResourceID
            self.sourceResourceVersionID = sourceResourceVersionID; self.sourceCaptureID = sourceCaptureID
            self.createdByRunID = createdByRunID; self.createdAt = createdAt; self.updatedAt = updatedAt
            self.utiIdentifier = utiIdentifier; self.mimeType = mimeType; self.validationReceiptJSON = validationReceiptJSON
        }

        var format: FamiliarArtifactFormat { FamiliarArtifactFormat(rawValue: formatRawValue) ?? .markdown }
        var source: FamiliarArtifactSource { FamiliarArtifactSource(rawValue: sourceKindRawValue) ?? .generated }
    }
}

nonisolated enum FamiliarArtifactFormat: String, Codable, CaseIterable, Sendable {
    case markdown
    case plainText
    case docx
    case pdf
    case xlsx
    case html

    var filenameExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        case .docx: "docx"
        case .pdf: "pdf"
        case .xlsx: "xlsx"
        case .html: "html"
        }
    }

    var mimeType: String {
        switch self {
        case .markdown: "text/markdown"
        case .plainText: "text/plain"
        case .docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .pdf: "application/pdf"
        case .xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case .html: "text/html"
        }
    }

    var utiIdentifier: String {
        switch self {
        case .markdown: "net.daringfireball.markdown"
        case .plainText: "public.plain-text"
        case .docx: "org.openxmlformats.wordprocessingml.document"
        case .pdf: "com.adobe.pdf"
        case .xlsx: "org.openxmlformats.spreadsheetml.sheet"
        case .html: "public.html"
        }
    }
}
nonisolated enum FamiliarArtifactSource: String, Codable, Sendable { case generated, webCapture, projectResource }
