import SwiftUI

struct FamiliarApprovalCard: View {
    let surface: FamiliarSurfaceDescriptor
    let onResolve: (UUID, FamiliarToolConfirmationDecision) -> Void

    @AccessibilityFocusState private var isAccessibilityFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDecision: FamiliarToolConfirmationDecision
    @State private var submittedDecision: FamiliarToolConfirmationDecision?

    init(
        surface: FamiliarSurfaceDescriptor,
        onResolve: @escaping (UUID, FamiliarToolConfirmationDecision) -> Void
    ) {
        self.surface = surface
        self.onResolve = onResolve
        _selectedDecision = State(initialValue: Self.defaultDecision(for: surface))
    }

    var body: some View {
        Group {
            if let submittedDecision {
                submittedState(submittedDecision)
            } else if surface.approvalRequestID == nil {
                interruptedState
            } else {
                approvalCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityFocused($isAccessibilityFocused)
        .onAppear { isAccessibilityFocused = true }
    }

    private var interruptedState: some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
            Text(surface.detail ?? String(localized: "approval.interrupted", defaultValue: "This approval was interrupted and can no longer be answered."))
                .font(.subheadline)
                .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
        }
        .frame(minHeight: FamiliarControlSize.minimumHitTarget)
        .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
        .background(FamiliarAISurfaceColor.inset, in: Capsule())
        .accessibilityIdentifier("approval.interrupted")
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceL) {
            heading
            approvalFields
            policySummary
            authorizationScope
            actions
        }
        .padding(FamiliarAISurfaceMetric.spaceL)
        .background(
            FamiliarAISurfaceColor.surface,
            in: RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous)
                .stroke(FamiliarAISurfaceColor.line, lineWidth: FamiliarAISurfaceMetric.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("approval.card")
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceM) {
            Image(systemName: riskSymbol)
                .font(.system(size: FamiliarIconSize.standard, weight: .semibold))
                .foregroundStyle(riskColor)
                .frame(width: FamiliarControlSize.compactVisual, height: FamiliarControlSize.compactVisual)
                .background(riskColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                Text(surface.title)
                    .font(.headline)
                    .foregroundStyle(FamiliarAISurfaceColor.ink)
                if let target = surface.approvalTarget, !target.isEmpty {
                    Text(target)
                        .font(.subheadline)
                        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var approvalFields: some View {
        if !surface.approvalFields.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(surface.approvalFields.enumerated()), id: \.element.id) { index, field in
                    if index > 0 {
                        Divider()
                    }
                    LabeledContent {
                        Text(field.formattedValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FamiliarAISurfaceColor.ink)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    } label: {
                        Text(field.label)
                            .font(.subheadline)
                            .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                    }
                    .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
                    .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                }
            }
            .background(
                FamiliarAISurfaceColor.inset,
                in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.control, style: .continuous)
            )
        }
    }

    private var policySummary: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
            Label(riskTitle, systemImage: riskSymbol)
            if let consequence = surface.approvalConsequence, !consequence.isEmpty {
                Label(consequence, systemImage: "exclamationmark.circle")
            }
            if let undoPolicy = surface.approvalUndoPolicy {
                Label(undoTitle(undoPolicy), systemImage: undoPolicy == .unavailable ? "arrow.uturn.backward.slash" : "arrow.uturn.backward")
            }
        }
        .font(.caption)
        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var authorizationScope: some View {
        if authorizationOptions.count > 1 {
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceS) {
                Text(String(localized: "approval.scope.question", defaultValue: "How long should Familiar allow this action?"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                VStack(spacing: FamiliarAISurfaceMetric.spaceXS) {
                    ForEach(authorizationOptions) { option in
                        Button {
                            withAnimation(reduceMotion ? nil : FamiliarMotion.micro) {
                                selectedDecision = option.decision
                            }
                        } label: {
                            HStack(spacing: FamiliarAISurfaceMetric.spaceM) {
                                Image(systemName: selectedDecision == option.decision ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedDecision == option.decision ? FamiliarAISurfaceColor.accent : FamiliarAISurfaceColor.inkTertiary)
                                Text(option.title)
                                    .font(.subheadline)
                                    .foregroundStyle(FamiliarAISurfaceColor.ink)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
                            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                            .contentShape(Rectangle())
                            .background(
                                selectedDecision == option.decision ? FamiliarAISurfaceColor.accentTint : Color.clear,
                                in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.control, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedDecision == option.decision ? .isSelected : [])
                        .accessibilityIdentifier("approval.scope.\(option.id)")
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceM) {
            Button(String(localized: "common.cancel")) {
                resolve(.cancelled)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(minHeight: FamiliarControlSize.minimumHitTarget)

            Button(String(localized: "approval.approve", defaultValue: "Approve")) {
                resolve(selectedDecision)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(FamiliarAISurfaceColor.accent)
            .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget)
            .accessibilityIdentifier("approval.confirm")
        }
    }

    private func submittedState(_ decision: FamiliarToolConfirmationDecision) -> some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
            Image(systemName: decision == .cancelled ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(decision == .cancelled ? FamiliarAISurfaceColor.inkTertiary : FamiliarAISurfaceColor.success)
            Text(decision == .cancelled
                 ? String(localized: "approval.skipped", defaultValue: "Approval cancelled")
                 : String(localized: "approval.sent", defaultValue: "Approved"))
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
        .frame(minHeight: FamiliarControlSize.minimumHitTarget)
        .transition(.opacity)
        .accessibilityIdentifier("approval.sent")
    }

    private var authorizationOptions: [FamiliarApprovalOption] {
        let all: [FamiliarApprovalOption] = [
            .init(id: "once", title: String(localized: "authorization.once", defaultValue: "Only Once"), decision: .confirmedOnce),
            .init(id: "session", title: String(localized: "authorization.session", defaultValue: "Allow This Session"), decision: .confirmed),
            .init(id: "always", title: String(localized: "authorization.always", defaultValue: "Always Allow"), decision: .confirmedAlways)
        ]
        return all.filter { option in
            guard let duration = option.decision.authorizationDuration else { return false }
            return surface.approvalAllowedAuthorizationDurations.contains(duration)
        }
    }

    private var riskSymbol: String {
        switch surface.approvalRisk {
        case .high: "exclamationmark.triangle.fill"
        case .sensitive: "hand.raised.fill"
        case .low, nil: "checkmark.shield.fill"
        }
    }

    private var riskColor: Color {
        switch surface.approvalRisk {
        case .high: FamiliarAISurfaceColor.failure
        case .sensitive: FamiliarAISurfaceColor.warning
        case .low, nil: FamiliarAISurfaceColor.accent
        }
    }

    private var riskTitle: String {
        switch surface.approvalRisk {
        case .high: String(localized: "approval.risk.high", defaultValue: "High-risk action")
        case .sensitive: String(localized: "approval.risk.sensitive", defaultValue: "Uses sensitive data")
        case .low, nil: String(localized: "approval.risk.low", defaultValue: "Low-risk action")
        }
    }

    private func undoTitle(_ policy: FamiliarApprovalUndoPolicy) -> String {
        switch policy {
        case .durable: String(localized: "approval.undo.durable", defaultValue: "Can be undone after the app restarts")
        case .currentSession: String(localized: "approval.undo.session", defaultValue: "Can be undone during this session")
        case .unavailable: String(localized: "approval.undo.unavailable", defaultValue: "This action cannot be undone")
        }
    }

    private func resolve(_ decision: FamiliarToolConfirmationDecision) {
        guard let id = surface.approvalRequestID else { return }
        withAnimation(reduceMotion ? nil : FamiliarMotion.state) {
            submittedDecision = decision
        }
        onResolve(id, decision)
    }

    private static func defaultDecision(for surface: FamiliarSurfaceDescriptor) -> FamiliarToolConfirmationDecision {
        if surface.approvalAllowedAuthorizationDurations.contains(.once) {
            return .confirmedOnce
        }
        if surface.approvalAllowedAuthorizationDurations.contains(.session) {
            return .confirmed
        }
        return .confirmedAlways
    }
}

private struct FamiliarApprovalOption: Identifiable {
    let id: String
    let title: String
    let decision: FamiliarToolConfirmationDecision
}
