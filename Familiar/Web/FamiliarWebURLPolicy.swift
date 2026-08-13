import Darwin
import Foundation

nonisolated enum FamiliarWebURLPolicy {
    private static let blockedSuffixes = [
        "localhost", ".localhost", ".local", ".internal", ".lan", ".home",
        "home.arpa", ".home.arpa", ".test", ".invalid", ".example", ".onion"
    ]

    static func normalize(_ value: String, relativeTo baseURL: URL? = nil) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2_048,
              !trimmed.contains("\\"),
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil
        else { throw FamiliarWebError.invalidURL }

        let resolved = baseURL.flatMap { URL(string: trimmed, relativeTo: $0)?.absoluteURL } ?? URL(string: trimmed)
        guard let resolved,
              resolved.scheme?.lowercased() == "https",
              resolved.user == nil,
              resolved.password == nil,
              let host = resolved.host?.lowercased(),
              !host.isEmpty
        else {
            if resolved?.scheme?.lowercased() != "https" { throw FamiliarWebError.httpsRequired }
            throw FamiliarWebError.invalidURL
        }
        guard resolved.port == nil || resolved.port == 443 else { throw FamiliarWebError.invalidURL }
        guard !blockedSuffixes.contains(where: { host == $0 || host.hasSuffix($0) }) else {
            throw FamiliarWebError.privateNetworkBlocked
        }

        var components = URLComponents(url: resolved, resolvingAgainstBaseURL: true)
        components?.scheme = "https"
        components?.host = host
        components?.port = nil
        components?.fragment = nil
        if components?.path.isEmpty == true { components?.path = "/" }
        guard let normalized = components?.url else { throw FamiliarWebError.invalidURL }
        return normalized
    }

    static func isPublicAddress(_ address: String) -> Bool {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, address, &ipv4) == 1 {
            let value = UInt32(bigEndian: ipv4.s_addr)
            let first = value >> 24
            let firstTwo = value >> 16
            if first == 0 || first == 10 || first == 127 || first >= 224 { return false }
            if firstTwo == 0xA9FE || firstTwo == 0xC0A8 { return false }
            if value >= 0x64400000 && value <= 0x647FFFFF { return false }
            if value >= 0xAC100000 && value <= 0xAC1FFFFF { return false }
            if value >= 0xC0000000 && value <= 0xC00000FF { return false }
            if value >= 0xC0000200 && value <= 0xC00002FF { return false }
            if value >= 0xC6120000 && value <= 0xC613FFFF { return false }
            if value >= 0xC6336400 && value <= 0xC63364FF { return false }
            if value >= 0xCB007100 && value <= 0xCB0071FF { return false }
            return true
        }

        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, address, &ipv6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
        if bytes.allSatisfy({ $0 == 0 }) || bytes == Array(repeating: 0, count: 15) + [1] { return false }
        if bytes[0] == 0xFF || (bytes[0] & 0xFE) == 0xFC { return false }
        if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return false }
        if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0D && bytes[3] == 0xB8 { return false }
        if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
            return isPublicAddress(bytes[12...15].map(String.init).joined(separator: "."))
        }
        return true
    }
}
