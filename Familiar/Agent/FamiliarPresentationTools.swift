import Foundation

private nonisolated enum FamiliarPresentationToolError: LocalizedError, Sendable {
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let detail): detail
        }
    }
}

nonisolated struct FamiliarTaskPlanTool: FamiliarTool {
    struct Input: Codable, Sendable {
        let planID: String
        let title: String
        let tasks: [FamiliarToolPresentationPayload.TaskItem]
        let expectedDeliverables: [FamiliarDeliverableSpec]?
    }

    let manifest = FamiliarToolManifest(
        name: "task_plan",
        title: "Present task plan",
        description: "Present or update an ordered task plan. Reuse the same planID to replace that plan in place. Only provide progress when it is known; never invent completion percentages.",
        parameters: .object(
            [
                "planID": .string("Stable identifier reused for updates to this plan."),
                "title": .string("Plan title."),
                "tasks": .objectArray(
                    "Tasks in display order.",
                    properties: [
                        "id": .string("Stable task identifier, unique within this plan."),
                        "title": .string("Short task title."),
                        "status": .string("Current task status.", enumValues: FamiliarToolPresentationPayload.TaskStatus.allCases.map(\.rawValue)),
                        "detail": .string("Optional one-line detail."),
                        "progress": .number("Real progress. Omit entirely when unknown; never invent a value.", minimum: 0, maximum: 1)
                    ],
                    required: ["id", "title", "status"],
                    minItems: 1
                ),
                "expectedDeliverables": .objectArray(
                    "Optional real files this run must produce before it can claim completion.",
                    properties: [
                        "id": .string("Stable deliverable identifier."),
                        "title": .string("User-visible deliverable title."),
                        "format": .string("Artifact format.", enumValues: FamiliarArtifactFormat.allCases.map(\.rawValue))
                    ],
                    required: ["id", "title", "format"]
                )
            ],
            required: ["planID", "title", "tasks"]
        ),
        effect: .read,
        risk: .low
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let planID = input.planID.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !planID.isEmpty, !title.isEmpty, !input.tasks.isEmpty else {
            throw FamiliarPresentationToolError.invalidInput("A task plan requires a stable planID, title, and at least one task.")
        }
        guard Set(input.tasks.map(\.id)).count == input.tasks.count,
              input.tasks.allSatisfy({ !$0.id.isEmpty && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              input.tasks.allSatisfy({ $0.progress.map { (0...1).contains($0) } ?? true })
        else {
            throw FamiliarPresentationToolError.invalidInput("Task IDs must be unique and progress must be between 0 and 1 when supplied.")
        }
        let deliverables = input.expectedDeliverables ?? []
        let formats = Set(FamiliarArtifactFormat.allCases.map(\.rawValue))
        guard Set(deliverables.map(\.id)).count == deliverables.count,
              deliverables.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && formats.contains($0.format) })
        else { throw FamiliarPresentationToolError.invalidInput("Deliverables require unique IDs, titles, and supported formats.") }
        let payload = FamiliarToolPresentationPayload.TaskList(planID: planID, title: title, tasks: input.tasks, expectedDeliverables: deliverables)
        return .result(.init(
            envelope: try .init(model: input, presentation: .taskList(payload)),
            deliverables: deliverables
        ))
    }
}

nonisolated struct FamiliarPresentRecommendationTool: FamiliarTool {
    struct Input: Codable, Sendable {
        let title: String
        let explanation: String
        let nextPrompt: String
        let alternatives: [FamiliarToolPresentationPayload.RecommendationAlternative]
        let confidenceLevel: FamiliarToolPresentationPayload.ConfidenceLevel?
    }

    let manifest = FamiliarToolManifest(
        name: "present_recommendation",
        title: "Present recommendation",
        description: "Present a recommendation with a suggested next prompt and optional alternatives. Confidence is categorical only, never a percentage. Selecting any prompt only fills the composer and does not execute it.",
        parameters: .object(
            [
                "title": .string("Recommendation title."),
                "explanation": .string("Why this is recommended."),
                "nextPrompt": .string("Suggested next user prompt."),
                "alternatives": .objectArray(
                    "Alternative directions the user can choose instead.",
                    properties: [
                        "id": .string("Stable alternative identifier."),
                        "title": .string("Short alternative title."),
                        "prompt": .string("Prompt filled into the composer when chosen.")
                    ],
                    required: ["id", "title", "prompt"]
                ),
                "confidenceLevel": .string(
                    "Categorical confidence only, never a percentage.",
                    enumValues: FamiliarToolPresentationPayload.ConfidenceLevel.allCases.map(\.rawValue)
                )
            ],
            required: ["title", "explanation", "nextPrompt", "alternatives"]
        ),
        effect: .read,
        risk: .low
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.nextPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(input.alternatives.map(\.id)).count == input.alternatives.count,
              input.alternatives.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && !$0.prompt.isEmpty })
        else { throw FamiliarPresentationToolError.invalidInput("A recommendation requires a title, explanation, next prompt, and valid alternatives.") }
        let payload = FamiliarToolPresentationPayload.Recommendation(title: input.title, explanation: input.explanation, nextPrompt: input.nextPrompt, alternatives: input.alternatives, confidenceLevel: input.confidenceLevel)
        return .result(.init(envelope: try .init(model: input, presentation: .recommendation(payload))))
    }
}

nonisolated struct FamiliarPresentInsightTool: FamiliarTool {
    struct Input: Codable, Sendable {
        let title: String
        let explanation: String
        let metrics: [FamiliarToolPresentationPayload.InsightMetric]
    }

    let manifest = FamiliarToolManifest(
        name: "present_insight",
        title: "Present insight",
        description: "Present an insight and only real, explicitly named metrics. Use an empty metrics array when there are no metrics; the UI will not draw a chart.",
        parameters: .object(
            [
                "title": .string("Insight title."),
                "explanation": .string("What the insight means."),
                "metrics": .objectArray(
                    "Only real, explicitly named metrics. Use an empty array when there are none.",
                    properties: [
                        "label": .string("Metric name."),
                        "value": .number("Metric value."),
                        "unit": .string("Optional unit."),
                        "change": .number("Optional change versus the previous period.")
                    ],
                    required: ["label", "value"]
                )
            ],
            required: ["title", "explanation", "metrics"]
        ),
        effect: .read,
        risk: .low
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              input.metrics.allSatisfy({ !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.value.isFinite && ($0.change?.isFinite ?? true) })
        else { throw FamiliarPresentationToolError.invalidInput("An insight requires a title, explanation, and finite named metrics.") }
        let payload = FamiliarToolPresentationPayload.Insight(title: input.title, explanation: input.explanation, metrics: input.metrics)
        return .result(.init(envelope: try .init(model: input, presentation: .insight(payload))))
    }
}

nonisolated struct FamiliarAskUserTool: FamiliarTool {
    struct Input: Codable, Sendable {
        let question: String
        let options: [FamiliarClarificationOption]
        let allowCustom: Bool
    }

    let manifest = FamiliarToolManifest(
        name: "ask_user",
        title: "Ask user",
        description: "Pause the run and ask the user a clarification question. Provide stable option IDs. Use allowCustom when a free-text response is useful. This is not authorization for any action.",
        parameters: .object(
            [
                "question": .string("The clarification question shown to the user."),
                "options": .objectArray(
                    "Selectable answers. May be empty only when allowCustom is true.",
                    properties: [
                        "id": .string("Stable option identifier."),
                        "label": .string("User-visible option label.")
                    ],
                    required: ["id", "label"]
                ),
                "allowCustom": .boolean("Whether a free-text answer is accepted.")
            ],
            required: ["question", "options", "allowCustom"]
        ),
        effect: .read,
        risk: .low
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let question = input.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty,
              (!input.options.isEmpty || input.allowCustom),
              Set(input.options.map(\.id)).count == input.options.count,
              input.options.allSatisfy({ !$0.id.isEmpty && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw FamiliarPresentationToolError.invalidInput("A clarification requires a question and at least one response path.") }
        return .clarification(.init(question: question, options: input.options, allowCustom: input.allowCustom))
    }
}
