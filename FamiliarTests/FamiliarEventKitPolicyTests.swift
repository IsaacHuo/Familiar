import Foundation
import Testing
@testable import Familiar

private actor FamiliarFakeEventKitService: FamiliarEventKitServicing {
    var availabilityValue: FamiliarCapabilityAvailability
    var commits: [String: FamiliarWriteCommitResult] = [:]
    var undone: Set<String> = []
    var failsCommit = false

    init(availability: FamiliarCapabilityAvailability = .available) {
        availabilityValue = availability
    }

    func availability(for requirement: FamiliarCapabilityRequirement) -> FamiliarCapabilityAvailability { availabilityValue }
    func request(_ requirement: FamiliarCapabilityRequirement) throws {
        if case .unavailable(let reason) = availabilityValue { throw FamiliarToolRegistryError.capabilityUnavailable(reason) }
        availabilityValue = .available
    }
    func targetDescription(for request: FamiliarPendingWriteRequest) -> String { "Test Calendar" }
    func events(from startISO8601: String, to endISO8601: String, limit: Int) -> [FamiliarCalendarEvent] { [] }
    func reminders(from startISO8601: String?, to endISO8601: String?, text: String?, limit: Int) -> [FamiliarReminder] { [] }
    func commit(_ request: FamiliarPendingWriteRequest, idempotencyKey: String) throws -> FamiliarWriteCommitResult {
        if failsCommit { throw CocoaError(.fileWriteUnknown) }
        if let existing = commits[idempotencyKey] { return existing }
        let kind: FamiliarEventKitAccessKind = switch request { case .event: .events; case .reminder: .reminders }
        let result = FamiliarWriteCommitResult(idempotencyKey: idempotencyKey, kind: kind, identifier: "created-1")
        commits[idempotencyKey] = result
        return result
    }
    func undoCommit(idempotencyKey: String) throws -> FamiliarToolExecutionResult {
        guard commits[idempotencyKey] != nil, undone.insert(idempotencyKey).inserted else { throw FamiliarEventKitError.undoUnavailable }
        return .init(envelope: try .init(canonicalModelJSON: #"{"undone":true}"#, presentation: .mutationReceipt(.init(summary: "已撤销", operation: "undo", targetIdentifier: nil, succeeded: true, undoAvailable: false))))
    }
    func setFailsCommit() { failsCommit = true }
}

@Suite("EventKit policy and action proposals")
struct FamiliarEventKitPolicyTests {
    private let event = FamiliarEventWriteRequest(title: "Meeting", startISO8601: "2026-08-13T10:00:00Z", endISO8601: "2026-08-13T11:00:00Z", isAllDay: false, location: nil, notes: nil, urlString: nil, calendarIdentifier: nil)

    @Test("A write returns a proposal and commit is idempotent with one-shot undo")
    func proposalCommitAndUndo() async throws {
        let service = FamiliarFakeEventKitService(availability: .requestable)
        let tool = FamiliarCreateCalendarEventTool(service: service)
        let outcome = try await tool.execute(event, context: .init(runID: "run", toolCallID: "call"))
        guard case .action(let proposal) = outcome else { Issue.record("Expected action proposal"); return }
        #expect(proposal.target == "Test Calendar")
        let first = try await proposal.commit()
        let second = try await proposal.commit()
        #expect(first.result.artifactIdentifier == "created-1")
        #expect(second.result.artifactIdentifier == first.result.artifactIdentifier)
        let undo = try #require(first.undo)
        _ = try await undo()
        await #expect(throws: FamiliarEventKitError.self) { _ = try await undo() }
    }

    @Test("Denied capability and system save failure remain failures")
    func deniedAndFailure() async throws {
        let denied = FamiliarFakeEventKitService(availability: .unavailable(reason: "Denied"))
        let registry = try FamiliarToolRegistry(tools: [AnyFamiliarTool(FamiliarCalendarEventsTool(service: denied))], capabilities: denied)
        #expect(await registry.manifests().isEmpty)

        let failing = FamiliarFakeEventKitService()
        await failing.setFailsCommit()
        let outcome = try await FamiliarCreateCalendarEventTool(service: failing).execute(event, context: .init(runID: "run", toolCallID: "call"))
        guard case .action(let proposal) = outcome else { Issue.record("Expected action proposal"); return }
        await #expect(throws: Error.self) { _ = try await proposal.commit() }
    }
}
