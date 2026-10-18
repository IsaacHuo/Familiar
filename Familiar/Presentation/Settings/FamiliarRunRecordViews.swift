import AVFoundation
import Contacts
import CoreBluetooth
import CoreLocation
import EventKit
import HealthKit
import MusicKit
import Photos
import Speech
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers


struct FamiliarRunRecordList: View {
    let runs: [FamiliarAgentRun]

    var body: some View {
        List(runs) { run in
            NavigationLink {
                FamiliarRunRecordDetail(run: run)
            } label: {
                FamiliarRunRecordRow(run: run)
            }
        }
        .navigationTitle(String(localized: "project.runs", defaultValue: "Runs"))
    }
}

struct FamiliarRunRecordRow: View {
    let run: FamiliarAgentRun

    var body: some View {
        HStack(spacing: FamiliarSpacing.medium) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                Text(runTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(run.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(FamiliarTypography.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var runTitle: String {
        let snapshot = run.contextSnapshot
        let providerID = snapshot?.providerID ?? ""
        let modelID = snapshot?.modelID ?? ""
        let providerName = FamiliarProviderCatalog.descriptor(for: providerID)?.displayName ?? providerID
        let modelName = FamiliarProviderCatalog.descriptor(for: providerID)?.model(for: modelID).displayName ?? modelID
        return [providerName, modelName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var statusIcon: String {
        switch run.status {
        case .running: "bolt.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch run.status {
        case .running: FamiliarTheme.accent
        case .completed: .green
        case .cancelled: .secondary
        case .failed: .red
        }
    }
}

struct FamiliarRunRecordDetail: View {
    @Query(sort: \FamiliarRunSkillSnapshotRecord.sequence) private var allSkillSnapshots: [FamiliarRunSkillSnapshotRecord]
    @Query private var activities: [FamiliarActivityRecord]
    @Query private var approvals: [FamiliarApprovalRecord]
    @Query private var results: [FamiliarToolResultRecord]
    @Query private var invocations: [FamiliarToolInvocationRecord]
    let run: FamiliarAgentRun

    init(run: FamiliarAgentRun) {
        self.run = run
        let runtimeID = run.runtimeID
        _activities = Query(
            filter: #Predicate<FamiliarActivityRecord> { $0.runtimeID == runtimeID },
            sort: \FamiliarActivityRecord.sequence
        )
        _approvals = Query(
            filter: #Predicate<FamiliarApprovalRecord> { $0.runtimeID == runtimeID },
            sort: \FamiliarApprovalRecord.requestedAt
        )
        _results = Query(
            filter: #Predicate<FamiliarToolResultRecord> { $0.runtimeID == runtimeID },
            sort: \FamiliarToolResultRecord.createdAt
        )
        _invocations = Query(
            filter: #Predicate<FamiliarToolInvocationRecord> { $0.runtimeID == runtimeID },
            sort: \FamiliarToolInvocationRecord.startedAt
        )
    }

    var body: some View {
        List {
            Section(String(localized: "project.run.execution", defaultValue: "Execution")) {
                LabeledContent(String(localized: "project.run.status", defaultValue: "Status"), value: statusText)
                LabeledContent(String(localized: "settings.provider"), value: providerName)
                LabeledContent(String(localized: "settings.model"), value: modelName)
                LabeledContent(String(localized: "project.run.started", defaultValue: "Started")) {
                    Text(run.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                }
                if let finishedAt = run.finishedAt {
                    LabeledContent(String(localized: "project.run.finished", defaultValue: "Finished")) {
                        Text(finishedAt, format: .dateTime.year().month().day().hour().minute().second())
                    }
                }
                if let reason = run.finishReason, !reason.isEmpty {
                    LabeledContent(String(localized: "settings.runs.result", defaultValue: "Result"), value: reason)
                }
                if let finishedAt = run.finishedAt {
                    LabeledContent(String(localized: "project.run.duration", defaultValue: "Duration")) {
                        Text(verbatim: "\(finishedAt.timeIntervalSince(run.startedAt).formatted(.number.precision(.fractionLength(1)))) s")
                    }
                }
            }

            Section(String(localized: "project.run.steps", defaultValue: "Execution Steps")) {
                if toolActivities.isEmpty {
                    Text(String(localized: "settings.runs.no_activities", defaultValue: "No persisted activities"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(toolActivities) { activity in
                        FamiliarRunRecordStep(
                            activity: activity,
                            invocation: invocations.first { $0.activityID == activity.activityID },
                            approval: approvals.first { $0.activityID == activity.activityID },
                            result: results.first { $0.activityID == activity.activityID }
                        )
                    }
                }
            }

            if !approvals.isEmpty {
                Section(String(localized: "project.run.authorizations", defaultValue: "Authorizations")) {
                    ForEach(approvals) { approval in
                        FamiliarRunRecordApproval(approval: approval)
                    }
                }
            }

            Section(String(localized: "project.run.resources", defaultValue: "Resources Used")) {
                if resourceReferences.isEmpty {
                    Text(String(localized: "project.run.resources.empty", defaultValue: "No project resources were used."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(resourceReferences, id: \.id) { reference in
                        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                            Text(reference.filename)
                            Text("v\(reference.version) · \(String(reference.contentHash.prefix(12)))")
                                .font(FamiliarTypography.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(String(localized: "project.run.skills", defaultValue: "Skills Used")) {
                if skillSnapshots.isEmpty {
                    Text(String(localized: "project.run.skills.empty", defaultValue: "No Skills were used."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(skillSnapshots) { skill in
                        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                            Text(skill.name)
                            Text("\(skill.stableID) · v\(skill.version) · \(String(skill.contentHash.prefix(12)))")
                                .font(FamiliarTypography.caption.monospaced()).foregroundStyle(.secondary)
                            if !skill.allowedTools.isEmpty {
                                Text(skill.allowedTools.joined(separator: ", "))
                                    .font(FamiliarTypography.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section(String(localized: "project.run.tools", defaultValue: "Available Tools")) {
                if toolNames.isEmpty {
                    Text(String(localized: "project.run.tools.empty", defaultValue: "No tools were exposed."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(toolNames, id: \.self) { toolName in
                        Label(toolName, systemImage: "wrench.and.screwdriver")
                    }
                }
            }
        }
        .navigationTitle(String(localized: "project.run", defaultValue: "Run"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var snapshot: FamiliarContextSnapshotRecord? { run.contextSnapshot }
    private var toolActivities: [FamiliarActivityRecord] {
        activities.filter { $0.kind == .tool }
    }
    private var providerName: String {
        guard let snapshot else { return String(localized: "common.unknown", defaultValue: "Unknown") }
        return FamiliarProviderCatalog.descriptor(for: snapshot.providerID)?.displayName ?? snapshot.providerID
    }
    private var modelName: String {
        guard let snapshot else { return String(localized: "common.unknown", defaultValue: "Unknown") }
        return FamiliarProviderCatalog.descriptor(for: snapshot.providerID)?.model(for: snapshot.modelID).displayName ?? snapshot.modelID
    }
    private var resourceReferences: [FamiliarContextResourceReference] {
        snapshot?.resourceReferences.sorted {
            $0.filename == $1.filename ? $0.version < $1.version : $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
        } ?? []
    }
    private var toolNames: [String] {
        guard let data = snapshot?.exposedToolNamesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded.sorted()
    }
    private var skillSnapshots: [FamiliarRunSkillSnapshotRecord] {
        allSkillSnapshots.filter { $0.runID == run.id }.sorted { $0.sequence < $1.sequence }
    }
    private var statusText: String {
        switch run.status {
        case .running: String(localized: "project.run.status.running", defaultValue: "Running")
        case .completed: String(localized: "project.run.status.completed", defaultValue: "Completed")
        case .cancelled: String(localized: "project.run.status.cancelled", defaultValue: "Cancelled")
        case .failed: String(localized: "project.run.status.failed", defaultValue: "Failed")
        }
    }
}

struct FamiliarRunRecordStep: View {
    let activity: FamiliarActivityRecord
    let invocation: FamiliarToolInvocationRecord?
    let approval: FamiliarApprovalRecord?
    let result: FamiliarToolResultRecord?

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
                LabeledContent(String(localized: "project.run.step.call_id", defaultValue: "Call ID"), value: activity.toolCallID ?? String(localized: "common.unknown", defaultValue: "Unknown"))
                LabeledContent(String(localized: "project.run.step.effect", defaultValue: "Effect"), value: activity.effect?.rawValue ?? FamiliarToolEffect.read.rawValue)
                LabeledContent(String(localized: "project.run.started", defaultValue: "Started")) {
                    Text(activity.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                }
                if let endedAt = activity.endedAt {
                    LabeledContent(String(localized: "project.run.finished", defaultValue: "Finished")) {
                        Text(endedAt, format: .dateTime.year().month().day().hour().minute().second())
                    }
                }
                if let invocation {
                    LabeledContent(String(localized: "project.run.step.invocation", defaultValue: "Invocation"), value: invocation.state.rawValue)
                    LabeledContent(String(localized: "project.run.step.arguments_hash", defaultValue: "Arguments hash")) {
                        Text(invocation.argumentsHash)
                            .font(FamiliarTypography.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                if let failureCode = activity.failureCode {
                    LabeledContent(String(localized: "project.run.step.failure_code", defaultValue: "Failure code"), value: failureCode)
                    if let retryable = activity.failureRetryable {
                        LabeledContent(String(localized: "project.run.step.retryable", defaultValue: "Retryable"), value: retryable ? String(localized: "common.yes", defaultValue: "Yes") : String(localized: "common.no", defaultValue: "No"))
                    }
                }
                if let detail = activity.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let approval {
                    Divider()
                    Label(authorizationSummary(approval), systemImage: "hand.raised")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let result {
                    Divider()
                    LabeledContent(String(localized: "project.run.step.payload", defaultValue: "Result payload"), value: result.payloadName)
                    LabeledContent(String(localized: "project.run.step.payload_hash", defaultValue: "Payload hash")) {
                        Text(result.payloadHash)
                            .font(FamiliarTypography.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    if let envelope = try? JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(result.envelopeJSON.utf8)) {
                        Text(envelope.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(FamiliarTypography.caption)
            .padding(.vertical, FamiliarSpacing.small)
        } label: {
            HStack(spacing: FamiliarSpacing.medium) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .frame(width: FamiliarIconSize.standard)
                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                    Text(activity.toolName.map { FamiliarToolPresentationName.title(for: $0) } ?? activity.summary)
                        .foregroundStyle(.primary)
                    Text(activity.phase.rawValue)
                        .font(FamiliarTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusSymbol: String {
        switch activity.phase {
        case .queued, .running: "circle.dotted"
        case .awaitingApproval: "hand.raised.fill"
        case .awaitingClarification: "questionmark.bubble"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .undone: "arrow.uturn.backward.circle.fill"
        }
    }

    private var statusColor: Color {
        switch activity.phase {
        case .succeeded: FamiliarTheme.success
        case .failed: FamiliarTheme.failure
        case .cancelled, .undone: .secondary
        default: FamiliarTheme.accent
        }
    }

    private func authorizationSummary(_ approval: FamiliarApprovalRecord) -> String {
        if approval.automaticAuthorization {
            return String(localized: "project.run.authorization.automatic", defaultValue: "Allowed by a remembered authorization")
        }
        guard approval.decision == .approved else {
            return String(localized: "project.run.authorization.cancelled", defaultValue: "Cancelled by the user")
        }
        return approval.scope?.rawValue ?? FamiliarApprovalScope.once.rawValue
    }
}

struct FamiliarRunRecordApproval: View {
    let approval: FamiliarApprovalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
            HStack {
                Label(FamiliarToolPresentationName.title(for: approval.toolName), systemImage: approval.automaticAuthorization ? "checkmark.shield.fill" : "hand.raised.fill")
                    .font(FamiliarTypography.sectionTitle)
                Spacer(minLength: 0)
                Text(decisionTitle)
                    .font(FamiliarTypography.caption.weight(.semibold))
                    .foregroundStyle(approval.decision == .approved ? FamiliarTheme.success : .secondary)
            }
            if let target = approval.target, !target.isEmpty {
                Text(target)
                    .font(FamiliarTypography.secondary)
                    .foregroundStyle(.secondary)
            }
            ForEach(fields) { field in
                LabeledContent(field.label, value: field.formattedValue)
                    .font(FamiliarTypography.caption)
            }
            LabeledContent(String(localized: "project.run.authorization.risk", defaultValue: "Risk"), value: approval.risk.rawValue)
                .font(FamiliarTypography.caption)
            LabeledContent(String(localized: "project.run.authorization.scope", defaultValue: "Scope"), value: approval.scope?.rawValue ?? "-")
                .font(FamiliarTypography.caption)
            LabeledContent(String(localized: "project.run.authorization.allowed", defaultValue: "Allowed choices"), value: allowedDurations.map(\.rawValue).joined(separator: ", "))
                .font(FamiliarTypography.caption)
            Text(approval.consequence)
                .font(FamiliarTypography.caption)
                .foregroundStyle(.secondary)
            Text(approval.requestedAt, format: .dateTime.year().month().day().hour().minute().second())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, FamiliarSpacing.xSmall)
    }

    private var fields: [FamiliarApprovalField] {
        (try? JSONDecoder().decode([FamiliarApprovalField].self, from: Data(approval.orderedFieldsJSON.utf8))) ?? []
    }

    private var allowedDurations: [FamiliarAuthorizationDuration] {
        (try? JSONDecoder().decode([FamiliarAuthorizationDuration].self, from: Data(approval.allowedAuthorizationDurationsJSON.utf8))) ?? []
    }

    private var decisionTitle: String {
        if approval.automaticAuthorization {
            return String(localized: "project.run.authorization.automatic.short", defaultValue: "Automatic")
        }
        return switch approval.decision {
        case .approved: String(localized: "approval.sent", defaultValue: "Approved")
        case .cancelled: String(localized: "settings.runs.cancelled", defaultValue: "Cancelled")
        case nil: String(localized: "agent.status.awaiting_confirmation", defaultValue: "Awaiting approval")
        }
    }
}
