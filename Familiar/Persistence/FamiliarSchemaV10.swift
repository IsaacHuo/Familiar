import Foundation
import SwiftData

enum FamiliarSchemaV10: VersionedSchema {
    static let versionIdentifier = Schema.Version(10, 0, 0)

    static var models: [any PersistentModel.Type] {
        FamiliarSchemaV9.models + [
            FamiliarActivityRecord.self,
            FamiliarToolResultRecord.self,
            FamiliarApprovalRecord.self,
            FamiliarResponseBlockRecord.self,
            FamiliarClarificationRecord.self
        ]
    }

    @Model
    final class FamiliarActivityRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var activityID: String
        var runtimeID: String
        var parentID: String?
        var assistantTurnID: String
        var kindRawValue: String
        var effectRawValue: String?
        var phaseRawValue: String
        var toolName: String?
        var toolCallID: String?
        var summary: String
        var detail: String?
        var progress: Double?
        var resultRecordID: UUID?
        var approvalRecordID: UUID?
        var sequence: Int
        var startedAt: Date
        var endedAt: Date?

        init(
            id: UUID = UUID(),
            activityID: String,
            runtimeID: String,
            parentID: String? = nil,
            assistantTurnID: String,
            kind: FamiliarActivityKind,
            effect: FamiliarToolEffect? = nil,
            phase: FamiliarActivityPhase,
            toolName: String? = nil,
            toolCallID: String? = nil,
            summary: String,
            detail: String? = nil,
            progress: Double? = nil,
            resultRecordID: UUID? = nil,
            approvalRecordID: UUID? = nil,
            sequence: Int,
            startedAt: Date,
            endedAt: Date? = nil
        ) {
            self.id = id
            self.activityID = activityID
            self.runtimeID = runtimeID
            self.parentID = parentID
            self.assistantTurnID = assistantTurnID
            kindRawValue = kind.rawValue
            effectRawValue = effect?.rawValue
            phaseRawValue = phase.rawValue
            self.toolName = toolName
            self.toolCallID = toolCallID
            self.summary = summary
            self.detail = detail
            self.progress = progress
            self.resultRecordID = resultRecordID
            self.approvalRecordID = approvalRecordID
            self.sequence = sequence
            self.startedAt = startedAt
            self.endedAt = endedAt
        }

        var kind: FamiliarActivityKind {
            FamiliarActivityKind(rawValue: kindRawValue) ?? .runtimeNotice
        }

        var effect: FamiliarToolEffect? {
            effectRawValue.flatMap(FamiliarToolEffect.init(rawValue:))
        }

        var phase: FamiliarActivityPhase {
            get { FamiliarActivityPhase(rawValue: phaseRawValue) ?? .failed }
            set { phaseRawValue = newValue.rawValue }
        }
    }

    @Model
    final class FamiliarToolResultRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var activityID: String
        var runtimeID: String
        var assistantTurnID: String
        var toolCallID: String
        var envelopeJSON: String
        var schemaVersion: Int
        var payloadName: String
        var payloadHash: String
        var semanticID: String?
        var revision: Int
        var trustRawValue: String
        var truncated: Bool
        var createdAt: Date

        init(
            id: UUID = UUID(),
            activityID: String,
            runtimeID: String,
            assistantTurnID: String,
            toolCallID: String,
            envelopeJSON: String,
            schemaVersion: Int,
            payloadName: String,
            payloadHash: String,
            semanticID: String? = nil,
            revision: Int = 1,
            trust: FamiliarContentTrust,
            truncated: Bool,
            createdAt: Date
        ) {
            self.id = id
            self.activityID = activityID
            self.runtimeID = runtimeID
            self.assistantTurnID = assistantTurnID
            self.toolCallID = toolCallID
            self.envelopeJSON = envelopeJSON
            self.schemaVersion = schemaVersion
            self.payloadName = payloadName
            self.payloadHash = payloadHash
            self.semanticID = semanticID
            self.revision = revision
            trustRawValue = trust.rawValue
            self.truncated = truncated
            self.createdAt = createdAt
        }

        var trust: FamiliarContentTrust {
            FamiliarContentTrust(rawValue: trustRawValue) ?? .untrusted
        }
    }

    @Model
    final class FamiliarApprovalRecord {
        @Attribute(.unique) var id: UUID
        var runtimeID: String
        var assistantTurnID: String
        var activityID: String
        var toolCallID: String
        var toolName: String
        var title: String
        var orderedFieldsJSON: String
        var target: String?
        var effectRawValue: String
        var riskRawValue: String
        var consequence: String
        var undoPolicyRawValue: String
        var decisionRawValue: String?
        var scopeRawValue: String?
        var requestedAt: Date
        var resolvedAt: Date?
        var automaticAuthorization: Bool

        init(
            id: UUID,
            runtimeID: String,
            assistantTurnID: String,
            activityID: String,
            toolCallID: String,
            toolName: String,
            title: String,
            orderedFieldsJSON: String,
            target: String?,
            effect: FamiliarToolEffect,
            risk: FamiliarToolRisk,
            consequence: String,
            undoPolicy: FamiliarApprovalUndoPolicy,
            decision: FamiliarApprovalDecision? = nil,
            scope: FamiliarApprovalScope? = nil,
            requestedAt: Date,
            resolvedAt: Date? = nil,
            automaticAuthorization: Bool
        ) {
            self.id = id
            self.runtimeID = runtimeID
            self.assistantTurnID = assistantTurnID
            self.activityID = activityID
            self.toolCallID = toolCallID
            self.toolName = toolName
            self.title = title
            self.orderedFieldsJSON = orderedFieldsJSON
            self.target = target
            effectRawValue = effect.rawValue
            riskRawValue = risk.rawValue
            self.consequence = consequence
            undoPolicyRawValue = undoPolicy.rawValue
            decisionRawValue = decision?.rawValue
            scopeRawValue = scope?.rawValue
            self.requestedAt = requestedAt
            self.resolvedAt = resolvedAt
            self.automaticAuthorization = automaticAuthorization
        }

        var effect: FamiliarToolEffect { FamiliarToolEffect(rawValue: effectRawValue) ?? .read }
        var risk: FamiliarToolRisk { FamiliarToolRisk(rawValue: riskRawValue) ?? .low }
        var undoPolicy: FamiliarApprovalUndoPolicy { FamiliarApprovalUndoPolicy(rawValue: undoPolicyRawValue) ?? .unavailable }
        var decision: FamiliarApprovalDecision? { decisionRawValue.flatMap(FamiliarApprovalDecision.init(rawValue:)) }
        var scope: FamiliarApprovalScope? { scopeRawValue.flatMap(FamiliarApprovalScope.init(rawValue:)) }
    }

    @Model
    final class FamiliarResponseBlockRecord {
        @Attribute(.unique) var id: UUID
        var runtimeID: String
        var assistantTurnID: String
        var messageID: UUID?
        var kindRawValue: String
        var order: Int
        var stateRawValue: String
        var content: String
        var payloadJSON: String
        var schemaVersion: Int
        var startedAt: Date
        var endedAt: Date?
        var contentHash: String

        init(
            id: UUID = UUID(),
            runtimeID: String,
            assistantTurnID: String,
            messageID: UUID?,
            kind: FamiliarResponseBlockKind,
            order: Int,
            state: FamiliarResponseBlockState,
            content: String,
            payloadJSON: String = "{}",
            schemaVersion: Int = 1,
            startedAt: Date,
            endedAt: Date?,
            contentHash: String
        ) {
            self.id = id
            self.runtimeID = runtimeID
            self.assistantTurnID = assistantTurnID
            self.messageID = messageID
            kindRawValue = kind.rawValue
            self.order = order
            stateRawValue = state.rawValue
            self.content = content
            self.payloadJSON = payloadJSON
            self.schemaVersion = schemaVersion
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.contentHash = contentHash
        }

        var kind: FamiliarResponseBlockKind {
            FamiliarResponseBlockKind(rawValue: kindRawValue) ?? .runtimeNotice
        }

        var state: FamiliarResponseBlockState {
            get { FamiliarResponseBlockState(rawValue: stateRawValue) ?? .failed }
            set { stateRawValue = newValue.rawValue }
        }
    }

    @Model
    final class FamiliarClarificationRecord {
        @Attribute(.unique) var id: UUID
        var runtimeID: String
        var assistantTurnID: String
        var activityID: String
        var toolCallID: String
        var question: String
        var optionsJSON: String
        var allowCustom: Bool
        var stateRawValue: String
        var resolutionJSON: String?
        var requestedAt: Date
        var resolvedAt: Date?

        init(id: UUID, runtimeID: String, assistantTurnID: String, activityID: String, toolCallID: String, question: String, optionsJSON: String, allowCustom: Bool, state: FamiliarClarificationState = .requested, resolutionJSON: String? = nil, requestedAt: Date, resolvedAt: Date? = nil) {
            self.id = id
            self.runtimeID = runtimeID
            self.assistantTurnID = assistantTurnID
            self.activityID = activityID
            self.toolCallID = toolCallID
            self.question = question
            self.optionsJSON = optionsJSON
            self.allowCustom = allowCustom
            stateRawValue = state.rawValue
            self.resolutionJSON = resolutionJSON
            self.requestedAt = requestedAt
            self.resolvedAt = resolvedAt
        }

        var state: FamiliarClarificationState {
            get { FamiliarClarificationState(rawValue: stateRawValue) ?? .interrupted }
            set { stateRawValue = newValue.rawValue }
        }
    }
}

nonisolated enum FamiliarActivityKind: String, Codable, Sendable {
    case assistantTurn
    case tool
    case runtimeNotice
}

nonisolated enum FamiliarActivityPhase: String, Codable, Sendable {
    case queued
    case running
    case awaitingApproval
    case awaitingClarification
    case succeeded
    case failed
    case cancelled
    case undone

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .undone: true
        case .queued, .running, .awaitingApproval, .awaitingClarification: false
        }
    }
}

nonisolated enum FamiliarContentTrust: String, Codable, Sendable {
    case trusted
    case untrusted
}

nonisolated enum FamiliarApprovalDecision: String, Codable, Sendable {
    case approved
    case cancelled
}

nonisolated enum FamiliarApprovalScope: String, Codable, Sendable {
    case once
    case session
    case always
}

nonisolated enum FamiliarResponseBlockKind: String, Codable, Sendable {
    case text
    case markdown
    case reasoningSummary
    case runtimeNotice
}

nonisolated enum FamiliarResponseBlockState: String, Codable, Sendable {
    case completed
    case failed
    case cancelled
}

nonisolated enum FamiliarClarificationState: String, Codable, Sendable {
    case requested
    case resolved
    case cancelled
    case interrupted
}
