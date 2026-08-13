import AppIntents
import Foundation
import Observation

nonisolated struct FamiliarSystemEntryRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let deepLink: FamiliarDeepLink
    let automaticallySubmit: Bool

    init(id: UUID = UUID(), deepLink: FamiliarDeepLink, automaticallySubmit: Bool) {
        self.id = id
        self.deepLink = deepLink
        self.automaticallySubmit = automaticallySubmit
    }

    static func deepLink(_ deepLink: FamiliarDeepLink) -> Self {
        Self(deepLink: deepLink, automaticallySubmit: false)
    }

    static func appIntent(text: String) -> Self {
        let boundedText = String(text.prefix(FamiliarDeepLink.maximumPrefillCharacters))
        return Self(deepLink: .newDraft(text: boundedText), automaticallySubmit: true)
    }
}

@MainActor
@Observable
final class FamiliarAppIntentHandoff {
    static let shared = FamiliarAppIntentHandoff()

    private(set) var pendingRequest: FamiliarSystemEntryRequest?

    private init() {}

    func submit(_ request: FamiliarSystemEntryRequest) {
        pendingRequest = request
    }

    func takePendingRequest() -> FamiliarSystemEntryRequest? {
        defer { pendingRequest = nil }
        return pendingRequest
    }
}

struct AskFamiliarIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Ask Familiar"
    nonisolated static let description = IntentDescription("Open Familiar and run a question with the selected model provider.")

    @available(iOS, introduced: 18.0, deprecated: 26.0, message: "Use supportedModes on iOS 26 and later.")
    nonisolated static var openAppWhenRun: Bool { true }

    @available(iOS 26.0, *)
    nonisolated static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Question")
    var question: String

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: "Add a question before running this action.")
        }
        await MainActor.run {
            FamiliarAppIntentHandoff.shared.submit(.appIntent(text: text))
        }
        return .result(dialog: "Opening Familiar.")
    }
}

struct ProcessWithFamiliarIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Process with Familiar"
    nonisolated static let description = IntentDescription("Open Familiar and run provided text as a new request.")

    @available(iOS, introduced: 18.0, deprecated: 26.0, message: "Use supportedModes on iOS 26 and later.")
    nonisolated static var openAppWhenRun: Bool { true }

    @available(iOS 26.0, *)
    nonisolated static let supportedModes: IntentModes = .foreground

    @Parameter(
        title: "Text",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var text: String

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return .result(dialog: "Add text before running this action.")
        }
        await MainActor.run {
            FamiliarAppIntentHandoff.shared.submit(.appIntent(text: content))
        }
        return .result(dialog: "Opening Familiar.")
    }
}

nonisolated struct OpenFamiliarIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Familiar"
    static let description = IntentDescription("Open Familiar without changing the current draft or conversation.")

    @available(iOS, introduced: 18.0, deprecated: 26.0, message: "Use supportedModes on iOS 26 and later.")
    static var openAppWhenRun: Bool { true }

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground

    func perform() async throws -> some IntentResult {
        .result()
    }
}

nonisolated struct FamiliarAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskFamiliarIntent(),
            phrases: ["Ask \(.applicationName)"],
            shortTitle: "Ask Familiar",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: ProcessWithFamiliarIntent(),
            phrases: ["Process text with \(.applicationName)"],
            shortTitle: "Process with Familiar",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: OpenFamiliarIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Familiar",
            systemImageName: "bubble.left.and.bubble.right"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
