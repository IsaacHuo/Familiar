import Foundation
import SwiftData

/// One scoped entry for the product's Files. Byte layouts remain behind storage adapters.
nonisolated struct FamiliarFileCatalogService {
    func adoptLegacyOutputs(projectID: UUID, workspaceStore: FamiliarWorkspaceStore = .init(), in context: ModelContext) throws {
        let runs = try context.fetch(FetchDescriptor<FamiliarAgentRun>())
        let chats = try context.fetch(FetchDescriptor<FamiliarConversation>()).filter { ($0.project?.id ?? FamiliarProject.dailyProjectID) == projectID }
        let workspaces: [FamiliarWorkspaceID] = [.project(projectID)] + chats.map { .conversation($0.id) }
        let storedResults = try context.fetch(FetchDescriptor<FamiliarToolResultRecord>())
        let managed = FamiliarManagedFileStore()
        var captured: [FamiliarProducedFile] = []
        do {
            for workspace in workspaces {
                let directory = workspaceStore.rootURL.appendingPathComponent(workspace.directoryName).appendingPathComponent("Outputs")
                guard FileManager.default.fileExists(atPath: directory.path) else { continue }
                for entry in try workspaceStore.entries(in: workspace) where entry.relativePath.hasPrefix("Outputs/") {
                    let key = workspace.directoryName + "/" + entry.relativePath
                    if let existing = try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.projectID == projectID && $0.originKey == key })).first,
                       existing.latestVersion?.contentHash == entry.contentHash { continue }
                    let data = try workspaceStore.read(relativePath: entry.relativePath, in: workspace)
                    let output = try managed.capture(data, filename: URL(fileURLWithPath: entry.relativePath).lastPathComponent,
                        projectID: projectID, originKey: key, runID: nil, toolCallID: nil)
                    captured.append(output)
                    try stageProducedFiles([output], chatID: nil, in: context)
                    let versionID = output.versionID
                    guard let owner = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.id == versionID })).first?.file else { throw FamiliarFileError.missingFile }
                    // Historical path evidence associates a Chat; it does not claim these current
                    // workspace bytes are an exact capture from that old execution.
                    for run in runs {
                        guard let chatID = run.conversation?.id else { continue }
                        let runWorkspace = run.contextSnapshot?.projectID.map(FamiliarWorkspaceID.project) ?? .conversation(chatID)
                        guard runWorkspace == workspace else { continue }
                        for result in storedResults where result.runtimeID == run.runtimeID {
                            guard let envelope = try? JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(result.envelopeJSON.utf8)),
                                  case .shellExecution(let shell) = envelope.presentation.content,
                                  shell.status == "succeeded", (shell.addedFiles + shell.modifiedFiles).contains(entry.relativePath) else { continue }
                            if !owner.chatIDs.contains(chatID) { owner.chatIDs += [chatID] }
                        }
                    }
                }
            }
            if context.hasChanges { try context.save() }
        } catch {
            context.rollback()
            for file in captured { try? managed.remove(file) }
            throw error
        }
    }

    func snapshots(projectID: UUID, in context: ModelContext) throws -> [FamiliarFileSnapshot] {
        try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.projectID == projectID }))
            .compactMap(snapshot)
    }

    func snapshot(_ version: FamiliarFileVersionRecord) -> FamiliarFileSnapshot? {
        guard let file = version.file, file.id == version.fileID, file.projectID == version.projectID,
              let origin = FamiliarFileOrigin(rawValue: file.originRawValue),
              let kind = FamiliarFileStorageKind(rawValue: version.storageKindRawValue) else { return nil }
        return .init(reference: .init(fileID: file.id, versionID: version.id, projectID: file.projectID),
            name: file.displayName, origin: origin, version: version.version, filename: version.filename,
            mimeType: version.mimeType, byteSize: version.byteSize, contentHash: version.contentHash,
            storage: .init(kind: kind, relativePath: version.storageRelativePath), isProjectContext: file.isProjectContext,
            updatedAt: file.updatedAt)
    }

    func stageProducedFiles(_ produced: [FamiliarProducedFile], chatID: UUID?, in context: ModelContext) throws {
        for output in produced {
            let versionID = output.versionID
            if let existing = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.id == versionID })).first {
                guard existing.projectID == output.projectID, existing.contentHash == output.contentHash else { throw FamiliarFileError.contentMismatch }
                continue
            }
            let projectID = output.projectID, key = output.originKey
            let file: FamiliarFileRecord
            if let existing = try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.projectID == projectID && $0.originKey == key })).first {
                file = existing
            } else {
                file = FamiliarFileRecord(id: output.versionID, projectID: projectID, displayName: output.filename, origin: .shell)
                file.originKey = key
                context.insert(file)
            }
            if let chatID, !file.chatIDs.contains(chatID) { file.chatIDs += [chatID] }
            let row = FamiliarFileVersionRecord(id: output.versionID, version: file.lastVersionNumber + 1,
                filename: output.filename, mimeType: output.mimeType, byteSize: output.byteSize,
                contentHash: output.contentHash, extractedText: "", extractedTextHash: "", storage: output.storage,
                provenanceJSON: String(decoding: try JSONEncoder().encode(["workspaceOrigin": key]), as: UTF8.self),
                createdByRunID: output.createdByRunID, createdAt: output.capturedAt, file: file)
            row.createdByToolCallID = output.toolCallID
            context.insert(row)
            file.updatedAt = output.capturedAt
        }
    }

    func stageUndoProducedFiles(runID: String, toolCallID: String, in context: ModelContext) throws {
        let rows = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.createdByRunID == runID && $0.createdByToolCallID == toolCallID }))
        for row in rows {
            if let file = row.file, file.versions.count == 1 { context.delete(file) }
            else { context.delete(row) }
        }
    }

    func move(_ chat: FamiliarConversation, to project: FamiliarProject, in context: ModelContext) throws {
        guard chat.project?.id != project.id else { return }
        var copiedPaths: [String] = []
        do {
            try stageMove(chat, to: project, copiedPaths: &copiedPaths, in: context)
            try context.save()
        } catch {
            context.rollback()
            FamiliarAttachmentStore.remove(relativePaths: copiedPaths)
            throw error
        }
    }

    func stageMove(_ chat: FamiliarConversation, to project: FamiliarProject, copiedPaths: inout [String], in context: ModelContext) throws {
        guard let sourceProjectID = chat.project?.id, sourceProjectID != project.id else { return }
        let owned = try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.projectID == sourceProjectID }))
            .filter { $0.chatIDs.contains(chat.id) }
        for source in owned {
            guard let origin = FamiliarFileOrigin(rawValue: source.originRawValue) else { throw FamiliarFileError.invalidPath }
            let newID = UUID()
            let copy = FamiliarFileRecord(id: newID, projectID: project.id, displayName: source.displayName,
                origin: origin, chatIDs: [chat.id], createdAt: source.createdAt)
            context.insert(copy)
            for (index, version) in source.versions.sorted(by: { $0.version < $1.version }).enumerated() {
                let versionID = index == 0 ? newID : UUID()
                let reference = FamiliarFileReference(fileID: source.id, versionID: version.id, projectID: sourceProjectID)
                let data = try read(reference, inProject: sourceProjectID, context: context)
                let path = try FamiliarAttachmentStore.copyFileData(data, projectID: project.id, fileID: newID,
                    versionID: versionID, filename: version.filename)
                copiedPaths.append(path)
                context.insert(FamiliarFileVersionRecord(id: versionID, version: version.version,
                    filename: version.filename, mimeType: version.mimeType, byteSize: Int64(data.count),
                    contentHash: FamiliarHash.sha256(data), extractedText: version.extractedText,
                    extractedTextHash: version.extractedTextHash, storage: .init(kind: .attachment, relativePath: path),
                    sourceURLString: version.sourceURLString, provenanceJSON: version.provenanceJSON,
                    createdByRunID: version.createdByRunID, createdAt: version.createdAt, file: copy))
                for attachment in chat.messages.flatMap(\.attachments) where attachment.id == version.id || attachment.resourceVersion?.id == version.id {
                    attachment.id = versionID
                    attachment.relativePath = path
                    attachment.resourceVersion = nil
                }
            }
            source.chatIDs = source.chatIDs.filter { $0 != chat.id }
        }
        chat.project = project
        chat.contextSummary = nil
        chat.summaryThroughSequence = nil
        chat.updatedAt = Date()
    }

    func ownedAttachmentPaths(in context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>())
            .filter { $0.storageKindRawValue == FamiliarFileStorageKind.attachment.rawValue }.map(\.storageRelativePath))
    }

    func unownedAttachmentPaths(_ paths: [String], in context: ModelContext) -> [String] {
        // A lookup failure cannot authorize deleting bytes that may belong to Files.
        guard let owned = try? ownedAttachmentPaths(in: context) else { return [] }
        return paths.filter { !owned.contains($0) }
    }

    func stageRemoval(fileID: UUID, in context: ModelContext) throws {
        if let file = try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.id == fileID })).first {
            context.delete(file)
        }
    }

    func stageRemoval(versionID: UUID, in context: ModelContext) throws {
        guard let version = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.id == versionID })).first else { return }
        if let file = version.file, file.versions.count == 1 { context.delete(file) }
        else { context.delete(version) }
    }

    func url(for snapshot: FamiliarFileSnapshot) -> URL? {
        FamiliarFileByteReader.url(for: snapshot)
    }

    func read(_ reference: FamiliarFileReference, inProject projectID: UUID, context: ModelContext) throws -> Data {
        guard reference.projectID == projectID,
              let version = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.id == reference.versionID })).first,
              let file = version.file, file.id == reference.fileID, file.projectID == projectID,
              version.projectID == projectID, version.fileID == file.id,
              let origin = FamiliarFileOrigin(rawValue: file.originRawValue),
              let kind = FamiliarFileStorageKind(rawValue: version.storageKindRawValue) else { throw FamiliarFileError.invalidPath }
        let snapshot = FamiliarFileSnapshot(reference: reference, name: file.displayName, origin: origin,
            version: version.version, filename: version.filename, mimeType: version.mimeType,
            byteSize: version.byteSize, contentHash: version.contentHash,
            storage: .init(kind: kind, relativePath: version.storageRelativePath),
            isProjectContext: file.isProjectContext, updatedAt: file.updatedAt)
        guard let url = url(for: snapshot) else { throw FamiliarFileError.missingFile }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard version.contentHash.isEmpty || FamiliarHash.sha256(data) == version.contentHash else { throw FamiliarFileError.contentMismatch }
        return data
    }

    func setProjectContext(_ enabled: Bool, file: FamiliarFileRecord, in context: ModelContext) throws {
        file.isProjectContext = enabled
        do { try context.save() } catch { context.rollback(); throw error }
    }

    func stageUploads(_ attachments: [FamiliarAttachment], in context: ModelContext) throws {
        for attachment in attachments {
            guard attachment.resourceVersion == nil else { throw FamiliarFileError.invalidIdentifier }
            let projectID = attachment.message?.conversation?.project?.id ?? FamiliarProject.dailyProjectID
            let versionID = attachment.id
            let chatIDs = attachment.message?.conversation.map { [$0.id] } ?? []
            if let existing = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.id == versionID })).first {
                guard existing.projectID == projectID, existing.storageRelativePath == attachment.relativePath else { throw FamiliarFileError.contentMismatch }
                if let file = existing.file { file.chatIDs = Array(Set(file.chatIDs + chatIDs)) }
                continue
            }
            guard let url = FamiliarAttachmentStore.url(for: attachment.relativePath) else { throw FamiliarFileError.missingFile }
            let file = FamiliarFileRecord(id: versionID, projectID: projectID, displayName: attachment.filename,
                origin: .upload, chatIDs: chatIDs, createdAt: attachment.createdAt, updatedAt: attachment.createdAt)
            let provenance = ["extractionEngine": attachment.extractionEngine, "extractionVersion": attachment.extractionVersion,
                "detectedFormat": attachment.detectedFormat, "usedOCR": String(attachment.usedOCR)]
            let version = FamiliarFileVersionRecord(id: versionID, version: 1, filename: attachment.filename, mimeType: attachment.mimeType,
                byteSize: attachment.byteSize, contentHash: FamiliarHash.sha256(try Data(contentsOf: url, options: [.mappedIfSafe])),
                extractedText: attachment.extractedText, extractedTextHash: FamiliarHash.sha256(attachment.extractedText),
                storage: .init(kind: .attachment, relativePath: attachment.relativePath),
                provenanceJSON: String(decoding: try JSONEncoder().encode(provenance), as: UTF8.self), createdAt: attachment.createdAt, file: file)
            context.insert(file); context.insert(version)
        }
    }

    func contextResources(projectID: UUID, in context: ModelContext) throws -> [FamiliarContextResource] {
        try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.projectID == projectID && $0.isProjectContext })).compactMap { file in
            guard let version = file.latestVersion, version.projectID == projectID, version.fileID == file.id else { return nil }
            let text: String
            if !version.extractedText.isEmpty { text = version.extractedText }
            else {
                let reference = FamiliarFileReference(fileID: file.id, versionID: version.id, projectID: projectID)
                text = try FamiliarFileReadTool.extractText(data: read(reference, inProject: projectID, context: context), filename: version.filename).0
            }
            return .init(resourceID: file.id, resourceVersionID: version.id, version: version.version,
                displayName: file.displayName, filename: version.filename, mimeType: version.mimeType,
                contentHash: version.contentHash, extractedText: text,
                extractedTextHash: version.extractedTextHash.isEmpty ? FamiliarHash.sha256(Data(text.utf8)) : version.extractedTextHash, projectID: projectID)
        }
    }

    /// Remove bytes only after the metadata transaction commits, and restore them on failure.
    func delete(_ file: FamiliarFileRecord, in context: ModelContext) throws {
        let fileID = file.id
        let versions = file.versions
        var staged: [(original: URL, backup: URL)] = []
        do {
            for version in versions {
                guard let kind = FamiliarFileStorageKind(rawValue: version.storageKindRawValue),
                      let origin = FamiliarFileOrigin(rawValue: file.originRawValue) else { throw FamiliarFileError.invalidPath }
                let snapshot = FamiliarFileSnapshot(reference: .init(fileID: file.id, versionID: version.id, projectID: file.projectID),
                    name: file.displayName, origin: origin, version: version.version, filename: version.filename,
                    mimeType: version.mimeType, byteSize: version.byteSize, contentHash: version.contentHash,
                    storage: .init(kind: kind, relativePath: version.storageRelativePath),
                    isProjectContext: file.isProjectContext, updatedAt: file.updatedAt)
                guard let original = url(for: snapshot), FileManager.default.fileExists(atPath: original.path) else { continue }
                let backup = original.deletingLastPathComponent().appendingPathComponent(".deleted-" + UUID().uuidString)
                try FileManager.default.moveItem(at: original, to: backup)
                staged.append((original, backup))
            }
            if let resource = try context.fetch(FetchDescriptor<FamiliarResource>(predicate: #Predicate { $0.id == fileID })).first { context.delete(resource) }
            for stored in try context.fetch(FetchDescriptor<FamiliarStoredFileVersion>(predicate: #Predicate { $0.fileID == fileID })) { context.delete(stored) }
            context.delete(file)
            try context.save()
        } catch {
            context.rollback()
            for pair in staged.reversed() { try? FileManager.default.moveItem(at: pair.backup, to: pair.original) }
            throw error
        }
        for pair in staged { try? FileManager.default.removeItem(at: pair.backup) }
    }

}
