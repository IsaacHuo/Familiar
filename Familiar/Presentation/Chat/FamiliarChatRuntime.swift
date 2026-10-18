import Observation
import SwiftData
import SwiftUI
import UIKit

struct FamiliarRuntimeCard: View {
    let activity: FamiliarRuntimeActivityGroup
    let disclosure: FamiliarRuntimeDisclosureState
    var context: FamiliarRunContextSummary? = nil
    var metrics: FamiliarReplyMetrics? = nil
    var undo: (() -> Void)? = nil
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @Environment(\.familiarChatScrollSession) private var scroll
    @State private var destination: FamiliarRuntimeSheetDestination?

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
            HStack(spacing: FamiliarSpacing.small) {
                Button {
                    FamiliarHaptics.shared.perform(.selection)
                    scroll?.beginInspection()
                    destination = .init(id: activity.id)
                } label: {
                    HStack(spacing: FamiliarSpacing.small) {
                        FamiliarRuntimeStatusIcon(status: activity.status)
                        Text(activity.status.isActive ? activity.activeTitle : activity.summary)
                            .font(FamiliarTypography.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: FamiliarSpacing.small)
                        Image(systemName: "chevron.right").font(FamiliarTypography.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("runtime.open.\(activity.id)")
                .accessibilityHint(String(localized: "runtime.ui.open_results", defaultValue: "Open tool results"))
                // Receipts fold into this row, so the row itself offers Undo while
                // the run's Undo is still executable.
                if let undo {
                    Button(String(localized: "common.undo"), action: undo)
                        .font(FamiliarTypography.caption)
                        .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                        .accessibilityIdentifier("runtime.undo.\(activity.id)")
                }
            }
        }
        .tint(.secondary)
        .sheet(item: $destination, onDismiss: { scroll?.endInspection() }) { _ in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: FamiliarSpacing.large) {
                        ForEach(activity.stages) { stage in
                            FamiliarRuntimeStageView(stage: stage, disclosure: disclosure)
                        }
                        NavigationLink {
                            FamiliarRuntimeDetail(activity: activity, context: context, metrics: metrics)
                        } label: {
                            Label(String(localized: "runtime.ui.technical_details"), systemImage: "info.circle")
                                .font(FamiliarTypography.secondary)
                                .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                        }
                        .accessibilityIdentifier("runtime.details")
                    }
                    .padding(FamiliarSpacing.large)
                }
                .navigationTitle(String(localized: "runtime.ui.results"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { FamiliarDismissButton() } }
                .accessibilityIdentifier("runtime.results")
            }
            .modifier(FamiliarSheetBrowser())
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .transaction { if reduceMotion { $0.animation = nil } }
        .onChange(of: activity.status) { old, new in
            guard old.isActive, !new.isActive else { return }
            if new == .completed { FamiliarHaptics.shared.perform(.success, event: activity.id + ":completed") }
            else if new == .failed || new == .warning { FamiliarHaptics.shared.perform(.warning, event: activity.id + ":warning") }
        }
    }
}

struct FamiliarRuntimeSheetDestination: Identifiable { let id: String }

struct FamiliarRuntimeDetail: View {
    let activity: FamiliarRuntimeActivityGroup
    let context: FamiliarRunContextSummary?
    let metrics: FamiliarReplyMetrics?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarSpacing.large) {
                if let context { FamiliarContextTrace(context: context, metrics: metrics) }
                ForEach(activity.activities) { surface in FamiliarRuntimeTechnicalDetails(surface: surface) }
                ForEach(activity.notices) { notice in
                    VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                        Text(notice.title).font(FamiliarTypography.caption.weight(.medium))
                        if let call = notice.toolCallID { Text(call).font(FamiliarTypography.caption.monospaced()) }
                        if let detail = notice.detail { Text(FamiliarRuntimeTechnicalText.redacted(detail)).textSelection(.enabled) }
                    }
                }
            }
            .font(FamiliarTypography.caption).foregroundStyle(.secondary)
            .padding(FamiliarSpacing.large)
        }
        .navigationTitle(String(localized: "runtime.ui.technical_details"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("runtime.detail")
    }
}

struct FamiliarRuntimeStageView: View {
    let stage: FamiliarRuntimeStage
    let disclosure: FamiliarRuntimeDisclosureState

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
            HStack(spacing: FamiliarSpacing.small) {
                FamiliarRuntimeStatusIcon(status: stage.status)
                Text(stage.kind.title).font(FamiliarTypography.secondary)
                Spacer(minLength: FamiliarSpacing.small)
                Text(statusTitle).font(FamiliarTypography.caption)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            Text(String(format: String(localized: "runtime.ui.call_count"), stage.activities.count))
                .font(FamiliarTypography.caption)
                .foregroundStyle(.tertiary)
            DisclosureGroup(isExpanded: disclosure.binding(for: "results:\(stage.id)")) {
                VStack(alignment: .leading, spacing: FamiliarSpacing.medium) {
                    if stage.kind == .search {
                        FamiliarRuntimeSourceResults(results: stage.searchResults)
                    } else {
                        ForEach(stage.activities) { surface in FamiliarRuntimeResult(surface: surface) }
                    }
                }
                .padding(.top, FamiliarSpacing.small)
            } label: {
                Text(String(localized: "runtime.ui.results"))
                    .font(FamiliarTypography.caption)
                    .frame(minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
            }
            .tint(.secondary)
        }
    }

    private var statusTitle: String {
        switch stage.status {
        case .running: String(localized: "runtime.ui.running")
        case .completed: String(localized: "runtime.ui.completed")
        case .warning: String(localized: "runtime.ui.partial_failure")
        case .failed: String(localized: "settings.runs.failed")
        case .waiting: String(localized: "runtime.ui.waiting")
        case .cancelled:
            String(localized: stage.activities.allSatisfy { $0.phase == .cancelled && $0.approvalDecision == .cancelled }
                ? "runtime.ui.skipped" : "runtime.ui.stopped")
        case .undone: String(localized: "common.undone")
        }
    }
}

struct FamiliarRuntimeStatusIcon: View {
    let status: FamiliarRuntimeDisplayStatus
    @Environment(\.familiarReduceMotion) private var reduceMotion
    var body: some View {
        Image(systemName: symbol)
            .font(FamiliarTypography.caption)
            .foregroundStyle(status == .failed ? FamiliarTheme.failure : status == .warning ? FamiliarTheme.warning : FamiliarTheme.inkSecondary)
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .symbolEffect(.breathe, isActive: status == .running && !reduceMotion)
            .animation(reduceMotion ? nil : FamiliarMotion.micro, value: status)
            .frame(width: FamiliarIconSize.standard, height: FamiliarIconSize.standard)
            .accessibilityHidden(true)
    }
    private var symbol: String {
        switch status {
        case .running: "circle.dotted"
        case .completed: "checkmark.circle"
        case .warning: "exclamationmark.circle"
        case .failed: "exclamationmark.triangle"
        case .waiting: "clock"
        case .cancelled: "pause.circle"
        case .undone: "arrow.uturn.backward.circle"
        }
    }
}

struct FamiliarRuntimeResult: View {
    let surface: FamiliarSurfaceDescriptor
    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
            if surface.phase == .failed || surface.phase == .cancelled {
                Label(surface.title, systemImage: surface.phase == .cancelled ? "pause.circle" : "exclamationmark.circle")
                    .font(FamiliarTypography.caption).foregroundStyle(.secondary)
            } else if case .searchResults(let search)? = surface.resultEnvelope?.presentation.content {
                Text(search.query).font(FamiliarTypography.caption).foregroundStyle(.secondary)
                FamiliarRuntimeSourceResults(results: search.results)
            } else {
                switch surface.resultEnvelope?.presentation.content {
                case .recordCollection: FamiliarRecordCollectionSurface(surface: surface)
                case .shellExecution:
                    Text(surface.title).font(FamiliarTypography.caption).foregroundStyle(.secondary)
                default: FamiliarTypedResult(surface: surface)
                }
                if surface.toolName == "web_fetch", surface.phase == .succeeded,
                   let call = surface.toolCallID, let envelope = surface.resultEnvelope,
                   let output = try? JSONDecoder().decode(FamiliarWebFetchOutput.self, from: Data(envelope.modelContent.utf8)) {
                    FamiliarWebCaptureSaveButton(runtimeID: surface.runID, toolCallID: call, truncated: output.truncated)
                }
            }
        }
    }
}

struct FamiliarRuntimeSourceResults: View {
    let results: [FamiliarToolPresentationPayload.SearchResult]
    var body: some View {
        ForEach(results, id: \.url) { result in
            if let url = URL(string: result.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                        Text(result.title).font(FamiliarTypography.caption)
                        Text(url.host ?? result.url).font(FamiliarTypography.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct FamiliarRuntimeTechnicalDetails: View {
    let surface: FamiliarSurfaceDescriptor
    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
            LabeledContent(String(localized: "runtime.ui.tool_name"), value: surface.toolName ?? surface.title)
            if let arguments = surface.argumentsJSON {
                Text(FamiliarRuntimeTechnicalText.redacted(arguments)).font(FamiliarTypography.caption.monospaced()).textSelection(.enabled)
            } else {
                Text(String(localized: "runtime.ui.parameters_unavailable")).foregroundStyle(.tertiary)
            }
            if case .document(let document)? = surface.resultEnvelope?.presentation.content, let url = document.url {
                Text(FamiliarRuntimeTechnicalText.redacted(url)).textSelection(.enabled)
            }
            if let code = surface.failureCode { Text(code).font(FamiliarTypography.caption.monospaced()).textSelection(.enabled) }
            if let detail = surface.detail, !detail.isEmpty {
                Text(FamiliarRuntimeTechnicalText.redacted(detail)).textSelection(.enabled)
            }
            if case .shellExecution = surface.resultEnvelope?.presentation.content {
                FamiliarShellExecutionSurface(surface: surface)
            }
        }
        .font(FamiliarTypography.caption)
        .foregroundStyle(.secondary)
    }
}

struct FamiliarTypedResult: View {
    let surface: FamiliarSurfaceDescriptor
    var readURLs: Set<String> = []
    var showsHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
            if showsHeader {
                HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                    Image(systemName: symbol).frame(width: FamiliarAISurfaceMetric.icon)
                    Text(surface.title).font(FamiliarTypography.caption.weight(.semibold))
                }
                .foregroundStyle(FamiliarTheme.inkSecondary)
            }
            if let content = surface.resultEnvelope?.presentation.content { contentView(content) }
            else if let detail = surface.detail { Text(detail).font(FamiliarTypography.caption).foregroundStyle(FamiliarTheme.inkSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func contentView(_ content: FamiliarToolPresentationPayload.Content) -> some View {
        switch content {
        case .scalar(let scalar):
            traceValue(label: scalar.label, value: scalar.value)
        case .searchResults(let search):
            let readCount = search.results.filter { readURLs.contains($0.url) }.count
            traceValue(label: String(localized: "search.activity.query", defaultValue: "Query"), value: search.query)
            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                FamiliarSourceStatusLabel(
                    title: String(format: String(localized: "search.activity.read_count", defaultValue: "%lld read"), readCount),
                    isRead: true
                )
                FamiliarSourceStatusLabel(
                    title: String(format: String(localized: "search.activity.discovered_count", defaultValue: "%lld discovered only"), search.results.count - readCount),
                    isRead: false
                )
            }
            .accessibilityElement(children: .combine)
            Text(String(format: String(localized: "search.activity.result_count", defaultValue: "%lld results"), search.results.count))
                .font(.caption2)
                .foregroundStyle(FamiliarTheme.inkTertiary)
        case .document(let document):
            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                if let title = document.title { Text(title).font(FamiliarTypography.caption.weight(.medium)).foregroundStyle(FamiliarTheme.ink) }
                Spacer(minLength: 0)
                FamiliarSourceStatusLabel(title: String(localized: "source.status.read", defaultValue: "Read"), isRead: true)
            }
            Text(document.text).font(.caption2).foregroundStyle(FamiliarTheme.inkSecondary).lineLimit(8).textSelection(.enabled)
        case .mutationReceipt(let receipt):
            traceValue(label: receipt.operation, value: receipt.targetIdentifier ?? receipt.summary)
        case .fileMutation(let file):
            traceValue(label: file.operation, value: file.title)
        case .recordCollection, .shellExecution:
            EmptyView()
        }
    }

    private func traceValue(label: String?, value: String) -> some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
            if let label { Text(label).font(.caption2.weight(.semibold)).foregroundStyle(FamiliarTheme.inkTertiary) }
            Text(value).font(FamiliarTypography.caption).foregroundStyle(FamiliarTheme.ink).textSelection(.enabled)
        }
    }

    private var symbol: String {
        switch surface.kind {
        case .search: "magnifyingglass"
        case .context: "text.magnifyingglass"
        case .records: "list.bullet.rectangle"
        case .mutationReceipt: "checkmark.seal"
        case .file: "doc.richtext"
        case .failure: "exclamationmark.triangle"
        case .toolSummary: "wrench.and.screwdriver"
        case .approval: "checklist.checked"
        case .runStatus: "sparkles"
        case .activityTrace: "waveform.path.ecg"
        case .clarification: "bubble.left.and.bubble.right"
        case .shell: "terminal"
        }
    }
}

struct FamiliarShellExecutionSurface: View {
    let surface: FamiliarSurfaceDescriptor

    var body: some View {
        if case .shellExecution(let shell) = surface.resultEnvelope?.presentation.content {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                    Image(systemName: "terminal")
                        .foregroundStyle(FamiliarTheme.accentInk)
                    Text(shell.summary)
                        .font(FamiliarTypography.secondary.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(shell.status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(shell.status == "succeeded" ? FamiliarTheme.success : FamiliarTheme.inkSecondary)
                }

                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                    Text(String(localized: "shell.command", defaultValue: "Command"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FamiliarTheme.inkTertiary)
                    Text(FamiliarRuntimeTechnicalText.redacted(shell.command))
                        .font(FamiliarTypography.caption.monospaced())
                        .foregroundStyle(FamiliarTheme.ink)
                        .textSelection(.enabled)
                    Text("\(shell.workingDirectory) · \(shell.networkEnabled ? String(localized: "shell.network.enabled", defaultValue: "Public Internet On") : String(localized: "shell.network.disabled", defaultValue: "Network Off"))")
                        .font(.caption2)
                        .foregroundStyle(FamiliarTheme.inkTertiary)
                }

                if !shell.standardOutput.isEmpty {
                    output(shell.standardOutput, color: FamiliarTheme.ink)
                }
                if !shell.standardError.isEmpty {
                    output(shell.standardError, color: FamiliarTheme.failure)
                }
                if shell.outputWasTruncated {
                    Label(String(localized: "shell.output.truncated", defaultValue: "Output was truncated at the safety limit."), systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(FamiliarTheme.inkSecondary)
                }

                let diffCount = shell.addedFiles.count + shell.modifiedFiles.count + shell.removedFiles.count
                if diffCount > 0 {
                    Text(String(
                        format: String(localized: "shell.diff.summary", defaultValue: "%lld added · %lld modified · %lld removed"),
                        shell.addedFiles.count,
                        shell.modifiedFiles.count,
                        shell.removedFiles.count
                    ))
                    .font(FamiliarTypography.caption)
                    .foregroundStyle(FamiliarTheme.inkSecondary)
                }
            }
            .padding(FamiliarAISurfaceMetric.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FamiliarTheme.inset, in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    private func output(_ value: String, color: Color) -> some View {
        ScrollView(.horizontal) {
            Text(FamiliarRuntimeTechnicalText.redacted(outputTail(value)))
                .font(.caption2.monospaced())
                .foregroundStyle(color)
                .textSelection(.enabled)
                .padding(FamiliarAISurfaceMetric.spaceS)
        }
        .background(FamiliarTheme.field, in: RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous))
    }

    private func outputTail(_ value: String) -> String {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(20).joined(separator: "\n")
    }
}
