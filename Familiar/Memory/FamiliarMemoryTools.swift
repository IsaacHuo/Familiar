import Foundation

/// Proposes a long-term memory. The model cannot store memory on its own: this returns
/// an action proposal, and the row is only written after the user approves and the
/// controller persists the request that travels back on the result.
nonisolated struct FamiliarMemoryRememberTool: FamiliarTool {
    struct Input: Decodable, Sendable { let content: String; let scope: String? }

    private struct Output: Encodable {
        let remembered: Bool
        let scope: String
        let content: String
    }

    let manifest = FamiliarToolManifest(
        name: "memory_remember",
        title: "记住偏好或事实",
        description: "在用户明确表达长期偏好或需要长期记住的事实时，提议保存一条长期记忆。需要用户确认后才会保存。不要保存一次性任务细节、可推导的内容，也不要保存密钥、口令或其他敏感信息。",
        parameters: FamiliarJSONSchema(type: .object, properties: [
            "content": .init(type: .string, description: "要记住的一句话，简洁、自足、不含敏感信息。"),
            "scope": .init(type: .string, description: "global 表示长期通用偏好，project 表示只属于当前项目。默认 project；普通聊天默认 global。")
        ], required: ["content"]),
        effect: .reversibleWrite,
        risk: .low,
        dataDomains: ["memory"],
        privacyLabels: ["local-only"],
        supportsParallelism: false
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let content = input.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content.count <= FamiliarMemoryService.maximumContentLength else {
            throw FamiliarMemoryError.invalidContent
        }
        // Refused before the approval card appears, so a secret is never shown back to
        // the user as something Familiar is about to remember.
        guard !FamiliarMemoryService.looksSensitive(content) else {
            throw FamiliarMemoryError.sensitiveContent
        }
        let scope = Self.resolvedScope(requested: input.scope, projectID: context.projectID)
        guard scope != .project || context.projectID != nil else { throw FamiliarMemoryError.invalidScope }
        let request = FamiliarMemoryWriteRequest(
            content: content,
            scope: scope,
            projectID: scope == .project ? context.projectID : nil,
            conversationID: nil,
            provenance: "run:\(context.runID)"
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
            consequence: "Familiar 会在以后的对话中记住这条信息。可以随时在设置中查看或删除。",
            // No runtime undo closure exists: the tool is nonisolated and cannot delete
            // the row. Claiming .durable here would promise an undo the runtime cannot
            // perform. Removal is the Settings path named in the consequence.
            undoPolicy: .unavailable,
            idempotencyKey: context.idempotencyKey,
            // Only .once: a session or long-term grant would let the Agent keep writing
            // memory without asking, and the contract requires every remembered item to
            // be user-confirmed.
            allowedAuthorizationDurations: [.once],
            commit: {
                FamiliarCommittedAction(result: .init(
                    envelope: try FamiliarToolResultEnvelope(
                        model: Output(remembered: true, scope: scope.rawValue, content: content),
                        presentation: .mutationReceipt(.init(
                            summary: "已记住：\(content)",
                            operation: "memoryRemember",
                            targetIdentifier: nil,
                            succeeded: true,
                            undoAvailable: false
                        ))
                    ),
                    memoryWrite: request
                ))
            }
        ))
    }

    /// Project scope is the default inside a Project so one Project's preferences do not
    /// leak into unrelated work; ordinary chats have no Project to own the memory.
    static func resolvedScope(requested: String?, projectID: UUID?) -> FamiliarMemoryScope {
        switch requested?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "global": .global
        case "project": projectID == nil ? .global : .project
        default: projectID == nil ? .global : .project
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
