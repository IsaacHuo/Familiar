import Foundation

/// Records a long-term memory. The model cannot store memory on its own: this returns
/// a level-2 action proposal, which the runtime executes automatically (receipt + Undo)
/// while the user's "remember across conversations" switch is on. The row is persisted
/// through the runtime's success-boundary callback, and Undo removes it again.
nonisolated struct FamiliarMemoryRememberTool: FamiliarTool {
    struct Input: Decodable, Sendable { let content: String; let scope: String? }

    private struct Output: Encodable {
        let remembered: Bool
        let scope: String
        let content: String
    }

    private struct UndoOutput: Encodable {
        let forgotten: Bool
        let content: String
    }

    let manifest = FamiliarToolManifest(
        name: "memory_remember",
        title: "记住偏好或事实",
        description: "在用户明确表达长期偏好或需要长期记住的事实时，提议保存一条长期记忆。需要用户确认后才会保存。不要保存一次性任务细节、可推导的内容，也不要保存密钥、口令或其他敏感信息。",
        parameters: FamiliarJSONSchema(type: .object, properties: [
            "content": .init(type: .string, description: "要记住的一句话，简洁、自足、不含敏感信息。"),
            "scope": .init(type: .string, description: "global 表示长期通用偏好，project 表示只属于当前项目。默认 project；普通聊天默认 conversation；只有用户明确要求跨对话记住时选择 global。")
        ], required: ["content"]),
        effect: .reversibleWrite,
        risk: .low,
        dataDomains: ["memory"],
        privacyLabels: ["local-only"],
        supportsParallelism: false
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let content = input.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.count <= FamiliarMemoryPolicy.maximumContentLength else {
            throw FamiliarMemoryError.invalidContent
        }
        // Refused before the approval card appears, so a secret is never shown back to
        // the user as something Familiar is about to remember.
        guard !FamiliarMemoryPolicy.looksSensitive(content) else {
            throw FamiliarMemoryError.sensitiveContent
        }
        let scope = Self.resolvedScope(requested: input.scope, projectID: context.projectID)
        guard (scope != .project || context.projectID != nil),
              (scope != .conversation || context.conversationID != nil) else { throw FamiliarMemoryError.invalidScope }
        let request = FamiliarMemoryWriteRequest(
            content: content,
            scope: scope,
            projectID: scope != .global ? context.projectID : nil,
            conversationID: scope == .conversation ? context.conversationID : nil,
            provenance: "run:\(context.idempotencyKey)"
        )
        return .action(FamiliarActionProposal(
            title: "记住这条信息",
            fields: [
                .init(id: "content", label: "内容", type: .text, value: content),
                .init(id: "scope", label: "范围", type: .text, value: Self.scopeLabel(scope))
            ],
            target: Self.scopeLabel(scope),
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: "Familiar 会在以后的对话中记住这条信息。可以随时撤销，或在设置中查看或删除。",
            // Undo runs through the controller, which deletes the row by this run's
            // provenance; the tool itself has no database access.
            undoPolicy: .currentSession,
            idempotencyKey: context.idempotencyKey,
            // Only .once as a fallback: the level-2 automatic path does not ask, and a
            // reusable grant would let the Agent keep writing memory without receipts.
            allowedAuthorizationDurations: [.once],
            commit: {
                FamiliarCommittedAction(
                    result: .init(
                        envelope: try FamiliarToolResultEnvelope(
                            model: Output(remembered: true, scope: scope.rawValue, content: content),
                            presentation: .mutationReceipt(.init(
                                summary: "已记住：\(content)",
                                operation: "memoryRemember",
                                targetIdentifier: nil,
                                succeeded: true,
                                undoAvailable: true
                            ))
                        ),
                        memoryWrite: request
                    ),
                    undo: {
                        .init(envelope: try FamiliarToolResultEnvelope(
                            model: UndoOutput(forgotten: true, content: content),
                            presentation: .mutationReceipt(.init(
                                summary: "已忘记：\(content)",
                                operation: "memoryForget",
                                targetIdentifier: nil,
                                succeeded: true,
                                undoAvailable: false
                            ))
                        ))
                    },
                    // The row is inserted in the same SwiftData transaction as this
                    // result's persistence, so a failed save rolls it back and there
                    // is nothing to compensate here.
                    rollback: {}
                )
            }
        ))
    }

    /// Project scope is the default inside a Project so one Project's preferences do not
    /// leak into unrelated work; ordinary chats have no Project to own the memory.
    static func resolvedScope(requested: String?, projectID: UUID?) -> FamiliarMemoryScope {
        switch requested?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "global": .global
        case "project": .project
        case "conversation": .conversation
        default: projectID == nil ? .conversation : .project
        }
    }

    private static func scopeLabel(_ scope: FamiliarMemoryScope) -> String {
        switch scope {
        case .global: "所有对话"
        case .project: "仅当前项目"
        case .conversation: "仅当前对话"
        }
    }
}

/// Reads the memory the Context Compiler already froze into this run. The tool does not
/// query SwiftData: a run must see one stable set of memories, and re-reading mid-run
/// would let the prompt and the tool disagree about what Familiar remembers.
nonisolated struct FamiliarMemorySearchTool: FamiliarTool {
    struct Input: Decodable, Sendable { let query: String? }

    private struct Match: Encodable {
        let id: UUID
        let scope: String
        let content: String
        let provenance: String
    }

    let manifest = FamiliarToolManifest(
        name: "memory_search",
        title: "查看长期记忆",
        description: "查看本次运行可用的长期记忆。只返回已由用户确认保存并与本次任务相关的记忆，不是完整历史。",
        parameters: FamiliarJSONSchema(type: .object, properties: [
            "query": .init(type: .string, description: "可选的关键词，用于在本次可用记忆中进一步筛选。")
        ], required: []),
        effect: .read,
        risk: .low,
        dataDomains: ["memory"],
        privacyLabels: ["local-only", "read-only"],
        supportsParallelism: true
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let query = input.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tokens = Set(query.lowercased().split { $0.isWhitespace || $0.isPunctuation }.map(String.init))
        let matches = context.memories
            .filter { memory in
                guard !tokens.isEmpty else { return true }
                let content = memory.content.lowercased()
                return tokens.contains { content.contains($0) }
            }
            .map { Match(id: $0.id, scope: $0.scope.rawValue, content: $0.content, provenance: $0.provenance) }
        let summary = matches.isEmpty
            ? "本次没有可用的长期记忆。"
            : "本次可用的长期记忆共 \(matches.count) 条。"
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: matches,
            presentation: .recordCollection(.init(
                summary: summary,
                recordType: "memory",
                records: matches.map { match in
                    FamiliarToolPresentationPayload.Record(id: match.id.uuidString, fields: [
                        .init(name: "content", value: match.content),
                        .init(name: "scope", value: match.scope)
                    ])
                }
            ))
        )))
    }
}
