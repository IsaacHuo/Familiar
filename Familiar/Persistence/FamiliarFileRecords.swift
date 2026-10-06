import Foundation
import SwiftData

@Model
final class FamiliarFileRecord {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var displayName: String
    var originRawValue: String
    var originKey: String?
    var isProjectContext: Bool
    var chatIDsJSON: String
    var createdAt: Date
    var updatedAt: Date
    var lastVersionNumber: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \FamiliarFileVersionRecord.file)
    var versions: [FamiliarFileVersionRecord]

    init(id: UUID = UUID(), projectID: UUID, displayName: String, origin: FamiliarFileOrigin,
         isProjectContext: Bool = false, chatIDs: [UUID] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.projectID = projectID
        self.displayName = displayName
        originRawValue = origin.rawValue
        self.isProjectContext = isProjectContext
        chatIDsJSON = String(decoding: (try? JSONEncoder().encode(chatIDs)) ?? Data("[]".utf8), as: UTF8.self)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        versions = []
    }

    var chatIDs: [UUID] {
        get { (try? JSONDecoder().decode([UUID].self, from: Data(chatIDsJSON.utf8))) ?? [] }
        set { chatIDsJSON = String(decoding: (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8), as: UTF8.self) }
    }

    var latestVersion: FamiliarFileVersionRecord? {
        versions.max {
            if $0.version != $1.version { return $0.version < $1.version }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var snapshot: FamiliarFileSnapshot? {
        guard let version = latestVersion, version.projectID == projectID, version.fileID == id,
              let origin = FamiliarFileOrigin(rawValue: originRawValue),
              let kind = FamiliarFileStorageKind(rawValue: version.storageKindRawValue) else { return nil }
        return .init(reference: .init(fileID: id, versionID: version.id, projectID: projectID),
                     name: displayName, origin: origin, version: version.version, filename: version.filename,
                     mimeType: version.mimeType, byteSize: version.byteSize, contentHash: version.contentHash,
                     storage: .init(kind: kind, relativePath: version.storageRelativePath),
                     isProjectContext: isProjectContext, updatedAt: updatedAt)
    }
}

/// Version payload is append-only. Changes create another row, never replace bytes.
@Model
final class FamiliarFileVersionRecord {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var fileID: UUID
    var identifier: String
    var version: Int
    var filename: String
    var mimeType: String
    var byteSize: Int64
    var contentHash: String
    var extractedText: String
    var extractedTextHash: String
    var storageKindRawValue: String
    var storageRelativePath: String
    var sourceURLString: String?
    var provenanceJSON: String
    var createdByRunID: String?
    var createdByToolCallID: String?
    var createdAt: Date
    var file: FamiliarFileRecord?

    init(id: UUID = UUID(), version: Int, filename: String, mimeType: String, byteSize: Int64,
         contentHash: String, extractedText: String, extractedTextHash: String,
         storage: FamiliarFileStorageReference, sourceURLString: String? = nil, provenanceJSON: String = "{}",
         createdByRunID: String? = nil, createdAt: Date = Date(), file: FamiliarFileRecord) {
        self.id = id
        projectID = file.projectID
        fileID = file.id
        identifier = "file_" + id.uuidString
        self.version = version
        self.filename = filename
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.contentHash = contentHash
        self.extractedText = extractedText
        self.extractedTextHash = extractedTextHash
        storageKindRawValue = storage.kind.rawValue
        storageRelativePath = storage.relativePath
        self.sourceURLString = sourceURLString
        self.provenanceJSON = provenanceJSON
        self.createdByRunID = createdByRunID
        self.createdAt = createdAt
        self.file = file
        file.lastVersionNumber = max(file.lastVersionNumber, version)
    }

    private var provenance: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(provenanceJSON.utf8))) ?? [:]
    }

    var lineageID: UUID { fileID }
    var title: String { provenance["title"] ?? file?.displayName ?? filename }
    var relativePath: String { storageRelativePath }
    var updatedAt: Date { createdAt }
    var formatRawValue: String { provenance["format"] ?? FamiliarFileFormat.plainText.rawValue }
    var format: FamiliarFileFormat { FamiliarFileFormat(rawValue: formatRawValue) ?? .plainText }
    var sourceKindRawValue: String { provenance["source"] ?? FamiliarFileSource.generated.rawValue }
    var source: FamiliarFileSource { FamiliarFileSource(rawValue: sourceKindRawValue) ?? .generated }
    var sourceResourceID: UUID? { provenance["sourceResourceID"].flatMap(UUID.init(uuidString:)) }
    var sourceResourceVersionID: UUID? { provenance["sourceResourceVersionID"].flatMap(UUID.init(uuidString:)) }
    var sourceCaptureID: String? { provenance["sourceCaptureID"].flatMap { $0.isEmpty ? nil : $0 } }
    var utiIdentifier: String? { provenance["utiIdentifier"].flatMap { $0.isEmpty ? nil : $0 } }
    var validationReceiptJSON: String? { provenance["validationReceipt"].flatMap { $0.isEmpty ? nil : $0 } }

    /// Native file-delivery adapter. Version fields still have one canonical storage owner.
    convenience init(id: UUID = UUID(), projectID: UUID, identifier: String, title: String,
        lineageID: UUID? = nil, version: Int = 1, format: FamiliarFileFormat = .markdown,
        relativePath: String, byteSize: Int64, contentHash: String, source: FamiliarFileSource = .generated,
        sourceURLString: String? = nil, sourceResourceID: UUID? = nil, sourceResourceVersionID: UUID? = nil,
        sourceCaptureID: String? = nil, createdByRunID: String? = nil, utiIdentifier: String? = nil,
        mimeType: String? = nil, validationReceiptJSON: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        let record = FamiliarFileRecord(id: lineageID ?? id, projectID: projectID, displayName: title,
            origin: source == .webCapture ? .webCapture : .generated, createdAt: createdAt, updatedAt: updatedAt)
        let fields = ["title": title, "format": format.rawValue, "source": source.rawValue,
            "sourceResourceID": sourceResourceID?.uuidString ?? "", "sourceResourceVersionID": sourceResourceVersionID?.uuidString ?? "",
            "sourceCaptureID": sourceCaptureID ?? "", "utiIdentifier": utiIdentifier ?? "", "validationReceipt": validationReceiptJSON ?? ""]
        let encoded = (try? JSONEncoder().encode(fields)) ?? Data("{}".utf8)
        self.init(id: id, version: version, filename: URL(fileURLWithPath: relativePath).lastPathComponent,
            mimeType: mimeType ?? format.mimeType, byteSize: byteSize, contentHash: contentHash,
            extractedText: "", extractedTextHash: "", storage: .init(kind: .file, relativePath: relativePath),
            sourceURLString: sourceURLString, provenanceJSON: String(decoding: encoded, as: UTF8.self),
            createdByRunID: createdByRunID, createdAt: createdAt, file: record)
        self.identifier = identifier
    }
}
