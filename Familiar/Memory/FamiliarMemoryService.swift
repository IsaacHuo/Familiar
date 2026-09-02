import Foundation
import SwiftData

enum FamiliarMemoryScope: String, Codable, Sendable, CaseIterable { case global, project, conversation }
enum FamiliarMemoryCreator: String, Codable, Sendable { case user, agentConfirmed }

@MainActor
struct FamiliarMemoryService {
    static let maximumContentLength = 2_000
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

    /// Returns the memories in scope for this run, most useful first, and stamps
    /// `lastUsedAt` on exactly the ones returned. Marking here rather than on every
    /// fetch keeps the field meaning "was actually selected as context", which is what
    /// the ordering depends on.
    func search(
        query: String,
        projectID: UUID?,
        conversationID: UUID?,
        in context: ModelContext,
        limit: Int = Self.defaultSearchLimit,
        now: Date = Date()
    ) throws -> [FamiliarMemoryItem] {
        let selected = Array(
            try candidates(query: query, projectID: projectID, conversationID: conversationID, in: context)
                .prefix(max(limit, 0))
        )
        guard !selected.isEmpty else { return [] }
        for item in selected { item.lastUsedAt = now }
        try context.save()
        return selected
    }

    /// Same selection and ordering as `search` without recording usage, for surfaces
    /// that only display memory.
    func candidates(
        query: String,
        projectID: UUID?,
        conversationID: UUID?,
        in context: ModelContext
    ) throws -> [FamiliarMemoryItem] {
        let tokens = Set(
            query.lowercased()
                .split { $0.isWhitespace || $0.isPunctuation }
                .map(String.init)
        )
        return try context.fetch(FetchDescriptor<FamiliarMemoryItem>())
            .filter { item in
                guard item.isVisible, item.isInScope(projectID: projectID, conversationID: conversationID) else { return false }
                guard !tokens.isEmpty else { return true }
                let content = item.content.lowercased()
                return tokens.contains { content.contains($0) }
            }
            .sorted(by: Self.isMoreUseful)
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
        guard !trimmed.isEmpty, trimmed.count <= Self.maximumContentLength else {
            throw FamiliarMemoryError.invalidContent
        }
        guard scope == .global
            || (scope == .project && projectID != nil)
            || (scope == .conversation && conversationID != nil)
        else { throw FamiliarMemoryError.invalidScope }

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
        switch scope {
        case .global: true
        case .project: self.projectID != nil && self.projectID == projectID
        case .conversation: self.conversationID != nil && self.conversationID == conversationID
        }
    }
}

enum FamiliarMemoryError: LocalizedError, Sendable {
    case invalidContent
    case invalidScope

    var errorDescription: String? {
        switch self {
        case .invalidContent: "Memory 内容无效或过长。"
        case .invalidScope: "Memory 作用域缺少所属对象。"
        }
    }
}
