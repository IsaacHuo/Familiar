import Foundation

private nonisolated enum FamiliarPresentationToolError: LocalizedError, Sendable {
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let detail): detail
        }
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
