import Foundation
import SwiftUI

struct FamiliarToolChips: View {
    let surfaces: [FamiliarSurfaceDescriptor]
    let status: FamiliarSurfaceDescriptor?
    let reasoningSummary: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen = true
    @State private var openRows: Set<String> = []
    @State private var previewedDiffID: String?
    @State private var showsAllDiffs = false
    @State private var diffsVisible = false

    init(
        surfaces: [FamiliarSurfaceDescriptor],
        status: FamiliarSurfaceDescriptor? = nil,
        reasoningSummary: String? = nil
    ) {
        self.surfaces = surfaces
        self.status = status
        self.reasoningSummary = reasoningSummary
    }

    private var toolItems: [FamiliarToolChipItem] {
        FamiliarToolChipProjection.items(from: surfaces)
    }

    private var rows: [FamiliarToolChipItem] {
        guard let status else { return toolItems }
        return [FamiliarToolChipProjection.thinkingItem(
            status: status,
            reasoningSummary: reasoningSummary
        )] + toolItems
    }

    private var diffs: [FamiliarToolDiffChip] {
        toolItems.compactMap(\.diff)
    }

    private var messageCount: Int {
        max(1, Set(toolItems.compactMap(\.assistantTurnID)).count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isOpen {
                VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        FamiliarToolChipRow(
                            item: item,
                            index: index,
                            isOpen: openRows.contains(item.id),
                            onToggle: { toggleRow(item.id) }
                        )
                    }

                    if diffsVisible, !diffs.isEmpty {
                        diffChips
                            .transition(.opacity)
                    }
                }
                .padding(.top, FamiliarAISurfaceMetric.spaceXS)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .animation(reduceMotion ? nil : FamiliarMotion.state, value: isOpen)
        .task(id: diffs.count) {
            guard !diffs.isEmpty, !diffsVisible else { return }
            if !reduceMotion {
                try? await Task.sleep(
                    for: .milliseconds(min(rows.count * 80, 400))
                )
            }
            withAnimation(reduceMotion ? nil : FamiliarMotion.reveal) {
                diffsVisible = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tool-chips")
    }

    private var header: some View {
        Button {
            withAnimation(reduceMotion ? nil : FamiliarMotion.state) {
                isOpen.toggle()
                if !isOpen { previewedDiffID = nil }
            }
        } label: {
            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 0 : -90))
                Text(
                    String(
                        format: String(
                            localized: "tool_chips.header",
                            defaultValue: "%1$lld tool calls, %2$lld messages"
                        ),
                        toolItems.count,
                        messageCount
                    )
                )
                .font(.caption.weight(.medium))
                .monospacedDigit()
            }
            .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
            .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
            .contentShape(RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            isOpen
                ? String(localized: "common.expanded", defaultValue: "Expanded")
                : String(localized: "common.collapsed", defaultValue: "Collapsed")
        )
    }

    private var diffChips: some View {
        let shown = showsAllDiffs ? diffs : Array(diffs.prefix(3))
        return FamiliarToolChipFlowLayout(spacing: FamiliarAISurfaceMetric.spaceS) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, diff in
                    FamiliarToolDiffChipButton(
                        diff: diff,
                        index: index,
                        isPreviewed: previewedDiffID == diff.id,
                        onPreviewChange: { visible in
                            withAnimation(reduceMotion ? nil : FamiliarMotion.micro) {
                                previewedDiffID = visible ? diff.id : nil
                            }
                        }
                    )
                }

                if !showsAllDiffs, diffs.count > shown.count {
                    Button {
                        withAnimation(reduceMotion ? nil : FamiliarMotion.state) {
                            showsAllDiffs = true
                        }
                    } label: {
                        Text(
                            String(
                                format: String(
                                    localized: "tool_chips.more_diffs",
                                    defaultValue: "+%lld more"
                                ),
                                diffs.count - shown.count
                            )
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                        .underline()
                        .frame(minHeight: 28)
                    }
                    .buttonStyle(.plain)
                }
        }
        .padding(.top, FamiliarAISurfaceMetric.spaceM)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FamiliarAISurfaceColor.line)
                .frame(height: FamiliarAISurfaceMetric.hairline)
        }
        .overlay(alignment: .topLeading) {
            if let previewedDiff {
                FamiliarToolDiffPreview(diff: previewedDiff)
                    .offset(y: 44)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                    .zIndex(10)
            }
        }
        .padding(.top, FamiliarAISurfaceMetric.spaceS)
        .zIndex(previewedDiffID == nil ? 0 : 10)
    }

    private var previewedDiff: FamiliarToolDiffChip? {
        guard let previewedDiffID else { return nil }
        return diffs.first { $0.id == previewedDiffID }
    }

    private func toggleRow(_ id: String) {
        withAnimation(reduceMotion ? nil : FamiliarMotion.state) {
            if openRows.contains(id) {
                openRows.remove(id)
            } else {
                openRows.insert(id)
            }
        }
    }
}

private struct FamiliarToolChipRow: View {
    let item: FamiliarToolChipItem
    let index: Int
    let isOpen: Bool
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isVisible = false

    private var showsChevron: Bool { isOpen || isHovered }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                    leadingIcon
                    Text(item.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FamiliarAISurfaceColor.ink)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(item.chip)
                        .font(item.isMonospaced ? .caption2.monospaced() : .caption2)
                        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .background(
                            FamiliarAISurfaceColor.field,
                            in: RoundedRectangle(
                                cornerRadius: FamiliarAISurfaceRadius.chip,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: FamiliarAISurfaceRadius.chip,
                                style: .continuous
                            )
                            .stroke(
                                FamiliarAISurfaceColor.line,
                                lineWidth: FamiliarAISurfaceMetric.hairline
                            )
                        }
                }
                .padding(.horizontal, FamiliarAISurfaceMetric.spaceXS)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: FamiliarAISurfaceRadius.control,
                        style: .continuous
                    )
                )
                .background(
                    isHovered ? FamiliarAISurfaceColor.hover : Color.clear,
                    in: RoundedRectangle(
                        cornerRadius: FamiliarAISurfaceRadius.control,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel("\(item.label), \(item.chip)")
            .accessibilityValue(
                isOpen
                    ? String(localized: "common.expanded", defaultValue: "Expanded")
                    : String(localized: "common.collapsed", defaultValue: "Collapsed")
            )

            if isOpen {
                HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceM) {
                    Rectangle()
                        .fill(FamiliarAISurfaceColor.line)
                        .frame(width: FamiliarAISurfaceMetric.hairline)
                    VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                        ForEach(item.details) { detail in
                            Text(detail.text)
                                .font(item.detailIsMonospaced ? .caption2.monospaced() : .caption2)
                                .foregroundStyle(detail.color)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
                }
                .padding(.leading, FamiliarAISurfaceMetric.spaceS)
                .padding(.bottom, FamiliarAISurfaceMetric.spaceXS)
                .transition(.opacity)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .animation(
            reduceMotion ? nil : FamiliarMotion.reveal.delay(min(Double(index) * 0.08, 0.4)),
            value: isVisible
        )
        .onAppear { isVisible = true }
    }

    private var leadingIcon: some View {
        ZStack {
            Image(systemName: item.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(item.iconColor)
                .opacity(showsChevron ? 0 : 1)
                .scaleEffect(showsChevron ? 0.25 : 1)
                .blur(radius: showsChevron ? 4 : 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                .rotationEffect(.degrees(isOpen ? 0 : -90))
                .opacity(showsChevron ? 1 : 0)
                .scaleEffect(showsChevron ? 1 : 0.25)
                .blur(radius: showsChevron ? 0 : 4)
        }
        .frame(width: 16, height: 16)
        .animation(reduceMotion ? nil : FamiliarMotion.micro, value: showsChevron)
        .animation(reduceMotion ? nil : FamiliarMotion.micro, value: isOpen)
    }
}

private struct FamiliarToolDiffChipButton: View {
    let diff: FamiliarToolDiffChip
    let index: Int
    let isPreviewed: Bool
    let onPreviewChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        Button {
            onPreviewChange(!isPreviewed)
        } label: {
            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                Text(diff.title)
                    .foregroundStyle(FamiliarAISurfaceColor.ink)
                    .lineLimit(1)
                Text("+\(diff.additions)")
                    .foregroundStyle(FamiliarAISurfaceColor.success)
                    .monospacedDigit()
                if diff.deletions > 0 {
                    Text("−\(diff.deletions)")
                        .foregroundStyle(FamiliarAISurfaceColor.failure)
                        .monospacedDigit()
                }
            }
            .font(.caption2.monospaced())
            .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
            .frame(maxWidth: 240, minHeight: 28)
            .background(FamiliarAISurfaceColor.surface, in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.chip, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.chip, style: .continuous))
        }
        .buttonStyle(FamiliarToolChipPressStyle())
        .onHover(perform: onPreviewChange)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(reduceMotion || isVisible ? 1 : 0.96)
        .animation(
            reduceMotion ? nil : FamiliarMotion.reveal.delay(min(Double(index) * 0.08, 0.3)),
            value: isVisible
        )
        .onAppear { isVisible = true }
        .accessibilityLabel(
            String(
                format: String(
                    localized: "tool_chips.diff.accessibility",
                    defaultValue: "%1$@, %2$lld additions, %3$lld deletions"
                ),
                diff.title,
                diff.additions,
                diff.deletions
            )
        )
        .accessibilityValue(
            isPreviewed
                ? String(localized: "common.expanded", defaultValue: "Expanded")
                : String(localized: "common.collapsed", defaultValue: "Collapsed")
        )
    }
}

private struct FamiliarToolDiffPreview: View {
    let diff: FamiliarToolDiffChip

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                Text(diff.title)
                    .lineLimit(1)
                    .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                Spacer(minLength: 0)
                Text("+\(diff.additions)")
                    .foregroundStyle(FamiliarAISurfaceColor.success)
                if diff.deletions > 0 {
                    Text("−\(diff.deletions)")
                        .foregroundStyle(FamiliarAISurfaceColor.failure)
                }
            }
            .font(.caption2.monospaced())
            .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
            .frame(minHeight: 32)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FamiliarAISurfaceColor.line)
                    .frame(height: FamiliarAISurfaceMetric.hairline)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(diff.previewLines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: FamiliarAISurfaceMetric.spaceS) {
                        Text(line.tone.marker)
                            .frame(width: 12, alignment: .leading)
                            .foregroundStyle(line.tone.color)
                        Text(line.text)
                            .lineLimit(1)
                            .foregroundStyle(line.tone.color)
                    }
                    .font(.caption2.monospaced())
                    .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .background(line.tone.background)
                }
            }
            .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
        }
        .frame(width: 288)
        .background(FamiliarAISurfaceColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.card, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }
}

private struct FamiliarToolChipPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(FamiliarMotion.micro, value: configuration.isPressed)
    }
}

private struct FamiliarToolChipFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct FamiliarToolChipItem: Identifiable {
    let id: String
    let assistantTurnID: String?
    let label: String
    let chip: String
    let details: [FamiliarToolChipDetail]
    let symbol: String
    let phase: FamiliarSurfacePhase
    let isMonospaced: Bool
    let detailIsMonospaced: Bool
    let startedAt: Date?
    let diff: FamiliarToolDiffChip?

    var iconColor: Color {
        switch phase {
        case .failed: FamiliarAISurfaceColor.failure
        case .cancelled, .undone: FamiliarAISurfaceColor.inkTertiary
        case .queued, .planning, .running, .awaitingApproval, .awaitingClarification:
            FamiliarAISurfaceColor.accent
        case .succeeded: FamiliarAISurfaceColor.inkTertiary
        }
    }
}

private struct FamiliarToolChipDetail: Identifiable {
    enum Tone {
        case normal
        case add
        case delete
    }

    let id: String
    let text: String
    let tone: Tone

    var color: Color {
        switch tone {
        case .normal: FamiliarAISurfaceColor.inkSecondary
        case .add: FamiliarAISurfaceColor.success
        case .delete: FamiliarAISurfaceColor.failure
        }
    }
}

private struct FamiliarToolDiffChip: Identifiable {
    let id: String
    let title: String
    let additions: Int
    let deletions: Int
    let previewLines: [FamiliarToolDiffLine]
}

private struct FamiliarToolDiffLine: Identifiable {
    enum Tone {
        case add
        case delete
        case context

        var marker: String {
            switch self {
            case .add: "+"
            case .delete: "−"
            case .context: " "
            }
        }

        var color: Color {
            switch self {
            case .add: FamiliarAISurfaceColor.success
            case .delete: FamiliarAISurfaceColor.failure
            case .context: FamiliarAISurfaceColor.inkSecondary
            }
        }

        var background: Color {
            switch self {
            case .add: FamiliarAISurfaceColor.successTint
            case .delete: FamiliarAISurfaceColor.failureTint
            case .context: Color.clear
            }
        }
    }

    let id: String
    let text: String
    let tone: Tone
}

private enum FamiliarToolChipProjection {
    static func items(from surfaces: [FamiliarSurfaceDescriptor]) -> [FamiliarToolChipItem] {
        let eligible = surfaces.filter {
            $0.toolCallID != nil
                && $0.toolName != nil
                && $0.kind != .runStatus
                && $0.kind != .activityTrace
        }
        let grouped = Dictionary(grouping: eligible) {
            $0.runID + ":" + ($0.toolCallID ?? $0.id)
        }

        return grouped.compactMap { id, group in
            guard let surface = group.max(by: { score($0) < score($1) }),
                  let toolName = surface.toolName
            else { return nil }
            let content = surface.resultEnvelope?.presentation.content
            return FamiliarToolChipItem(
                id: id,
                assistantTurnID: surface.assistantTurnID,
                label: FamiliarToolPresentationName.title(for: toolName),
                chip: chipText(surface: surface, content: content),
                details: detailLines(surface: surface, content: content),
                symbol: FamiliarToolPresentationName.symbol(for: toolName, effect: surface.effect),
                phase: phase(from: group),
                isMonospaced: isMonospaced(toolName: toolName, content: content),
                detailIsMonospaced: isMonospaced(toolName: toolName, content: content),
                startedAt: group.compactMap(\.startedAt).min(),
                diff: diffChip(id: id, content: content)
            )
        }
        .sorted {
            let lhsDate = $0.startedAt ?? .distantPast
            let rhsDate = $1.startedAt ?? .distantPast
            return lhsDate == rhsDate ? $0.id < $1.id : lhsDate < rhsDate
        }
    }

    static func thinkingItem(
        status: FamiliarSurfaceDescriptor,
        reasoningSummary: String?
    ) -> FamiliarToolChipItem {
        let reasoningLines = reasoningSummary.map { nonEmptyLines($0) } ?? []
        let chip = reasoningLines.first.map(String.init)
            ?? status.detail
            ?? status.title
        let details: [FamiliarToolChipDetail]
        if reasoningLines.isEmpty {
            details = [
                .init(
                    id: status.id + ":thinking",
                    text: phaseTitle(status.phase),
                    tone: .normal
                )
            ]
        } else {
            details = Array(reasoningLines.prefix(4).enumerated()).map { index, line in
                .init(
                    id: status.id + ":thinking:\(index)",
                    text: bounded(String(line), limit: 220),
                    tone: .normal
                )
            }
        }
        return FamiliarToolChipItem(
            id: status.runID + ":thinking",
            assistantTurnID: status.assistantTurnID,
            label: String(localized: "agent.status.thinking"),
            chip: bounded(chip),
            details: details,
            symbol: "sparkles",
            phase: status.phase,
            isMonospaced: false,
            detailIsMonospaced: false,
            startedAt: status.startedAt,
            diff: nil
        )
    }

    private static func score(_ surface: FamiliarSurfaceDescriptor) -> Int {
        var value = surface.resultEnvelope == nil ? 0 : 100
        if surface.phase.isTerminal { value += 20 }
        if surface.kind == .failure { value += 10 }
        return value
    }

    private static func phase(from surfaces: [FamiliarSurfaceDescriptor]) -> FamiliarSurfacePhase {
        if surfaces.contains(where: { $0.phase == .failed }) { return .failed }
        if surfaces.contains(where: { $0.phase == .cancelled }) { return .cancelled }
        if surfaces.contains(where: { $0.phase == .undone }) { return .undone }
        if surfaces.contains(where: { !$0.phase.isTerminal }) {
            return surfaces.first(where: { !$0.phase.isTerminal })?.phase ?? .running
        }
        return .succeeded
    }

    private static func chipText(
        surface: FamiliarSurfaceDescriptor,
        content: FamiliarToolPresentationPayload.Content?
    ) -> String {
        guard let content else {
            return bounded(
                surface.approvalTarget
                    ?? (surface.kind == .clarification ? surface.title : nil)
                    ?? surface.detail
                    ?? surface.toolName
                    ?? surface.title
            )
        }
        switch content {
        case .scalar(let value): return bounded(value.value)
        case .searchResults(let value): return bounded(value.query)
        case .document(let value): return bounded(value.title ?? value.url ?? value.summary)
        case .contextMatches(let value): return bounded(value.query)
        case .recordCollection(let value): return bounded(value.recordType)
        case .mutationReceipt(let value): return bounded(value.targetIdentifier ?? value.summary)
        case .artifactMutation(let value): return bounded(value.title)
        case .diff(let value): return bounded(value.summary)
        case .taskList(let value): return bounded(value.title)
        case .recommendation(let value): return bounded(value.title)
        case .insight(let value): return bounded(value.title)
        case .code(let value): return bounded(value.filename ?? value.language ?? value.summary)
        case .shareDraft(let value): return bounded(value.title ?? value.summary)
        case .shellExecution(let value): return bounded(value.command)
        }
    }

    private static func detailLines(
        surface: FamiliarSurfaceDescriptor,
        content: FamiliarToolPresentationPayload.Content?
    ) -> [FamiliarToolChipDetail] {
        var values: [(String, FamiliarToolChipDetail.Tone)] = []
        if let detail = surface.detail, !detail.isEmpty {
            values.append((detail, surface.phase == .failed ? .delete : .normal))
        }

        if surface.kind == .approval {
            values += surface.approvalFields.prefix(3).map {
                ("\($0.label): \($0.formattedValue)", .normal)
            }
            if let consequence = surface.approvalConsequence, !consequence.isEmpty {
                values.append((consequence, .normal))
            }
        } else if surface.kind == .clarification {
            values += surface.clarificationOptions.prefix(3).map { ($0.label, .normal) }
            if let answer = surface.clarificationResolution?.answer, !answer.isEmpty {
                values.append((answer, .normal))
            }
        }

        if let content {
            switch content {
            case .scalar(let value):
                values.append((value.label.map { "\($0): \(value.value)" } ?? value.value, .normal))
            case .searchResults(let value):
                values += value.results.prefix(2).map { ($0.title, .normal) }
            case .document(let value):
                values += nonEmptyLines(value.text).prefix(2).map { (String($0), .normal) }
            case .contextMatches(let value):
                values += value.matches.prefix(2).map { ($0.title, .normal) }
            case .recordCollection(let value):
                values.append((value.summary, .normal))
                values += value.records.prefix(2).map { ($0.id, .normal) }
            case .mutationReceipt(let value):
                values.append((value.summary, value.succeeded ? .add : .delete))
            case .artifactMutation(let value):
                values.append(("\(value.operation) · \(ByteCountFormatter.string(fromByteCount: value.byteSize, countStyle: .file))", .add))
            case .diff(let value):
                let diff = lineDiff(before: value.before, after: value.after)
                values.append(("+\(diff.additions)  −\(diff.deletions)", .normal))
            case .taskList(let value):
                values += value.tasks.prefix(3).map { ("\(taskStatusTitle($0.status)) · \($0.title)", .normal) }
            case .recommendation(let value):
                values.append((value.explanation, .normal))
            case .insight(let value):
                values.append((value.explanation, .normal))
            case .code(let value):
                values += nonEmptyLines(value.code).prefix(2).map { (String($0), .add) }
            case .shareDraft(let value):
                values += nonEmptyLines(value.text).prefix(2).map { (String($0), .normal) }
            case .shellExecution(let value):
                values.append(("\(value.runtime) · \(value.status)", value.status == "succeeded" ? .add : .normal))
                values += nonEmptyLines(value.standardOutput).suffix(2).map { (String($0), .normal) }
                values += nonEmptyLines(value.standardError).suffix(1).map { (String($0), .delete) }
            }
        }

        if values.isEmpty {
            values.append((phaseTitle(surface.phase), .normal))
        }
        return Array(values.prefix(4).enumerated()).map { index, value in
            FamiliarToolChipDetail(
                id: "\(surface.id):\(index)",
                text: bounded(value.0, limit: 220),
                tone: value.1
            )
        }
    }

    private static func diffChip(
        id: String,
        content: FamiliarToolPresentationPayload.Content?
    ) -> FamiliarToolDiffChip? {
        guard case .diff(let diff)? = content else { return nil }
        let result = lineDiff(before: diff.before, after: diff.after)
        return FamiliarToolDiffChip(
            id: id,
            title: diff.summary,
            additions: result.additions,
            deletions: result.deletions,
            previewLines: result.lines
        )
    }

    private static func lineDiff(before: String, after: String) -> (
        additions: Int,
        deletions: Int,
        lines: [FamiliarToolDiffLine]
    ) {
        let beforeLines = before.components(separatedBy: .newlines)
        let afterLines = after.components(separatedBy: .newlines)
        let difference = afterLines.difference(from: beforeLines)
        var additions: [(Int, String)] = []
        var deletions: [(Int, String)] = []
        for change in difference {
            switch change {
            case .insert(let offset, let element, _): additions.append((offset, element))
            case .remove(let offset, let element, _): deletions.append((offset, element))
            }
        }
        additions.sort { $0.0 < $1.0 }
        deletions.sort { $0.0 < $1.0 }

        var preview: [FamiliarToolDiffLine] = []
        let firstOffset = min(additions.first?.0 ?? .max, deletions.first?.0 ?? .max)
        if firstOffset != .max, firstOffset > 0, firstOffset - 1 < beforeLines.count {
            preview.append(.init(
                id: "context:\(firstOffset - 1)",
                text: beforeLines[firstOffset - 1],
                tone: .context
            ))
        }
        preview += deletions.prefix(3).map {
            .init(id: "delete:\($0.0):\($0.1)", text: $0.1, tone: .delete)
        }
        preview += additions.prefix(max(0, 5 - preview.count)).map {
            .init(id: "add:\($0.0):\($0.1)", text: $0.1, tone: .add)
        }
        if preview.isEmpty, let first = afterLines.first {
            preview.append(.init(id: "context:0", text: first, tone: .context))
        }
        return (additions.count, deletions.count, preview)
    }

    /// Monospacing is decided by tool family prefix, which is stable across new
    /// tools in the same family, unlike the removed symbol heuristic.
    private static func isMonospaced(
        toolName: String,
        content: FamiliarToolPresentationPayload.Content?
    ) -> Bool {
        if toolName.contains("workspace")
            || toolName.contains("resource")
            || toolName.contains("artifact")
            || toolName.contains("shell") {
            return true
        }
        if case .code? = content { return true }
        if case .diff? = content { return true }
        return false
    }

    private static func phaseTitle(_ phase: FamiliarSurfacePhase) -> String {
        switch phase {
        case .queued: String(localized: "tool_chips.phase.queued", defaultValue: "Queued")
        case .planning: String(localized: "tool_chips.phase.planning", defaultValue: "Planning")
        case .running: String(localized: "tool_chips.phase.running", defaultValue: "Running")
        case .awaitingApproval: String(localized: "agent.status.awaiting_confirmation")
        case .awaitingClarification: String(localized: "clarification.awaiting", defaultValue: "Waiting for your answer")
        case .succeeded: String(localized: "tool_chips.phase.succeeded", defaultValue: "Completed")
        case .failed: String(localized: "settings.runs.failed", defaultValue: "Failed")
        case .cancelled: String(localized: "settings.runs.cancelled", defaultValue: "Cancelled")
        case .undone: String(localized: "tool.undone", defaultValue: "Undone")
        }
    }

    private static func taskStatusTitle(
        _ status: FamiliarToolPresentationPayload.TaskStatus
    ) -> String {
        switch status {
        case .pending: String(localized: "task.status.pending", defaultValue: "Pending")
        case .running: String(localized: "task.status.running", defaultValue: "Running")
        case .completed: String(localized: "task.status.completed", defaultValue: "Completed")
        case .failed: String(localized: "task.status.failed", defaultValue: "Failed")
        }
    }

    private static func nonEmptyLines(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isNewline).filter {
            !String($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func bounded(_ value: String, limit: Int = 120) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "…"
    }
}
