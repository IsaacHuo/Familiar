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
typealias FamiliarActivityRecord = FamiliarSchemaV10.FamiliarActivityRecord
typealias FamiliarToolResultRecord = FamiliarSchemaV10.FamiliarToolResultRecord
typealias FamiliarApprovalRecord = FamiliarSchemaV10.FamiliarApprovalRecord
typealias FamiliarResponseBlockRecord = FamiliarSchemaV10.FamiliarResponseBlockRecord
typealias FamiliarClarificationRecord = FamiliarSchemaV10.FamiliarClarificationRecord

nonisolated enum FamiliarStoreProfile: Sendable {
    case development
    case release

    static var current: FamiliarStoreProfile {
#if DEBUG
        .development
#else
        .release
#endif
    }

    var storeName: String {
        switch self {
        case .development: "FamiliarDevelopment"
        case .release: "Familiar"
        }
    }
}

enum FamiliarModelContainer {
    static var storeName: String { FamiliarStoreProfile.current.storeName }
    static var storeFilename: String { storeName + ".store" }

    static var currentSchema: Schema { Schema(versionedSchema: FamiliarReleaseSchemaV1.self) }

    static func make(at storeURL: URL, configurationName: String = storeName) throws -> ModelContainer {
        let schema = currentSchema
        let configuration = ModelConfiguration(
            configurationName,
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: FamiliarReleaseMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func makeInMemory(name: String = "FamiliarTests") throws -> ModelContainer {
        let schema = currentSchema
        let configuration = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: FamiliarReleaseMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
