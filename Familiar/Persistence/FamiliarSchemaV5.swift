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

        init(grant: FamiliarAuthorizationGrant) {
            id = grant.id
            userAction = grant.userAction
            sourceRawValue = grant.source.rawValue
            capabilityID = grant.capabilityID
            capabilityVersion = grant.capabilityVersion
            argumentsHash = grant.argumentsHash
            projectID = grant.projectID
            expiresAt = grant.expiresAt
            singleUse = grant.singleUse
            evidence = grant.evidence
            consumedAt = grant.consumedAt
            stateRawValue = grant.state.rawValue
        }

        var state: FamiliarAuthorizationGrantState {
            get { FamiliarAuthorizationGrantState(rawValue: stateRawValue) ?? .rejected }
            set { stateRawValue = newValue.rawValue }
        }
    }
}
