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
    let snapshot = try FamiliarProjectContextAssembler.assemble(
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
    // Policy fixtures explicitly expose their fake tools so retry/budget/approval tests
    // isolate those behaviors. Lazy-exposure tests use the production assembler directly.
    return .init(id: snapshot.id, createdAt: snapshot.createdAt, projectID: snapshot.projectID, projectName: snapshot.projectName,
        conversationID: snapshot.conversationID, projectInstruction: snapshot.projectInstruction,
        providerID: snapshot.providerID, modelID: snapshot.modelID, providerMessages: snapshot.providerMessages,
        toolManifests: manifests, availableToolManifests: snapshot.availableToolManifests,
        protectedPrefixMessageCount: snapshot.protectedPrefixMessageCount, maximumInputCharacters: snapshot.maximumInputCharacters,
        initialInputCharacters: FamiliarProjectContextAssembler.inputCharacterCount(messages: snapshot.providerMessages, manifests: manifests),
        resources: snapshot.resources, attachments: snapshot.attachments, skills: snapshot.skills,
        availableSkills: snapshot.availableSkills, memories: snapshot.memories, visualEvidence: snapshot.visualEvidence,
        visualEvidenceMessageID: snapshot.visualEvidenceMessageID)
}

actor FamiliarFakeCapabilities: FamiliarCapabilityProviding {
    var value: FamiliarCapabilityAvailability
    init(_ value: FamiliarCapabilityAvailability) { self.value = value }
    func availability(for requirement: FamiliarCapabilityRequirement) -> FamiliarCapabilityAvailability { value }
    func request(_ requirement: FamiliarCapabilityRequirement) { value = .available }
}
