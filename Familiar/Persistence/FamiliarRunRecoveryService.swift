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

    func beginInvocation(idempotencyKey: String, runtimeID: String, toolCallID: String, toolName: String, arguments: String, assistantTurnID: String?, activityID: String, in context: ModelContext) throws -> FamiliarToolInvocationRecord {
        if let existing = try context.fetch(FetchDescriptor<FamiliarToolInvocationRecord>(predicate: #Predicate { $0.idempotencyKey == idempotencyKey })).first {
            if existing.state == .committed { throw Error.invocationAlreadyCommitted }
            return existing
        }
        let record = FamiliarToolInvocationRecord(idempotencyKey: idempotencyKey, runtimeID: runtimeID, toolCallID: toolCallID, toolName: toolName, argumentsHash: FamiliarAuthorizationGrant.argumentsHash(arguments), assistantTurnID: assistantTurnID, activityID: activityID, state: .requested)
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

    func beginCommit(_ value: FamiliarToolCommitContext, in context: ModelContext) throws {
        let key = value.idempotencyKey
        let existing = try context.fetch(FetchDescriptor<FamiliarToolInvocationRecord>(predicate: #Predicate { $0.idempotencyKey == key })).first
        if let existing {
            guard existing.state != .committed, existing.state != .committing else { throw Error.invocationAlreadyCommitted }
            existing.state = .committing
        } else {
            context.insert(FamiliarToolInvocationRecord(idempotencyKey: key, runtimeID: value.runID,
                toolCallID: value.call.id, toolName: value.call.name,
                argumentsHash: FamiliarAuthorizationGrant.argumentsHash(value.call.arguments),
                assistantTurnID: value.assistantTurnID,
                activityID: FamiliarRunPersistenceRecorder.toolActivityID(runtimeID: value.runID, toolCallID: value.call.id), state: .committing))
        }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Regeneration must not erase an action's receipts and replay its original prompt.
    func requiresInspection(_ run: FamiliarAgentRun, in context: ModelContext) throws -> Bool {
        let runtimeID = run.runtimeID
        let invocations = try context.fetch(FetchDescriptor<FamiliarToolInvocationRecord>(predicate: #Predicate { $0.runtimeID == runtimeID }))
        if invocations.contains(where: { $0.state == .committing }) { return true }
        let activities = try context.fetch(FetchDescriptor<FamiliarActivityRecord>(predicate: #Predicate { $0.runtimeID == runtimeID }))
        if activities.contains(where: {
            guard let effect = $0.effect, effect != .read else { return false }
            return $0.phase == .succeeded || ["tool_commit_unconfirmed", "tool_persistence_failed", "tool_rollback_failed"].contains($0.failureCode ?? "")
        }) { return true }
        var effects: [String: FamiliarToolEffect] = [:]
        for activity in activities where activity.kind == .tool {
            if let name = activity.toolName, let effect = activity.effect { effects[name] = effect }
        }
        if let snapshotID = run.contextSnapshot?.id {
            let snapshots = try context.fetch(FetchDescriptor<FamiliarCapabilitySnapshotRecord>(predicate: #Predicate { $0.contextSnapshotID == snapshotID }))
            for snapshot in snapshots {
                let manifests = try JSONDecoder().decode([FamiliarToolManifest].self, from: Data(snapshot.manifestsJSON.utf8))
                for manifest in manifests { effects[manifest.name] = manifest.effect }
            }
        }
        return invocations.contains { $0.state == .committed && effects[$0.toolName] != .read }
    }

    @discardableResult
    func recoverInterruptedRuns(in context: ModelContext, reason: String = "interrupted") throws -> Int {
        let runningRaw = FamiliarAgentRunStatus.running.rawValue
        let runs = try context.fetch(FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.statusRawValue == runningRaw }))
        let runtimeIDs = runs.map(\.runtimeID)
        let now = Date()
        let recorder = FamiliarRunPersistenceRecorder()
        for run in runs {
            let runtimeID = run.runtimeID
            let cursor = try context.fetch(FetchDescriptor<FamiliarRunResumeCursorRecord>(predicate: #Predicate { $0.runtimeID == runtimeID })).first
            recorder.finishRun(
                runtimeID: runtimeID,
                outcome: .init(status: .failed, failureKind: .unknown, message: reason),
                eventSequence: (cursor?.lastEventSequence ?? -1) + 1,
                at: now,
                context: context
            )
        }
        for runtimeID in runtimeIDs {
            let invocations = try context.fetch(FetchDescriptor<FamiliarToolInvocationRecord>(predicate: #Predicate { $0.runtimeID == runtimeID }))
            for invocation in invocations {
                switch invocation.state {
                case .requested, .approved:
                    invocation.state = .cancelled
                case .committing, .committed, .failed, .cancelled:
                    break
                }
            }
            let cursors = try context.fetch(FetchDescriptor<FamiliarRunResumeCursorRecord>(predicate: #Predicate { $0.runtimeID == runtimeID }))
            for cursor in cursors {
                cursor.phase = .terminal
                cursor.updatedAt = now
            }
        }
        if !runs.isEmpty { try context.save() }
        return runs.count
    }
}
