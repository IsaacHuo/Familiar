import Foundation
import SwiftData

enum FamiliarProjectStatus: String, Sendable {
    case active
    case archived
}

typealias FamiliarConversation = FamiliarSchemaV3.FamiliarConversation
typealias FamiliarMessage = FamiliarSchemaV3.FamiliarMessage
typealias FamiliarSourceRecord = FamiliarSchemaV3.FamiliarSourceRecord
typealias FamiliarAttachment = FamiliarSchemaV3.FamiliarAttachment
typealias FamiliarAgentRun = FamiliarSchemaV3.FamiliarAgentRun
typealias FamiliarAgentStep = FamiliarSchemaV3.FamiliarAgentStep
typealias FamiliarProject = FamiliarSchemaV3.FamiliarProject
typealias FamiliarProjectInstruction = FamiliarSchemaV3.FamiliarProjectInstruction
typealias FamiliarResource = FamiliarSchemaV3.FamiliarResource
typealias FamiliarResourceVersion = FamiliarSchemaV3.FamiliarResourceVersion
typealias FamiliarContextSnapshotRecord = FamiliarSchemaV3.FamiliarContextSnapshotRecord
typealias FamiliarContextResourceReference = FamiliarSchemaV3.FamiliarContextResourceReference
typealias FamiliarArtifact = FamiliarSchemaV4.FamiliarArtifact
typealias FamiliarCapabilitySnapshotRecord = FamiliarSchemaV5.FamiliarCapabilitySnapshotRecord
typealias FamiliarAuthorizationGrantRecord = FamiliarSchemaV5.FamiliarAuthorizationGrantRecord
typealias FamiliarRunResumeCursorRecord = FamiliarSchemaV6.FamiliarRunResumeCursorRecord
typealias FamiliarToolInvocationRecord = FamiliarSchemaV6.FamiliarToolInvocationRecord
typealias FamiliarAuthorizationRuleRecord = FamiliarSchemaV7.FamiliarAuthorizationRuleRecord
typealias FamiliarEventKitUndoRecord = FamiliarSchemaV7.FamiliarEventKitUndoRecord
typealias FamiliarVisualEvidenceRecord = FamiliarSchemaV7.FamiliarVisualEvidenceRecord
typealias FamiliarSkill = FamiliarSchemaV8.FamiliarSkill
typealias FamiliarMemoryItem = FamiliarSchemaV8.FamiliarMemoryItem
typealias FamiliarMCPServerRecord = FamiliarSchemaV8.FamiliarMCPServerRecord
typealias FamiliarMCPBindingRecord = FamiliarSchemaV8.FamiliarMCPBindingRecord
typealias FamiliarRunSkillSnapshotRecord = FamiliarSchemaV9.FamiliarRunSkillSnapshotRecord

enum FamiliarModelContainer {
    static let storeName = "FamiliarDevelopment"
    static let storeFilename = storeName + ".store"

    static var currentSchema: Schema { FamiliarModelSchema.schema }

    static func make(at storeURL: URL) throws -> ModelContainer {
        let schema = currentSchema
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeInMemory(name: String = "FamiliarTests") throws -> ModelContainer {
        let schema = currentSchema
        let configuration = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
