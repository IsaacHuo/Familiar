import Foundation
import SwiftData

nonisolated enum FamiliarPinnedTargetType: String, CaseIterable, Sendable {
    case conversation
    case project

    func targetKey(for targetID: UUID) -> String {
        "\(rawValue):\(targetID.uuidString)"
    }
}

@Model
final class FamiliarPinnedItemRecord {
    @Attribute(.unique) var targetKey: String
    var targetTypeRawValue: String
    var targetID: UUID
    var pinnedAt: Date

    init(targetType: FamiliarPinnedTargetType, targetID: UUID, pinnedAt: Date = Date()) {
        targetKey = targetType.targetKey(for: targetID)
        targetTypeRawValue = targetType.rawValue
        self.targetID = targetID
        self.pinnedAt = pinnedAt
    }

    var targetType: FamiliarPinnedTargetType? {
        FamiliarPinnedTargetType(rawValue: targetTypeRawValue)
    }
}

nonisolated enum FamiliarModelSchema {
    static let models: [any PersistentModel.Type] = FamiliarSchemaV3.models + [
        FamiliarArtifact.self,
        FamiliarCapabilitySnapshotRecord.self,
        FamiliarAuthorizationGrantRecord.self,
        FamiliarRunResumeCursorRecord.self,
        FamiliarToolInvocationRecord.self,
        FamiliarAuthorizationRuleRecord.self,
        FamiliarEventKitUndoRecord.self,
        FamiliarVisualEvidenceRecord.self,
        FamiliarSkill.self,
        FamiliarMemoryItem.self,
        FamiliarMCPServerRecord.self,
        FamiliarMCPBindingRecord.self,
        FamiliarRunSkillSnapshotRecord.self,
        FamiliarPinnedItemRecord.self,
        FamiliarActivityRecord.self,
        FamiliarToolResultRecord.self,
        FamiliarApprovalRecord.self,
        FamiliarResponseBlockRecord.self,
        FamiliarClarificationRecord.self
    ]

    static var schema: Schema { Schema(models) }
}

/// The first public, stable Familiar schema. The earlier FamiliarSchemaV3...
/// V10 types are source-organization history, not released migration steps.
enum FamiliarReleaseSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { FamiliarModelSchema.models }
}

enum FamiliarReleaseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FamiliarReleaseSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
