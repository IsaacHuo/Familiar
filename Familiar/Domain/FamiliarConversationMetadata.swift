import Foundation
import SwiftData

extension FamiliarSchemaV1 {
@Model
final class FamiliarModelSwitchRecord {
    @Attribute(.unique) var id: UUID
    var previousProviderID: String
    var previousModelID: String
    var currentProviderID: String
    var currentModelID: String
    var sequence: Int
    var createdAt: Date
    var conversation: FamiliarConversation?

    init(
        id: UUID = UUID(),
        previousProviderID: String,
        previousModelID: String,
        currentProviderID: String = FamiliarProviderCatalog.deepSeek.id,
        currentModelID: String = FamiliarProviderCatalog.deepSeek.defaultModel.id,
        sequence: Int,
        createdAt: Date = Date(),
        conversation: FamiliarConversation? = nil
    ) {
        self.id = id
        self.previousProviderID = previousProviderID
        self.previousModelID = previousModelID
        self.currentProviderID = currentProviderID
        self.currentModelID = currentModelID
        self.sequence = sequence
        self.createdAt = createdAt
        self.conversation = conversation
    }
}
}

typealias FamiliarModelSwitchRecord = FamiliarSchemaV3.FamiliarModelSwitchRecord
