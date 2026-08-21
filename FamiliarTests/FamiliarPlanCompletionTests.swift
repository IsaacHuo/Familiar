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

    @Test("FastVLM manifest is pinned to the verified Apple archive")
    @MainActor
    func fastVLMManifest() {
        #expect(FamiliarLocalVisionModelManager.archiveSize == 1_232_152_649)
        #expect(FamiliarLocalVisionModelManager.archiveSHA256 == "661506b66e9101463165b2834a99c89868b0d65fe7b1debbd46bdbd3b4f98d13")
        #expect(FamiliarLocalVisionModelManager.downloadURL.host == "ml-site.cdn-apple.com")
    }

    @Test("Basic OCR requests do not route to FastVLM")
    func visionRouting() {
        #expect(!FamiliarVisionRouting.shouldUseFastVLM(prompt: "请提取文字"))
        #expect(!FamiliarVisionRouting.shouldUseFastVLM(prompt: "scan this QR code"))
        #expect(FamiliarVisionRouting.shouldUseFastVLM(prompt: "比较这两张图的内容"))
    }

    @Test("FastVLM evidence stays explicitly untrusted")
    func evidenceProvenance() {
        let evidence = FamiliarVisualEvidence(
            id: UUID(), attachmentID: UUID(), filename: "photo.jpg", sourceRelativePath: "Drafts/photo.jpg",
            renderedText: "<visual_evidence source=\"apple_vision\">OCR</visual_evidence>",
            processingMethod: "apple_vision", engineVersion: "test", createdAt: Date()
        ).includingFastVLM("A chart")
        #expect(evidence.processingMethod == "apple_vision+fastvlm-0.5b")
        #expect(evidence.renderedText.contains("source=\"fastvlm-0.5b\""))
        #expect(evidence.renderedText.contains("untrusted, read-only"))
    }

    @Test("Remembered authorization remains scoped to exact arguments")
    @MainActor
    func authorizationArgumentScope() throws {
        let container = try FamiliarTestStore.make(name: "AuthorizationArgumentScope")
        let manifest = FamiliarToolManifest(
            name: "calendar_create", title: "Create event", description: "", parameters: .init(type: .object),
            effect: .reversibleWrite, risk: .low, requirements: []
        )
        let runtime = FamiliarAuthorizationRuntime(context: container.mainContext, sessionID: "session")
        try runtime.issueAuthorization(
            duration: .always,
            manifest: manifest,
            arguments: "{\"title\":\"A\"}",
            projectID: nil,
            targetKey: "calendar:default",
            evidence: "test"
        )
        #expect(runtime.matchingAuthorization(manifest: manifest, arguments: "{\"title\":\"A\"}", projectID: nil, targetKey: "calendar:default"))
        #expect(!runtime.matchingAuthorization(manifest: manifest, arguments: "{\"title\":\"B\"}", projectID: nil, targetKey: "calendar:default"))
    }
}
