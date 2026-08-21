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
        let manifest = FamiliarToolManifest(name: "fixture", title: "Fixture", description: "Fixture", parameters: .init(type: .object), effect: .reversibleWrite, risk: .low)
        let catalog = FamiliarCapabilityCatalog(manifests: [manifest])
        let now = Date(timeIntervalSince1970: 100)
        let snapshot = catalog.snapshot(now: now)
        #expect(snapshot.manifests.map(\.id) == ["fixture"])
        let projectID = UUID()
        let grant = FamiliarAuthorizationGrant(id: UUID(), userAction: "confirm", source: .builtIn, capabilityID: manifest.id, capabilityVersion: manifest.version, argumentsHash: FamiliarAuthorizationGrant.argumentsHash("{}"), projectID: projectID, expiresAt: now.addingTimeInterval(60), singleUse: true, evidence: "fixture", consumedAt: nil, state: .issued)
        #expect(grant.isValid(for: manifest, arguments: "{}", projectID: projectID, now: now))
        #expect(!grant.isValid(for: manifest, arguments: "{\"changed\":true}", projectID: projectID, now: now))
        #expect(!grant.isValid(for: manifest, arguments: "{}", projectID: nil, now: now))
        #expect(FamiliarExecutionPolicy().decide(manifest: manifest, availability: .available, grant: grant, arguments: "{}", projectID: projectID, now: now) == .execute)
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
