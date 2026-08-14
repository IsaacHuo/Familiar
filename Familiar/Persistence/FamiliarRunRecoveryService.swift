import Foundation
import SwiftData

@MainActor
final class FamiliarRunRecoveryService {
    enum Error: Swift.Error { case invalidGrantSource, grantMismatch, alreadyConsumed, invocationAlreadyCommitted }

    func persistCapabilitySnapshot(_ snapshot: FamiliarCapabilitySnapshot, contextSnapshotID: UUID, conversationID: UUID, in context: ModelContext) throws {
        let data = try JSONEncoder().encode(snapshot.manifests)
        let record = FamiliarCapabilitySnapshotRecord(createdAt: snapshot.createdAt, projectID: snapshot.projectID, conversationID: conversationID, contextSnapshotID: contextSnapshotID, manifestsJSON: String(decoding: data, as: UTF8.self))
        context.insert(record)
        try context.save()
    }

    func issueGrant(_ grant: FamiliarAuthorizationGrant, in context: ModelContext) throws {
        guard grant.source == .builtIn else { throw Error.invalidGrantSource }
        context.insert(FamiliarAuthorizationGrantRecord(grant: grant))
        try context.save()
    }

    func consumeGrant(_ grant: FamiliarAuthorizationGrant, manifest: FamiliarToolManifest, arguments: String, projectID: UUID?, in context: ModelContext, now: Date = Date()) throws {
        guard grant.isValid(for: manifest, arguments: arguments, projectID: projectID, now: now) else { throw Error.grantMismatch }
        guard let record = try context.fetch(FetchDescriptor<FamiliarAuthorizationGrantRecord>(predicate: #Predicate { $0.id == grant.id })).first else { throw Error.grantMismatch }
        guard record.state == .issued else { throw Error.alreadyConsumed }
        record.state = .consumed
        record.consumedAt = now
        try context.save()
    }

    func beginCursor(runtimeID: String, runID: UUID?, contextSnapshotID: UUID, in context: ModelContext) throws -> FamiliarRunResumeCursorRecord {
        let cursor = FamiliarRunResumeCursorRecord(runtimeID: runtimeID, contextSnapshotID: contextSnapshotID, runID: runID)
        context.insert(cursor)
        try context.save()
        return cursor
    }

    func updateCursor(_ cursor: FamiliarRunResumeCursorRecord, iteration: Int, phase: FamiliarRunRecoveryPhase, eventSequence: Int, toolCallID: String? = nil, toolName: String? = nil, in context: ModelContext) throws {
        cursor.nextIteration = iteration
        cursor.phase = phase
        cursor.lastEventSequence = eventSequence
        cursor.pendingToolCallID = toolCallID
        cursor.pendingToolName = toolName
        cursor.updatedAt = Date()
        try context.save()
    }

    func beginInvocation(idempotencyKey: String, runtimeID: String, toolName: String, arguments: String, in context: ModelContext) throws -> FamiliarToolInvocationRecord {
        if let existing = try context.fetch(FetchDescriptor<FamiliarToolInvocationRecord>(predicate: #Predicate { $0.idempotencyKey == idempotencyKey })).first {
            if existing.state == .committed { throw Error.invocationAlreadyCommitted }
            return existing
        }
        let record = FamiliarToolInvocationRecord(idempotencyKey: idempotencyKey, runtimeID: runtimeID, toolName: toolName, argumentsHash: FamiliarAuthorizationGrant.argumentsHash(arguments), state: .requested)
        context.insert(record)
        try context.save()
        return record
    }

    func setInvocationState(_ invocation: FamiliarToolInvocationRecord, state: FamiliarToolInvocationState, resultReference: String? = nil, in context: ModelContext) throws {
        invocation.state = state
        invocation.resultReference = resultReference
        if state == .committed { invocation.committedAt = Date() }
        try context.save()
    }
}
