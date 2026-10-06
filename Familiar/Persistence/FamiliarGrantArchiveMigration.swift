import Foundation
import SwiftData

/// Migration-only provenance, never an executable authorization.
nonisolated struct FamiliarArchivedGrant: Codable, Equatable, Sendable {
    let id: UUID
    let userAction: String
    let sourceRawValue: String
    let capabilityID: String
    let capabilityVersion: String
    let argumentsHash: String
    let projectID: UUID?
    let expiresAt: Date
    let singleUse: Bool
    let evidence: String
    let consumedAt: Date?
    let stateRawValue: String
}

nonisolated enum FamiliarGrantArchiveMigration {
    enum Error: Swift.Error { case conflictingArchive(UUID) }

    static func archive(in context: ModelContext) throws {
        for grant in try context.fetch(FetchDescriptor<FamiliarSchemaV5.FamiliarAuthorizationGrantRecord>()) {
            let id = grant.id
            let audit = FamiliarArchivedGrant(id: id, userAction: grant.userAction, sourceRawValue: grant.sourceRawValue,
                capabilityID: grant.capabilityID, capabilityVersion: grant.capabilityVersion,
                argumentsHash: grant.argumentsHash, projectID: grant.projectID, expiresAt: grant.expiresAt,
                singleUse: grant.singleUse, evidence: grant.evidence, consumedAt: grant.consumedAt, stateRawValue: grant.stateRawValue)
            let activityID = "legacy-grant:" + id.uuidString
            if let existing = try context.fetch(FetchDescriptor<FamiliarActivityRecord>(predicate: #Predicate { $0.activityID == activityID })).first {
                guard let detail = existing.detail, try JSONDecoder().decode(FamiliarArchivedGrant.self, from: Data(detail.utf8)) == audit
                else { throw Error.conflictingArchive(id) }
                continue
            }
            context.insert(FamiliarActivityRecord(activityID: activityID,
                runtimeID: runtimeID(projectID: grant.projectID), assistantTurnID: "legacy-grant", kind: .runtimeNotice,
                phase: .succeeded, summary: "archived_authorization_provenance",
                detail: String(decoding: try JSONEncoder().encode(audit), as: UTF8.self), sequence: -1,
                startedAt: grant.consumedAt ?? grant.expiresAt, endedAt: grant.consumedAt))
        }
        try context.save()
    }

    static func runtimeID(projectID: UUID?) -> String { "legacy-grants:" + (projectID?.uuidString ?? "global") }
}
