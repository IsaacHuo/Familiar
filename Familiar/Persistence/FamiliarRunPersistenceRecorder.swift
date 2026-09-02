import Foundation
import SwiftData

@MainActor
final class FamiliarRunPersistenceRecorder {
    static func toolActivityID(runtimeID: String, toolCallID: String) -> String {
        "tool:\(runtimeID):\(toolCallID)"
    }

    static func turnActivityID(assistantTurnID: String) -> String {
        "turn:\(assistantTurnID)"
    }

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
        for attachment in snapshot.attachments {
            let sourceData = FamiliarAttachmentStore.url(for: attachment.relativePath)
                .flatMap { try? Data(contentsOf: $0, options: [.mappedIfSafe]) }
                ?? Data(attachment.extractedText.utf8)
            context.insert(FamiliarContextAttachmentReference(
                contextSnapshotID: snapshot.id,
                attachmentID: attachment.id,
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                sourceRelativePath: attachment.relativePath,
                byteSize: attachment.byteSize,
                contentHash: FamiliarHash.sha256(sourceData),
                extractedTextHash: FamiliarHash.sha256(Data(attachment.extractedText.utf8)),
                createdAt: snapshot.createdAt
            ))
        }
        for (sequence, skill) in snapshot.skills.enumerated() {
            let allowedToolsData = try? JSONEncoder().encode(skill.allowedTools)
            context.insert(FamiliarRunSkillSnapshotRecord(
                runID: run.id,
                runtimeID: run.runtimeID,
                contextSnapshotID: snapshot.id,
                projectID: snapshot.projectID,
                sequence: sequence,
                stableID: skill.stableID,
                version: skill.version,
                name: skill.name,
                contentHash: skill.contentHash,
                allowedToolsJSON: allowedToolsData.map { String(decoding: $0, as: UTF8.self) } ?? "[]",
                createdAt: snapshot.createdAt
            ))
        }
        for evidence in snapshot.visualEvidence {
            context.insert(FamiliarVisualEvidenceRecord(
                id: evidence.id,
                attachmentID: evidence.attachmentID,
                messageID: snapshot.visualEvidenceMessageID,
                contextSnapshotID: snapshot.id,
                filename: evidence.filename,
                sourceRelativePath: evidence.sourceRelativePath,
                renderedText: evidence.renderedText,
                processingMethod: evidence.processingMethod,
                engineVersion: evidence.engineVersion,
                createdAt: evidence.createdAt
            ))
        }
        do {
            try context.save()
        } catch {
            context.rollback()
        }
    }

    func recordLoadedSkill(
        runtimeID: String,
        skill: FamiliarSkillSnapshot,
        at date: Date,
        context: ModelContext
    ) throws {
        guard let run = fetchRun(runtimeID: runtimeID, in: context),
              let snapshotID = run.contextSnapshot?.id
        else { return }
        let existing = try context.fetch(FetchDescriptor<FamiliarRunSkillSnapshotRecord>(
            predicate: #Predicate { $0.runtimeID == runtimeID }
        ))
        guard !existing.contains(where: { $0.stableID == skill.stableID && $0.contentHash == skill.contentHash }) else { return }
        let allowedToolsData = try JSONEncoder().encode(skill.allowedTools)
        context.insert(FamiliarRunSkillSnapshotRecord(
            runID: run.id,
            runtimeID: runtimeID,
            contextSnapshotID: snapshotID,
            projectID: run.project?.id,
            sequence: existing.count,
            stableID: skill.stableID,
            version: skill.version,
            name: skill.name,
            contentHash: skill.contentHash,
            allowedToolsJSON: String(decoding: allowedToolsData, as: UTF8.self),
            createdAt: date
        ))
        try context.save()
    }

    func recordRunPhase(
        _ phase: FamiliarRunPhase,
        runtimeID: String,
        eventSequence: Int,
        at date: Date,
        context: ModelContext
    ) throws {
        guard fetchRun(runtimeID: runtimeID, in: context) != nil else { return }
        let value: String = switch phase {
        case .starting: "starting"
        case .compactingContext: "compactingContext"
        case .planning: "planning"
        case .preparingEnvironment: "preparingEnvironment"
        case .executing: "executing"
        case .validating: "validating"
        case .repairing(let attempt): "repairing:\(attempt)"
        case .delivering: "delivering"
        case .reasoning: "reasoning"
        case .responding: "responding"
        case .executingActivities(let names): "executingActivities:\(names.joined(separator: ","))"
        case .awaitingApproval: "awaitingApproval"
        case .awaitingClarification: "awaitingClarification"
        }
        context.insert(FamiliarActivityRecord(
            activityID: "phase:\(runtimeID):\(eventSequence)",
            runtimeID: runtimeID,
            assistantTurnID: "\(runtimeID):phase",
            kind: .runtimeNotice,
            phase: .succeeded,
            summary: value,
            sequence: eventSequence,
            startedAt: date,
            endedAt: date
        ))
        try context.save()
    }

    func recordActivityStarted(
        _ activity: FamiliarRuntimeActivity,
        runtimeID: String,
        assistantTurnID: String,
        eventSequence: Int,
        context: ModelContext
    ) throws {
        guard let run = fetchRun(runtimeID: runtimeID, in: context) else { return }
        run.assistantTurnID = assistantTurnID
        let parentID = ensureTurnActivity(run: run, assistantTurnID: assistantTurnID, sequence: eventSequence, at: activity.startedAt, context: context).activityID
        let activityID = Self.toolActivityID(runtimeID: runtimeID, toolCallID: activity.id)
        if fetchActivity(activityID: activityID, in: context) == nil {
            context.insert(FamiliarActivityRecord(
                activityID: activityID,
                runtimeID: runtimeID,
                parentID: parentID,
                assistantTurnID: assistantTurnID,
                kind: .tool,
                effect: activity.effect,
                phase: .queued,
                toolName: activity.toolName,
                toolCallID: activity.id,
                summary: activity.toolName,
                progress: 0,
                sequence: eventSequence,
                startedAt: activity.startedAt
            ))
        }
        try context.save()
    }

    func recordActivityProgress(
        _ progress: FamiliarRuntimeActivityProgress,
        runtimeID: String,
        at date: Date,
        context: ModelContext
    ) throws {
        guard let activity = fetchActivity(activityID: Self.toolActivityID(runtimeID: runtimeID, toolCallID: progress.id), in: context) else { return }
        activity.detail = progress.detail
        activity.phase = .running
        activity.progress = progress.fractionCompleted
        try context.save()
    }

    func recordActivityCompleted(
        _ event: FamiliarRuntimeActivityCompletion,
        eventSequence: Int,
        conversationID: UUID?,
        context: ModelContext
    ) throws {
        guard let conversationID,
              let conversation = fetchConversation(id: conversationID, in: context),
              let run = conversation.agentRuns.first(where: { $0.runtimeID == event.runID })
        else { return }
        run.assistantTurnID = event.assistantTurnID
        let parentID = ensureTurnActivity(run: run, assistantTurnID: event.assistantTurnID, sequence: eventSequence, at: event.startedAt, context: context).activityID
        let activityID = Self.toolActivityID(runtimeID: event.runID, toolCallID: event.toolCallID)
        let activity: FamiliarActivityRecord
        if let existing = fetchActivity(activityID: activityID, in: context) {
            activity = existing
        } else {
            activity = FamiliarActivityRecord(activityID: activityID, runtimeID: event.runID, parentID: parentID, assistantTurnID: event.assistantTurnID, kind: .tool, effect: event.effect, phase: activityPhase(for: event.status), toolName: event.toolName, toolCallID: event.toolCallID, summary: event.toolName, sequence: eventSequence, startedAt: event.startedAt)
            context.insert(activity)
        }
        activity.effectRawValue = event.effect.rawValue
        activity.phase = activityPhase(for: event.status)
        activity.summary = event.toolName
        activity.detail = event.detail.isEmpty ? nil : event.detail
        activity.failureCode = event.failureCode
        activity.failureRetryable = event.failureRetryable
        activity.progress = 1
        activity.endedAt = event.finishedAt
        if let automatic = event.automaticApprovalRequest {
            let approval = upsertApproval(automatic, assistantTurnID: event.assistantTurnID, activityID: activityID, requestedAt: event.finishedAt, context: context)
            approval.decisionRawValue = FamiliarApprovalDecision.approved.rawValue
            approval.scopeRawValue = approvalScope(for: automatic.automaticAuthorizationScope)?.rawValue
            approval.resolvedAt = event.finishedAt
            activity.approvalRecordID = approval.id
            linkInvocation(runtimeID: event.runID, toolCallID: event.toolCallID, approvalRecordID: approval.id, toolResultRecordID: nil, context: context)
        }
        conversation.updatedAt = event.finishedAt
        try context.save()
    }

    func recordApprovalRequested(
        _ request: FamiliarToolConfirmationRequest,
        assistantTurnID: String,
        eventSequence: Int,
        at date: Date,
        context: ModelContext
    ) throws {
        guard fetchRun(runtimeID: request.runID, in: context) != nil else { return }
        try recordActivityStarted(
            .init(id: request.toolCallID, toolName: request.toolName, effect: request.effect, startedAt: date),
            runtimeID: request.runID,
            assistantTurnID: assistantTurnID,
            eventSequence: eventSequence,
            context: context
        )
        let activityID = Self.toolActivityID(runtimeID: request.runID, toolCallID: request.toolCallID)
        let record = upsertApproval(request, assistantTurnID: assistantTurnID, activityID: activityID, requestedAt: date, context: context)
        if let activity = fetchActivity(activityID: activityID, in: context) {
            activity.phase = .awaitingApproval
            activity.approvalRecordID = record.id
            activity.summary = request.toolName
        }
        linkInvocation(runtimeID: request.runID, toolCallID: request.toolCallID, approvalRecordID: record.id, toolResultRecordID: nil, context: context)
        try context.save()
    }

    func recordApprovalResolved(
        requestID: UUID,
        decision: FamiliarToolConfirmationDecision,
        eventSequence: Int,
        at date: Date,
        context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<FamiliarApprovalRecord>(predicate: #Predicate { $0.id == requestID })
        guard let record = try context.fetch(descriptor).first else { return }
        let values = approvalValues(for: decision)
        record.decisionRawValue = values.decision.rawValue
        record.scopeRawValue = values.scope?.rawValue
        record.resolvedAt = date
        if let activity = fetchActivity(activityID: record.activityID, in: context) {
            activity.phase = decision.isConfirmed ? .running : .cancelled
            if !decision.isConfirmed { activity.endedAt = date }
        }
        try context.save()
    }

    func recordClarificationRequested(
        _ request: FamiliarClarificationRequest,
        assistantTurnID: String,
        eventSequence: Int,
        at date: Date,
        context: ModelContext
    ) throws {
        guard fetchRun(runtimeID: request.runID, in: context) != nil else { return }
        let activityID = Self.toolActivityID(runtimeID: request.runID, toolCallID: request.toolCallID)
        if fetchActivity(activityID: activityID, in: context) == nil {
            try recordActivityStarted(
                .init(id: request.toolCallID, toolName: "ask_user", effect: .read, startedAt: date),
                runtimeID: request.runID,
                assistantTurnID: assistantTurnID,
                eventSequence: eventSequence,
                context: context
            )
        }
        let descriptor = FetchDescriptor<FamiliarClarificationRecord>(predicate: #Predicate { $0.id == request.id })
        if try context.fetch(descriptor).first == nil {
            context.insert(FamiliarClarificationRecord(
                id: request.id,
                runtimeID: request.runID,
                assistantTurnID: assistantTurnID,
                activityID: activityID,
                toolCallID: request.toolCallID,
                question: request.question,
                optionsJSON: try Self.requireEncodedJSON(request.options),
                allowCustom: request.allowCustom,
                requestedAt: date
            ))
        }
        if let activity = fetchActivity(activityID: activityID, in: context) {
            activity.phase = .awaitingClarification
            activity.summary = request.question
        }
        try context.save()
    }

    func recordClarificationResolved(
        requestID: UUID,
        resolution: FamiliarClarificationResolution,
        at date: Date,
        context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<FamiliarClarificationRecord>(predicate: #Predicate { $0.id == requestID })
        guard let record = try context.fetch(descriptor).first else { return }
        record.state = switch resolution {
        case .selectedOption, .custom: .resolved
        case .cancelled: .cancelled
        case .interrupted: .interrupted
        }
        record.resolutionJSON = try Self.requireEncodedJSON(resolution)
        record.resolvedAt = date
        if let activity = fetchActivity(activityID: record.activityID, in: context) {
            activity.phase = record.state == .resolved ? .running : .cancelled
            activity.detail = resolution.answer
            if record.state != .resolved { activity.endedAt = date }
        }
        try context.save()
    }

    func recordRuntimeNotice(
        _ notice: FamiliarRuntimeNotice,
        runtimeID: String,
        assistantTurnID: String,
        eventSequence: Int,
        at date: Date,
        context: ModelContext
    ) throws {
        guard let run = fetchRun(runtimeID: runtimeID, in: context) else { return }
        run.assistantTurnID = assistantTurnID
        let parentID = ensureTurnActivity(run: run, assistantTurnID: assistantTurnID, sequence: eventSequence, at: date, context: context).activityID
        let activityID = "notice:\(runtimeID):\(notice.kind.rawValue):\(notice.attempt)"
        guard fetchActivity(activityID: activityID, in: context) == nil else { return }
        context.insert(FamiliarActivityRecord(
            activityID: activityID,
            runtimeID: runtimeID,
            parentID: parentID,
            assistantTurnID: assistantTurnID,
            kind: .runtimeNotice,
            phase: .succeeded,
            summary: notice.kind.rawValue,
            detail: "attempt=\(notice.attempt);delay=\(notice.delay);failure=\(notice.failureKind.rawValue)",
            progress: 1,
            sequence: eventSequence,
            startedAt: date,
            endedAt: date
        ))
        try context.save()
    }

    @discardableResult
    func recordToolResult(
        _ event: FamiliarToolResultProduced,
        eventSequence: Int,
        conversationID: UUID?,
        context: ModelContext
    ) throws -> Bool {
        guard let conversationID,
              let conversation = fetchConversation(id: conversationID, in: context),
              let run = conversation.agentRuns.first(where: { $0.runtimeID == event.runID })
        else { return false }
        let activityID = Self.toolActivityID(runtimeID: event.runID, toolCallID: event.toolCallID)
        let turnID = event.assistantTurnID
        run.assistantTurnID = turnID
        _ = ensureTurnActivity(run: run, assistantTurnID: turnID, sequence: eventSequence, at: event.producedAt, context: context)
        guard let activity = fetchActivity(activityID: activityID, in: context) else { return false }
        let insertedResult = activity.resultRecordID == nil
        let result = try upsertToolResult(event.envelope, event: event, activityID: activityID, context: context)
        activity.resultRecordID = result.id
        linkInvocation(runtimeID: event.runID, toolCallID: event.toolCallID, approvalRecordID: nil, toolResultRecordID: result.id, context: context)
        conversation.updatedAt = event.producedAt
        do {
            try context.save()
            return insertedResult
        } catch {
            context.rollback()
            throw error
        }
    }

    func updateRunFirstToken(runtimeID: String, date: Date, context: ModelContext) {
        guard let run = fetchRun(runtimeID: runtimeID, in: context), run.firstTokenAt == nil else { return }
        run.firstTokenAt = date
        try? context.save()
    }

    func finishRun(
        runtimeID: String,
        outcome: FamiliarRunOutcome,
        eventSequence: Int,
        at date: Date,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.runtimeID == runtimeID })
        guard let run = try? context.fetch(descriptor).first else { return }
        let status: FamiliarAgentRunStatus = switch outcome.status {
        case .succeeded: .completed
        case .cancelled: .cancelled
        case .failed: .failed
        }
        let reason = outcome.message ?? outcome.failureKind?.code ?? outcome.status.rawValue
        run.status = status
        run.finishReason = reason
        run.finishedAt = date
        if status == .failed || status == .cancelled {
            ensureTerminalProjection(for: run, status: status, reason: reason, eventSequence: eventSequence, at: date, context: context)
        }
        finishClarifications(runtimeID: runtimeID, state: status == .cancelled ? .cancelled : .interrupted, at: date, context: context)
        finishTurnActivities(for: run, status: status, at: date, context: context)
        try? context.save()
    }

    @discardableResult
    func recordResponseBlock(
        id: UUID = UUID(),
        runtimeID: String,
        assistantTurnID: String,
        messageID: UUID?,
        kind: FamiliarResponseBlockKind,
        state: FamiliarResponseBlockState,
        content: String,
        payloadJSON: String = "{}",
        schemaVersion: Int = 1,
        order: Int? = nil,
        startedAt: Date? = nil,
        endedAt: Date,
        context: ModelContext
    ) throws -> FamiliarResponseBlockRecord? {
        guard let run = fetchRun(runtimeID: runtimeID, in: context) else { return nil }
        let descriptor = FetchDescriptor<FamiliarResponseBlockRecord>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if existing.messageID == nil, let messageID {
                existing.messageID = messageID
                run.responseBlockID = existing.id
                if state == .completed { run.responseMessageID = messageID }
                try context.save()
            }
            return existing
        }
        let block = FamiliarResponseBlockRecord(
            id: id,
            runtimeID: runtimeID,
            assistantTurnID: assistantTurnID,
            messageID: messageID,
            kind: kind,
            order: order ?? nextBlockOrder(runtimeID: runtimeID, context: context),
            state: state,
            content: content,
            payloadJSON: payloadJSON,
            schemaVersion: schemaVersion,
            startedAt: startedAt ?? run.startedAt,
            endedAt: endedAt,
            contentHash: FamiliarHash.sha256(content)
        )
        context.insert(block)
        run.assistantTurnID = assistantTurnID
        run.responseBlockID = block.id
        if state == .completed { run.responseMessageID = messageID }
        try context.save()
        return block
    }

    func finishActiveRuns(
        conversationID: UUID,
        outcome: FamiliarRunOutcome,
        context: ModelContext
    ) {
        let status: FamiliarAgentRunStatus = switch outcome.status {
        case .succeeded: .completed
        case .cancelled: .cancelled
        case .failed: .failed
        }
        let reason = outcome.message ?? outcome.failureKind?.code ?? outcome.status.rawValue
        guard let conversation = fetchConversation(id: conversationID, in: context) else { return }
        for run in conversation.agentRuns where run.status == .running {
            run.status = status
            run.finishReason = reason
            let date = Date()
            run.finishedAt = date
            ensureTerminalProjection(for: run, status: status, reason: reason, eventSequence: nextActivitySequence(runtimeID: run.runtimeID, context: context), at: date, context: context)
            finishTurnActivities(for: run, status: status, at: date, context: context)
        }
        try? context.save()
    }

    private func activityPhase(for status: FamiliarToolRunTerminalStatus) -> FamiliarActivityPhase {
        switch status {
        case .succeeded: .succeeded
        case .cancelled: .cancelled
        case .failed: .failed
        }
    }

    private func ensureTurnActivity(run: FamiliarAgentRun, assistantTurnID: String, sequence: Int, at date: Date, context: ModelContext) -> FamiliarActivityRecord {
        let activityID = Self.turnActivityID(assistantTurnID: assistantTurnID)
        if let existing = fetchActivity(activityID: activityID, in: context) { return existing }
        let activity = FamiliarActivityRecord(
            activityID: activityID,
            runtimeID: run.runtimeID,
            assistantTurnID: assistantTurnID,
            kind: .assistantTurn,
            phase: .running,
            summary: "Assistant turn",
            sequence: sequence,
            startedAt: date
        )
        context.insert(activity)
        return activity
    }

    private func upsertApproval(_ request: FamiliarToolConfirmationRequest, assistantTurnID: String, activityID: String, requestedAt: Date, context: ModelContext) -> FamiliarApprovalRecord {
        let descriptor = FetchDescriptor<FamiliarApprovalRecord>(predicate: #Predicate { $0.id == request.id })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let fieldsJSON = Self.encodedJSON(request.fields) ?? "[]"
        let durationsJSON = Self.encodedJSON(request.allowedAuthorizationDurations) ?? "[]"
        let record = FamiliarApprovalRecord(
            id: request.id,
            runtimeID: request.runID,
            assistantTurnID: assistantTurnID,
            activityID: activityID,
            toolCallID: request.toolCallID,
            toolName: request.toolName,
            title: request.title,
            orderedFieldsJSON: fieldsJSON,
            target: request.target,
            effect: request.effect,
            risk: request.risk,
            consequence: request.consequence,
            undoPolicy: request.undoPolicy,
            allowedAuthorizationDurationsJSON: durationsJSON,
            requestedAt: requestedAt,
            automaticAuthorization: request.automaticAuthorization
        )
        context.insert(record)
        return record
    }

    private func upsertToolResult(_ envelope: FamiliarToolResultEnvelope, event: FamiliarToolResultProduced, activityID: String, context: ModelContext) throws -> FamiliarToolResultRecord {
        let descriptor = FetchDescriptor<FamiliarToolResultRecord>(predicate: #Predicate { $0.activityID == activityID })
        if let existing = try context.fetch(descriptor).first { return existing }
        let envelopeJSON = try Self.requireEncodedJSON(envelope)
        let payloadJSON = try Self.requireEncodedJSON(envelope.presentation)
        let truncated = if case .document(let document) = envelope.presentation.content { document.truncated } else { false }
        let semanticID: String? = if case .taskList(let taskList) = envelope.presentation.content { taskList.planID } else { nil }
        if let semanticID,
           let existing = try context.fetch(FetchDescriptor<FamiliarToolResultRecord>()).first(where: { $0.runtimeID == event.runID && $0.semanticID == semanticID }) {
            for activity in try context.fetch(FetchDescriptor<FamiliarActivityRecord>()) where activity.resultRecordID == existing.id {
                activity.resultRecordID = nil
            }
            existing.activityID = activityID
            existing.assistantTurnID = event.assistantTurnID
            existing.toolCallID = event.toolCallID
            existing.envelopeJSON = envelopeJSON
            existing.schemaVersion = envelope.presentation.schemaVersion
            existing.payloadName = envelope.presentation.name.rawValue
            existing.payloadHash = FamiliarHash.sha256(payloadJSON)
            existing.revision += 1
            existing.truncated = truncated
            existing.createdAt = event.producedAt
            return existing
        }
        let result = FamiliarToolResultRecord(
            activityID: activityID,
            runtimeID: event.runID,
            assistantTurnID: event.assistantTurnID,
            toolCallID: event.toolCallID,
            envelopeJSON: envelopeJSON,
            schemaVersion: envelope.presentation.schemaVersion,
            payloadName: envelope.presentation.name.rawValue,
            payloadHash: FamiliarHash.sha256(payloadJSON),
            semanticID: semanticID,
            trust: .untrusted,
            truncated: truncated,
            createdAt: event.producedAt
        )
        context.insert(result)
        return result
    }

    private func finishClarifications(runtimeID: String, state: FamiliarClarificationState, at date: Date, context: ModelContext) {
        let records = (try? context.fetch(FetchDescriptor<FamiliarClarificationRecord>())) ?? []
        for record in records where record.runtimeID == runtimeID && record.state == .requested {
            record.state = state
            let resolution: FamiliarClarificationResolution = state == .cancelled ? .cancelled : .interrupted
            record.resolutionJSON = Self.encodedJSON(resolution)
            record.resolvedAt = date
        }
    }

    private func ensureTerminalProjection(for run: FamiliarAgentRun, status: FamiliarAgentRunStatus, reason: String, eventSequence: Int, at date: Date, context: ModelContext) {
        let assistantTurnID = run.assistantTurnID ?? "\(run.runtimeID):runtime"
        let activityID = "notice:\(run.runtimeID):terminal"
        if fetchActivity(activityID: activityID, in: context) == nil {
            context.insert(FamiliarActivityRecord(
                activityID: activityID,
                runtimeID: run.runtimeID,
                assistantTurnID: assistantTurnID,
                kind: .runtimeNotice,
                phase: status == .cancelled ? .cancelled : .failed,
                summary: status == .cancelled ? "Run cancelled" : "Run failed",
                detail: reason,
                progress: 1,
                sequence: eventSequence,
                startedAt: run.startedAt,
                endedAt: date
            ))
        }
        let blocks = responseBlocks(runtimeID: run.runtimeID, context: context)
        guard !blocks.contains(where: { $0.kind == .runtimeNotice }) else { return }
        let block = FamiliarResponseBlockRecord(
            runtimeID: run.runtimeID,
            assistantTurnID: assistantTurnID,
            messageID: nil,
            kind: .runtimeNotice,
            order: blocks.count,
            state: status == .cancelled ? .cancelled : .failed,
            content: reason,
            payloadJSON: Self.encodedJSON(["reason": reason]) ?? "{}",
            startedAt: run.startedAt,
            endedAt: date,
            contentHash: FamiliarHash.sha256(reason)
        )
        context.insert(block)
        run.responseBlockID = block.id
    }

    private func finishTurnActivities(for run: FamiliarAgentRun, status: FamiliarAgentRunStatus, at date: Date, context: ModelContext) {
        let runtimeID = run.runtimeID
        let descriptor = FetchDescriptor<FamiliarActivityRecord>(predicate: #Predicate { $0.runtimeID == runtimeID })
        let phase: FamiliarActivityPhase = switch status {
        case .completed: .succeeded
        case .cancelled: .cancelled
        case .running, .failed: .failed
        }
        for activity in ((try? context.fetch(descriptor)) ?? []) where !activity.phase.isTerminal {
            activity.phase = phase
            activity.progress = 1
            activity.endedAt = date
        }
    }

    private func linkInvocation(runtimeID: String, toolCallID: String, approvalRecordID: UUID?, toolResultRecordID: UUID?, context: ModelContext) {
        let key = runtimeID + ":" + toolCallID
        let descriptor = FetchDescriptor<FamiliarToolInvocationRecord>(predicate: #Predicate { $0.idempotencyKey == key })
        guard let invocation = try? context.fetch(descriptor).first else { return }
        if let approvalRecordID { invocation.approvalRecordID = approvalRecordID }
        if let toolResultRecordID { invocation.toolResultRecordID = toolResultRecordID }
    }

    private func approvalValues(for decision: FamiliarToolConfirmationDecision) -> (decision: FamiliarApprovalDecision, scope: FamiliarApprovalScope?) {
        switch decision {
        case .confirmedOnce: (.approved, .once)
        case .confirmed: (.approved, .session)
        case .confirmedAlways: (.approved, .always)
        case .cancelled: (.cancelled, nil)
        }
    }

    private func approvalScope(for duration: FamiliarAuthorizationDuration?) -> FamiliarApprovalScope? {
        switch duration {
        case .once: .once
        case .session: .session
        case .always: .always
        case nil: nil
        }
    }

    private func nextBlockOrder(runtimeID: String, context: ModelContext) -> Int {
        responseBlocks(runtimeID: runtimeID, context: context).map(\.order).max().map { $0 + 1 } ?? 0
    }

    private func responseBlocks(runtimeID: String, context: ModelContext) -> [FamiliarResponseBlockRecord] {
        let descriptor = FetchDescriptor<FamiliarResponseBlockRecord>(predicate: #Predicate { $0.runtimeID == runtimeID })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func nextActivitySequence(runtimeID: String, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<FamiliarActivityRecord>(predicate: #Predicate { $0.runtimeID == runtimeID })
        return ((try? context.fetch(descriptor)) ?? []).map(\.sequence).max().map { $0 + 1 } ?? 0
    }

    private func fetchRun(runtimeID: String, in context: ModelContext) -> FamiliarAgentRun? {
        let descriptor = FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.runtimeID == runtimeID })
        return try? context.fetch(descriptor).first
    }

    private func fetchActivity(activityID: String, in context: ModelContext) -> FamiliarActivityRecord? {
        let descriptor = FetchDescriptor<FamiliarActivityRecord>(predicate: #Predicate { $0.activityID == activityID })
        return try? context.fetch(descriptor).first
    }

    private static func encodedJSON<T: Encodable>(_ value: T) -> String? {
        try? requireEncodedJSON(value)
    }

    private static func requireEncodedJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func fetchConversation(id: UUID, in context: ModelContext) -> FamiliarConversation? {
        var descriptor = FetchDescriptor<FamiliarConversation>(
            predicate: #Predicate { conversation in conversation.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
