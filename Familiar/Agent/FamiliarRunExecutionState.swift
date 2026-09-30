import Foundation

nonisolated struct FamiliarExecutionContractError: LocalizedError, FamiliarStructuredToolError {
    let detail: String
    var errorDescription: String? { detail }
    var code: String { "execution_contract_violation" }
    var isRetryable: Bool { true }
}

/// Run-local authority for the plan. Model-authored presentation status is a proposal,
/// and cannot substitute for tool evidence or a committed Artifact receipt.
actor FamiliarRunExecutionState {
    struct Snapshot: Codable, Equatable, Sendable {
        var plan: FamiliarToolPresentationPayload.TaskList?
        var revision = 0
        var evidence: [String: [String]] = [:]
        var deliveries: [String: Delivery] = [:]
        var repairAttempts = 0
    }
    struct Delivery: Codable, Equatable, Sendable {
        let artifactID: String
        let contentHash: String
        let format: String
        let receipt: FamiliarValidationReceipt
    }
    private var value = Snapshot()
    private var installedSkills: [FamiliarSkillSnapshot] = []
    private var successfulWrites: Set<String> = []

    func snapshot() -> Snapshot { value }
    func hasPlan() -> Bool { value.plan != nil }
    func skills(available: [FamiliarSkillSnapshot]) -> [FamiliarSkillSnapshot] {
        var all = Dictionary(available.map { ($0.stableID, $0) }, uniquingKeysWith: { _, new in new })
        for skill in installedSkills { all[skill.stableID] = skill }
        return all.values.sorted { $0.stableID < $1.stableID }
    }
    func admit(_ skill: FamiliarSkillSnapshot) { installedSkills.append(skill) }

    func apply(_ plan: FamiliarToolPresentationPayload.TaskList) throws {
        if let previous = value.plan {
            guard previous.planID == plan.planID else { throw error("Reuse the active planID.") }
            for old in previous.expectedDeliverables ?? [] {
                guard let new = plan.expectedDeliverables?.first(where: { $0.id == old.id }),
                      new.format == old.format,
                      Set(old.requiredText ?? []).isSubset(of: Set(new.requiredText ?? [])),
                      (new.minimumSources ?? 0) >= (old.minimumSources ?? 0)
                else { throw error("A plan revision cannot remove or weaken a promised deliverable.") }
            }
            for old in previous.tasks where old.status == .completed {
                guard plan.tasks.contains(where: { $0.id == old.id && $0.status == .completed }) else {
                    throw error("Completed steps and their evidence must remain in the plan.")
                }
            }
        }
        var encounteredIncomplete = false
        var running = 0
        for step in plan.tasks {
            if step.status == .completed {
                guard !encounteredIncomplete, !(value.evidence[step.id] ?? []).isEmpty else {
                    throw error("Complete steps in order and only after successful tool evidence.")
                }
            } else {
                if step.status == .running {
                    guard !encounteredIncomplete else { throw error("Only the next unfinished step may run.") }
                    running += 1
                }
                encounteredIncomplete = true
            }
        }
        guard running <= 1 else { throw error("Only one step may be active.") }
        value.plan = plan
        value.revision += 1
    }

    func activeStepID() -> String? {
        value.plan?.tasks.first(where: { $0.status != .completed })?.id
    }
    func requirePlan() throws {
        guard value.plan != nil else { throw error("Call task_plan before preparing an environment or producing files.") }
    }
    func spec(id: String?, format: String) throws -> FamiliarDeliverableSpec {
        try requirePlan()
        guard let id, let spec = value.plan?.expectedDeliverables?.first(where: { $0.id == id }), spec.format == format else {
            throw error("artifact_publish requires an exact deliverableID and format from the active plan.")
        }
        return spec
    }
    func record(call: FamiliarToolCall, result: FamiliarToolExecutionResult) throws {
        if let artifact = result.artifact, let id = result.deliverableID {
            let spec = try spec(id: id, format: artifact.format.rawValue)
            guard let receipt = artifact.validationReceipt, receipt.format.rawValue == spec.format,
                  !value.deliveries.contains(where: { $0.key != id && $0.value.artifactID == artifact.identifier })
            else { throw error("A distinct validated Artifact is required for each deliverable.") }
            value.deliveries[id] = .init(artifactID: artifact.identifier, contentHash: artifact.contentHash,
                                        format: artifact.format.rawValue, receipt: receipt)
        }
        if let id = activeStepID(), !["task_plan", "skill_list", "skill_read", "ask_user"].contains(call.name) {
            value.evidence[id, default: []].append(call.id)
        }
    }
    func missing() -> [FamiliarDeliverableSpec] {
        (value.plan?.expectedDeliverables ?? []).filter { value.deliveries[$0.id] == nil }
    }
    func unfinishedSteps() -> [String] { value.plan?.tasks.filter { $0.status != .completed }.map(\.title) ?? [] }
    func beginRepair() throws -> Int {
        guard value.repairAttempts < 2 else { throw error("Delivery repair limit reached; the task is incomplete.") }
        value.repairAttempts += 1
        return value.repairAttempts
    }
    func wasWritten(_ fingerprint: String) -> Bool { successfulWrites.contains(fingerprint) }
    func didWrite(_ fingerprint: String) { successfulWrites.insert(fingerprint) }
    private func error(_ detail: String) -> FamiliarExecutionContractError { .init(detail: detail) }
}
