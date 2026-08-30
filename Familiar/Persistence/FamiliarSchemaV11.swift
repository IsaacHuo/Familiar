import Foundation
import SwiftData

enum FamiliarSchemaV11: VersionedSchema {
    static let versionIdentifier = Schema.Version(11, 0, 0)

    static var models: [any PersistentModel.Type] {
        FamiliarSchemaV10.models + [
            FamiliarContextAttachmentReference.self,
            FamiliarEventKitUndoMutationRecord.self
        ]
    }

    /// Immutable evidence that an exact message attachment was exposed to one
    /// ContextSnapshot. The source attachment remains the file owner; this record
    /// freezes the identity and hashes used by the Run.
    @Model
    final class FamiliarContextAttachmentReference {
        @Attribute(.unique) var id: UUID
        var contextSnapshotID: UUID
        var attachmentID: UUID
        var filename: String
        var mimeType: String
        var sourceRelativePath: String
        var byteSize: Int64
        var contentHash: String
        var extractedTextHash: String
        var createdAt: Date

        init(
            id: UUID = UUID(),
            contextSnapshotID: UUID,
            attachmentID: UUID,
            filename: String,
            mimeType: String,
            sourceRelativePath: String,
            byteSize: Int64,
            contentHash: String,
            extractedTextHash: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.contextSnapshotID = contextSnapshotID
            self.attachmentID = attachmentID
            self.filename = filename
            self.mimeType = mimeType
            self.sourceRelativePath = sourceRelativePath
            self.byteSize = byteSize
            self.contentHash = contentHash
            self.extractedTextHash = extractedTextHash
            self.createdAt = createdAt
        }
    }

    /// Persists the exact inverse snapshot needed to undo an EventKit create,
    /// update, or deletion across app launches.
    @Model
    final class FamiliarEventKitUndoMutationRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var idempotencyKey: String
        var operationRawValue: String
        var descriptorJSON: String
        var originalCalendarItemIdentifier: String
        var restoredCalendarItemIdentifier: String?
        var createdAt: Date

        init(
            id: UUID = UUID(),
            idempotencyKey: String,
            descriptor: FamiliarEventKitUndoDescriptor,
            createdAt: Date = Date()
        ) throws {
            self.id = id
            self.idempotencyKey = idempotencyKey
            operationRawValue = descriptor.operation.rawValue
            descriptorJSON = String(decoding: try JSONEncoder().encode(descriptor), as: UTF8.self)
            originalCalendarItemIdentifier = descriptor.calendarItemIdentifier
            self.createdAt = createdAt
        }

        var operation: FamiliarEventKitMutationOperation {
            FamiliarEventKitMutationOperation(rawValue: operationRawValue) ?? .create
        }

        func descriptor() throws -> FamiliarEventKitUndoDescriptor {
            try JSONDecoder().decode(FamiliarEventKitUndoDescriptor.self, from: Data(descriptorJSON.utf8))
        }
    }
}
