import Foundation

nonisolated enum FamiliarMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

nonisolated struct FamiliarMessageSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: FamiliarMessageRole
    let content: String
    let createdAt: Date
    let sequence: Int
}

nonisolated enum FamiliarModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case flash = "deepseek-v4-flash"
    case pro = "deepseek-v4-pro"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flash: "Flash"
        case .pro: "Pro"
        }
    }

    var detail: String {
        switch self {
        case .flash: "响应更快，适合日常问答"
        case .pro: "推理更充分，适合复杂问题"
        }
    }
}

nonisolated struct FamiliarSettings: Codable, Equatable, Sendable {
    var model: FamiliarModel
    var systemPrompt: String

    static let defaultValue = FamiliarSettings(
        model: .flash,
        systemPrompt: "你是 Familiar，一个可靠、清晰、诚实的通用助手。直接回答用户的问题；不声称能够读取账号、设备数据、校园系统或其他未提供的信息。"
    )

    var normalizedSystemPrompt: String {
        let value = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? Self.defaultValue.systemPrompt : String(value.prefix(3_000))
    }
}

@MainActor
enum FamiliarSettingsStore {
    private static let key = "familiar.chat.settings.v1"

    static func load() -> FamiliarSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(FamiliarSettings.self, from: data)
        else { return .defaultValue }
        return settings
    }

    static func save(_ settings: FamiliarSettings) throws {
        let data = try JSONEncoder().encode(settings)
        UserDefaults.standard.set(data, forKey: key)
    }
}
