import Foundation
import SwiftData

enum FamiliarSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        FamiliarSchemaV5.models + [FamiliarRunResumeCursorRecord.self, FamiliarToolInvocationRecord.self]
    }

    @Model
    final class FamiliarRunResumeCursorRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var runtimeID: String
        var runID: UUID?
        var contextSnapshotID: UUID
        var nextIteration: Int
        var phaseRawValue: String
        var lastEventSequence: Int
        var pendingToolCallID: String?
        var pendingToolName: String?
        var updatedAt: Date

        init(runtimeID: String, contextSnapshotID: UUID, runID: UUID? = nil, nextIteration: Int = 0, phase: FamiliarRunRecoveryPhase = .model, lastEventSequence: Int = -1, updatedAt: Date = Date()) {
            id = UUID()
            self.runtimeID = runtimeID
            self.runID = runID
            self.contextSnapshotID = contextSnapshotID
            self.nextIteration = nextIteration
            phaseRawValue = phase.rawValue
            self.lastEventSequence = lastEventSequence
            self.updatedAt = updatedAt
        }

        var phase: FamiliarRunRecoveryPhase {
            get { FamiliarRunRecoveryPhase(rawValue: phaseRawValue) ?? .terminal }
            set { phaseRawValue = newValue.rawValue }
        }
    }

    @Model
    final class FamiliarToolInvocationRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var idempotencyKey: String
        var runtimeID: String
        var toolName: String
        var argumentsHash: String
        var stateRawValue: String
        var startedAt: Date
        var committedAt: Date?
        var resultReference: String?

        init(idempotencyKey: String, runtimeID: String, toolName: String, argumentsHash: String, state: FamiliarToolInvocationState = .requested, startedAt: Date = Date()) {
            id = UUID()
            self.idempotencyKey = idempotencyKey
            self.runtimeID = runtimeID
            self.toolName = toolName
            self.argumentsHash = argumentsHash
            stateRawValue = state.rawValue
            self.startedAt = startedAt
        }

        var state: FamiliarToolInvocationState {
            get { FamiliarToolInvocationState(rawValue: stateRawValue) ?? .failed }
            set { stateRawValue = newValue.rawValue }
        }
    }
}

nonisolated enum FamiliarRunRecoveryPhase: String, Codable, Sendable { case model, awaitingApproval, committingTool, terminal }
nonisolated enum FamiliarToolInvocationState: String, Codable, Sendable { case requested, approved, committing, committed, failed, cancelled }
