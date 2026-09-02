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

@Model
final class FamiliarProjectEnvironmentRecord {
    @Attribute(.unique) var projectID: UUID
    var revision: UUID
    var stateRawValue: String
    var requestedPackagesJSON: String
    var pythonVersion: String
    var resolvedPackagesJSON: String
    var lockHash: String
    var byteSize: Int64
    var preparedAt: Date

    init(receipt: FamiliarEnvironmentReceipt) throws {
        projectID = receipt.projectID
        revision = receipt.revision
        stateRawValue = receipt.state.rawValue
        requestedPackagesJSON = String(decoding: try JSONEncoder().encode(receipt.requestedPackages), as: UTF8.self)
        pythonVersion = receipt.lock.pythonVersion
        resolvedPackagesJSON = String(decoding: try JSONEncoder().encode(receipt.lock.resolvedPackages), as: UTF8.self)
        lockHash = receipt.lock.contentHash
        byteSize = receipt.byteSize
        preparedAt = receipt.preparedAt
    }

    var state: FamiliarRuntimeEnvironmentState {
        FamiliarRuntimeEnvironmentState(rawValue: stateRawValue) ?? .failed
    }
}

@Model
final class FamiliarProjectSkillBindingRecord {
    @Attribute(.unique) var bindingKey: String
    var projectID: UUID
    var skillID: UUID
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(projectID: UUID, skillID: UUID, enabled: Bool = true, now: Date = Date()) {
        bindingKey = "\(projectID.uuidString):\(skillID.uuidString)"
        self.projectID = projectID
        self.skillID = skillID
        self.enabled = enabled
        createdAt = now
        updatedAt = now
    }
}

@Model
final class FamiliarProjectCapabilityBindingRecord {
    @Attribute(.unique) var bindingKey: String
    var projectID: UUID
    var capabilityID: String
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(projectID: UUID, capabilityID: String, enabled: Bool = true, now: Date = Date()) {
        bindingKey = "\(projectID.uuidString):\(capabilityID)"
        self.projectID = projectID
        self.capabilityID = capabilityID
        self.enabled = enabled
        createdAt = now
        updatedAt = now
    }
}

/// Durable undo for an AlarmKit alarm scheduled by the Agent.
///
/// An alarm's whole purpose is to fire later, very likely after the app has been
/// relaunched, so a session-scoped undo would promise a reversal that no longer
/// exists by the time the user wants it. Only the alarm identity is persisted;
/// cancelling needs nothing else.
@Model
final class FamiliarAlarmUndoRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var idempotencyKey: String
    var runtimeID: String
    var toolCallID: String
    var toolName: String
    var alarmIdentifier: String
    var stateRawValue: String
    var createdAt: Date
    var undoneAt: Date?
    var lastError: String?

    init(
        idempotencyKey: String,
        runtimeID: String,
        toolCallID: String,
        toolName: String,
        alarmIdentifier: String,
        state: FamiliarDurableUndoState = .available,
        createdAt: Date = Date()
    ) {
        id = UUID()
        self.idempotencyKey = idempotencyKey
        self.runtimeID = runtimeID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.alarmIdentifier = alarmIdentifier
        stateRawValue = state.rawValue
        self.createdAt = createdAt
    }

    var state: FamiliarDurableUndoState {
        get { FamiliarDurableUndoState(rawValue: stateRawValue) ?? .unavailable }
        set { stateRawValue = newValue.rawValue }
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
        FamiliarEventKitUndoMutationRecord.self,
        FamiliarProjectEnvironmentRecord.self,
        FamiliarProjectSkillBindingRecord.self,
        FamiliarProjectCapabilityBindingRecord.self,
        FamiliarAlarmUndoRecord.self
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
