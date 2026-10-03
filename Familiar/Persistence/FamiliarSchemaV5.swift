import Foundation
import SwiftData

enum FamiliarSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        FamiliarSchemaV4.models + [FamiliarCapabilitySnapshotRecord.self, FamiliarAuthorizationGrantRecord.self]
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

    @Model
    // Stored historical audit columns only. No runtime signs or consumes these rows;
    // current authorization uses FamiliarAuthorizationRuleRecord.
    final class FamiliarAuthorizationGrantRecord {
        @Attribute(.unique) var id: UUID
        var userAction: String
        var sourceRawValue: String
        var capabilityID: String
        var capabilityVersion: String
        var argumentsHash: String
        var projectID: UUID?
        var expiresAt: Date
        var singleUse: Bool
        var evidence: String
        var consumedAt: Date?
        var stateRawValue: String

        init(id: UUID, userAction: String, sourceRawValue: String, capabilityID: String,
             capabilityVersion: String, argumentsHash: String, projectID: UUID?, expiresAt: Date,
             singleUse: Bool, evidence: String, consumedAt: Date?, stateRawValue: String) {
            self.id = id
            self.userAction = userAction
            self.sourceRawValue = sourceRawValue
            self.capabilityID = capabilityID
            self.capabilityVersion = capabilityVersion
            self.argumentsHash = argumentsHash
            self.projectID = projectID
            self.expiresAt = expiresAt
            self.singleUse = singleUse
            self.evidence = evidence
            self.consumedAt = consumedAt
            self.stateRawValue = stateRawValue
        }
    }
}
