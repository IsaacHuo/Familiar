import Foundation

/// A single Run's allowed catalog and cached remote discovery. Activation is returned
/// to the existing Loop, which owns the current request's exact tool list.
actor FamiliarToolLoader {
    private let registry: FamiliarToolRegistry
    private let catalog: [FamiliarToolManifest]
    private let deferred: [FamiliarDeferredToolGroup]
    private var discovered: [String: [FamiliarToolManifest]] = [:]

    init(registry: FamiliarToolRegistry, catalog: [FamiliarToolManifest], deferred: [FamiliarDeferredToolGroup]) {
        self.registry = registry
        self.catalog = catalog
        self.deferred = deferred
    }

    func load(groups: [String], toolNames: [String]?, offset: Int, skill: FamiliarSkillSnapshot?, schemaBudget: Int) async throws -> FamiliarToolLoadResult {
        guard groups.count <= 2, Set(groups).count == groups.count, offset >= 0,
              (toolNames?.count ?? 0) <= 16, toolNames.map({ Set($0).count == $0.count }) ?? true else {
            throw FamiliarToolLoadError("Choose at most two groups and sixteen distinct tool names.")
        }
        let scopedCatalog = catalog.filter { FamiliarToolGroup.allows($0.name, skill: skill) }
        let localGroups = FamiliarToolGroup.directory(for: scopedCatalog)
        let knownIDs = Set(localGroups.map(\.id) + deferred.map { $0.summary.id })
        guard groups.allSatisfy(knownIDs.contains) else { throw FamiliarToolLoadError("A selected group is outside this run's allowed scope.") }
        var candidates: [FamiliarToolManifest] = []
        var remoteNames = Set<String>()
        for id in groups {
            try Task.checkCancellation()
            if let source = deferred.first(where: { $0.summary.id == id }) {
                let manifests: [FamiliarToolManifest]
                if let cached = discovered[id] {
                    manifests = cached
                } else {
                    let tools: [AnyFamiliarTool]
                    do { tools = try await source.discover() }
                    catch is CancellationError { throw CancellationError() }
                    catch { throw FamiliarToolLoadError("Cannot load \(source.summary.title): \(error.localizedDescription)") }
                    try Task.checkCancellation()
                    // Validate the complete discovery before changing the run registry.
                    try await registry.registerGroup(tools)
                    manifests = tools.map(\.manifest)
                    discovered[id] = manifests
                }
                let scoped = manifests.filter { FamiliarToolGroup.allows($0.name, skill: skill) }
                candidates += scoped
                remoteNames.formUnion(scoped.map(\.name))
            } else {
                candidates += scopedCatalog.filter { FamiliarToolGroup.group(for: $0.name).rawValue == id }
            }
        }
        candidates.sort { $0.name < $1.name }
        let candidateNames = Set(candidates.map(\.name))
        if let toolNames, !toolNames.allSatisfy(candidateNames.contains) {
            throw FamiliarToolLoadError("A selected tool is outside the selected groups or Skill scope.")
        }
        var available: [FamiliarToolManifest] = []
        var unavailable: [FamiliarUnavailableTool] = []
        for manifest in candidates {
            try Task.checkCancellation()
            if case .unavailable(let reason) = await registry.availability(for: manifest) {
                unavailable.append(.init(name: manifest.name, title: manifest.title, reason: reason))
            } else {
                available.append(manifest)
            }
        }
        let selected = toolNames.map { Set($0) }
        let extensions = available.filter { manifest in
            if let selected { return selected.contains(manifest.name) }
            return !remoteNames.contains(manifest.name)
        }
        let base = catalog.filter { FamiliarToolGroup.baseToolNames.contains($0.name) }
        let active = (base + extensions).sorted { $0.name < $1.name }
        let page = available.dropFirst(offset).prefix(32).map {
            FamiliarToolLoadResult.ToolSummary(name: $0.name, title: String($0.title.prefix(160)), description: String($0.description.prefix(160)))
        }
        let report = FamiliarToolLoadResult.Report(groups: groups, activeTools: active.map(\.name), availableTools: page,
            nextOffset: offset + page.count < available.count ? offset + page.count : nil, unavailable: unavailable)
        let reportCharacters = String(decoding: try JSONEncoder().encode(report), as: UTF8.self).count
        guard FamiliarContextCompiler.inputCharacterCount(messages: [], manifests: active) + reportCharacters + 128 <= schemaBudget else {
            throw FamiliarToolLoadError("The selected schemas exceed this run's remaining input budget. Select fewer tools.")
        }
        return .init(manifests: active, report: report)
    }
}
