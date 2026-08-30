import SwiftUI

struct FamiliarApprovalCard: View {
    let surface: FamiliarSurfaceDescriptor
    let onResolve: (UUID, FamiliarToolConfirmationDecision) -> Void

    @AccessibilityFocusState private var isAccessibilityFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var previousStep = 0
    @State private var selectedDecision: FamiliarToolConfirmationDecision?
    @State private var isOpen = true
    @State private var didSubmit = false
    @State private var submittedDecision: FamiliarToolConfirmationDecision?

    private let stepCount = 2

    var body: some View {
        Group {
            if didSubmit {
                submittedState
            } else if isOpen {
                approvalCard
            } else {
                reopenButton
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityFocused($isAccessibilityFocused)
        .onAppear { isAccessibilityFocused = true }
    }

    private var reopenButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : FamiliarMotion.state) {
                isOpen = true
            }
        } label: {
            Text(String(localized: "approval.open", defaultValue: "Open approval"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(FamiliarAISurfaceColor.ink)
                .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
                .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                .background(
                    FamiliarAISurfaceColor.surface,
                    in: RoundedRectangle(cornerRadius: FamiliarRadius.control, style: .continuous)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("approval.open")
    }

    private var approvalCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                stepContent
                    .padding(FamiliarAISurfaceMetric.spaceL)
                    .padding(.trailing, FamiliarAISurfaceMetric.spaceL)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(reduceMotion ? nil : FamiliarMotion.micro) {
                        isOpen = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                        .frame(
                            width: FamiliarControlSize.minimumHitTarget,
                            height: FamiliarControlSize.minimumHitTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "common.close"))
                .accessibilityIdentifier("approval.dismiss")
            }
            .animation(reduceMotion ? nil : FamiliarMotion.spatial, value: step)

            footer
        }
        .background(FamiliarAISurfaceColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous)
                .stroke(FamiliarAISurfaceColor.line, lineWidth: FamiliarAISurfaceMetric.hairline)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("approval.card")
    }

    @ViewBuilder
    private var stepContent: some View {
        if step == 0 {
            reviewStep
                .id("approval-review")
                .transition(stepTransition)
        } else {
            scopeStep
                .id("approval-scope")
                .transition(stepTransition)
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
            heading(title: surface.title, detail: surface.approvalTarget)

            VStack(spacing: FamiliarAISurfaceMetric.spaceXS) {
                ForEach(Array(surface.approvalFields.enumerated()), id: \.element.id) { index, field in
                    if index > 0 {
                        Rectangle()
                            .fill(FamiliarAISurfaceColor.line)
                            .frame(height: FamiliarAISurfaceMetric.hairline)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: FamiliarAISurfaceMetric.spaceM) {
                            approvalFieldLabel(field.label)
                                .frame(width: 82, alignment: .leading)
                            approvalFieldValue(field.formattedValue)
                        }
                        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                            approvalFieldLabel(field.label)
                            approvalFieldValue(field.formattedValue)
                        }
                    }
                    .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
                    .frame(minHeight: 36)
                }
            }
            .padding(FamiliarAISurfaceMetric.spaceXS)
            .background(
                FamiliarAISurfaceColor.inset,
                in: RoundedRectangle(cornerRadius: FamiliarAISurfaceRadius.card, style: .continuous)
            )

            if let consequence = surface.approvalConsequence, !consequence.isEmpty {
                Text(consequence)
                    .font(.caption)
                    .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scopeStep: some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
            heading(
                title: String(
                    localized: "approval.scope.question",
                    defaultValue: "How long should Familiar allow this action?"
                ),
                detail: surface.title
            )

            VStack(spacing: FamiliarAISurfaceMetric.spaceXS) {
                ForEach(authorizationOptions) { option in
                    Button {
                        withAnimation(reduceMotion ? nil : FamiliarMotion.micro) {
                            selectedDecision = option.decision
                        }
                    } label: {
                        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                            selectionMark(isSelected: selectedDecision == option.decision)
                            Text(option.title)
                                .font(.subheadline)
                                .foregroundStyle(
                                    selectedDecision == option.decision
                                        ? FamiliarAISurfaceColor.ink
                                        : FamiliarAISurfaceColor.inkSecondary
                                )
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, FamiliarAISurfaceMetric.spaceS)
                        .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: FamiliarAISurfaceRadius.control,
                                style: .continuous
                            )
                        )
                        .background(
                            selectedDecision == option.decision
                                ? FamiliarAISurfaceColor.hover
                                : Color.clear,
                            in: RoundedRectangle(
                                cornerRadius: FamiliarAISurfaceRadius.control,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        selectedDecision == option.decision ? .isSelected : []
                    )
                    .accessibilityIdentifier("approval.scope.\(option.id)")
                }
            }
        }
    }

    private func heading(title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FamiliarAISurfaceColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
            }
        }
        .padding(.trailing, FamiliarControlSize.compactVisual)
    }

    private func selectionMark(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(
                    isSelected ? FamiliarAISurfaceColor.ink : FamiliarAISurfaceColor.lineStrong,
                    lineWidth: 1.5
                )
                .frame(width: 18, height: 18)
            Circle()
                .fill(FamiliarAISurfaceColor.ink)
                .frame(width: 8, height: 8)
                .scaleEffect(isSelected ? 1 : 0.25)
                .opacity(isSelected ? 1 : 0)
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: FamiliarAISurfaceMetric.spaceM) {
                stepNavigator
                Spacer(minLength: 0)
                footerActions
            }
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                stepNavigator
                footerActions
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
        .padding(.vertical, FamiliarAISurfaceMetric.spaceXS)
        .background(FamiliarAISurfaceColor.inset)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FamiliarAISurfaceColor.line)
                .frame(height: FamiliarAISurfaceMetric.hairline)
        }
    }

    private var stepNavigator: some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceXS) {
            stepButton(
                symbol: "chevron.up",
                label: String(localized: "approval.previous", defaultValue: "Previous step"),
                disabled: step == 0
            ) {
                goTo(step - 1)
            }
            Text("\(step + 1) / \(stepCount)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
                .contentTransition(.numericText(countsDown: step < previousStep))
                .animation(reduceMotion ? nil : FamiliarMotion.state, value: step)
            stepButton(
                symbol: "chevron.down",
                label: String(localized: "approval.next", defaultValue: "Next step"),
                disabled: step == stepCount - 1
            ) {
                goTo(step + 1)
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
            Button(String(localized: "approval.skip", defaultValue: "Skip")) {
                if step < stepCount - 1 {
                    goTo(step + 1)
                } else {
                    resolve(.cancelled)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
            .buttonStyle(.plain)
            .frame(minHeight: FamiliarControlSize.minimumHitTarget)

            Button {
                if step < stepCount - 1 {
                    goTo(step + 1)
                } else if let selectedDecision {
                    resolve(selectedDecision)
                }
            } label: {
                HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
                    Text(
                        step == stepCount - 1
                            ? String(localized: "approval.approve", defaultValue: "Approve")
                            : String(localized: "common.continue")
                    )
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(FamiliarApprovalPrimaryButtonStyle())
            .disabled(step == stepCount - 1 && selectedDecision == nil)
        }
    }

    private func stepButton(
        symbol: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(
                    width: FamiliarControlSize.minimumHitTarget,
                    height: FamiliarControlSize.minimumHitTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(FamiliarAISurfaceColor.inkTertiary)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(label)
    }

    private var submittedState: some View {
        HStack(spacing: FamiliarAISurfaceMetric.spaceS) {
            Image(systemName: submittedDecision == .cancelled ? "xmark" : "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 20, height: 20)
                .background(submittedDecision == .cancelled ? FamiliarAISurfaceColor.inkTertiary : FamiliarAISurfaceColor.success, in: Circle())
            Text(submittedDecision == .cancelled
                 ? String(localized: "approval.skipped", defaultValue: "Approval skipped")
                 : String(localized: "approval.sent", defaultValue: "Approval sent"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(submittedDecision == .cancelled ? FamiliarAISurfaceColor.inkSecondary : FamiliarAISurfaceColor.success)
        }
        .padding(.leading, FamiliarAISurfaceMetric.spaceXS)
        .padding(.trailing, FamiliarAISurfaceMetric.spaceM)
        .frame(minHeight: 32)
        .background(submittedDecision == .cancelled ? FamiliarAISurfaceColor.inset : FamiliarAISurfaceColor.successTint, in: Capsule())
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityIdentifier("approval.sent")
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let movingForward = step >= previousStep
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: movingForward ? .bottom : .top)),
            removal: .opacity.combined(with: .move(edge: movingForward ? .top : .bottom))
        )
    }

    private func goTo(_ next: Int) {
        previousStep = step
        withAnimation(reduceMotion ? nil : FamiliarMotion.spatial) {
            step = min(max(next, 0), stepCount - 1)
        }
    }

    private var authorizationOptions: [FamiliarApprovalOption] {
        let all: [FamiliarApprovalOption] = [
            .init(
                id: "once",
                title: String(localized: "authorization.once", defaultValue: "Only Once"),
                decision: .confirmedOnce
            ),
            .init(
                id: "session",
                title: String(
                    localized: "authorization.session",
                    defaultValue: "Allow This Session"
                ),
                decision: .confirmed
            ),
            .init(
                id: "always",
                title: String(localized: "authorization.always", defaultValue: "Always Allow"),
                decision: .confirmedAlways
            ),
        ]
        return all.filter { option in
            guard let duration = option.decision.authorizationDuration else { return false }
            return surface.approvalAllowedAuthorizationDurations.contains(duration)
        }
    }

    private func approvalFieldLabel(_ label: String) -> some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(FamiliarAISurfaceColor.inkSecondary)
    }

    private func approvalFieldValue(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.medium))
            .foregroundStyle(FamiliarAISurfaceColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func resolve(_ decision: FamiliarToolConfirmationDecision) {
        guard let id = surface.approvalRequestID else { return }
        submittedDecision = decision
        withAnimation(reduceMotion ? nil : FamiliarMotion.reveal) {
            didSubmit = true
        }
        onResolve(id, decision)
    }
}

private struct FamiliarApprovalOption: Identifiable {
    let id: String
    let title: String
    let decision: FamiliarToolConfirmationDecision
}

private struct FamiliarApprovalPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(FamiliarAISurfaceColor.surface)
            .padding(.leading, FamiliarAISurfaceMetric.spaceM)
            .padding(.trailing, FamiliarAISurfaceMetric.spaceS)
            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
            .background(FamiliarAISurfaceColor.ink, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(FamiliarMotion.micro, value: configuration.isPressed)
    }
}
