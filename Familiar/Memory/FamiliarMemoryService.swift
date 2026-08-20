import Foundation
import SwiftData

enum FamiliarMemoryScope: String, Codable, Sendable { case global, project, conversation }
enum FamiliarMemoryCreator: String, Codable, Sendable { case user, agentConfirmed }

@MainActor
struct FamiliarMemoryService {
    func search(query: String, projectID: UUID?, conversationID: UUID?, in context: ModelContext, limit: Int = 8) throws -> [FamiliarMemoryItem] {
        let tokens = Set(query.lowercased().split { $0.isWhitespace || $0.isPunctuation }.map(String.init))
        let items = try context.fetch(FetchDescriptor<FamiliarMemoryItem>()).filter { item in
            guard item.isVisible, item.scopeRawValue == FamiliarMemoryScope.global.rawValue || (item.scopeRawValue == FamiliarMemoryScope.project.rawValue && item.projectID == projectID) || (item.scopeRawValue == FamiliarMemoryScope.conversation.rawValue && item.conversationID == conversationID) else { return false }
            return tokens.isEmpty || tokens.contains { item.content.lowercased().contains($0) || item.normalizedKey.contains($0) }
        }
        return Array(items.sorted { ($0.lastUsedAt ?? .distantPast, $0.updatedAt) > ($1.lastUsedAt ?? .distantPast, $1.updatedAt) }.prefix(limit))
    }

    func insert(content: String, scope: FamiliarMemoryScope, projectID: UUID?, conversationID: UUID?, provenance: String, creator: FamiliarMemoryCreator, in context: ModelContext) throws -> FamiliarMemoryItem {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, content.count <= 2_000 else { throw FamiliarMemoryError.invalidContent }
        guard scope == .global || (scope == .project && projectID != nil) || (scope == .conversation && conversationID != nil) else { throw FamiliarMemoryError.invalidScope }
        let key = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = try context.fetch(FetchDescriptor<FamiliarMemoryItem>(predicate: #Predicate { $0.normalizedKey == key })).first { existing.content = content; existing.updatedAt = Date(); try context.save(); return existing }
        let item = FamiliarMemoryItem(scopeRawValue: scope.rawValue, projectID: projectID, conversationID: conversationID, content: content, normalizedKey: key, provenance: provenance, confidence: 1, createdByRawValue: creator.rawValue)
        context.insert(item); try context.save(); return item
    }
}

enum FamiliarMemoryError: LocalizedError, Sendable { case invalidContent, invalidScope
    var errorDescription: String? { switch self { case .invalidContent: "Memory 内容无效或过长。"; case .invalidScope: "Memory 作用域缺少所属对象。" } }
}
