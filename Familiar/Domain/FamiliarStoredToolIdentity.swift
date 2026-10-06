import Foundation

/// Converts saved configuration/history only. Runtime calls must match exposed current names.
nonisolated enum FamiliarStoredToolIdentity {
    static func currentName(_ storedName: String) -> String {
        switch storedName {
        case "artifact_write": "file_write"
        case "artifact_edit": "file_edit"
        case "artifact_read": "file_read"
        case "artifact_publish": "file_publish"
        case "resource_list": "file_list"
        case "resource_read": "file_read"
        case "resource_search": "file_search"
        default: storedName
        }
    }

    static func currentFileIdentifier(_ storedIdentifier: String) -> String {
        guard storedIdentifier.hasPrefix("artifact_"),
              let id = UUID(uuidString: String(storedIdentifier.dropFirst("artifact_".count))) else { return storedIdentifier }
        return "file_" + id.uuidString
    }
}
