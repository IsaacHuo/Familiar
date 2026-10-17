import Foundation
import SwiftData

/// One scoped entry for the product's Files. Byte layouts remain behind storage adapters.
nonisolated struct FamiliarFileCatalogService {
    func snapshots(scope: FamiliarWorkScope, in context: ModelContext) throws -> [FamiliarFileSnapshot] {
        let key = scope.storageKey
        return try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.scopeKey == key }))
            .compactMap(snapshot)
    }

    func snapshot(_ version: FamiliarFileVersionRecord) -> FamiliarFileSnapshot? {
        guard let file = version.file, file.id == version.fileID, file.scope == version.scope,
              let origin = FamiliarFileOrigin(rawValue: file.originRawValue),
              let kind = FamiliarFileStorageKind(rawValue: version.storageKindRawValue) else { return nil }
        return .init(reference: .init(fileID: file.id, versionID: version.id, scope: file.scope),
            name: file.displayName, origin: origin, version: version.version, filename: version.filename,
            mimeType: version.mimeType, byteSize: version.byteSize, contentHash: version.contentHash,
            storage: .init(kind: kind, relativePath: version.storageRelativePath), isProjectContext: file.isProjectContext,
            updatedAt: file.updatedAt)
    }

    func stageProducedFiles(_ produced: [FamiliarProducedFile], chatID: UUID?, in context: ModelContext) throws {
        for output in produced {
            let versionID = output.versionID
            if let existing = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.id == versionID })).first {
                guard existing.scope == output.scope, existing.contentHash == output.contentHash else { throw FamiliarFileError.contentMismatch }
                continue
            }
            let scope = output.scope, key = output.originKey
            let ownerKey = scope.storageKey
            let file: FamiliarFileRecord
            if let existing = try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.scopeKey == ownerKey && $0.originKey == key })).first {
                file = existing
            } else {
                file = FamiliarFileRecord(id: output.versionID, scope: scope, displayName: output.filename, origin: .shell)
                file.originKey = key
                context.insert(file)
            }
            if let chatID, !file.chatIDs.contains(chatID) { file.chatIDs += [chatID] }
            // Shell bytes always register. Known formats are parsed best-effort so the
            // Files content is checkable; a parse failure is recorded, never faked.
            let parsed = Self.parseProducedFile(output)
            var provenance: [String: String] = ["workspaceOrigin": key]
            for (name, value) in parsed.note { provenance["validation." + name] = value }
            let row = FamiliarFileVersionRecord(id: output.versionID, version: file.lastVersionNumber + 1,
                filename: output.filename, mimeType: output.mimeType, byteSize: output.byteSize,
                contentHash: output.contentHash, extractedText: parsed.text,
                extractedTextHash: parsed.text.isEmpty ? "" : FamiliarHash.sha256(parsed.text), storage: output.storage,
                provenanceJSON: String(decoding: try JSONEncoder().encode(provenance), as: UTF8.self),
                createdByRunID: output.createdByRunID, createdAt: output.capturedAt, file: file)
            row.createdByToolCallID = output.toolCallID
            context.insert(row)
            file.updatedAt = output.capturedAt
        }
    }

    private static let maximumExtractedCharacters = 48_000
    private static let maximumValidatedBytes: Int64 = 16 * 1_024 * 1_024

    private static func parseProducedFile(_ output: FamiliarProducedFile) -> (text: String, note: [String: String]) {
        let fileExtension = URL(fileURLWithPath: output.filename).pathExtension.lowercased()
        guard let format = FamiliarFileFormat.allCases.first(where: { $0.filenameExtension == fileExtension }) else {
            return ("", ["state": "unvalidated", "reason": "unknown-format"])
        }
        guard output.byteSize <= maximumValidatedBytes else {
            return ("", ["state": "unvalidated", "reason": "too-large"])
        }
        guard output.storage.kind == .managed,
              let url = try? FamiliarManagedFileStore().url(for: output.storage.relativePath) else {
            return ("", ["state": "unvalidated", "reason": "missing-bytes"])
        }
        do {
            let extraction = try FamiliarFileValidator.extract(fileURL: url, format: format)
            let text = String(extraction.text.prefix(maximumExtractedCharacters))
            return (text, [
                "state": "verified",
                "validator": extraction.validator,
                "validatorVersion": extraction.validatorVersion,
                "checks": extraction.checks.joined(separator: ",")
            ])
        } catch {
            return ("", ["state": "failed", "reason": error.localizedDescription])
        }
    }

    func stageUndoProducedFiles(runID: String, toolCallID: String, in context: ModelContext) throws {
        let rows = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.createdByRunID == runID && $0.createdByToolCallID == toolCallID }))
        for row in rows {
            if let file = row.file, file.versions.count == 1 { context.delete(file) }
            else { context.delete(row) }
        }
    }

    func move(_ chat: FamiliarConversation, to project: FamiliarProject?, in context: ModelContext) throws {
        guard !chat.agentRuns.contains(where: { $0.status == .running }) else { throw FamiliarProjectServiceError.projectHasRunningRun }
        let source = chat.project.map { FamiliarWorkScope.project($0.id) } ?? .conversation(chat.id)
        let target = project.map { FamiliarWorkScope.project($0.id) } ?? .conversation(chat.id)
        guard source != target else { return }
        var copiedPaths: [String] = [], staged: [FamiliarStagedFileDirectory] = []
        var workspace: FamiliarStagedWorkspaceDirectory?
        do {
            try stageMove(chat, to: target, copiedPaths: &copiedPaths, in: context)
            if source.conversationID != nil {
                if let value = try FamiliarFileStore().stageScopeDirectory(scope: source) { staged.append(value) }
                if let value = try FamiliarManagedFileStore().stageScopeDirectory(scope: source) { staged.append(value) }
                if let value = try FamiliarAttachmentStore.stageScopeDirectory(source) { staged.append(value) }
                workspace = try FamiliarWorkspaceStore().stageWorkspace(source)
            }
            chat.project = project
            try context.save()
        } catch {
            context.rollback()
            for value in staged.reversed() { try? FamiliarFileStore().restore(value) }
            if let workspace { try? FamiliarWorkspaceStore().restore(workspace) }
            FamiliarAttachmentStore.remove(relativePaths: copiedPaths)
            throw error
        }
        for value in staged { try? FamiliarFileStore().discard(value) }
        if let workspace { try? FamiliarWorkspaceStore().discard(workspace) }
    }

    func stageMove(_ chat: FamiliarConversation, to target: FamiliarWorkScope, copiedPaths: inout [String], in context: ModelContext) throws {
        let sourceScope = chat.project.map { FamiliarWorkScope.project($0.id) } ?? .conversation(chat.id)
        guard sourceScope != target else { return }
        let key = sourceScope.storageKey
        let owned = try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.scopeKey == key }))
            .filter { sourceScope.conversationID != nil || $0.chatIDs.contains(chat.id) }
        for source in owned {
            guard let origin = FamiliarFileOrigin(rawValue: source.originRawValue) else { throw FamiliarFileError.invalidPath }
            let newID = UUID()
            let copy = FamiliarFileRecord(id: newID, scope: target, displayName: source.displayName,
                origin: origin, chatIDs: [chat.id], createdAt: source.createdAt)
            context.insert(copy)
            for version in source.versions.sorted(by: { $0.version < $1.version }) {
                let versionID = UUID()
                let reference = FamiliarFileReference(fileID: source.id, versionID: version.id, scope: sourceScope)
                let data = try read(reference, inScope: sourceScope, context: context)
                let path = try FamiliarAttachmentStore.copyFileData(data, scope: target, fileID: newID,
                    versionID: versionID, filename: version.filename)
                copiedPaths.append(path)
                var provenance = (try? JSONDecoder().decode([String: String].self, from: Data(version.provenanceJSON.utf8))) ?? [:]
                provenance["sourceFileVersionIDs"] = String(decoding: try JSONEncoder().encode(Array(Set(version.sourceFileVersionIDs + [version.id]))), as: UTF8.self)
                provenance["sourceFileScope"] = sourceScope.storageKey
                let row = FamiliarFileVersionRecord(id: versionID, version: version.version,
                    filename: version.filename, mimeType: version.mimeType, byteSize: Int64(data.count),
                    contentHash: FamiliarHash.sha256(data), extractedText: version.extractedText,
                    extractedTextHash: version.extractedTextHash, storage: .init(kind: .attachment, relativePath: path),
                    sourceURLString: version.sourceURLString,
                    provenanceJSON: String(decoding: try JSONEncoder().encode(provenance), as: UTF8.self),
                    createdByRunID: version.createdByRunID, createdAt: version.createdAt, file: copy)
                row.createdByToolCallID = version.createdByToolCallID
                context.insert(row)
                for attachment in chat.messages.flatMap(\.attachments) where attachment.id == version.id || attachment.resourceVersion?.id == version.id {
                    attachment.id = versionID; attachment.relativePath = path; attachment.resourceVersion = nil
                }
            }
            source.chatIDs.removeAll { $0 == chat.id }
            if sourceScope.conversationID != nil { context.delete(source) }
        }
        chat.contextSummary = nil
        chat.summaryThroughSequence = nil
        chat.updatedAt = Date()
        // Authorization never follows a Chat into its new work scope.
        if sourceScope.conversationID != nil {
            for environment in try context.fetch(FetchDescriptor<FamiliarEnvironmentRecord>()) where environment.scopeKey == key { context.delete(environment) }
            for rule in try context.fetch(FetchDescriptor<FamiliarAuthorizationRuleRecord>()) where rule.scopeKey == key { context.delete(rule) }
        }
        for memory in try context.fetch(FetchDescriptor<FamiliarMemoryItem>()) where memory.conversationID == chat.id {
            memory.projectID = target.projectID
        }
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

    func read(_ reference: FamiliarFileReference, inScope scope: FamiliarWorkScope, context: ModelContext) throws -> Data {
        guard reference.scope == scope,
              let version = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.id == reference.versionID })).first,
              let file = version.file, file.id == reference.fileID, file.scope == scope,
              version.scope == scope, version.fileID == file.id,
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
        guard !enabled || file.scope.projectID != nil else { throw FamiliarFileError.workScopeRequired }
        file.isProjectContext = enabled
        do { try context.save() } catch { context.rollback(); throw error }
    }

    func stageUploads(_ attachments: [FamiliarAttachment], in context: ModelContext) throws {
        for attachment in attachments {
            guard attachment.resourceVersion == nil else { throw FamiliarFileError.invalidIdentifier }
            guard let chat = attachment.message?.conversation else { throw FamiliarFileError.workScopeRequired }
            let scope = chat.project.map { FamiliarWorkScope.project($0.id) } ?? .conversation(chat.id)
            let versionID = attachment.id
            let chatIDs = attachment.message?.conversation.map { [$0.id] } ?? []
            if let existing = try context.fetch(FetchDescriptor<FamiliarFileVersionRecord>(predicate: #Predicate { $0.id == versionID })).first {
                guard existing.scope == scope, existing.storageRelativePath == attachment.relativePath else { throw FamiliarFileError.contentMismatch }
                if let file = existing.file { file.chatIDs = Array(Set(file.chatIDs + chatIDs)) }
                continue
            }
            guard let url = FamiliarAttachmentStore.url(for: attachment.relativePath) else { throw FamiliarFileError.missingFile }
            let file = FamiliarFileRecord(id: versionID, scope: scope, displayName: attachment.filename,
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
        let scope = FamiliarWorkScope.project(projectID), key = FamiliarWorkScope.project(projectID).storageKey
        return try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.scopeKey == key && $0.isProjectContext })).compactMap { file in
            guard let version = file.latestVersion, version.scope == scope, version.fileID == file.id else { return nil }
            let text: String
            if !version.extractedText.isEmpty { text = version.extractedText }
            else {
                let reference = FamiliarFileReference(fileID: file.id, versionID: version.id, scope: scope)
                text = try FamiliarFileReadTool.extractText(data: read(reference, inScope: scope, context: context), filename: version.filename).0
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
                let snapshot = FamiliarFileSnapshot(reference: .init(fileID: file.id, versionID: version.id, scope: file.scope),
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
