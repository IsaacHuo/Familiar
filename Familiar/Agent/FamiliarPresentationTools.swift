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
    }

    let manifest = FamiliarToolManifest(
        name: "task_plan",
        title: "Present task plan",
        description: "Present or update an ordered task plan. Reuse the same planID to replace that plan in place. Only provide progress when it is known; never invent completion percentages.",
        parameters: .init(
            type: .object,
            properties: [
                "planID": .init(type: .string, description: "Stable identifier reused for updates to this plan."),
                "title": .init(type: .string, description: "Plan title."),
                "tasks": .init(type: .array, description: "Tasks in display order. Each item requires stable string id, title, and status pending|running|completed|failed; detail and real progress from 0 to 1 are optional. Omit progress when unknown.")
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
        let payload = FamiliarToolPresentationPayload.TaskList(planID: planID, title: title, tasks: input.tasks)
        return .result(.init(envelope: try .init(model: input, presentation: .taskList(payload))))
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
        parameters: .init(
            type: .object,
            properties: [
                "title": .init(type: .string),
                "explanation": .init(type: .string),
                "nextPrompt": .init(type: .string, description: "Suggested next user prompt."),
                "alternatives": .init(type: .array, description: "Alternative objects with required stable string id, title, and prompt."),
                "confidenceLevel": .init(type: .string, enumValues: ["low", "medium", "high", "needsReview"])
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
        parameters: .init(
            type: .object,
            properties: [
                "title": .init(type: .string),
                "explanation": .init(type: .string),
                "metrics": .init(type: .array, description: "Metric objects with required label and numeric value; unit and numeric change are optional.")
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
        parameters: .init(
            type: .object,
            properties: [
                "question": .init(type: .string),
                "options": .init(type: .array, description: "Option objects with required stable string id and label."),
                "allowCustom": .init(type: .boolean)
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
