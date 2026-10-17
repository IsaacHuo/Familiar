import Foundation
import SwiftData

enum FamiliarSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        FamiliarSchemaV3.models + [FamiliarCapabilitySnapshotRecord.self]
    }

    @Model
    final class FamiliarCapabilitySnapshotRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var projectID: UUID?
        var conversationID: UUID
        var contextSnapshotID: UUID
        var manifestsJSON: String

        init(id: UUID = UUID(), createdAt: Date, projectID: UUID?, conversationID: UUID, contextSnapshotID: UUID, manifestsJSON: String) {
            self.id = id
            self.createdAt = createdAt
            self.projectID = projectID
            self.conversationID = conversationID
            self.contextSnapshotID = contextSnapshotID
            self.manifestsJSON = manifestsJSON
        }
    }

}
