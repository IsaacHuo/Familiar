import Foundation
import SwiftData

enum FamiliarSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FamiliarStoreSchemaV1.self, FamiliarFilesBridgeSchema.self, FamiliarFilesSchemaV3.self, FamiliarReleaseSchema.self]
    }

    static var stages: [MigrationStage] {
        [.custom(fromVersion: FamiliarStoreSchemaV1.self, toVersion: FamiliarFilesBridgeSchema.self,
                 willMigrate: nil, didMigrate: { context in
            try FamiliarFileMetadataMigration.convert(in: context, storedRows: context.fetch(FetchDescriptor<FamiliarSchemaV4.FamiliarArtifact>()))
            let projects = try context.fetch(FetchDescriptor<FamiliarProject>()).map(\.id)
            let chats = try context.fetch(FetchDescriptor<FamiliarConversation>())
            for projectID in Set(projects + chats.map { $0.project?.id ?? FamiliarProject.dailyProjectID }) {
                try FamiliarFileCatalogService().adoptLegacyOutputs(projectID: projectID, in: context)
            }
        }), .lightweight(fromVersion: FamiliarFilesBridgeSchema.self, toVersion: FamiliarFilesSchemaV3.self),
            .custom(fromVersion: FamiliarFilesSchemaV3.self, toVersion: FamiliarReleaseSchema.self,
                    willMigrate: { context in try FamiliarGrantArchiveMigration.archive(in: context) }, didMigrate: nil)]
    }
}

/// Historical Files schema. Stored definitions are unchanged; only Grant is removed in 4.0.0.
enum FamiliarFilesSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { FamiliarModelSchema.filesV3Models }
}

/// Internal migration-only bridge retains old generated-file rows until conversion succeeds.
enum FamiliarFilesBridgeSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        FamiliarModelSchema.legacyModels + [FamiliarFileRecord.self, FamiliarFileVersionRecord.self]
    }
}

/// Additive metadata conversion: no user bytes, audit records or old identities are deleted.
/// Legacy storage adapters remain available until their callers move to the Files service.
nonisolated enum FamiliarFileMetadataMigration {
    static func convert(in context: ModelContext, resourceRows: [FamiliarResource]? = nil,
                        storedRows: [FamiliarSchemaV4.FamiliarArtifact]? = [],
                        attachmentRows: [FamiliarAttachment]? = nil, save: Bool = true) throws {
        if save {
            let bindings = try context.fetch(FetchDescriptor<FamiliarProjectCapabilityBindingRecord>())
            for binding in bindings {
                let name = FamiliarStoredToolIdentity.currentName(binding.capabilityID)
                guard name != binding.capabilityID else { continue }
                if let existing = bindings.first(where: { !$0.isDeleted && $0 !== binding && $0.projectID == binding.projectID && $0.capabilityID == name }) {
                    existing.enabled = existing.enabled && binding.enabled
                    context.delete(binding)
                    continue
                }
                binding.capabilityID = name
                binding.bindingKey = "\(binding.projectID.uuidString):\(name)"
            }
            let chats = try context.fetch(FetchDescriptor<FamiliarConversation>())
            for memory in try context.fetch(FetchDescriptor<FamiliarMemoryItem>()) where memory.scopeRawValue == "conversation" && memory.projectID == nil {
                if let chat = chats.first(where: { $0.id == memory.conversationID }) { memory.projectID = chat.project?.id ?? FamiliarProject.dailyProjectID }
            }
        }
        var files = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<FamiliarFileRecord>()).map { ($0.id, $0) })
        let existingVersions = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>())
        var versionIDs = Set(existingVersions.map(\.id))
        let resources = try resourceRows ?? context.fetch(FetchDescriptor<FamiliarResource>())
        for resource in resources {
            guard let project = resource.project else { throw FamiliarFileMigrationError.missingOwner(resource.id) }
            let file = files[resource.id] ?? FamiliarFileRecord(id: resource.id, projectID: project.id,
                displayName: resource.displayName,
                origin: resource.versions.contains { $0.source == .fetchedWeb } ? .webCapture : .projectImport,
                isProjectContext: true, createdAt: resource.createdAt, updatedAt: resource.updatedAt)
            if files[resource.id] == nil { context.insert(file); files[file.id] = file }
            if file.originKey == nil, let capture = resource.versions.first(where: { $0.source == .fetchedWeb }),
               capture.extractedText.hasPrefix("[Captured web page; untrusted external content]"),
               let sourceLine = capture.extractedText.split(separator: "\n").prefix(6).first(where: { $0.hasPrefix("Source ID: ") }) {
                if let hashLine = capture.extractedText.split(separator: "\n").prefix(6).first(where: { $0.hasPrefix("Captured text SHA-256: ") }) {
                    file.originKey = "web:" + String(sourceLine.dropFirst("Source ID: ".count)) + "|"
                        + String(capture.createdAt.timeIntervalSince1970) + "|" + String(hashLine.dropFirst("Captured text SHA-256: ".count))
                }
            }
            guard file.projectID == project.id else { throw FamiliarFileMigrationError.conflictingIdentity(file.id) }
            for version in resource.versions where !versionIDs.contains(version.id) {
                let provenance = try encode(["extractionEngine": version.extractionEngine,
                    "extractionVersion": version.extractionVersion, "detectedFormat": version.detectedFormat,
                    "usedOCR": String(version.usedOCR), "source": version.sourceRawValue])
                context.insert(FamiliarFileVersionRecord(id: version.id, version: version.version,
                    filename: version.filename, mimeType: version.mimeType, byteSize: version.byteSize,
                    contentHash: version.contentHash, extractedText: version.extractedText,
                    extractedTextHash: version.extractedTextHash,
                    storage: .init(kind: .resource, relativePath: version.originalRelativePath),
                    sourceURLString: version.sourceURLString, provenanceJSON: provenance,
                    createdAt: version.createdAt, file: file))
                versionIDs.insert(version.id)
            }
        }

        let storedVersions = try storedRows ?? context.fetch(FetchDescriptor<FamiliarSchemaV4.FamiliarArtifact>())
        for stored in storedVersions.sorted(by: { $0.version < $1.version }) {
            let record = files[stored.lineageID] ?? FamiliarFileRecord(id: stored.lineageID,
                projectID: stored.projectID, displayName: stored.title,
                origin: stored.source == .webCapture ? .webCapture : .generated,
                createdAt: stored.createdAt, updatedAt: stored.updatedAt)
            if files[record.id] == nil { context.insert(record); files[record.id] = record }
            guard record.projectID == stored.projectID,
                  record.originRawValue == FamiliarFileOrigin.generated.rawValue || record.originRawValue == FamiliarFileOrigin.webCapture.rawValue
            else { throw FamiliarFileMigrationError.conflictingIdentity(record.id) }
            if !versionIDs.contains(stored.id) {
                let provenance = try encode(["identifier": stored.identifier, "title": stored.title, "format": stored.formatRawValue, "utiIdentifier": stored.utiIdentifier ?? "",
                    "source": stored.sourceKindRawValue, "sourceCaptureID": stored.sourceCaptureID ?? "",
                    "sourceResourceID": stored.sourceResourceID?.uuidString ?? "",
                    "sourceResourceVersionID": stored.sourceResourceVersionID?.uuidString ?? "",
                    "validationReceipt": stored.validationReceiptJSON ?? ""])
                context.insert(FamiliarFileVersionRecord(id: stored.id, version: stored.version,
                    filename: URL(fileURLWithPath: stored.relativePath).lastPathComponent,
                    mimeType: stored.mimeType ?? "application/octet-stream", byteSize: stored.byteSize,
                    contentHash: stored.contentHash, extractedText: "", extractedTextHash: "",
                    storage: .init(kind: .file, relativePath: stored.relativePath),
                    sourceURLString: stored.sourceURLString, provenanceJSON: provenance,
                    createdByRunID: stored.createdByRunID, createdAt: stored.createdAt, file: record))
                versionIDs.insert(stored.id)
            }
            if stored.updatedAt >= record.updatedAt { record.displayName = stored.title; record.updatedAt = stored.updatedAt }
            if let runID = stored.createdByRunID,
               let chat = try context.fetch(FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.runtimeID == runID })).first?.conversation {
                associate(chat.id, with: record)
            }
        }

        for attachment in try attachmentRows ?? context.fetch(FetchDescriptor<FamiliarAttachment>()) {
            guard let chat = attachment.message?.conversation else { throw FamiliarFileMigrationError.missingOwner(attachment.id) }
            let projectID = chat.project?.id ?? FamiliarProject.dailyProjectID
            if let known = existingVersions.first(where: { $0.id == attachment.id }), let file = known.file {
                guard file.projectID == projectID, known.storageRelativePath == attachment.relativePath else {
                    throw FamiliarFileMigrationError.conflictingIdentity(attachment.id)
                }
                associate(chat.id, with: file)
                continue
            }
            if let resource = attachment.resourceVersion?.resource, let file = files[resource.id] {
                // Only an existing explicit same-Project relationship may share identity.
                guard file.projectID == projectID else { throw FamiliarFileMigrationError.conflictingIdentity(attachment.id) }
                associate(chat.id, with: file)
                continue
            }
            let file = files[attachment.id] ?? FamiliarFileRecord(id: attachment.id, projectID: projectID,
                displayName: attachment.filename, origin: .upload, chatIDs: [chat.id],
                createdAt: attachment.createdAt, updatedAt: attachment.createdAt)
            if files[file.id] == nil { context.insert(file); files[file.id] = file }
            guard file.projectID == projectID else { throw FamiliarFileMigrationError.conflictingIdentity(file.id) }
            associate(chat.id, with: file)
            if !versionIDs.contains(attachment.id) {
                let provenance = try encode(["attachmentID": attachment.id.uuidString,
                    "extractionEngine": attachment.extractionEngine, "extractionVersion": attachment.extractionVersion,
                    "detectedFormat": attachment.detectedFormat, "usedOCR": String(attachment.usedOCR),
                    "contentHashStatus": "notRecordedByLegacyAttachment"])
                // The old Attachment never stored a byte hash. Do not invent one or read all bytes during migration.
                context.insert(FamiliarFileVersionRecord(id: attachment.id, version: 1,
                    filename: attachment.filename, mimeType: attachment.mimeType, byteSize: attachment.byteSize,
                    contentHash: "", extractedText: attachment.extractedText,
                    extractedTextHash: FamiliarHash.sha256(Data(attachment.extractedText.utf8)),
                    storage: .init(kind: .attachment, relativePath: attachment.relativePath),
                    provenanceJSON: provenance, createdAt: attachment.createdAt, file: file))
                versionIDs.insert(attachment.id)
            }
        }
        // Saving inside the migration transaction lets SwiftData roll back a failed conversion.
        if save { try context.save() }
    }

    private static func associate(_ chatID: UUID, with file: FamiliarFileRecord) {
        if !file.chatIDs.contains(chatID) { file.chatIDs = file.chatIDs + [chatID] }
    }

    private static func encode(_ fields: [String: String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(fields), as: UTF8.self)
    }
}

nonisolated enum FamiliarFileMigrationError: Error {
    case missingOwner(UUID)
    case conflictingIdentity(UUID)
}
