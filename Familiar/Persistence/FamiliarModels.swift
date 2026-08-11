import Foundation
import SwiftData

@Model
final class FamiliarConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var currentProviderID: String
    var currentModelID: String

    @Relationship(deleteRule: .cascade, inverse: \FamiliarMessage.conversation)
    var messages: [FamiliarMessage]

    @Relationship(deleteRule: .cascade, inverse: \FamiliarModelSwitchRecord.conversation)
    var modelSwitchRecords: [FamiliarModelSwitchRecord]

    init(
        id: UUID = UUID(),
        title: String = String(localized: "conversation.new"),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        currentProviderID: String = FamiliarProviderCatalog.deepSeek.id,
        currentModelID: String = FamiliarProviderCatalog.deepSeek.defaultModel.id
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.currentProviderID = currentProviderID
        self.currentModelID = currentModelID
        messages = []
        modelSwitchRecords = []
    }
}

@Model
final class FamiliarMessage {
    @Attribute(.unique) var id: UUID
    var roleRawValue: String
    var content: String
    var createdAt: Date
    var sequence: Int
    var providerID: String?
    var modelID: String?
    var conversation: FamiliarConversation?

    init(
        id: UUID = UUID(),
        role: FamiliarMessageRole,
        content: String,
        createdAt: Date = Date(),
        sequence: Int,
        providerID: String? = nil,
        modelID: String? = nil,
        conversation: FamiliarConversation? = nil
    ) {
        self.id = id
        roleRawValue = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.sequence = sequence
        self.providerID = providerID
        self.modelID = modelID
        self.conversation = conversation
    }

    var role: FamiliarMessageRole {
        FamiliarMessageRole(rawValue: roleRawValue) ?? .assistant
    }
}
