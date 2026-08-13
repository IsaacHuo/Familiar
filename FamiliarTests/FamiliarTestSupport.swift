import Foundation
import SwiftData
@testable import Familiar

struct FamiliarFixedClock: Sendable {
    let now: Date
}

struct FamiliarFixedUUIDGenerator: Sendable {
    let value: UUID
    func next() -> UUID { value }
}

enum FamiliarTestStore {
    @MainActor
    static func make() throws -> ModelContainer {
        let schema = Schema([FamiliarConversation.self, FamiliarMessage.self, FamiliarSourceRecord.self, FamiliarAttachment.self, FamiliarModelSwitchRecord.self, FamiliarAgentRun.self, FamiliarAgentStep.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration("FamiliarTests", schema: schema, isStoredInMemoryOnly: true)])
    }
}

actor FamiliarFakeCapabilities: FamiliarCapabilityProviding {
    var value: FamiliarCapabilityAvailability
    init(_ value: FamiliarCapabilityAvailability) { self.value = value }
    func availability(for requirement: FamiliarCapabilityRequirement) -> FamiliarCapabilityAvailability { value }
    func request(_ requirement: FamiliarCapabilityRequirement) { value = .available }
}
