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
        FamiliarClarificationRecord.self,
        FamiliarContextAttachmentReference.self,
        FamiliarEventKitUndoMutationRecord.self
    ]

    static var schema: Schema { Schema(models) }
}

/// The only persisted schema in the current test-stage product. Earlier
/// FamiliarSchemaV3...V11 types organize model declarations; they are not a
/// supported migration chain.
enum FamiliarReleaseSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { FamiliarModelSchema.models }
}
