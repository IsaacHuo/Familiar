import Foundation
import SwiftData

enum FamiliarSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        FamiliarSchemaV6.models + [FamiliarAuthorizationRuleRecord.self, FamiliarEventKitUndoRecord.self, FamiliarVisualEvidenceRecord.self]
    }

    @Model
    final class FamiliarAuthorizationRuleRecord {
        @Attribute(.unique) var id: UUID
        var projectID: UUID?
        var capabilityID: String
        var capabilityVersion: String
        var targetKey: String
        var argumentsHash: String
        var durationRawValue: String
        var sessionID: String?
        var createdAt: Date
        var expiresAt: Date
        var lastUsedAt: Date?
        var revokedAt: Date?
        var evidence: String

        init(id: UUID = UUID(), projectID: UUID?, capabilityID: String, capabilityVersion: String, targetKey: String, argumentsHash: String, duration: FamiliarAuthorizationDuration, sessionID: String?, createdAt: Date = Date(), expiresAt: Date, evidence: String) {
            self.id = id
            self.projectID = projectID
            self.capabilityID = capabilityID
            self.capabilityVersion = capabilityVersion
            self.targetKey = targetKey
            self.argumentsHash = argumentsHash
            durationRawValue = duration.rawValue
            self.sessionID = sessionID
            self.createdAt = createdAt
            self.expiresAt = expiresAt
            self.evidence = evidence
        }

        var duration: FamiliarAuthorizationDuration {
            FamiliarAuthorizationDuration(rawValue: durationRawValue) ?? .once
        }
    }

    @Model
    final class FamiliarEventKitUndoRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var idempotencyKey: String
        var runtimeID: String
        var toolCallID: String
        var toolName: String
        var kindRawValue: String
        var calendarItemIdentifier: String
        var stateRawValue: String
        var createdAt: Date
        var undoneAt: Date?
        var lastError: String?

        init(idempotencyKey: String, runtimeID: String, toolCallID: String, toolName: String, kind: FamiliarEventKitAccessKind, calendarItemIdentifier: String, state: FamiliarDurableUndoState = .available, createdAt: Date = Date()) {
            id = UUID()
            self.idempotencyKey = idempotencyKey
            self.runtimeID = runtimeID
            self.toolCallID = toolCallID
            self.toolName = toolName
            kindRawValue = kind.rawValue
            self.calendarItemIdentifier = calendarItemIdentifier
            stateRawValue = state.rawValue
            self.createdAt = createdAt
        }

        var kind: FamiliarEventKitAccessKind { FamiliarEventKitAccessKind(rawValue: kindRawValue) ?? .events }
        var state: FamiliarDurableUndoState {
            get { FamiliarDurableUndoState(rawValue: stateRawValue) ?? .unavailable }
            set { stateRawValue = newValue.rawValue }
        }
    }

    @Model
    final class FamiliarVisualEvidenceRecord {
        @Attribute(.unique) var id: UUID
        var attachmentID: UUID
        var messageID: UUID?
        var contextSnapshotID: UUID
        var filename: String
        var sourceRelativePath: String
        var renderedText: String
        var processingMethod: String
        var engineVersion: String
        var createdAt: Date

        init(id: UUID, attachmentID: UUID, messageID: UUID?, contextSnapshotID: UUID, filename: String, sourceRelativePath: String, renderedText: String, processingMethod: String, engineVersion: String, createdAt: Date) {
            self.id = id
            self.attachmentID = attachmentID
            self.messageID = messageID
            self.contextSnapshotID = contextSnapshotID
            self.filename = filename
            self.sourceRelativePath = sourceRelativePath
            self.renderedText = renderedText
            self.processingMethod = processingMethod
            self.engineVersion = engineVersion
            self.createdAt = createdAt
        }
    }
}

nonisolated enum FamiliarDurableUndoState: String, Codable, Sendable {
    case available
    case undone
    case unavailable
}
