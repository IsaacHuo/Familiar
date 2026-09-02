import CryptoKit
import Foundation

/// The single content-hash implementation.
///
/// The same `SHA256.hash(data:).map { String(format: "%02x", $0) }.joined()`
/// expression was copied into at least a dozen private helpers across artifacts,
/// workspace, persistence, resources, skills and the shell runtime. Hashes are
/// persisted and compared across app launches, so a single divergent copy would
/// silently invalidate stored content hashes.
nonisolated enum FamiliarHash {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ text: String) -> String {
        sha256(Data(text.utf8))
    }

    /// Hex digest of a file read incrementally, so a large artifact is never fully
    /// resident in memory.
    static func sha256(contentsOf url: URL, chunkSize: Int = 1 << 20) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
