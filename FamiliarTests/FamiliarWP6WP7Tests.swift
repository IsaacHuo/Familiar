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
        let invocation = try service.beginInvocation(idempotencyKey: "run:call", runtimeID: "run", toolName: "fixture", arguments: "{}", in: container.mainContext)
        try service.setInvocationState(invocation, state: .committed, resultReference: "artifact", in: container.mainContext)
        #expect(throws: FamiliarRunRecoveryService.Error.self) { try service.beginInvocation(idempotencyKey: "run:call", runtimeID: "run", toolName: "fixture", arguments: "{}", in: container.mainContext) }
    }

    @Test("V4 data migrates to V6 with empty recovery records")
    @MainActor
    func v4ToV6() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarV4ToV6-\(UUID().uuidString)")
        let url = root.appendingPathComponent(FamiliarModelContainer.storeFilename)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = Schema(versionedSchema: FamiliarSchemaV4.self)
        let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(FamiliarModelContainer.storeName, schema: schema, url: url)])
        old.mainContext.insert(FamiliarSchemaV4.FamiliarArtifact(projectID: UUID(), identifier: "a", title: "A", relativePath: "Projects/p/Artifacts/a/a.md", byteSize: 1, contentHash: "h"))
        try old.mainContext.save()
        let current = try FamiliarModelContainer.make(at: url)
        #expect(try current.mainContext.fetch(FetchDescriptor<FamiliarAuthorizationGrantRecord>()).isEmpty)
        #expect(try current.mainContext.fetch(FetchDescriptor<FamiliarToolInvocationRecord>()).isEmpty)
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
        let invocation = try service.beginInvocation(idempotencyKey: "run:call", runtimeID: "run", toolName: "tool", arguments: "{}", in: context)
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
