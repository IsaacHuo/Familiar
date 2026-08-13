import Foundation

nonisolated enum FamiliarDeepLink: Equatable, Sendable {
    static let scheme = "familiar"
    static let maximumPrefillCharacters = 20_000

    case newDraft(text: String)
    case conversation(UUID)
    case run(UUID)

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              let host = components.host?.lowercased()
        else { return nil }

        let path = components.path.split(separator: "/", omittingEmptySubsequences: true)
        switch host {
        case "new" where path.isEmpty:
            let value = components.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
            self = .newDraft(text: String(value.prefix(Self.maximumPrefillCharacters)))
        case "conversation" where path.count == 1:
            guard let id = UUID(uuidString: String(path[0])) else { return nil }
            self = .conversation(id)
        case "run" where path.count == 1:
            guard let id = UUID(uuidString: String(path[0])) else { return nil }
            self = .run(id)
        default:
            return nil
        }
    }
}
