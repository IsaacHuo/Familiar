import Foundation
import SwiftData
import NaturalLanguage

@MainActor
struct FamiliarMemoryService {
    static let defaultSearchLimit = 8

    /// Dedup identity. The scope and its owner are part of the key because the same
    /// sentence means different things in different Projects: a content-only key let
    /// one Project's memory silently overwrite another's, and global memory collide
    /// with both.
    static func normalizedKey(
        content: String,
        scope: FamiliarMemoryScope,
        projectID: UUID?,
        conversationID: UUID?
    ) -> String {
        let owner: String = switch scope {
        case .global: "global"
        case .project: "project:\(projectID?.uuidString ?? "-")"
        case .conversation: "conversation:\(conversationID?.uuidString ?? "-")"
        }
        let body = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(owner)|\(body)"
    }

    /// Read-only scoped candidates, ranked by lexical relevance, confidence and recency. The compiler
    /// applies its own budget before accepted submission records actual usage.
    func candidates(
        query: String,
        projectID: UUID?,
        conversationID: UUID?,
        in context: ModelContext
    ) throws -> [FamiliarMemoryItem] {
        let queryTerms = Self.words(query)
        // Confirmed scoped facts remain eligible even when wording/language changes.
        // Lexical overlap ranks first; the Compiler is the sole admission budget.
        let ranked = try context.fetch(FetchDescriptor<FamiliarMemoryItem>())
            .filter { $0.isVisible && $0.isInScope(projectID: projectID, conversationID: conversationID) }
            .map { item in (item, queryTerms.intersection(Self.words(item.content)).count) }
        return ranked.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return Self.isMoreUseful(lhs.0, rhs.0)
        }.map { $0.0 }
    }

    private static func words(_ input: String) -> Set<String> {
        let value = input.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = value
        var tokens = Set<String>()
        let stop: Set<String> = ["a", "an", "the", "i", "my", "me", "it", "to", "is", "of", "and", "please", "我", "请", "的", "是", "在", "了"]
        tokenizer.enumerateTokens(in: value.startIndex..<value.endIndex) { range, _ in
            let token = String(value[range])
            if !stop.contains(token) { tokens.insert(token) }
            return true
        }
        return tokens
    }

    /// Stage actual use in the same save as the accepted user message. Selection and
    /// rejected preparations must never advance recency or save memory independently.
    func stageUsage(ids: Set<UUID>, in context: ModelContext, now: Date = Date()) throws {
        guard !ids.isEmpty else { return }
        for item in try context.fetch(FetchDescriptor<FamiliarMemoryItem>()) where ids.contains(item.id) {
            item.lastUsedAt = now
        }
    }

    /// Confidence outranks recency: a memory the user confirmed should win over one the
    /// Agent proposed, even if the proposal was touched more recently.
    private static func isMoreUseful(_ lhs: FamiliarMemoryItem, _ rhs: FamiliarMemoryItem) -> Bool {
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        let lhsUsed = lhs.lastUsedAt ?? .distantPast
        let rhsUsed = rhs.lastUsedAt ?? .distantPast
        if lhsUsed != rhsUsed { return lhsUsed > rhsUsed }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Persists a memory the user approved. `agentConfirmed` records that the Agent
    /// proposed the text and the user accepted it; the model can never write memory on
    /// its own, because this is only reachable after an approval commit.
    @discardableResult
    func persist(_ request: FamiliarMemoryWriteRequest, in context: ModelContext) throws -> FamiliarMemoryItem {
        try insert(
            content: request.content,
            scope: request.scope,
            projectID: request.projectID,
            conversationID: request.conversationID,
            provenance: request.provenance,
            creator: .agentConfirmed,
            in: context
        )
    }

    @discardableResult
    func insert(
        content: String,
        scope: FamiliarMemoryScope,
        projectID: UUID?,
        conversationID: UUID?,
        provenance: String,
        creator: FamiliarMemoryCreator,
        confidence: Double = 1,
        in context: ModelContext,
        now: Date = Date()
    ) throws -> FamiliarMemoryItem {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= FamiliarMemoryPolicy.maximumContentLength else {
            throw FamiliarMemoryError.invalidContent
        }
        guard scope == .global
            || (scope == .project && projectID != nil)
            || (scope == .conversation && conversationID != nil)
        else { throw FamiliarMemoryError.invalidScope }
        guard !FamiliarMemoryPolicy.looksSensitive(trimmed) else { throw FamiliarMemoryError.sensitiveContent }

        let key = Self.normalizedKey(
            content: trimmed,
            scope: scope,
            projectID: projectID,
            conversationID: conversationID
        )
        let bounded = min(max(confidence, 0), 1)
        if let existing = try context.fetch(
            FetchDescriptor<FamiliarMemoryItem>(predicate: #Predicate { $0.normalizedKey == key })
        ).first {
            existing.content = trimmed
            existing.provenance = provenance
            existing.createdByRawValue = creator.rawValue
            existing.confidence = max(existing.confidence, bounded)
            existing.isVisible = true
            existing.updatedAt = now
            try context.save()
            return existing
        }
        let item = FamiliarMemoryItem(
            scopeRawValue: scope.rawValue,
            projectID: scope == .global ? nil : projectID,
            conversationID: scope == .conversation ? conversationID : nil,
            content: trimmed,
            normalizedKey: key,
            provenance: provenance,
            confidence: bounded,
            createdByRawValue: creator.rawValue,
            createdAt: now,
            updatedAt: now
        )
        context.insert(item)
        try context.save()
        return item
    }
}

extension FamiliarMemoryItem {
    var scope: FamiliarMemoryScope {
        FamiliarMemoryScope(rawValue: scopeRawValue) ?? .global
    }

    var creator: FamiliarMemoryCreator {
        FamiliarMemoryCreator(rawValue: createdByRawValue) ?? .user
    }

    func isInScope(projectID: UUID?, conversationID: UUID?) -> Bool {
        guard let scope = FamiliarMemoryScope(rawValue: scopeRawValue) else { return false }
        return switch scope {
        case .global: self.projectID == nil && self.conversationID == nil
        case .project: self.projectID != nil && self.projectID == projectID && self.conversationID == nil
        case .conversation: self.projectID == projectID && self.conversationID != nil && self.conversationID == conversationID
        }
    }
}

enum FamiliarMemoryError: LocalizedError, Sendable, FamiliarStructuredToolError {
    case invalidContent
    case invalidScope
    case sensitiveContent

    var errorDescription: String? {
        switch self {
        case .invalidContent: "Memory 内容无效或过长。"
        case .invalidScope: "Memory 作用域缺少所属对象。"
        case .sensitiveContent: "该内容看起来包含密钥、口令或其他敏感信息，不会保存为长期记忆。"
        }
    }

    var code: String {
        switch self {
        case .invalidContent: "memory_invalid_content"
        case .invalidScope: "memory_invalid_scope"
        case .sensitiveContent: "memory_sensitive_content"
        }
    }

    var isRetryable: Bool { false }
}
