import Foundation
import SwiftData

@Model
final class FamiliarConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \FamiliarMessage.conversation)
    var messages: [FamiliarMessage]

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        messages = []
    }
}

@Model
final class FamiliarMessage {
    @Attribute(.unique) var id: UUID
    var roleRawValue: String
    var content: String
    var createdAt: Date
    var sequence: Int
    var conversation: FamiliarConversation?

    init(
        id: UUID = UUID(),
        role: FamiliarMessageRole,
        content: String,
        createdAt: Date = Date(),
        sequence: Int,
        conversation: FamiliarConversation? = nil
    ) {
        self.id = id
        roleRawValue = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.sequence = sequence
        self.conversation = conversation
    }

    var role: FamiliarMessageRole {
        FamiliarMessageRole(rawValue: roleRawValue) ?? .assistant
    }
}
