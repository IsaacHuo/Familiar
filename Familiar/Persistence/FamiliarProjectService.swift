import Foundation
import SwiftData

enum FamiliarProjectServiceError: LocalizedError {
    case emptyName
    case projectHasRunningRun

    var errorDescription: String? {
        switch self {
        case .emptyName: String(localized: "project.error.empty_name")
        case .projectHasRunningRun: String(localized: "project.error.running")
        }
    }
}

@MainActor
struct FamiliarProjectService {
    static let maximumNameLength = 80
    static let maximumSummaryLength = 500
    nonisolated static let maximumInstructionLength = 8_000
    let resourceStore: FamiliarProjectResourceStore

    init(resourceStore: FamiliarProjectResourceStore = FamiliarProjectResourceStore()) {
        self.resourceStore = resourceStore
    }

    @discardableResult
    func create(name: String, summary: String = "", in context: ModelContext) throws -> FamiliarProject {
        let normalizedName = try normalizedName(name)
        let now = Date()
        let project = FamiliarProject(
            name: normalizedName,
            summary: normalized(summary, maximumLength: Self.maximumSummaryLength),
            createdAt: now,
            updatedAt: now
        )
        context.insert(project)
        try save(context)
        return project
    }

    func update(_ project: FamiliarProject, name: String, summary: String, in context: ModelContext) throws {
        project.name = try normalizedName(name)
        project.summary = normalized(summary, maximumLength: Self.maximumSummaryLength)
        project.updatedAt = Date()
        try save(context)
    }

    func updateInstruction(_ project: FamiliarProject, text: String, in context: ModelContext) throws {
        let value = normalized(text, maximumLength: Self.maximumInstructionLength)
        let now = Date()
        if value.isEmpty {
            if let instruction = project.instruction {
                context.delete(instruction)
            }
        } else if let instruction = project.instruction {
            instruction.text = value
            instruction.updatedAt = now
        } else {
            context.insert(FamiliarProjectInstruction(text: value, createdAt: now, updatedAt: now, project: project))
        }
        project.updatedAt = now
        try save(context)
    }

    func setArchived(_ archived: Bool, for project: FamiliarProject, in context: ModelContext) throws {
        project.status = archived ? .archived : .active
        project.updatedAt = Date()
        try save(context)
    }

    func permanentlyDelete(_ project: FamiliarProject, in context: ModelContext) throws {
        guard !project.agentRuns.contains(where: { $0.status == .running }) else {
            throw FamiliarProjectServiceError.projectHasRunningRun
        }
        let staged = try resourceStore.stageProjectDirectory(projectID: project.id)
        project.conversations.forEach { $0.project = nil }
        project.agentRuns.forEach { $0.project = nil }
        context.delete(project)
        do {
            try context.save()
            if let staged { try resourceStore.discard(staged) }
        } catch {
            context.rollback()
            if let staged { try? resourceStore.restore(staged) }
            throw error
        }
    }

    private func normalizedName(_ value: String) throws -> String {
        let name = normalized(value, maximumLength: Self.maximumNameLength)
        guard !name.isEmpty else { throw FamiliarProjectServiceError.emptyName }
        return name
    }

    private func normalized(_ value: String, maximumLength: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
    }

    private func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
