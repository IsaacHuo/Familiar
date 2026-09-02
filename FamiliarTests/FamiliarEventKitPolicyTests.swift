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
        let kind: FamiliarEventKitAccessKind = switch request {
        case .event, .eventUpdate, .eventDelete: .events
        case .reminder, .reminderUpdate, .reminderDelete: .reminders
        }
        let operation: FamiliarEventKitMutationOperation = switch request {
        case .event, .reminder: .create
        case .eventUpdate, .reminderUpdate: .update
        case .eventDelete, .reminderDelete: .delete
        }
        let result = FamiliarWriteCommitResult(idempotencyKey: idempotencyKey, kind: kind, identifier: "created-1", operation: operation)
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

        // The tool must not merely vanish: the concrete reason has to survive so the
        // model can report the missing capability instead of guessing an alternative.
        let report = await registry.availabilityReport()
        #expect(report.manifests.isEmpty)
        #expect(report.unavailable.map(\.name) == ["calendar_events"])
        #expect(report.unavailable.first?.reason == "Denied")

        let failing = FamiliarFakeEventKitService()
        await failing.setFailsCommit()
        let outcome = try await FamiliarCreateCalendarEventTool(service: failing).execute(event, context: .init(runID: "run", toolCallID: "call"))
        guard case .action(let proposal) = outcome else { Issue.record("Expected action proposal"); return }
        await #expect(throws: Error.self) { _ = try await proposal.commit() }
    }

    @Test("Update and delete writes remain pure proposals until commit")
    func updateAndDeleteProposalBoundary() async throws {
        let service = FamiliarFakeEventKitService()
        let update = FamiliarReminderUpdateRequest(
            identifier: "reminder-1",
            title: "Review",
            dueISO8601: "2026-08-30T15:00:00Z",
            listIdentifier: nil,
            priority: 3,
            notes: nil,
            isCompleted: true
        )
        let updateOutcome = try await FamiliarUpdateReminderTool(service: service).execute(
            update,
            context: .init(runID: "run", toolCallID: "update")
        )
        guard case .action(let updateProposal) = updateOutcome else { Issue.record("Expected update proposal"); return }
        #expect(await service.commits.isEmpty)
        #expect(updateProposal.fields.contains { $0.id == "completed" && $0.value == "true" })
        let updateCommit = try await updateProposal.commit()
        #expect(updateCommit.result.modelContent.contains(#""operation":"update""#))

        let deleteOutcome = try await FamiliarDeleteCalendarEventTool(service: service).execute(
            .init(identifier: "event-1"),
            context: .init(runID: "run", toolCallID: "delete")
        )
        guard case .action(let deleteProposal) = deleteOutcome else { Issue.record("Expected delete proposal"); return }
        #expect(await service.commits.count == 1)
        #expect(deleteProposal.allowedAuthorizationDurations == [.once])
        _ = try await deleteProposal.commit()
        #expect(await service.commits.count == 2)
    }
}
