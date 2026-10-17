import Observation
import SwiftUI

/// Only registered, currently waiting requests may own the input area.
nonisolated struct FamiliarPendingInteraction: Identifiable, Equatable {
    let id: UUID
    let surface: FamiliarSurfaceDescriptor

    static func project(surfaces: [FamiliarSurfaceDescriptor], approvals: [FamiliarToolConfirmationRequest],
                        questions: [FamiliarClarificationRequest]) -> [Self] {
        return surfaces.compactMap { surface in
            if surface.kind == .approval, surface.phase == .awaitingApproval,
               let id = surface.approvalRequestID,
               approvals.contains(where: { $0.id == id && $0.runID == surface.runID && $0.toolCallID == surface.toolCallID }) {
                return Self(id: id, surface: surface)
            }
            if surface.kind == .clarification, surface.phase == .awaitingClarification,
               let id = surface.clarificationRequestID,
               questions.contains(where: { $0.id == id && $0.runID == surface.runID && $0.toolCallID == surface.toolCallID }) {
                return Self(id: id, surface: surface)
            }
            return nil
        }.sorted { $0.surface.sequence < $1.surface.sequence }
    }
}

nonisolated struct FamiliarInteractionDrafts {
    private var answers: [UUID: String] = [:]
    private(set) var submitting: Set<UUID> = []
    func answer(for id: UUID) -> String { answers[id] ?? "" }
    mutating func setAnswer(_ answer: String, for id: UUID) { answers[id] = answer }
    mutating func reconcile(_ ids: Set<UUID>) {
        answers = answers.filter { ids.contains($0.key) }
        submitting.formIntersection(ids)
    }
    mutating func beginSubmission(_ id: UUID) -> Bool { submitting.insert(id).inserted }
}

/// Pending interactions observe activity boundaries, never the streaming text.
struct FamiliarChatInputDock: View {
    let controller: FamiliarChatController
    let skills: [FamiliarSkillMenuItem]
    let isListening: Bool
    let focus: FocusState<Bool>.Binding
    let availableHeight: CGFloat
    let onSpeech: () -> Void
    let onSend: () -> Void
    let onStop: () -> Void
    @State private var drafts = FamiliarInteractionDrafts()
    @State private var interactionHeight: CGFloat = 0

    private var interactions: [FamiliarPendingInteraction] {
        FamiliarPendingInteraction.project(surfaces: controller.surfaces.orderedSurfaces,
            approvals: controller.pendingConfirmations, questions: controller.pendingClarifications)
    }

    var body: some View {
        @Bindable var controller = controller
        let pending = interactions
        let current = pending.first
        let question = current?.surface.kind == .clarification ? current : nil
        VStack(spacing: 0) {
            if let current {
                VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
                    HStack(spacing: FamiliarSpacing.small) {
                        Text(String(localized: current.surface.kind == .clarification ? "clarification.title" : "approval.pending"))
                            .font(FamiliarTypography.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if pending.count > 1 {
                            Text(String(format: String(localized: "interaction.pending_count"), pending.count))
                                .font(FamiliarTypography.caption).foregroundStyle(.secondary)
                        }
                        Button(action: onStop) {
                            Image(systemName: "stop.circle")
                                .font(.system(size: FamiliarIconSize.standard))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(FamiliarIconButtonStyle())
                        .accessibilityLabel(String(localized: "message.stop"))
                        .accessibilityIdentifier("interaction.stop")
                    }
                    ScrollView {
                        Group {
                        if current.surface.kind == .approval {
                            FamiliarApprovalCard(surface: current.surface, isCompact: true) { id, decision in
                                guard drafts.beginSubmission(id) else { return }
                                controller.resolveConfirmation(requestID: id, decision: decision)
                            }
                            .id(current.id)
                        } else {
                            questionContent(current)
                        }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { interactionHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(interactionHeight > 0 ? interactionHeight : availableHeight * 0.42,
                                       max(88, availableHeight * 0.42)))
                    .disabled(drafts.submitting.contains(current.id))
                }
                .padding(.horizontal, FamiliarSpacing.medium)
                .accessibilityIdentifier("interaction.dock")
            }
            FamiliarComposer(
                draft: question.map { item in
                    Binding(get: { drafts.answer(for: item.id) }, set: { drafts.setAnswer($0, for: item.id) })
                } ?? $controller.draft,
                images: $controller.draftImages, documents: $controller.draftAttachments,
                selectedSkillID: $controller.selectedSkillID, skills: skills,
                isSending: controller.isSending, isListening: isListening,
                draftScopeID: controller.selectedConversationID ?? controller.selectedProjectID,
                focus: focus, onSpeech: onSpeech,
                onSend: {
                    if let question {
                        let answer = drafts.answer(for: question.id).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard question.surface.clarificationAllowsCustom, !answer.isEmpty,
                              drafts.beginSubmission(question.id) else { return }
                        focus.wrappedValue = false
                        controller.resolveClarification(requestID: question.id, resolution: .custom(answer))
                    } else { onSend() }
                }, availableHeight: availableHeight,
                isAnsweringClarification: question != nil,
                allowsCustomAnswer: question.map { $0.surface.clarificationAllowsCustom && !drafts.submitting.contains($0.id) } ?? true
            )
        }
        .onChange(of: pending.map(\.id), initial: true) { _, ids in
            drafts.reconcile(Set(ids))
            interactionHeight = 0
            focus.wrappedValue = false
        }
        .onChange(of: controller.selectedConversationID) { _, _ in drafts = .init() }
    }

    private func questionContent(_ item: FamiliarPendingInteraction) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
            Text(item.surface.title).font(FamiliarTypography.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(item.surface.clarificationOptions) { option in
                Button {
                    guard drafts.beginSubmission(item.id) else { return }
                    focus.wrappedValue = false
                    controller.resolveClarification(requestID: item.id, resolution: .selectedOption(id: option.id, label: option.label))
                } label: {
                    HStack(spacing: FamiliarSpacing.small) {
                        Text(option.label).font(FamiliarTypography.secondary)
                        Spacer(minLength: FamiliarSpacing.small)
                        Image(systemName: "arrow.up.left").font(FamiliarTypography.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clarification.option.\(option.id)")
            }
            Button(String(localized: "interaction.skip")) {
                guard drafts.beginSubmission(item.id) else { return }
                controller.resolveClarification(requestID: item.id, resolution: .cancelled)
            }
            .font(FamiliarTypography.secondary).foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .accessibilityIdentifier("clarification.skip")
        }
        .padding(FamiliarSpacing.medium)
        .background(FamiliarTheme.inset, in: RoundedRectangle(cornerRadius: FamiliarRadius.card))
        .accessibilityElement(children: .contain)
    }
}

/// History and waiting indicators never retain an executable approval control.
struct FamiliarInteractionReceipt: View {
    let surface: FamiliarSurfaceDescriptor
    @State private var record: FamiliarSurfaceDescriptor?
    @Environment(\.familiarChatScrollSession) private var scroll
    private var isWaiting: Bool { surface.phase == .awaitingApproval || surface.phase == .awaitingClarification }

    var body: some View {
        Button { scroll?.beginInspection(); record = surface } label: {
            HStack(alignment: .firstTextBaseline, spacing: FamiliarSpacing.small) {
                Image(systemName: isWaiting ? "questionmark.circle" : (surface.phase == .cancelled ? "pause.circle" : "checkmark.circle"))
                    .frame(width: FamiliarIconSize.standard)
                    .accessibilityHidden(true)
                Text(summary).font(FamiliarTypography.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: FamiliarSpacing.small)
                Image(systemName: "chevron.right").font(FamiliarTypography.caption)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("interaction.receipt.\(surface.id)")
        .sheet(item: $record, onDismiss: { scroll?.endInspection() }) { value in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: FamiliarSpacing.medium) {
                        Text(value.title).font(FamiliarTypography.body.weight(.medium))
                        if let target = value.approvalTarget { Text(target).textSelection(.enabled) }
                        ForEach(value.approvalFields) { field in LabeledContent(field.label, value: field.formattedValue) }
                        if let consequence = value.approvalConsequence { Text(consequence) }
                        if let detail = value.detail { Text(detail) }
                        Text(summary).foregroundStyle(.secondary)
                    }.padding(FamiliarSpacing.large)
                }
                .navigationTitle(String(localized: value.kind == .clarification ? "clarification.title" : "approval.pending"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { FamiliarDismissButton() } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var summary: String {
        if isWaiting { return String(localized: surface.kind == .clarification ? "interaction.waiting_answer" : "interaction.waiting_approval") }
        if let answer = surface.clarificationResolution?.answer { return answer }
        if surface.phase == .cancelled { return String(localized: "runtime.ui.skipped") }
        if surface.phase == .failed { return surface.detail ?? String(localized: "approval.interrupted") }
        if surface.kind == .approval { return String(localized: "interaction.approval_recorded") }
        return surface.detail ?? surface.title
    }
}
