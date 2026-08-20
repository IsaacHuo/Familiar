import Foundation
import SwiftData

enum FamiliarSchemaV9: VersionedSchema {
    static let versionIdentifier = Schema.Version(9, 0, 0)

    static var models: [any PersistentModel.Type] {
        FamiliarSchemaV8.models + [FamiliarRunSkillSnapshotRecord.self]
    }

    @Model
    final class FamiliarRunSkillSnapshotRecord {
        @Attribute(.unique) var id: UUID
        var runID: UUID
        var runtimeID: String
        var contextSnapshotID: UUID
        var projectID: UUID?
        var sequence: Int
        var stableID: String
        var version: String
        var name: String
        var contentHash: String
        var allowedToolsJSON: String
        var createdAt: Date

        init(
            id: UUID = UUID(),
            runID: UUID,
            runtimeID: String,
            contextSnapshotID: UUID,
            projectID: UUID?,
            sequence: Int,
            stableID: String,
            version: String,
            name: String,
            contentHash: String,
            allowedToolsJSON: String,
            createdAt: Date
        ) {
            self.id = id
            self.runID = runID
            self.runtimeID = runtimeID
            self.contextSnapshotID = contextSnapshotID
            self.projectID = projectID
            self.sequence = sequence
            self.stableID = stableID
            self.version = version
            self.name = name
            self.contentHash = contentHash
            self.allowedToolsJSON = allowedToolsJSON
            self.createdAt = createdAt
        }

        var allowedTools: [String] {
            guard let data = allowedToolsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
    }
}
