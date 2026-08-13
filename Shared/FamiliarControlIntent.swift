import AppIntents

nonisolated enum FamiliarControlDestination: String, AppEnum {
    case app

    static let typeDisplayRepresentation = TypeDisplayRepresentation("Familiar destination")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .app: DisplayRepresentation(title: "Familiar")
    ]
}

struct OpenFamiliarControlIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Familiar"

    @Parameter(title: "Destination")
    var target: FamiliarControlDestination

    init() {
        target = .app
    }

    init(target: FamiliarControlDestination) {
        self.target = target
    }
}
