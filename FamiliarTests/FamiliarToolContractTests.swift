import Foundation
import Testing
@testable import Familiar

@Suite("Structured tool contracts")
struct FamiliarToolContractTests {
    @Test("Every presentation payload round-trips with a stable schema tag", arguments: payloads)
    func presentationRoundTrip(payload: FamiliarToolPresentationPayload) throws {
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(FamiliarToolPresentationPayload.self, from: data)

        #expect(decoded == payload)
        #expect(decoded.schemaVersion == FamiliarToolPresentationPayload.currentSchemaVersion)
        #expect(!decoded.name.rawValue.isEmpty)
    }

    @Test("Envelope preserves canonical model JSON and typed presentation")
    func envelopeRoundTrip() throws {
        let presentation = FamiliarToolPresentationPayload.scalar(.init(summary: "Ready", label: "status", value: "ready"))
        let envelope = try FamiliarToolResultEnvelope(
            canonicalModelJSON: #"{ "z": 2, "a": 1 }"#,
            presentation: presentation
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: data)

        #expect(decoded == envelope)
        #expect(decoded.modelContent == #"{"a":1,"z":2}"#)
        #expect(decoded.summary == "Ready")
        #expect(!String(decoding: data, as: UTF8.self).contains("trustedUICommand"))
    }

    @Test("Tool failures use code, retryability, and message")
    func failureContract() throws {
        let failure = FamiliarToolFailure(code: "timeout", retryable: true, message: "Request timed out.")
        let data = try JSONEncoder().encode(failure)
        let decoded = try JSONDecoder().decode(FamiliarToolFailure.self, from: data)

        #expect(decoded == failure)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["code", "retryable", "message"])
    }

    @Test("Approval fields preserve author-defined order through request coding")
    func approvalFieldOrder() throws {
        let fields = [
            FamiliarApprovalField(id: "when", label: "When", type: .date, value: "2026-08-21T10:00:00Z"),
            FamiliarApprovalField(id: "private", label: "Private", type: .boolean, value: "true"),
            FamiliarApprovalField(id: "priority", label: "Priority", type: .number, value: "3"),
            FamiliarApprovalField(id: "link", label: "Link", type: .url, value: "https://example.com"),
            FamiliarApprovalField(id: "token", label: "Token", type: .sensitive, value: "secret"),
            FamiliarApprovalField(id: "title", label: "Title", type: .text, value: "Review")
        ]
        let request = FamiliarToolConfirmationRequest(
            runID: "run",
            toolCallID: "call",
            toolName: "fixture_write",
            effect: .reversibleWrite,
            risk: .sensitive,
            title: "Review change",
            fields: fields,
            target: "Fixture",
            consequence: "Writes one fixture.",
            undoPolicy: .currentSession
        )
        let decoded = try JSONDecoder().decode(
            FamiliarToolConfirmationRequest.self,
            from: JSONEncoder().encode(request)
        )

        #expect(decoded.fields.map(\.id) == fields.map(\.id))
        #expect(decoded.effect == .reversibleWrite)
        #expect(decoded.risk == .sensitive)
        #expect(decoded.target == "Fixture")
        #expect(decoded.consequence == "Writes one fixture.")
        #expect(decoded.undoPolicy == .currentSession)
        #expect(decoded.fields[1].formattedValue == String(localized: "common.yes"))
        #expect(decoded.fields[4].formattedValue != "secret")
    }

    private static let payloads: [FamiliarToolPresentationPayload] = [
        .scalar(.init(summary: "Scalar", value: "42")),
        .searchResults(.init(summary: "One result", query: "familiar", results: [.init(id: "1", title: "Familiar", url: "https://example.com", snippet: "Result")])),
        .document(.init(summary: "Document", title: "Doc", text: "Body", mimeType: "text/plain", url: nil, truncated: false)),
        .contextMatches(.init(summary: "One match", query: "body", matches: [.init(resourceID: UUID(), versionID: UUID(), version: 3, title: "Doc", excerpt: "Body")])),
        .recordCollection(.init(summary: "One record", recordType: "fixture", records: [.init(id: "1", fields: [.init(name: "title", value: "Record")])])),
        .mutationReceipt(.init(summary: "Created", operation: "create", targetIdentifier: "1", succeeded: true, undoAvailable: true)),
        .artifactMutation(.init(summary: "Written", operation: "write", identifier: "artifact_1", title: "Draft", byteSize: 4, contentHash: "hash")),
        .diff(.init(summary: "Changed", before: "old", after: "new")),
        .taskList(.init(planID: "release", title: "Release", tasks: [.init(id: "verify", title: "Verify", status: .running, detail: "Build", progress: 0.5)])),
        .recommendation(.init(title: "Next step", explanation: "Verify first.", nextPrompt: "Verify the build", alternatives: [.init(id: "review", title: "Review", prompt: "Review the diff")], confidenceLevel: .needsReview)),
        .insight(.init(title: "Latency", explanation: "Latency improved.", metrics: [.init(label: "P95", value: 120, unit: "ms", change: -18)])),
        .code(.init(summary: "Example", language: "swift", filename: "Example.swift", code: "let value = 1")),
        .shareDraft(.init(summary: "Ready to share", title: "Draft", text: "Share this text"))
    ]
}
