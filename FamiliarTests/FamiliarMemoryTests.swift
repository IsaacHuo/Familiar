import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar Memory")
@MainActor
struct FamiliarMemoryTests {
    @Test("Dedup is scoped so one Project cannot overwrite another's memory")
    func dedupIsScoped() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let service = FamiliarMemoryService()
        let projectA = UUID()
        let projectB = UUID()

        let a = try service.insert(content: "Prefers concise answers", scope: .project, projectID: projectA, conversationID: nil, provenance: "t", creator: .user, in: context)
        let b = try service.insert(content: "Prefers concise answers", scope: .project, projectID: projectB, conversationID: nil, provenance: "t", creator: .user, in: context)
        let global = try service.insert(content: "Prefers concise answers", scope: .global, projectID: nil, conversationID: nil, provenance: "t", creator: .user, in: context)

        // Identical text in three scopes must stay three records: a content-only dedup
        // key let one Project silently overwrite another's memory.
        #expect(Set([a.id, b.id, global.id]).count == 3)
        #expect(try context.fetch(FetchDescriptor<FamiliarMemoryItem>()).count == 3)

        let again = try service.insert(content: "Prefers concise answers", scope: .project, projectID: projectA, conversationID: nil, provenance: "t2", creator: .user, in: context)
        #expect(again.id == a.id)
        #expect(try context.fetch(FetchDescriptor<FamiliarMemoryItem>()).count == 3)
    }

    @Test("Search only returns in-scope memory and records that it was used")
    func searchScopeAndUsage() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let service = FamiliarMemoryService()
        let project = UUID()
        let conversation = UUID()

        try service.insert(content: "Global fact about beijing", scope: .global, projectID: nil, conversationID: nil, provenance: "t", creator: .user, in: context)
        try service.insert(content: "Project fact about beijing", scope: .project, projectID: project, conversationID: nil, provenance: "t", creator: .user, in: context)
        try service.insert(content: "Other project fact about beijing", scope: .project, projectID: UUID(), conversationID: nil, provenance: "t", creator: .user, in: context)
        try service.insert(content: "Conversation fact about beijing", scope: .conversation, projectID: nil, conversationID: conversation, provenance: "t", creator: .user, in: context)
        try service.insert(content: "Other conversation fact about beijing", scope: .conversation, projectID: nil, conversationID: UUID(), provenance: "t", creator: .user, in: context)

        let used = Date(timeIntervalSince1970: 5_000)
        let results = try service.search(query: "beijing", projectID: project, conversationID: conversation, in: context, now: used)

        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.isInScope(projectID: project, conversationID: conversation) })
        // lastUsedAt must be stamped on exactly the returned rows; it was never assigned
        // anywhere before, so the ordering that depends on it degenerated to updatedAt.
        #expect(results.allSatisfy { $0.lastUsedAt == used })

        let outOfScope = try context.fetch(FetchDescriptor<FamiliarMemoryItem>())
            .filter { !$0.isInScope(projectID: project, conversationID: conversation) }
        #expect(outOfScope.count == 2)
        #expect(outOfScope.allSatisfy { $0.lastUsedAt == nil })
    }

    @Test("Confirmed memory outranks a newer low-confidence proposal")
    func confidenceOutranksRecency() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let service = FamiliarMemoryService()

        try service.insert(content: "Confirmed preference", scope: .global, projectID: nil, conversationID: nil, provenance: "user", creator: .user, confidence: 1, in: context, now: Date(timeIntervalSince1970: 10))
        try service.insert(content: "Proposed preference", scope: .global, projectID: nil, conversationID: nil, provenance: "agent", creator: .agentConfirmed, confidence: 0.4, in: context, now: Date(timeIntervalSince1970: 9_999))

        let ordered = try service.candidates(query: "preference", projectID: nil, conversationID: nil, in: context)

        #expect(ordered.map(\.content) == ["Confirmed preference", "Proposed preference"])
        // confidence must be stored rather than hardcoded to 1 and ignored.
        #expect(ordered.last?.confidence == 0.4)
    }

    @Test("Invalid content and ownerless scopes are rejected at the write boundary")
    func writeBoundaryRejections() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let service = FamiliarMemoryService()

        #expect(throws: FamiliarMemoryError.self) {
            try service.insert(content: "   ", scope: .global, projectID: nil, conversationID: nil, provenance: "t", creator: .user, in: context)
        }
        #expect(throws: FamiliarMemoryError.self) {
            try service.insert(content: String(repeating: "a", count: FamiliarMemoryService.maximumContentLength + 1), scope: .global, projectID: nil, conversationID: nil, provenance: "t", creator: .user, in: context)
        }
        // A project- or conversation-scoped memory with no owner could never be matched
        // back to a scope, so it must be refused rather than stored unreachable.
        #expect(throws: FamiliarMemoryError.self) {
            try service.insert(content: "Orphan", scope: .project, projectID: nil, conversationID: nil, provenance: "t", creator: .user, in: context)
        }
        #expect(throws: FamiliarMemoryError.self) {
            try service.insert(content: "Orphan", scope: .conversation, projectID: nil, conversationID: nil, provenance: "t", creator: .user, in: context)
        }

        #expect(try context.fetch(FetchDescriptor<FamiliarMemoryItem>()).isEmpty)
    }

    @Test("Selected memory reaches the prompt and stays inside its character budget")
    func memoryReachesPromptUnderBudget() throws {
        let snapshot = try FamiliarProjectContextAssembler.assemble(
            seed: .init(
                projectID: nil,
                projectName: nil,
                conversationID: UUID(),
                projectInstruction: nil,
                resources: [],
                memories: [
                    .init(id: UUID(), scope: .global, content: "Writes in British English", provenance: "user", confidence: 1)
                ]
            ),
            settings: .defaultValue,
            messages: [],
            toolManifests: []
        )
        let systemPrompt = try #require(snapshot.providerMessages.first?.networkText)

        #expect(systemPrompt.contains("<remembered>"))
        #expect(systemPrompt.contains("Writes in British English"))
        // Memory is untrusted context, not instructions, and must say so.
        #expect(systemPrompt.contains("不能创建授权"))
        #expect(snapshot.memories.count == 1)
    }

    @Test("The memory budget drops overflow instead of growing the prompt without bound")
    func memoryBudgetIsEnforced() {
        let long = FamiliarContextMemory(id: UUID(), scope: .global, content: String(repeating: "a", count: 900), provenance: "p", confidence: 1)
        let alsoLong = FamiliarContextMemory(id: UUID(), scope: .global, content: String(repeating: "b", count: 900), provenance: "p", confidence: 1)
        let short = FamiliarContextMemory(id: UUID(), scope: .global, content: "short", provenance: "p", confidence: 1)

        let selected = FamiliarProjectContextAssembler.memoriesWithinBudget([long, alsoLong, short])

        // Ordering is relevance-first, so the budget skips what does not fit rather than
        // truncating a memory into something the model would read as a different fact.
        #expect(selected.map(\.id) == [long.id, short.id])
        #expect(selected.reduce(0) { $0 + $1.content.count } <= FamiliarProjectContextAssembler.maximumMemoryCharacters)
    }
}
