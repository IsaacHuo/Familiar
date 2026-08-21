import Foundation
import SwiftData

enum FamiliarSchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)
    static var models: [any PersistentModel.Type] {
        FamiliarSchemaV7.models + [
            FamiliarSkill.self, FamiliarMemoryItem.self,
            FamiliarMCPServerRecord.self, FamiliarMCPBindingRecord.self
        ]
    }

    @Model final class FamiliarSkill {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var stableID: String
        var version: String
        var name: String
        var descriptionText: String
        var instructions: String
        var examplesJSON: String
        var allowedToolsJSON: String
        var contentHash: String
        var installedAt: Date
        var updatedAt: Date

        init(id: UUID = UUID(), stableID: String, version: String, name: String, descriptionText: String, instructions: String, examplesJSON: String, allowedToolsJSON: String, contentHash: String, installedAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.stableID = stableID; self.version = version; self.name = name
            self.descriptionText = descriptionText; self.instructions = instructions; self.examplesJSON = examplesJSON
            self.allowedToolsJSON = allowedToolsJSON; self.contentHash = contentHash; self.installedAt = installedAt; self.updatedAt = updatedAt
        }
    }

    @Model final class FamiliarMemoryItem {
        @Attribute(.unique) var id: UUID
        var scopeRawValue: String
        var projectID: UUID?
        var conversationID: UUID?
        var content: String
        var normalizedKey: String
        var provenance: String
        var confidence: Double
        var createdByRawValue: String
        var createdAt: Date
        var updatedAt: Date
        var lastUsedAt: Date?
        var isVisible: Bool
        init(scopeRawValue: String, projectID: UUID?, conversationID: UUID?, content: String, normalizedKey: String, provenance: String, confidence: Double, createdByRawValue: String, id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date = Date(), isVisible: Bool = true) {
            self.id = id; self.scopeRawValue = scopeRawValue; self.projectID = projectID; self.conversationID = conversationID; self.content = content
            self.normalizedKey = normalizedKey; self.provenance = provenance; self.confidence = confidence; self.createdByRawValue = createdByRawValue
            self.createdAt = createdAt; self.updatedAt = updatedAt; self.isVisible = isVisible
        }
    }

    @Model final class FamiliarMCPServerRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var serverIdentity: String
        var displayName: String; var endpointString: String; var protocolVersion: String?; var serverName: String?; var serverVersion: String?
        var capabilitiesJSON: String; var toolsHash: String?; var enabled: Bool; var createdAt: Date; var updatedAt: Date; var lastConnectedAt: Date?; var lastError: String?
        init(displayName: String, endpointString: String, serverIdentity: String, id: UUID = UUID(), enabled: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.displayName = displayName; self.endpointString = endpointString; self.serverIdentity = serverIdentity; self.enabled = enabled
            self.capabilitiesJSON = "{}"; self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    @Model final class FamiliarMCPBindingRecord {
        @Attribute(.unique) var id: UUID
        var serverID: UUID; var projectID: UUID?; var conversationID: UUID?; var enabled: Bool; var enabledToolNamesJSON: String; var createdAt: Date; var updatedAt: Date
        init(serverID: UUID, projectID: UUID? = nil, conversationID: UUID? = nil, enabled: Bool = false, enabledToolNamesJSON: String = "[]", id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.serverID = serverID; self.projectID = projectID; self.conversationID = conversationID; self.enabled = enabled; self.enabledToolNamesJSON = enabledToolNamesJSON; self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }
}
