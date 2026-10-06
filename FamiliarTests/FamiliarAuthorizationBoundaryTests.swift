import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Current authorization boundary")
struct FamiliarAuthorizationBoundaryTests {
    @Test("Policy rejects changed preflight and permission before action")
    func policyRecheck() throws {
        let policy = FamiliarExecutionPolicy()
        let original = FamiliarToolAuthorizationAssessment(disposition: .requiresApproval, effect: .reversibleWrite,
            risk: .low, reason: "Save", targetKey: "version-a")
        let changed = FamiliarToolAuthorizationAssessment(disposition: .requiresApproval, effect: .reversibleWrite,
            risk: .low, reason: "Save", targetKey: "version-b")
        #expect(throws: FamiliarPolicyError.self) { try policy.revalidate(approved: original, current: changed, availability: .available) }
        #expect(throws: FamiliarPolicyError.self) { try policy.revalidate(approved: original, current: original, availability: .requestable) }
        try policy.revalidate(approved: original, current: original, availability: .available)
    }

    @Test("Dynamic read risk and interactivity prevent concurrent execution")
    func dynamicReadPolicy() async throws {
        let manifest = FamiliarToolManifest(name: "fixture_read", title: "Read", description: "Read",
            parameters: .object([:]), effect: .read, risk: .low, supportsParallelism: true)
        let assessment = FamiliarToolAuthorizationAssessment(disposition: .requiresApproval, effect: .read, risk: .high, reason: "Private data")
        let policy = FamiliarExecutionPolicy()
        #expect(!policy.allowsParallelRead(manifest: manifest, assessment: assessment, availability: .available))
        let decision = try await policy.evaluate(manifest: manifest, call: .init(id: "read", name: manifest.name, arguments: "{}"),
            context: .init(runID: "run", toolCallID: "read"), availability: .available, assessment: assessment, authorization: nil)
        #expect(decision.decision == .requireApproval)
        #expect(decision.approval?.risk == .high)
        #expect(decision.approval?.allowedAuthorizationDurations == [.once, .session])
    }

    @Test("Authorization requires exact Project, version, target, arguments and session")
    @MainActor
    func exactPersistedAuthorization() throws {
        let container = try FamiliarTestStore.make(name: "ExactAuthorization")
        let context = container.mainContext
        let project = UUID()
        let runtime = FamiliarAuthorizationRuntime(context: context, sessionID: "session-a")
        let manifest = manifest()
        try runtime.issueAuthorization(duration: .session, manifest: manifest, arguments: #"{"title":"A","count":2}"#,
            projectID: project, targetKey: "calendar:a", evidence: "User approved")
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest, arguments: #"{ "count":2, "title":"A" }"#,
            projectID: project, targetKey: "calendar:a") == .session)
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest, arguments: #"{"title":"B","count":2}"#,
            projectID: project, targetKey: "calendar:a") == nil)
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest, arguments: #"{"title":"A","count":2}"#,
            projectID: UUID(), targetKey: "calendar:a") == nil)
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest, arguments: #"{"title":"A","count":2}"#,
            projectID: project, targetKey: "calendar:b") == nil)
        #expect(try runtime.matchingAuthorizationScope(manifest: self.manifest(version: "2"), arguments: #"{"title":"A","count":2}"#,
            projectID: project, targetKey: "calendar:a") == nil)
        let otherSession = FamiliarAuthorizationRuntime(context: context, sessionID: "session-b")
        #expect(try otherSession.matchingAuthorizationScope(manifest: manifest, arguments: #"{"title":"A","count":2}"#,
            projectID: project, targetKey: "calendar:a") == nil)
    }

    @Test("Expired, revoked or malformed rules grant nothing", arguments: ["expired", "revoked", "malformed"])
    @MainActor
    func invalidRules(kind: String) throws {
        let container = try FamiliarTestStore.make(name: "InvalidAuthorization")
        let context = container.mainContext
        let rule = FamiliarAuthorizationRuleRecord(projectID: nil, capabilityID: manifest().id, capabilityVersion: "1",
            targetKey: "target", argumentsHash: FamiliarCanonicalJSON.argumentsHash("{}"), duration: .always,
            sessionID: nil, expiresAt: kind == "expired" ? .distantPast : .distantFuture, evidence: "fixture")
        if kind == "revoked" { rule.revokedAt = Date() }
        if kind == "malformed" { rule.durationRawValue = "not-a-duration" }
        context.insert(rule)
        try context.save()
        let runtime = FamiliarAuthorizationRuntime(context: context, sessionID: "session")
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest(), arguments: "{}", projectID: nil, targetKey: "target") == nil)
        #expect(rule.lastUsedAt == nil)
    }

    @Test("A one-time authorization is consumed before returning a match")
    @MainActor
    func onceIsConsumed() throws {
        let container = try FamiliarTestStore.make(name: "OnceAuthorization")
        let runtime = FamiliarAuthorizationRuntime(context: container.mainContext, sessionID: "session")
        try runtime.issueAuthorization(duration: .once, manifest: manifest(), arguments: "{}", projectID: nil, targetKey: "target", evidence: "User approved")
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest(), arguments: "{}", projectID: nil, targetKey: "target") == .once)
        let reopened = ModelContext(container)
        let next = FamiliarAuthorizationRuntime(context: reopened, sessionID: "session")
        #expect(try next.matchingAuthorizationScope(manifest: manifest(), arguments: "{}", projectID: nil, targetKey: "target") == nil)
        #expect(try reopened.fetch(FetchDescriptor<FamiliarAuthorizationRuleRecord>()).first?.revokedAt != nil)
    }

    @Test("Historical provenance rows cannot authorize an action", arguments: ["builtIn", "shareExtension", "appIntent", "deepLink"])
    @MainActor
    func historicalRowsAreInert(source: String) throws {
        let container = try FamiliarTestStore.make(name: "HistoricalAuthorization")
        let context = container.mainContext
        context.insert(FamiliarActivityRecord(activityID: "legacy-grant:fixture", runtimeID: "legacy-grants:global",
            assistantTurnID: "legacy-grant", kind: .runtimeNotice, phase: .succeeded, summary: "archived_authorization_provenance",
            detail: source, sequence: -1, startedAt: Date()))
        try context.save()
        let runtime = FamiliarAuthorizationRuntime(context: context, sessionID: "session")
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest(), arguments: "{}", projectID: nil, targetKey: "target") == nil)
        try runtime.issueAuthorization(duration: .always, manifest: manifest(), arguments: "{}", projectID: nil, targetKey: "target", evidence: "User approved now")
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest(), arguments: "{}", projectID: nil, targetKey: "target") == .always)
    }

    @Test("Authorization store failure prevents sensitive reads and external effects", arguments: FamiliarAuthorizationFailureCase.allCases)
    func storeFailureStopsEffect(mode: FamiliarAuthorizationFailureCase) async throws {
        let probe = FamiliarAuthorizationProbe()
        let tool = FamiliarAuthorizationFixtureTool(read: mode.isRead, probe: probe)
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(tool)])
        let coordinator = FamiliarToolConfirmationCoordinator()
        let loop = FamiliarAgentLoop(provider: FamiliarAuthorizationFixtureProvider(), registry: registry, policy: .init(),
            confirmationCoordinator: coordinator, undoStore: .init(),
            authorizationRuntime: FamiliarFailingAuthorizationStore(failMatch: mode.failMatch))
        let snapshot = try familiarTestContextSnapshot(manifests: await registry.snapshot())
        var events: [FamiliarRuntimeEvent] = []
        for try await event in loop.stream(contextSnapshot: snapshot) {
            events.append(event)
            if case .approvalRequested(let request) = event.payload {
                await coordinator.resolve(requestID: request.id, decision: .confirmed)
            }
        }
        #expect(await probe.count() == 0)
        #expect(!events.contains { if case .toolResultProduced = $0.payload { true } else { false } })
        #expect(events.contains { if case .activityCompleted(let value) = $0.payload { value.status == .failed } else { false } })
        #expect(events.filter { if case .runFinished = $0.payload { true } else { false } }.count == 1)
    }

    @Test("Startup ends an interrupted Run while retaining results and uncertain commits")
    @MainActor
    func recoveryKeepsEvidence() throws {
        let container = try FamiliarTestStore.make(name: "RetainedInterruptedEvidence")
        let context = container.mainContext
        let conversation = FamiliarConversation()
        context.insert(conversation)
        try context.save()
        let snapshot = try FamiliarContextCompiler.assemble(seed: .init(projectID: nil, projectName: nil,
            conversationID: conversation.id, projectInstruction: nil, resources: []), settings: .defaultValue, messages: [], toolManifests: [])
        let recorder = FamiliarRunPersistenceRecorder()
        recorder.ensureRun(runtimeID: "interrupted", snapshot: snapshot, startedAt: Date(), context: context)
        let activity = FamiliarRuntimeActivityCompletion(runID: "interrupted", toolCallID: "read", toolName: "web_fetch", effect: .read,
            assistantTurnID: "interrupted:turn:0", detail: "Read", confirmation: .notRequired, status: .succeeded,
            startedAt: Date(), finishedAt: Date(), fileIdentifier: nil, undoAvailable: false, automaticApprovalRequest: nil)
        try recorder.recordActivityCompleted(activity, eventSequence: 1, conversationID: conversation.id, context: context)
        let envelope = try FamiliarToolResultEnvelope(canonicalModelJSON: #"{"text":"Retain this evidence"}"#,
            presentation: .document(.init(summary: "Read", title: "Evidence", text: "Retain this evidence")))
        let result = FamiliarToolResultProduced(runID: "interrupted", toolCallID: "read", toolName: "web_fetch", effect: .read,
            assistantTurnID: "interrupted:turn:0", envelope: envelope, sources: [], file: nil, producedAt: Date())
        #expect(try recorder.recordToolResult(result, eventSequence: 2, conversationID: conversation.id, context: context))
        let recovery = FamiliarRunRecoveryService()
        let pending = try recovery.beginInvocation(idempotencyKey: "interrupted:pending", runtimeID: "interrupted", toolCallID: "pending",
            toolName: "fixture", arguments: "{}", assistantTurnID: "interrupted:turn:0", activityID: "tool:interrupted:pending", in: context)
        let committing = try recovery.beginInvocation(idempotencyKey: "interrupted:commit", runtimeID: "interrupted", toolCallID: "commit",
            toolName: "fixture", arguments: "{}", assistantTurnID: "interrupted:turn:0", activityID: "tool:interrupted:commit", in: context)
        try recovery.setInvocationState(committing, state: .committing, in: context)
        #expect(try recovery.recoverInterruptedRuns(in: context) == 1)
        #expect(conversation.agentRuns.first?.status == .failed)
        #expect(pending.state == .cancelled)
        #expect(committing.state == .committing)
        let retained = try #require(context.fetch(FetchDescriptor<FamiliarToolResultRecord>()).first)
        #expect(try JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(retained.envelopeJSON.utf8)) == envelope)
        #expect(try recovery.recoverInterruptedRuns(in: context) == 0)
    }

    private func manifest(version: String = "1") -> FamiliarToolManifest {
        .init(version: version, name: "fixture", title: "Fixture", description: "Fixture", parameters: .object([:]), effect: .reversibleWrite, risk: .sensitive)
    }
}

nonisolated enum FamiliarAuthorizationFailureCase: CaseIterable, Sendable {
    case matchingRead, matchingWrite, issuingRead, issuingWrite
    var isRead: Bool { self == .matchingRead || self == .issuingRead }
    var failMatch: Bool { self == .matchingRead || self == .matchingWrite }
}

private nonisolated struct FamiliarAuthorizationFixtureError: Error {}

private nonisolated struct FamiliarFailingAuthorizationStore: FamiliarAuthorizationServicing {
    let failMatch: Bool
    func matchingAuthorizationScope(manifest: FamiliarToolManifest, arguments: String, projectID: UUID?, targetKey: String) async throws -> FamiliarAuthorizationDuration? {
        if failMatch { throw FamiliarAuthorizationFixtureError() }
        return nil
    }
    func issueAuthorization(duration: FamiliarAuthorizationDuration, manifest: FamiliarToolManifest, arguments: String, projectID: UUID?, targetKey: String, evidence: String) async throws {
        throw FamiliarAuthorizationFixtureError()
    }
}

private actor FamiliarAuthorizationProbe {
    private var effects = 0
    func performed() { effects += 1 }
    func count() -> Int { effects }
}

private nonisolated struct FamiliarAuthorizationFixtureTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    let read: Bool
    let probe: FamiliarAuthorizationProbe
    var manifest: FamiliarToolManifest {
        .init(name: "fixture", title: "Fixture", description: "Fixture", parameters: .object([:]),
              effect: read ? .read : .reversibleWrite, risk: read ? .high : .sensitive)
    }
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let result = FamiliarToolExecutionResult(envelope: try .init(canonicalModelJSON: #"{"done":true}"#,
            presentation: .scalar(.init(summary: "Done", label: "Fixture", value: "Done"))))
        if read {
            await probe.performed()
            return .result(result)
        }
        return .action(.init(title: "Write", fields: [], target: "target", effect: .reversibleWrite, risk: .sensitive,
            consequence: "Effect", undoPolicy: .unavailable, idempotencyKey: context.idempotencyKey) {
                await probe.performed()
                return .init(result: result)
            })
    }
}

private nonisolated struct FamiliarAuthorizationFixtureProvider: FamiliarModelProvider {
    let providerID = "authorization-fixture"
    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            if request.messages.contains(where: { $0.role == .tool }) {
                continuation.yield(.textDelta("The action could not be authorized."))
                continuation.yield(.completed(.stop))
            } else {
                continuation.yield(.toolCallDelta(index: 0, id: "call", name: "fixture", arguments: "{}"))
                continuation.yield(.completed(.toolCalls))
            }
            continuation.finish()
        }
    }
}
