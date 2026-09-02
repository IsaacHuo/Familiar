import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar WP6 and WP7")
struct FamiliarWP6WP7Tests {
    @Test("Canonical JSON keeps authorization and invocation hashes stable")
    func canonicalArgumentsHash() {
        let first = #"{"title":"A","details":{"enabled":true,"count":2}}"#
        let reordered = #" { "details" : { "count" : 2, "enabled" : true }, "title" : "A" } "#
        let changed = #"{"title":"B","details":{"enabled":true,"count":2}}"#

        #expect(FamiliarCanonicalJSON.string(for: first) == FamiliarCanonicalJSON.string(for: reordered))
        #expect(FamiliarAuthorizationGrant.argumentsHash(first) == FamiliarAuthorizationGrant.argumentsHash(reordered))
        #expect(FamiliarAuthorizationGrant.argumentsHash(first) != FamiliarAuthorizationGrant.argumentsHash(changed))
    }

    @Test("Manifest snapshots are deterministic and grants are bound to exact arguments")
    func capabilityContract() throws {
        let manifest = FamiliarToolManifest(name: "fixture", title: "Fixture", description: "Fixture", parameters: .object([:]), effect: .reversibleWrite, risk: .low)
        let catalog = FamiliarCapabilityCatalog(manifests: [manifest])
        let now = Date(timeIntervalSince1970: 100)
        let snapshot = catalog.snapshot(now: now)
        #expect(snapshot.manifests.map(\.id) == ["fixture"])
        let projectID = UUID()
        let grant = FamiliarAuthorizationGrant(id: UUID(), userAction: "confirm", source: .builtIn, capabilityID: manifest.id, capabilityVersion: manifest.version, argumentsHash: FamiliarAuthorizationGrant.argumentsHash("{}"), projectID: projectID, expiresAt: now.addingTimeInterval(60), singleUse: true, evidence: "fixture", consumedAt: nil, state: .issued)
        #expect(grant.isValid(for: manifest, arguments: "{}", projectID: projectID, now: now))
        #expect(!grant.isValid(for: manifest, arguments: "{\"changed\":true}", projectID: projectID, now: now))
        #expect(!grant.isValid(for: manifest, arguments: "{}", projectID: nil, now: now))
        // The grant contract is consumed by FamiliarRunRecoveryService for external
        // entry points. FamiliarExecutionPolicy deliberately cannot see it, so a
        // grant alone never turns an approval into an automatic execution.
        #expect(FamiliarExecutionPolicy().decide(manifest: manifest, availability: .available) == .requestApproval)
    }

    @Test("Share, Intent, and Deep Link sources cannot issue write grants")
    @MainActor
    func grantSourceAndInvocationState() throws {
        let container = try FamiliarTestStore.make()
        let service = FamiliarRunRecoveryService()
        let grant = FamiliarAuthorizationGrant(id: UUID(), userAction: "share", source: .shareExtension, capabilityID: "fixture", capabilityVersion: "1", argumentsHash: "hash", projectID: nil, expiresAt: Date().addingTimeInterval(60), singleUse: true, evidence: "provenance", consumedAt: nil, state: .issued)
        #expect(throws: FamiliarRunRecoveryService.Error.self) { try service.issueGrant(grant, in: container.mainContext) }
        let invocation = try service.beginInvocation(idempotencyKey: "run:call", runtimeID: "run", toolCallID: "call", toolName: "fixture", arguments: "{}", assistantTurnID: "run:turn:0", activityID: "tool:run:call", in: container.mainContext)
        try service.setInvocationState(invocation, state: .committed, resultReference: "artifact", in: container.mainContext)
        #expect(throws: FamiliarRunRecoveryService.Error.self) { try service.beginInvocation(idempotencyKey: "run:call", runtimeID: "run", toolCallID: "call", toolName: "fixture", arguments: "{}", assistantTurnID: "run:turn:0", activityID: "tool:run:call", in: container.mainContext) }
    }

    @Test("Project Skill and Capability bindings narrow a Run without granting new tools")
    @MainActor
    func projectBindings() throws {
        let container = try FamiliarTestStore.make(name: "ProjectRuntimeBindings")
        let context = container.mainContext
        let project = FamiliarProject(name: "Runtime")
        context.insert(project)
        let skill = try FamiliarSkillService().install(.init(
            format: "familiar.skill",
            formatVersion: 1,
            id: "word-report",
            version: "1.0.0",
            name: "Word Report",
            description: "Generate reports",
            instructions: "Generate a validated Word report.",
            allowedTools: ["web_fetch", "artifact_publish"],
            examples: []
        ), in: context)
        let service = FamiliarProjectService()
        try service.setSkill(skill.id, enabled: true, projectID: project.id, in: context)
        let snapshots = try service.boundSkillSnapshots(projectID: project.id, in: context)
        #expect(snapshots.map(\.stableID) == ["word-report"])

        let manifests = [
            FamiliarToolManifest(name: "web_fetch", title: "Fetch", description: "Fetch", parameters: .init(type: .object), effect: .read, risk: .low),
            FamiliarToolManifest(name: "shell_execute", title: "Shell", description: "Shell", parameters: .init(type: .object), effect: .reversibleWrite, risk: .high),
            FamiliarToolManifest(name: "task_plan", title: "Plan", description: "Plan", parameters: .init(type: .object), effect: .read, risk: .low)
        ]
        try service.setCapability(
            "shell_execute",
            enabled: false,
            allCapabilityIDs: manifests.map(\.id),
            projectID: project.id,
            in: context
        )
        let filtered = try service.filterCapabilities(manifests, projectID: project.id, in: context)
        #expect(filtered.map(\.name).sorted() == ["task_plan", "web_fetch"])
    }

    @Test("Interrupted runs are finalized and in-flight invocations cancelled")
    @MainActor
    func recoverInterruptedRuns() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let conversation = FamiliarConversation()
        let run = FamiliarAgentRun(runtimeID: "run", status: .running, conversation: conversation)
        context.insert(conversation)
        context.insert(run)
        try context.save()

        let service = FamiliarRunRecoveryService()
        let invocation = try service.beginInvocation(idempotencyKey: "run:call", runtimeID: "run", toolCallID: "call", toolName: "tool", arguments: "{}", assistantTurnID: "run:turn:0", activityID: "tool:run:call", in: context)
        try service.setInvocationState(invocation, state: .approved, in: context)
        let cursor = try service.beginCursor(runtimeID: "run", runID: run.id, contextSnapshotID: UUID(), in: context)

        let count = try service.recoverInterruptedRuns(in: context)
        #expect(count == 1)
        #expect(run.status == .failed)
        #expect(run.finishReason == "interrupted")

        let restored = try context.fetch(FetchDescriptor<FamiliarToolInvocationRecord>(predicate: #Predicate { $0.idempotencyKey == "run:call" })).first
        #expect(restored?.state == .cancelled)
        #expect(cursor.phase == .terminal)
    }
}
