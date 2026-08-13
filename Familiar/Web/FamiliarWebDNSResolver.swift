import Darwin
import Foundation

nonisolated struct FamiliarWebDNSResolver: Sendable {
    func resolve(host: String) async throws -> [String] {
        try await Task.detached(priority: .utility) {
            var hints = addrinfo(
                ai_flags: AI_ADDRCONFIG,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: IPPROTO_TCP,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, "443", &hints, &result) == 0, let result else {
                throw FamiliarWebError.dnsFailed
            }
            defer { freeaddrinfo(result) }

            var addresses: [String] = []
            var cursor: UnsafeMutablePointer<addrinfo>? = result
            while let current = cursor {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let length = buffer.firstIndex(of: 0) ?? buffer.endIndex
                    addresses.append(String(decoding: buffer[..<length].map(UInt8.init(bitPattern:)), as: UTF8.self))
                }
                cursor = current.pointee.ai_next
            }
            let unique = Array(Set(addresses)).sorted()
            guard !unique.isEmpty else { throw FamiliarWebError.dnsFailed }
            guard unique.allSatisfy(FamiliarWebURLPolicy.isPublicAddress) else {
                throw FamiliarWebError.privateNetworkBlocked
            }
            return unique
        }.value
    }
}
