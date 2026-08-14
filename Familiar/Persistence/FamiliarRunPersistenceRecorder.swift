import Foundation
import SwiftData

@MainActor
final class FamiliarRunPersistenceRecorder {
    func ensureRun(
        runtimeID: String,
        snapshot: FamiliarContextSnapshot,
        startedAt: Date,
        context: ModelContext
    ) {
        guard let conversation = fetchConversation(id: snapshot.conversationID, in: context),
              !conversation.agentRuns.contains(where: { $0.runtimeID == runtimeID })
        else { return }
        let run = FamiliarAgentRun(
            runtimeID: runtimeID,
            startedAt: startedAt,
            conversation: conversation,
            project: conversation.project
        )
        let toolNamesData = try? JSONEncoder().encode(snapshot.exposedToolNames)
        let record = FamiliarContextSnapshotRecord(
            id: snapshot.id,
            createdAt: snapshot.createdAt,
            projectID: snapshot.projectID,
            projectName: snapshot.projectName,
            conversationID: snapshot.conversationID,
            projectInstruction: snapshot.projectInstruction,
            providerID: snapshot.providerID,
            modelID: snapshot.modelID,
            exposedToolNamesJSON: toolNamesData.map { String(decoding: $0, as: UTF8.self) } ?? "[]",
            maximumInputCharacters: snapshot.maximumInputCharacters,
            initialInputCharacters: snapshot.initialInputCharacters,
            run: run
        )
        context.insert(run)
        context.insert(record)
        for resource in snapshot.resources {
            context.insert(FamiliarContextResourceReference(
                resourceID: resource.resourceID,
                resourceVersionID: resource.resourceVersionID,
                version: resource.version,
                filename: resource.filename,
                mimeType: resource.mimeType,
                contentHash: resource.contentHash,
                extractedTextHash: resource.extractedTextHash,
                snapshot: record
            ))
        }
        do {
            try context.save()
        } catch {
            context.rollback()
        }
    }

    @discardableResult
    func recordTool(
        _ event: FamiliarToolRunTerminalEvent,
        eventSequence: Int,
        conversationID: UUID?,
        context: ModelContext
    ) throws -> Bool {
        guard let conversationID,
              let conversation = fetchConversation(id: conversationID, in: context),
              let run = conversation.agentRuns.first(where: { $0.runtimeID == event.runID }),
              !run.steps.contains(where: { $0.toolCallID == event.toolCallID })
        else { return false }
        context.insert(FamiliarAgentStep(
            type: .tool,
            eventSequence: eventSequence,
            timelineSequence: nextTimelineSequence(in: conversation),
            toolCallID: event.toolCallID,
            toolName: event.toolName,
            summary: event.summary,
            detail: event.detail,
            confirmation: event.confirmation,
            status: event.status,
            startedAt: event.startedAt,
            finishedAt: event.finishedAt,
            artifactIdentifier: event.artifactIdentifier,
            run: run
        ))
        conversation.updatedAt = event.finishedAt
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            throw error
        }
    }

    func recordCheckpoint(
        type: FamiliarAgentStepType,
        runtimeID: String,
        eventSequence: Int,
        summary: String,
        detail: String,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.runtimeID == runtimeID })
        guard let run = try? context.fetch(descriptor).first else { return }
        context.insert(FamiliarAgentStep(
            type: type,
            eventSequence: eventSequence,
            timelineSequence: nextTimelineSequence(in: run.conversation),
            toolCallID: "",
            toolName: "",
            summary: summary,
            detail: detail,
            confirmation: .notRequired,
            status: .succeeded,
            startedAt: Date(),
            finishedAt: Date(),
            run: run
        ))
        try? context.save()
    }

    func finishRun(
        runtimeID: String,
        status: FamiliarAgentRunStatus,
        reason: String,
        eventSequence: Int,
        at date: Date,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.runtimeID == runtimeID })
        guard let run = try? context.fetch(descriptor).first else { return }
        run.status = status
        run.finishReason = reason
        run.finishedAt = date
        if !run.steps.contains(where: { $0.type == .result }) {
            context.insert(FamiliarAgentStep(
                type: .result,
                eventSequence: eventSequence,
                timelineSequence: nextTimelineSequence(in: run.conversation),
                toolCallID: "",
                toolName: "",
                summary: "运行结束",
                detail: reason,
                confirmation: .notRequired,
                status: terminalStatus(for: status),
                startedAt: run.startedAt,
                finishedAt: date,
                run: run
            ))
        }
        try? context.save()
    }

    func finishActiveRuns(
        conversationID: UUID,
        status: FamiliarAgentRunStatus,
        reason: String,
        context: ModelContext
    ) {
        guard let conversation = fetchConversation(id: conversationID, in: context) else { return }
        for run in conversation.agentRuns where run.status == .running {
            run.status = status
            run.finishReason = reason
            run.finishedAt = Date()
        }
        try? context.save()
    }

    private func terminalStatus(for status: FamiliarAgentRunStatus) -> FamiliarToolRunTerminalStatus {
        switch status {
        case .completed: .succeeded
        case .cancelled: .cancelled
        case .running, .failed: .failed
        }
    }

    private func nextTimelineSequence(in conversation: FamiliarConversation?) -> Int {
        guard let conversation else { return 0 }
        let values = conversation.messages.map(\.sequence)
            + conversation.modelSwitchRecords.map(\.sequence)
            + conversation.agentRuns.flatMap(\.steps).map(\.timelineSequence)
        return (values.max() ?? -1) + 1
    }

    private func fetchConversation(id: UUID, in context: ModelContext) -> FamiliarConversation? {
        var descriptor = FetchDescriptor<FamiliarConversation>(
            predicate: #Predicate { conversation in conversation.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
