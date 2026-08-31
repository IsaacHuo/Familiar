import Foundation
import SwiftData

enum FamiliarProjectServiceError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case projectHasRunningRun

    var errorDescription: String? {
        switch self {
        case .emptyName: String(localized: "project.error.empty_name")
        case .duplicateName: String(localized: "project.error.duplicate_name")
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
    let artifactStore: FamiliarArtifactStore
    let workspaceStore: FamiliarWorkspaceStore

    init(
        resourceStore: FamiliarProjectResourceStore = FamiliarProjectResourceStore(),
        artifactStore: FamiliarArtifactStore = FamiliarArtifactStore(),
        workspaceStore: FamiliarWorkspaceStore = FamiliarWorkspaceStore()
    ) {
        self.resourceStore = resourceStore
        self.artifactStore = artifactStore
        self.workspaceStore = workspaceStore
    }

    @discardableResult
    func create(name: String, summary: String = "", in context: ModelContext) throws -> FamiliarProject {
        let normalizedName = try normalizedName(name)
        try ensureNameAvailable(normalizedName, excluding: nil, in: context)
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
        let normalizedName = try normalizedName(name)
        try ensureNameAvailable(normalizedName, excluding: project.id, in: context)
        project.name = normalizedName
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

    func persistEnvironment(_ receipt: FamiliarEnvironmentReceipt, in context: ModelContext) throws {
        let projectID = receipt.projectID
        if let existing = try context.fetch(FetchDescriptor<FamiliarProjectEnvironmentRecord>(
            predicate: #Predicate { $0.projectID == projectID }
        )).first {
            existing.revision = receipt.revision
            existing.stateRawValue = receipt.state.rawValue
            existing.requestedPackagesJSON = String(decoding: try JSONEncoder().encode(receipt.requestedPackages), as: UTF8.self)
            existing.pythonVersion = receipt.lock.pythonVersion
            existing.resolvedPackagesJSON = String(decoding: try JSONEncoder().encode(receipt.lock.resolvedPackages), as: UTF8.self)
            existing.lockHash = receipt.lock.contentHash
            existing.byteSize = receipt.byteSize
            existing.preparedAt = receipt.preparedAt
        } else {
            context.insert(try FamiliarProjectEnvironmentRecord(receipt: receipt))
        }
        try save(context)
    }

    func boundSkillSnapshots(projectID: UUID, in context: ModelContext) throws -> [FamiliarSkillSnapshot] {
        let bindings = try context.fetch(FetchDescriptor<FamiliarProjectSkillBindingRecord>(
            predicate: #Predicate { $0.projectID == projectID && $0.enabled }
        ))
        let skillIDs = Set(bindings.map(\.skillID))
        return try context.fetch(FetchDescriptor<FamiliarSkill>())
            .filter { skillIDs.contains($0.id) }
            .map { try FamiliarSkillService().snapshot(skillID: $0.id, in: context) }
            .sorted { $0.stableID < $1.stableID }
    }

    func filterCapabilities(
        _ manifests: [FamiliarToolManifest],
        projectID: UUID?,
        in context: ModelContext
    ) throws -> [FamiliarToolManifest] {
        guard let projectID else { return manifests }
        let bindings = try context.fetch(FetchDescriptor<FamiliarProjectCapabilityBindingRecord>(
            predicate: #Predicate { $0.projectID == projectID }
        ))
        guard !bindings.isEmpty else { return manifests }
        let enabled = Set(bindings.filter(\.enabled).map(\.capabilityID))
        let core: Set<String> = ["task_plan", "ask_user", "skill_list", "skill_read", "environment_status"]
        return manifests.filter { core.contains($0.name) || enabled.contains($0.id) }
    }

    func setSkill(
        _ skillID: UUID,
        enabled: Bool,
        projectID: UUID,
        in context: ModelContext
    ) throws {
        let key = "\(projectID.uuidString):\(skillID.uuidString)"
        if let binding = try context.fetch(FetchDescriptor<FamiliarProjectSkillBindingRecord>(
            predicate: #Predicate { $0.bindingKey == key }
        )).first {
            binding.enabled = enabled
            binding.updatedAt = Date()
        } else {
            context.insert(FamiliarProjectSkillBindingRecord(projectID: projectID, skillID: skillID, enabled: enabled))
        }
        try save(context)
    }

    func setCapability(
        _ capabilityID: String,
        enabled: Bool,
        allCapabilityIDs: [String],
        projectID: UUID,
        in context: ModelContext
    ) throws {
        let existing = try context.fetch(FetchDescriptor<FamiliarProjectCapabilityBindingRecord>(
            predicate: #Predicate { $0.projectID == projectID }
        ))
        if existing.isEmpty {
            for id in Set(allCapabilityIDs) {
                context.insert(FamiliarProjectCapabilityBindingRecord(
                    projectID: projectID,
                    capabilityID: id,
                    enabled: id == capabilityID ? enabled : true
                ))
            }
        } else {
            let key = "\(projectID.uuidString):\(capabilityID)"
            if let binding = existing.first(where: { $0.bindingKey == key }) {
                binding.enabled = enabled
                binding.updatedAt = Date()
            } else {
                context.insert(FamiliarProjectCapabilityBindingRecord(
                    projectID: projectID,
                    capabilityID: capabilityID,
                    enabled: enabled
                ))
            }
        }
        try save(context)
    }

    func permanentlyDelete(_ project: FamiliarProject, in context: ModelContext) throws {
        guard !project.agentRuns.contains(where: { $0.status == .running }) else {
            throw FamiliarProjectServiceError.projectHasRunningRun
        }
        var staged: FamiliarStagedResourceDirectory?
        var stagedArtifacts: FamiliarStagedArtifactDirectory?
        var stagedWorkspace: FamiliarStagedWorkspaceDirectory?
        let projectID = project.id
        do {
            staged = try resourceStore.stageProjectDirectory(projectID: projectID)
            stagedArtifacts = try artifactStore.stageProjectDirectory(projectID: projectID)
            stagedWorkspace = try workspaceStore.stageWorkspace(.project(projectID))
            project.conversations.forEach { $0.project = nil }
            project.agentRuns.forEach { $0.project = nil }
            let artifacts = try context.fetch(FetchDescriptor<FamiliarArtifact>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            let mcpBindings = try context.fetch(FetchDescriptor<FamiliarMCPBindingRecord>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            let memoryItems = try context.fetch(FetchDescriptor<FamiliarMemoryItem>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            let authorizationGrants = try context.fetch(FetchDescriptor<FamiliarAuthorizationGrantRecord>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            let authorizationRules = try context.fetch(FetchDescriptor<FamiliarAuthorizationRuleRecord>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            let environments = try context.fetch(FetchDescriptor<FamiliarProjectEnvironmentRecord>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            let skillBindings = try context.fetch(FetchDescriptor<FamiliarProjectSkillBindingRecord>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            let capabilityBindings = try context.fetch(FetchDescriptor<FamiliarProjectCapabilityBindingRecord>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            artifacts.forEach { context.delete($0) }
            mcpBindings.forEach { context.delete($0) }
            memoryItems.forEach { context.delete($0) }
            authorizationGrants.forEach { context.delete($0) }
            authorizationRules.forEach { context.delete($0) }
            environments.forEach { context.delete($0) }
            skillBindings.forEach { context.delete($0) }
            capabilityBindings.forEach { context.delete($0) }
            _ = try FamiliarPinService().stageRemoval(.project, targetIDs: [projectID], in: context)
            context.delete(project)
            try context.save()
            if let staged { try? resourceStore.discard(staged) }
            if let stagedArtifacts { try? artifactStore.discard(stagedArtifacts) }
            if let stagedWorkspace { try? workspaceStore.discard(stagedWorkspace) }
        } catch {
            context.rollback()
            if let staged { try? resourceStore.restore(staged) }
            if let stagedArtifacts { try? artifactStore.restore(stagedArtifacts) }
            if let stagedWorkspace { try? workspaceStore.restore(stagedWorkspace) }
            throw error
        }
    }

    private func normalizedName(_ value: String) throws -> String {
        let name = normalized(value, maximumLength: Self.maximumNameLength)
        guard !name.isEmpty else { throw FamiliarProjectServiceError.emptyName }
        return name
    }

    private func ensureNameAvailable(_ name: String, excluding projectID: UUID?, in context: ModelContext) throws {
        let projects = try context.fetch(FetchDescriptor<FamiliarProject>())
        let duplicate = projects.contains {
            $0.id != projectID && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard !duplicate else { throw FamiliarProjectServiceError.duplicateName }
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
