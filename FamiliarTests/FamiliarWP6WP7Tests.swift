import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar WP6 and WP7")
struct FamiliarWP6WP7Tests {
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
}
