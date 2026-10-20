import Foundation

nonisolated enum FamiliarMemoryListFilter: String, CaseIterable, Identifiable {
    case all, global, project, conversation
    var id: String { rawValue }
    var title: String { String(localized: String.LocalizationValue("settings.memory.filter." + rawValue)) }
}
