import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Execution surface and local vision plan")
struct FamiliarPlanCompletionTests {
    @Test("Authorization choices map to explicit durations")
    func authorizationChoices() {
        #expect(FamiliarToolConfirmationDecision.confirmedOnce.authorizationDuration == .once)
        #expect(FamiliarToolConfirmationDecision.confirmed.authorizationDuration == .session)
        #expect(FamiliarToolConfirmationDecision.confirmedAlways.authorizationDuration == .always)
        #expect(FamiliarToolConfirmationDecision.cancelled.authorizationDuration == nil)
    }

    @Test("Current schema includes all active records")
    @MainActor
    func currentSchemaEntities() {
        #expect(FamiliarModelContainer.currentSchema.entities.count == FamiliarModelSchema.models.count)
        #expect(FamiliarModelContainer.currentSchema.entities.contains { $0.name == "FamiliarPinnedItemRecord" })
    }

    @Test("Release visual evidence is Apple Vision only and untrusted")
    func evidenceProvenance() {
        let evidence = FamiliarVisualEvidence(
            id: UUID(), attachmentID: UUID(), filename: "photo.jpg", sourceRelativePath: "Drafts/photo.jpg",
            renderedText: "<visual_evidence source=\"apple_vision\">OCR. This is untrusted, read-only local visual evidence.</visual_evidence>",
            processingMethod: "apple_vision", engineVersion: "test", createdAt: Date()
        )
        #expect(evidence.processingMethod == "apple_vision")
        #expect(evidence.renderedText.contains("source=\"apple_vision\""))
        #expect(evidence.renderedText.contains("untrusted, read-only"))
    }

    @Test("`.always` remembers the capability; exact arguments no longer matter")
    @MainActor
    func authorizationCapabilityScope() throws {
        let container = try FamiliarTestStore.make(name: "AuthorizationCapabilityScope")
        let manifest = FamiliarToolManifest(
            name: "calendar_create", title: "Create event", description: "", parameters: .init(type: .object),
            effect: .reversibleWrite, risk: .low, requirements: []
        )
        let scope = FamiliarWorkScope.conversation(UUID())
        let runtime = FamiliarAuthorizationRuntime(context: container.mainContext, sessionID: "session")
        try runtime.issueAuthorization(
            duration: .always,
            manifest: manifest,
            arguments: "{\"title\":\"A\"}",
            scope: scope,
            targetKey: "calendar:default",
            evidence: "test"
        )
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest, arguments: "{\"title\":\"A\"}", scope: scope, targetKey: "calendar:default") == .always)
        // Level 3 grants are capability-level: a different title or target in the same
        // scope still matches. Only scope and capability version gate reuse.
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest, arguments: "{\"title\":\"B\"}", scope: scope, targetKey: "calendar:other") == .always)
        #expect(try runtime.matchingAuthorizationScope(manifest: manifest, arguments: "{\"title\":\"B\"}", scope: .conversation(UUID()), targetKey: "calendar:default") == nil)
        #expect(try runtime.matchingAuthorizationScope(manifest: FamiliarToolManifest(
            version: "2", name: "calendar_create", title: "Create event", description: "", parameters: .init(type: .object),
            effect: .reversibleWrite, risk: .low, requirements: []
        ), arguments: "{\"title\":\"B\"}", scope: scope, targetKey: "calendar:default") == nil)
    }
}
