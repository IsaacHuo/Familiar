import Foundation

nonisolated struct FamiliarSSEEvent: Equatable, Sendable {
    let name: String?
    let data: String
}

nonisolated enum FamiliarSSEParser {
    static func events(in fixture: String) -> [FamiliarSSEEvent] {
        var result: [FamiliarSSEEvent] = []
        var name: String?
        var data: [String] = []
        func flush() {
            guard !data.isEmpty else { name = nil; return }
            result.append(.init(name: name, data: data.joined(separator: "\n")))
            name = nil
            data = []
        }
        for line in fixture.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("event:") { name = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("data:") { data.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces)) }
        }
        flush()
        return result
    }
}
