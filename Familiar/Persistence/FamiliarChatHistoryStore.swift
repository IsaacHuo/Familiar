import Foundation
import SwiftData

nonisolated struct FamiliarHistoryReference: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case message(UUID, runID: String?)
        case modelSwitch(UUID)
        case orphanRun(String)
    }
    let kind: Kind
    let date: Date
    var id: String {
        switch kind {
        case .message(let id, let run): run.map { "run:" + $0 } ?? "message:" + id.uuidString
        case .modelSwitch(let id): "model-switch:" + id.uuidString
        case .orphanRun(let id): "run:" + id
        }
    }
    var messageID: UUID? { if case .message(let id, _) = kind { id } else { nil } }
    var switchID: UUID? { if case .modelSwitch(let id) = kind { id } else { nil } }
    var runtimeID: String? {
        switch kind { case .message(_, let id): id; case .orphanRun(let id): id; case .modelSwitch: nil }
    }
}

/// Identity/date index only; it holds no message bodies, attachments, receipts or managed objects.
nonisolated struct FamiliarConversationHistoryIndex: Sendable {
    let conversationID: UUID
    let entries: [FamiliarHistoryReference]
    let positions: [String: Int]
    let messageEntries: [UUID: String]
    let messageCount: Int
    let latestReplyID: UUID?
    init(conversationID: UUID, entries: [FamiliarHistoryReference], latestReplyID: UUID?) {
        self.conversationID = conversationID
        self.entries = entries.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        positions = Dictionary(uniqueKeysWithValues: self.entries.enumerated().map { ($0.element.id, $0.offset) })
        messageEntries = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in entry.messageID.map { ($0, entry.id) } })
        messageCount = messageEntries.count
        self.latestReplyID = latestReplyID
    }
    func range(anchor: String?) -> Range<Int> {
        FamiliarHistoryWindow.range(total: entries.count, center: anchor.flatMap { positions[$0] })
    }
}

nonisolated struct FamiliarConversationHistoryPage: Sendable {
    let messages: [FamiliarMessageSnapshot]
    let modelSwitches: [FamiliarModelSwitchSnapshot]
    let runs: [FamiliarAgentRunSnapshot]
    let undoRuntimeIDs: [String]
}

/// Reads the identity index separately from an at-most-80-entry rich page.
/// Uses the caller's context so terminal writes are visible in the same transaction.
@MainActor enum FamiliarChatHistoryStore {
    static func index(conversationID: UUID, in context: ModelContext) throws -> FamiliarConversationHistoryIndex {
        var messages = FetchDescriptor<FamiliarMessage>(predicate: #Predicate { $0.conversation?.id == conversationID },
            sortBy: [SortDescriptor(\.sequence), SortDescriptor(\.createdAt)])
        messages.propertiesToFetch = [\.id, \.createdAt, \.sequence, \.roleRawValue]
        var switches = FetchDescriptor<FamiliarModelSwitchRecord>(predicate: #Predicate { $0.conversation?.id == conversationID })
        switches.propertiesToFetch = [\.id, \.createdAt]
        var runs = FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.conversation?.id == conversationID })
        runs.propertiesToFetch = [\.runtimeID, \.responseMessageID, \.statusRawValue, \.startedAt]
        let runRecords = try context.fetch(runs)
        let finalRuns = runRecords.reduce(into: [UUID: String]()) { values, run in
            if let id = run.responseMessageID, values[id] == nil { values[id] = run.runtimeID }
        }
        let messageRecords = try context.fetch(messages)
        var entries = messageRecords.map { message in
            FamiliarHistoryReference(kind: .message(message.id, runID: message.role == .assistant ? finalRuns[message.id] : nil), date: message.createdAt)
        }
        entries += try context.fetch(switches).map { .init(kind: .modelSwitch($0.id), date: $0.createdAt) }
        entries += runRecords.filter { $0.responseMessageID == nil && $0.status != .running }
            .map { .init(kind: .orphanRun($0.runtimeID), date: $0.startedAt) }
        return .init(conversationID: conversationID, entries: entries,
            latestReplyID: messageRecords.last(where: { $0.role == .assistant })?.id)
    }

    static func page(conversation: FamiliarConversation, references: [FamiliarHistoryReference], activeRunID: String?,
                     in context: ModelContext) throws -> FamiliarConversationHistoryPage {
        guard references.count <= FamiliarHistoryWindow.pageSize else { throw CocoaError(.coderInvalidValue) }
        let conversationID = conversation.id
        let messageIDs = references.compactMap(\.messageID)
        let messageRecords = messageIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<FamiliarMessage>(predicate: #Predicate {
            $0.conversation?.id == conversationID && messageIDs.contains($0.id)
        }))
        let scopedMessageIDs = messageRecords.map(\.id)
        let messageBlocks = scopedMessageIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<FamiliarResponseBlockRecord>(predicate: #Predicate {
            $0.messageID.flatMap { scopedMessageIDs.contains($0) } ?? false
        }))
        // Partial assistant checkpoints can have a Runtime before the Run has
        // a final responseMessageID. Keep those blocks/receipts in the page too.
        let requestedRunIDs = Array(Set(references.compactMap(\.runtimeID) + messageRecords.compactMap(\.runtimeID) +
            messageBlocks.map(\.runtimeID) + [activeRunID].compactMap { $0 }))
        let selectedRuns = try FamiliarRunHistoryQuery.fetch(requestedRunIDs, in: context) { ids in
            FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.conversation?.id == conversationID && ids.contains($0.runtimeID) })
        }
        let conversationRuntimeIDs = selectedRuns.map(\.runtimeID)
        let activityRecords = try FamiliarRunHistoryQuery.fetch(conversationRuntimeIDs, in: context) { ids in
            FetchDescriptor<FamiliarActivityRecord>(predicate: #Predicate { ids.contains($0.runtimeID) })
        }
        let approvalRecords = try FamiliarRunHistoryQuery.fetch(conversationRuntimeIDs, in: context) { ids in
            FetchDescriptor<FamiliarApprovalRecord>(predicate: #Predicate { ids.contains($0.runtimeID) })
        }
        let resultRecords = try FamiliarRunHistoryQuery.fetch(conversationRuntimeIDs, in: context) { ids in
            FetchDescriptor<FamiliarToolResultRecord>(predicate: #Predicate { ids.contains($0.runtimeID) })
        }
        let clarificationRecords = try FamiliarRunHistoryQuery.fetch(conversationRuntimeIDs, in: context) { ids in
            FetchDescriptor<FamiliarClarificationRecord>(predicate: #Predicate { ids.contains($0.runtimeID) })
        }
        let invocationRecords = try FamiliarRunHistoryQuery.fetch(conversationRuntimeIDs, in: context) { ids in
            FetchDescriptor<FamiliarToolInvocationRecord>(predicate: #Predicate { ids.contains($0.runtimeID) })
        }
        let blockRecords = try FamiliarRunHistoryQuery.fetch(conversationRuntimeIDs, in: context) { ids in
            FetchDescriptor<FamiliarResponseBlockRecord>(predicate: #Predicate { ids.contains($0.runtimeID) })
        }
        let activeScope = conversation.project.map { FamiliarWorkScope.project($0.id) } ?? .conversation(conversation.id)
        let scopeKey = activeScope.storageKey
        let files = try FamiliarRunHistoryQuery.fetch(conversationRuntimeIDs, in: context) { ids in
            FetchDescriptor<FamiliarStoredFileVersion>(predicate: #Predicate {
                $0.scopeKey == scopeKey && ($0.createdByRunID.flatMap { ids.contains($0) } ?? false)
            })
        }
        let blockSnapshots = blockRecords.map(responseBlockSnapshot)
        let blocksByMessageID = Dictionary(grouping: blockSnapshots.compactMap { block in
            block.messageID.map { ($0, block) }
        }, by: \.0)
        let messages = projectMessages(messageRecords, blocksByMessageID: blocksByMessageID)
        let switchIDs = references.compactMap(\.switchID)
        let modelSwitches = (switchIDs.isEmpty ? [] : try context.fetch(FetchDescriptor<FamiliarModelSwitchRecord>(predicate: #Predicate {
            $0.conversation?.id == conversationID && switchIDs.contains($0.id)
        })))
            .sorted { lhs, rhs in
                lhs.sequence == rhs.sequence ? lhs.createdAt < rhs.createdAt : lhs.sequence < rhs.sequence
            }
            .map {
                FamiliarModelSwitchSnapshot(
                    id: $0.id,
                    previousProviderID: $0.previousProviderID,
                    previousModelID: $0.previousModelID,
                    currentProviderID: $0.currentProviderID,
                    currentModelID: $0.currentModelID,
                    sequence: $0.sequence,
                    createdAt: $0.createdAt
                )
            }
        let skillRecords = try FamiliarRunHistoryQuery.fetch(conversationRuntimeIDs, in: context) { ids in
            FetchDescriptor<FamiliarRunSkillSnapshotRecord>(predicate: #Predicate { ids.contains($0.runtimeID) })
        }
        let skillSnapshotsByRuntimeID = Dictionary(grouping: skillRecords, by: \.runtimeID)
        let activitiesByRun = Dictionary(grouping: activityRecords, by: \.runtimeID)
        let approvalsByRun = Dictionary(grouping: approvalRecords, by: \.runtimeID)
        let resultsByRun = Dictionary(grouping: resultRecords, by: \.runtimeID)
        let clarificationsByRun = Dictionary(grouping: clarificationRecords, by: \.runtimeID)
        let invocationsByRun = Dictionary(grouping: invocationRecords, by: \.runtimeID)
        let blocksByRun = Dictionary(grouping: blockRecords, by: \.runtimeID)
        let filesByRun = Dictionary(grouping: files, by: { $0.createdByRunID ?? "" })
        let agentRuns = selectedRuns
            .sorted { $0.startedAt < $1.startedAt }
            .map { run in
                let contextSummary: FamiliarRunContextSummary? = run.contextSnapshot.map { snapshot in
                    let toolNames = ((try? JSONDecoder().decode(
                        [String].self,
                        from: Data(snapshot.exposedToolNamesJSON.utf8)
                    )) ?? []).sorted()
                    let resources = snapshot.resourceReferences
                        .sorted {
                            $0.filename == $1.filename
                                ? $0.version < $1.version
                                : $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
                        }
                        .map {
                            FamiliarRunResourceSummary(
                                versionID: $0.resourceVersionID,
                                filename: $0.filename,
                                version: $0.version
                            )
                        }
                    let skills = (skillSnapshotsByRuntimeID[run.runtimeID] ?? [])
                        .sorted { $0.sequence < $1.sequence }
                        .map {
                            FamiliarRunSkillSummary(
                                stableID: $0.stableID,
                                name: $0.name,
                                version: $0.version
                            )
                        }
                    return FamiliarRunContextSummary(
                        projectName: snapshot.projectName,
                        providerID: snapshot.providerID,
                        modelID: snapshot.modelID,
                        resources: resources,
                        skills: skills,
                        toolNames: toolNames
                    )
                }
                return FamiliarAgentRunSnapshot(
                    id: run.runtimeID,
                    responseMessageID: run.responseMessageID,
                    status: run.status,
                    startedAt: run.startedAt,
                    finishedAt: run.finishedAt,
                    firstTokenAt: run.firstTokenAt,
                    context: contextSummary,
                    activities: (activitiesByRun[run.runtimeID] ?? [])
                        .filter { !$0.activityID.hasPrefix("context:") }
                        .sorted { $0.sequence < $1.sequence }
                        .map {
                            FamiliarActivitySnapshot(
                                activityID: $0.activityID,
                                parentID: $0.parentID,
                                assistantTurnID: $0.assistantTurnID,
                                kind: $0.kind,
                                effect: $0.effect,
                                phase: $0.phase,
                                toolName: $0.toolName,
                                toolCallID: $0.toolCallID,
                                summary: $0.summary,
                                detail: $0.detail,
                                failureCode: $0.failureCode,
                                failureRetryable: $0.failureRetryable,
                                progress: $0.progress,
                                resultRecordID: $0.resultRecordID,
                                approvalRecordID: $0.approvalRecordID,
                                sequence: $0.sequence,
                                startedAt: $0.startedAt,
                                endedAt: $0.endedAt
                            )
                        },
                    approvals: (approvalsByRun[run.runtimeID] ?? [])
                        .filter { !$0.activityID.hasPrefix("context:") }
                        .sorted { $0.requestedAt < $1.requestedAt }
                        .map { record in
                            FamiliarApprovalSnapshot(
                                id: record.id,
                                activityID: record.activityID,
                                assistantTurnID: record.assistantTurnID,
                                toolCallID: record.toolCallID,
                                toolName: record.toolName,
                                title: record.title,
                                fields: (try? JSONDecoder().decode([FamiliarApprovalField].self, from: Data(record.orderedFieldsJSON.utf8))) ?? [],
                                target: record.target,
                                effect: record.effect,
                                risk: record.risk,
                                consequence: record.consequence,
                                undoPolicy: record.undoPolicy,
                                allowedAuthorizationDurations: (try? JSONDecoder().decode(
                                    [FamiliarAuthorizationDuration].self,
                                    from: Data(record.allowedAuthorizationDurationsJSON.utf8)
                                )) ?? [.once],
                                decision: record.decision,
                                scope: record.scope,
                                requestedAt: record.requestedAt,
                                resolvedAt: record.resolvedAt,
                                automaticAuthorization: record.automaticAuthorization
                            )
                        },
                    clarifications: (clarificationsByRun[run.runtimeID] ?? [])
                        .filter { !$0.activityID.hasPrefix("context:") }
                        .sorted { $0.requestedAt < $1.requestedAt }
                        .map { record in
                            FamiliarClarificationSnapshot(
                                id: record.id,
                                activityID: record.activityID,
                                assistantTurnID: record.assistantTurnID,
                                toolCallID: record.toolCallID,
                                question: record.question,
                                options: (try? JSONDecoder().decode([FamiliarClarificationOption].self, from: Data(record.optionsJSON.utf8))) ?? [],
                                allowCustom: record.allowCustom,
                                state: record.state,
                                resolution: record.resolutionJSON.flatMap { try? JSONDecoder().decode(FamiliarClarificationResolution.self, from: Data($0.utf8)) },
                                requestedAt: record.requestedAt,
                                resolvedAt: record.resolvedAt
                            )
                        },
                    toolResults: (resultsByRun[run.runtimeID] ?? [])
                        .filter { !$0.activityID.hasPrefix("context:") }
                        .sorted { $0.createdAt < $1.createdAt }
                        .map { record in
                            FamiliarToolResultSnapshot(
                                id: record.id,
                                activityID: record.activityID,
                                toolCallID: record.toolCallID,
                                envelope: try? JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(record.envelopeJSON.utf8)),
                                envelopeJSON: record.envelopeJSON,
                                schemaVersion: record.schemaVersion,
                                payloadName: record.payloadName,
                                payloadHash: record.payloadHash,
                                semanticID: record.semanticID,
                                revision: record.revision,
                                trust: record.trust,
                                truncated: record.truncated,
                                file: fileDescriptor(for: record, files: filesByRun[record.runtimeID] ?? [])
                            )
                        },
                    responseBlocks: (blocksByRun[run.runtimeID] ?? []).map(responseBlockSnapshot)
                        .sorted { $0.order < $1.order },
                    regenerationRequiresInspection: (try? FamiliarRunRecoveryService().requiresInspection(run, in: context)) ?? true,
                    uncertainToolCallIDs: Set((invocationsByRun[run.runtimeID] ?? []).filter { $0.state == .committing }.map(\.toolCallID))
                )
            }
        let eligible = selectedRuns.filter { run in
            (run.contextSnapshot?.workScope ?? run.project.map { .project($0.id) } ?? .conversation(conversation.id)) == activeScope
        }.map(\.runtimeID)
        return .init(messages: messages, modelSwitches: modelSwitches, runs: agentRuns, undoRuntimeIDs: eligible)
    }

    /// Business operations deliberately read the complete history independently
    /// of the page on screen. Edit submissions can request their original prefix.
    static func messages(conversationID: UUID, beforeSequence: Int? = nil,
                         in context: ModelContext) throws -> [FamiliarMessageSnapshot] {
        let predicate: Predicate<FamiliarMessage>
        if let beforeSequence {
            predicate = #Predicate { $0.conversation?.id == conversationID && $0.sequence < beforeSequence }
        } else { predicate = #Predicate { $0.conversation?.id == conversationID } }
        let descriptor = FetchDescriptor(predicate: predicate,
            sortBy: [SortDescriptor(\FamiliarMessage.sequence), SortDescriptor(\.createdAt)])
        return try projectMessages(context.fetch(descriptor), conversationID: conversationID, in: context)
    }

    static func latestAssistantMessage(conversationID: UUID, in context: ModelContext) throws -> FamiliarMessageSnapshot? {
        var descriptor = FetchDescriptor<FamiliarMessage>(predicate: #Predicate {
            $0.conversation?.id == conversationID && $0.roleRawValue == "assistant"
        }, sortBy: [SortDescriptor(\.sequence, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try projectMessages(context.fetch(descriptor), conversationID: conversationID, in: context).first
    }

    private static func projectMessages(_ records: [FamiliarMessage], conversationID: UUID, in context: ModelContext) throws -> [FamiliarMessageSnapshot] {
        var blockRecords: [FamiliarResponseBlockRecord] = []
        let ids = records.map(\.id)
        for start in stride(from: 0, to: ids.count, by: 200) {
            let batch = Array(ids[start..<min(start + 200, ids.count)])
            blockRecords += try context.fetch(FetchDescriptor<FamiliarResponseBlockRecord>(predicate: #Predicate {
                $0.messageID.flatMap { batch.contains($0) } ?? false
            }))
        }
        let validRuns: [FamiliarAgentRun] = try FamiliarRunHistoryQuery.fetch(blockRecords.map(\.runtimeID), in: context) { batch in
            var query = FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate {
                $0.conversation?.id == conversationID && batch.contains($0.runtimeID)
            })
            query.propertiesToFetch = [\.runtimeID]
            return query
        }
        let allowed = Set(validRuns.map(\.runtimeID))
        let blocks = blockRecords.filter { allowed.contains($0.runtimeID) }.map(responseBlockSnapshot)
        let grouped = Dictionary(grouping: blocks.compactMap { block in block.messageID.map { ($0, block) } }, by: \.0)
        return projectMessages(records, blocksByMessageID: grouped)
    }

    private static func projectMessages(_ records: [FamiliarMessage],
        blocksByMessageID: [UUID: [(UUID, FamiliarResponseBlockSnapshot)]]) -> [FamiliarMessageSnapshot] {
        return records
            .sorted { lhs, rhs in
                lhs.sequence == rhs.sequence ? lhs.createdAt < rhs.createdAt : lhs.sequence < rhs.sequence
            }
            .map {
                FamiliarMessageSnapshot(
                    id: $0.id,
                    role: $0.role,
                    content: $0.content,
                    createdAt: $0.createdAt,
                    sequence: $0.sequence,
                    providerID: $0.providerID,
                    modelID: $0.modelID,
                    attachments: $0.attachments
                        .sorted { $0.createdAt < $1.createdAt }
                        .map {
                            FamiliarAttachmentSnapshot(
                                id: $0.id,
                                kind: $0.kind,
                                filename: $0.filename,
                                mimeType: $0.mimeType,
                                relativePath: $0.relativePath,
                                extractedText: $0.extractedText,
                                byteSize: $0.byteSize,
                                extractionEngine: $0.extractionEngine,
                                extractionVersion: $0.extractionVersion,
                                detectedFormat: $0.detectedFormat,
                                usedOCR: $0.usedOCR
                            )
                        },
                    sources: $0.sources
                        .sorted { $0.sequence < $1.sequence }
                        .compactMap { record in
                            guard let url = URL(string: record.urlString) else { return nil }
                            return FamiliarSource(
                                id: record.sourceID,
                                kind: record.kind,
                                title: record.title,
                                url: url,
                                siteName: record.siteName,
                                snippet: record.snippet,
                                retrievedAt: record.retrievedAt,
                                responseBlockID: record.responseBlockID,
                                retrievalActivityID: record.retrievalActivityID,
                                citationOrdinal: record.citationOrdinal
                            )
                        },
                    responseBlocks: (blocksByMessageID[$0.id] ?? [])
                        .map(\.1)
                        .sorted { $0.order < $1.order },
                    finalResponseBlockID: $0.responseBlockID
                )
            }
    }

    private static func fileDescriptor(for result: FamiliarToolResultRecord, files: [FamiliarStoredFileVersion]) -> FamiliarFileDescriptor? {
        guard let envelope = try? JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(result.envelopeJSON.utf8)),
              case .fileMutation(let mutation) = envelope.presentation.content,
              let file = files.first(where: {  $0.matchesFileIdentifier(mutation.identifier) && $0.createdByRunID == result.runtimeID })
        else { return nil }
        return FamiliarFileDescriptor(id: file.id, identifier: file.identifier, scope: file.scope,
            title: file.title, format: file.format, relativePath: file.relativePath, byteSize: file.byteSize,
            contentHash: file.contentHash, source: file.source, sourceURLString: file.sourceURLString,
            sourceResourceID: file.sourceResourceID, sourceResourceVersionID: file.sourceResourceVersionID,
            sourceCaptureID: file.sourceCaptureID, createdByRunID: file.createdByRunID,
            utiIdentifier: file.utiIdentifier, mimeType: file.mimeType,
            validationReceipt: file.validationReceiptJSON.flatMap { try? JSONDecoder().decode(FamiliarValidationReceipt.self, from: Data($0.utf8)) })
    }

    private static func responseBlockSnapshot(_ record: FamiliarResponseBlockRecord) -> FamiliarResponseBlockSnapshot {
        FamiliarResponseBlockSnapshot(
            id: record.id,
            assistantTurnID: record.assistantTurnID,
            messageID: record.messageID,
            kind: record.kind,
            order: record.order,
            state: record.state,
            content: record.content,
            payloadJSON: record.payloadJSON,
            schemaVersion: record.schemaVersion,
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            contentHash: record.contentHash
        )
    }

}
