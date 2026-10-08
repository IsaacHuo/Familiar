import Foundation

/// Storage roots may have real system ancestors (for example /var -> /private/var).
/// Links within the store cannot redirect a logical Project or version identity.
nonisolated enum FamiliarFilePath {
    static func confined(_ relativePath: String, to root: URL) throws -> URL {
        let relative = relativePath.replacingOccurrences(of: "\\", with: "/")
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty, !relative.hasPrefix("/"),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw FamiliarFileError.invalidPath
        }
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              candidate.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot.path + "/") else {
            throw FamiliarFileError.invalidPath
        }
        var cursor = root
        for part in parts {
            cursor.appendPathComponent(String(part))
            if (try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw FamiliarFileError.invalidPath
            }
        }
        return candidate
    }
}
