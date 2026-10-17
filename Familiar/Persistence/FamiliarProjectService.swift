import Foundation
import SwiftData

enum FamiliarProjectServiceError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case projectHasRunningRun
    case unknownModel

    var errorDescription: String? {
        switch self {
        case .emptyName: String(localized: "project.error.empty_name")
        case .duplicateName: String(localized: "project.error.duplicate_name")
        case .projectHasRunningRun: String(localized: "project.error.running")
        case .unknownModel: String(localized: "project.error.unknown_model", defaultValue: "That model is no longer available.")
        }
    }
}

@MainActor
struct FamiliarProjectService {
    static let maximumNameLength = 80
    static let maximumSummaryLength = 500
    nonisolated static let maximumInstructionLength = 8_000
    let resourceStore: FamiliarProjectResourceStore
    let fileStore: FamiliarFileStore
    let workspaceStore: FamiliarWorkspaceStore

    init(
        resourceStore: FamiliarProjectResourceStore = FamiliarProjectResourceStore(),
        fileStore: FamiliarFileStore = FamiliarFileStore(),
        workspaceStore: FamiliarWorkspaceStore = FamiliarWorkspaceStore()
    ) {
        self.resourceStore = resourceStore
        self.fileStore = fileStore
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
        do {
            let normalizedName = try normalizedName(name)
            try ensureNameAvailable(normalizedName, excluding: project.id, in: context)
            project.name = normalizedName
        }
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

    /// An empty value clears the override so the Project follows the global selection.
    /// Unknown IDs are rejected rather than stored, because a stored ID the provider no
    /// longer offers would only surface as a failure at send time.
    func updateModelOverride(_ project: FamiliarProject, modelID: String, providerID: String = FamiliarProviderCatalog.deepSeek.id, in context: ModelContext) throws {
        let value = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            project.modelIDOverride = nil
            project.providerIDOverride = nil
        } else {
            guard FamiliarProviderCatalog.descriptor(for: providerID)?.curatedModels.contains(where: { $0.id == value }) == true else {
                throw FamiliarProjectServiceError.unknownModel
            }
            project.modelIDOverride = value
            project.providerIDOverride = providerID
        }
        project.updatedAt = Date()
        try save(context)
    }

    func setArchived(_ archived: Bool, for project: FamiliarProject, in context: ModelContext) throws {
        project.status = archived ? .archived : .active
        project.updatedAt = Date()
        try save(context)
    }

    func persistEnvironment(_ receipt: FamiliarEnvironmentReceipt, in context: ModelContext) throws {
        let key = receipt.scope.storageKey
        if let existing = try context.fetch(FetchDescriptor<FamiliarEnvironmentRecord>(
            predicate: #Predicate { $0.scopeKey == key }
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
            context.insert(try FamiliarEnvironmentRecord(receipt: receipt))
        }
        try save(context)
    }

    /// Follows an undone environment replacement: the restored directory may carry an
    /// older receipt, and a first install leaves no environment at all.
    func removeEnvironment(scope: FamiliarWorkScope, in context: ModelContext) throws {
        let key = scope.storageKey
        if let existing = try context.fetch(FetchDescriptor<FamiliarEnvironmentRecord>(
            predicate: #Predicate { $0.scopeKey == key }
        )).first {
            context.delete(existing)
            try save(context)
        }
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
        let bindings: [FamiliarProjectCapabilityBindingRecord]
        if let projectID {
            bindings = try context.fetch(FetchDescriptor<FamiliarProjectCapabilityBindingRecord>(predicate: #Predicate { $0.projectID == projectID }))
        } else { bindings = [] }
        let enabled = Set(bindings.filter(\.enabled).map(\.capabilityID))
        let toggled = Set(bindings.map(\.capabilityID))
        // A binding row only records a capability the user explicitly switched.
        // Capabilities never toggled (including ones added after the snapshot) follow
        // the product defaults, so enabling Shell and document tools reaches
        // existing Projects instead of leaving them silently off.
        return manifests.filter { manifest in
            FamiliarToolGroup.baseToolNames.contains(manifest.name)
                || enabled.contains(manifest.id)
                || (!toggled.contains(manifest.id) && FamiliarToolGroup.isDefaultEnabled(manifest.name))
        }
    }

    func setSkill(
        _ skillID: UUID,
        enabled: Bool,
        projectID: UUID,
        in context: ModelContext
    ) throws {
        try stageSkill(skillID, enabled: enabled, projectID: projectID, in: context)
        try save(context)
    }

    func stageSkill(_ skillID: UUID, enabled: Bool, projectID: UUID, in context: ModelContext) throws {
        let key = "\(projectID.uuidString):\(skillID.uuidString)"
        if let binding = try context.fetch(FetchDescriptor<FamiliarProjectSkillBindingRecord>(
            predicate: #Predicate { $0.bindingKey == key }
        )).first {
            binding.enabled = enabled
            binding.updatedAt = Date()
        } else {
            context.insert(FamiliarProjectSkillBindingRecord(projectID: projectID, skillID: skillID, enabled: enabled))
        }
    }

    func setCapability(
        _ capabilityID: String,
        enabled: Bool,
        allCapabilities: [FamiliarToolManifest],
        projectID: UUID,
        in context: ModelContext
    ) throws {
        let existing = try context.fetch(FetchDescriptor<FamiliarProjectCapabilityBindingRecord>(
            predicate: #Predicate { $0.projectID == projectID }
        ))
        if existing.isEmpty {
            for manifest in allCapabilities {
                context.insert(FamiliarProjectCapabilityBindingRecord(
                    projectID: projectID,
                    capabilityID: manifest.id,
                    enabled: manifest.id == capabilityID ? enabled : FamiliarToolGroup.isDefaultEnabled(manifest.name)
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
        var stagedFiles: FamiliarStagedFileDirectory?
        var stagedWorkspace: FamiliarStagedWorkspaceDirectory?
        var stagedManagedFiles: FamiliarStagedFileDirectory?
        let managedFiles = FamiliarManagedFileStore()
        let projectID = project.id
        let scopeKey = FamiliarWorkScope.project(projectID).storageKey
        var copiedPaths: [String] = []
        var removedAttachmentPaths: [String] = []
        do {
            for chat in Array(project.conversations) {
                try FamiliarFileCatalogService().stageMove(chat, to: .conversation(chat.id), copiedPaths: &copiedPaths, in: context)
            }
            let ownedFiles = try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.scopeKey == scopeKey }))
            removedAttachmentPaths = ownedFiles.flatMap(\.versions)
                .filter { $0.storageKindRawValue == FamiliarFileStorageKind.attachment.rawValue }.map(\.storageRelativePath)
            staged = try resourceStore.stageProjectDirectory(projectID: projectID)
            stagedFiles = try fileStore.stageScopeDirectory(scope: .project(projectID))
            stagedManagedFiles = try managedFiles.stageScopeDirectory(scope: .project(projectID))
            stagedWorkspace = try workspaceStore.stageWorkspace(.project(projectID))
            Array(project.conversations).forEach { $0.project = nil }
            project.agentRuns.forEach { $0.project = nil }
            let files = try context.fetch(FetchDescriptor<FamiliarStoredFileVersion>(
                predicate: #Predicate { $0.scopeKey == scopeKey }
            ))
            let mcpBindings = try context.fetch(FetchDescriptor<FamiliarMCPBindingRecord>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            let memoryItems = try context.fetch(FetchDescriptor<FamiliarMemoryItem>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            let authorizationRules = try context.fetch(FetchDescriptor<FamiliarAuthorizationRuleRecord>(
                predicate: #Predicate { $0.scopeKey == scopeKey }
            ))
            let environments = try context.fetch(FetchDescriptor<FamiliarEnvironmentRecord>(
                predicate: #Predicate { $0.scopeKey == scopeKey }
            ))
            let skillBindings = try context.fetch(FetchDescriptor<FamiliarProjectSkillBindingRecord>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            let capabilityBindings = try context.fetch(FetchDescriptor<FamiliarProjectCapabilityBindingRecord>(
                predicate: #Predicate { $0.projectID == projectID }
            ))
            files.forEach { context.delete($0) }
            ownedFiles.forEach { context.delete($0) }
            mcpBindings.forEach { context.delete($0) }
            memoryItems.forEach { context.delete($0) }
            authorizationRules.forEach { context.delete($0) }
            environments.forEach { context.delete($0) }
            skillBindings.forEach { context.delete($0) }
            capabilityBindings.forEach { context.delete($0) }
            _ = try FamiliarPinService().stageRemoval(.project, targetIDs: [projectID], in: context)
            context.delete(project)
            try context.save()
            FamiliarAttachmentStore.remove(relativePaths: removedAttachmentPaths)
            if let staged { try? resourceStore.discard(staged) }
            if let stagedFiles { try? fileStore.discard(stagedFiles) }
            if let stagedManagedFiles { try? managedFiles.discard(stagedManagedFiles) }
            if let stagedWorkspace { try? workspaceStore.discard(stagedWorkspace) }
        } catch {
            context.rollback()
            FamiliarAttachmentStore.remove(relativePaths: copiedPaths)
            if let staged { try? resourceStore.restore(staged) }
            if let stagedFiles { try? fileStore.restore(stagedFiles) }
            if let stagedManagedFiles { try? managedFiles.restore(stagedManagedFiles) }
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
            $0.id != projectID && ($0.name.localizedCaseInsensitiveCompare(name) == .orderedSame || $0.displayName.localizedCaseInsensitiveCompare(name) == .orderedSame)
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
