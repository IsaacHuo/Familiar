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
    static func make(name: String = "FamiliarTests") throws -> ModelContainer {
        try FamiliarModelContainer.makeInMemory(name: name)
    }
}

func familiarTestContextSnapshot(
    messages: [FamiliarMessageSnapshot] = [],
    settings: FamiliarSettings = .defaultValue,
    manifests: [FamiliarToolManifest] = [],
    projectID: UUID? = nil,
    projectName: String? = nil,
    projectInstruction: String? = nil,
    resources: [FamiliarContextResource] = []
) throws -> FamiliarContextSnapshot {
    try FamiliarProjectContextAssembler.assemble(
        seed: FamiliarProjectContextSeed(
            projectID: projectID,
            projectName: projectName,
            conversationID: UUID(),
            projectInstruction: projectInstruction,
            resources: resources
        ),
        settings: settings,
        messages: messages,
        toolManifests: manifests
    )
}

actor FamiliarFakeCapabilities: FamiliarCapabilityProviding {
    var value: FamiliarCapabilityAvailability
    init(_ value: FamiliarCapabilityAvailability) { self.value = value }
    func availability(for requirement: FamiliarCapabilityRequirement) -> FamiliarCapabilityAvailability { value }
    func request(_ requirement: FamiliarCapabilityRequirement) { value = .available }
}
