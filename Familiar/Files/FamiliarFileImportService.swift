import Foundation
import SwiftData

enum FamiliarFileImportError: LocalizedError {
    case emptyText, textTooLarge, invalidWebCapture, projectUnavailable, destinationChanged
    var errorDescription: String? {
        switch self {
        case .destinationChanged: String(localized: "resource.error.destination_changed")
        case .emptyText: String(localized: "resource.error.empty_text")
        case .textTooLarge: String(localized: "resource.error.text_too_large")
        case .invalidWebCapture: String(localized: "resource.error.invalid_web_capture")
        case .projectUnavailable: String(localized: "resource.error.project_unavailable", defaultValue: "The destination Project is no longer available.")
        }
    }
}

/// Import writes canonical Files only. The existing resource directory remains a byte backend.
@MainActor
struct FamiliarFileImportService {
    let store: FamiliarProjectResourceStore
    init(store: FamiliarProjectResourceStore = FamiliarProjectResourceStore()) { self.store = store }

    @discardableResult
    func importDocument(from sourceURL: URL, into project: FamiliarProject, in context: ModelContext) async throws -> FamiliarFileRecord {
        let interval = FamiliarPerformance.begin("FileImport")
        defer { interval.end() }
        let draft = try await FamiliarAttachmentStore.importDocument(from: sourceURL)
        defer { FamiliarAttachmentStore.remove(relativePath: draft.relativePath) }
        try Task.checkCancellation()
        try requireProject(project, in: context)
        guard let stagedURL = FamiliarAttachmentStore.url(for: draft.relativePath) else { throw FamiliarAttachmentStoreError.sourceUnavailable }
        let fileID = UUID(), versionID = UUID()
        let prepared = try await Self.copyDocument(store: store, source: stagedURL, projectID: project.id,
            fileID: fileID, versionID: versionID, filename: draft.filename, text: draft.extractedText)
        let copied = prepared.file
        do {
            try Task.checkCancellation()
            try requireProject(project, in: context)
            return try persist(id: fileID, versionID: versionID, name: draft.filename, origin: .projectImport,
                filename: draft.filename, mimeType: draft.mimeType, copied: copied, text: draft.extractedText, textHash: prepared.textHash,
                sourceURL: sourceURL.absoluteString, provenance: ["extractionEngine": draft.extractionEngine,
                    "extractionVersion": draft.extractionVersion, "detectedFormat": draft.detectedFormat,
                    "usedOCR": String(draft.usedOCR), "source": FamiliarFileSource.projectResource.rawValue],
                into: project, in: context)
        } catch { context.rollback(); try? store.removeVersion(relativePath: copied.relativePath); throw error }
    }

    @discardableResult
    func importPastedText(_ text: String, title: String? = nil, into project: FamiliarProject, in context: ModelContext) async throws -> FamiliarFileRecord {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw FamiliarFileImportError.emptyText }
        guard Int64(body.utf8.count) <= FamiliarAttachmentStore.maximumSourceBytes else { throw FamiliarFileImportError.textTooLarge }
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.flatMap { $0.isEmpty ? nil : String($0.prefix(240)) } ?? String(localized: "resource.pasted_text")
        let stem = URL(fileURLWithPath: displayName).lastPathComponent
        let filename = stem.lowercased().hasSuffix(".txt") ? stem : stem + ".txt"
        return try await saveText(body, name: displayName, filename: filename, origin: .projectImport,
            sourceURL: nil, provenance: ["extractionEngine": "user_paste", "extractionVersion": "1", "detectedFormat": "txt",
                "usedOCR": "false", "source": FamiliarFileSource.projectResource.rawValue], into: project, in: context)
    }

    @discardableResult
    func importWebPage(from urlString: String, into project: FamiliarProject, in context: ModelContext,
                       webContentService: FamiliarWebContentService = FamiliarWebContentService()) async throws -> FamiliarFileRecord {
        let (output, _) = try await webContentService.fetch(url: urlString)
        try Task.checkCancellation()
        return try await importFetchedWebText(output.capture, displayName: output.title, into: project, in: context)
    }

    @discardableResult
    func saveFetchedWebResult(runtimeID: String, toolCallID: String, in context: ModelContext) async throws -> FamiliarFileRecord {
        let activityID = FamiliarRunPersistenceRecorder.toolActivityID(runtimeID: runtimeID, toolCallID: toolCallID)
        guard let activity = try context.fetch(FetchDescriptor<FamiliarActivityRecord>(predicate: #Predicate { $0.activityID == activityID })).first,
              activity.toolName == "web_fetch", activity.phase == .succeeded,
              let result = try context.fetch(FetchDescriptor<FamiliarToolResultRecord>(predicate: #Predicate { $0.activityID == activityID })).first,
              activity.resultRecordID == result.id,
              let chat = try context.fetch(FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.runtimeID == runtimeID })).first?.conversation
        else { throw FamiliarFileImportError.invalidWebCapture }
        let expectedScope = chat.project.map { FamiliarWorkScope.project($0.id) } ?? .conversation(chat.id)
        let capturedEnvelope = result.envelopeJSON
        let output = try await Self.decodeCapture(capturedEnvelope)
        try Task.checkCancellation()
        try requireChat(chat, scope: expectedScope)
        guard !result.isDeleted, !activity.isDeleted, activity.phase == .succeeded,
              activity.resultRecordID == result.id, result.envelopeJSON == capturedEnvelope
        else { throw FamiliarFileImportError.invalidWebCapture }
        if let project = chat.project {
            return try await importFetchedWebText(output.capture, displayName: output.title, into: project, in: context,
                validateOwnership: {
                    try requireChat(chat, scope: expectedScope)
                    guard !result.isDeleted, !activity.isDeleted, activity.phase == .succeeded,
                          activity.resultRecordID == result.id, result.envelopeJSON == capturedEnvelope
                    else { throw FamiliarFileImportError.invalidWebCapture }
                })
        }
        let capture = output.capture
        let textHash = try await Self.validateCapture(capture)
        let scope = FamiliarWorkScope.conversation(chat.id)
        let originKey = output.capture.fileOriginKey
        try requireChat(chat, scope: scope)
        if let existing = try await savedCapture(originKey: originKey, scope: scope, textHash: textHash, in: context) {
            try requireChat(chat, scope: scope)
            return existing
        }
        let id = UUID(), filename = "Web-" + output.sourceID + ".txt"
        let fileStore = FamiliarFileStore()
        let stored = try await Self.writeCaptured(output.capture.resourceText, scope: scope, id: id, filename: filename)
        do {
            try Task.checkCancellation()
            try requireChat(chat, scope: scope)
            if let existing = try await savedCapture(originKey: originKey, scope: scope, textHash: textHash, in: context) {
                try requireChat(chat, scope: scope)
                try? fileStore.remove(scope: scope, fileID: id)
                return existing
            }
            try Task.checkCancellation()
            try requireChat(chat, scope: scope)
            let file = FamiliarFileRecord(id: id, scope: scope, displayName: output.title ?? output.finalURL,
                origin: .webCapture, chatIDs: [chat.id])
            file.originKey = originKey
            context.insert(file)
            context.insert(FamiliarFileVersionRecord(id: id, version: 1, filename: filename, mimeType: "text/plain",
                byteSize: stored.byteSize, contentHash: stored.hash, extractedText: output.capture.resourceText,
                extractedTextHash: textHash, storage: .init(kind: .file, relativePath: stored.path),
                sourceURLString: output.finalURL, createdByRunID: runtimeID, createdAt: output.accessedAt, file: file))
            try context.save()
            return file
        } catch { context.rollback(); try? fileStore.remove(scope: scope, fileID: id); throw error }
    }

    func importFetchedWebText(_ capture: FamiliarWebCapture, displayName: String? = nil, into project: FamiliarProject,
                              in context: ModelContext, validateOwnership: @MainActor () throws -> Void = {}) async throws -> FamiliarFileRecord {
        try validateOwnership()
        try requireProject(project, in: context)
        let textHash = try await Self.validateCapture(capture)
        try Task.checkCancellation()
        try validateOwnership()
        try requireProject(project, in: context)
        let originKey = capture.fileOriginKey
        if let existing = try await savedCapture(originKey: originKey, scope: .project(project.id), textHash: textHash, in: context) {
            try validateOwnership()
            try requireProject(project, in: context)
            return existing
        }
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await saveText(capture.resourceText, name: name.flatMap { $0.isEmpty ? nil : String($0.prefix(300)) } ?? capture.urlString,
            filename: "Web-" + capture.captureID + ".txt", origin: .webCapture, sourceURL: capture.urlString,
            provenance: ["source": FamiliarFileSource.webCapture.rawValue, "sourceCaptureID": capture.captureID,
                "capturedBodyHash": capture.contentHash, "capturedAt": capture.accessedAt.ISO8601Format(),
                "truncated": String(capture.truncated), "extractionEngine": "web_fetch", "extractionVersion": "1"],
            originKey: originKey, createdAt: capture.accessedAt, into: project, in: context, validateOwnership: validateOwnership)
    }

    func quickLookURL(for version: FamiliarFileVersionRecord) -> URL? { store.url(for: version.storageRelativePath) }

    private func saveText(_ text: String, name: String, filename: String, origin: FamiliarFileOrigin,
                          sourceURL: String?, provenance: [String: String], originKey: String? = nil, createdAt: Date = Date(),
                          into project: FamiliarProject, in context: ModelContext,
                          validateOwnership: @MainActor () throws -> Void = {}) async throws -> FamiliarFileRecord {
        try validateOwnership()
        try requireProject(project, in: context)
        let fileID = UUID(), versionID = UUID()
        let prepared = try await Self.copyText(store: store, text: text, projectID: project.id,
            fileID: fileID, versionID: versionID, filename: filename)
        let copied = prepared.file
        do {
            try Task.checkCancellation()
            try requireProject(project, in: context)
            if let originKey, let existing = try await savedCapture(originKey: originKey,
                scope: .project(project.id), textHash: prepared.textHash, in: context) {
                try validateOwnership()
                try requireProject(project, in: context)
                try? store.removeVersion(relativePath: copied.relativePath)
                return existing
            }
            try Task.checkCancellation()
            try validateOwnership()
            try requireProject(project, in: context)
            return try persist(id: fileID, versionID: versionID, name: name, origin: origin, filename: filename, mimeType: "text/plain",
                copied: copied, text: text, textHash: prepared.textHash, sourceURL: sourceURL, provenance: provenance, originKey: originKey,
                createdAt: createdAt, into: project, in: context)
        } catch { context.rollback(); try? store.removeVersion(relativePath: copied.relativePath); throw error }
    }


    private func requireChat(_ chat: FamiliarConversation, scope: FamiliarWorkScope) throws {
        guard chat.modelContext != nil, !chat.isDeleted,
              (chat.project.map { FamiliarWorkScope.project($0.id) } ?? .conversation(chat.id)) == scope
        else { throw FamiliarFileImportError.destinationChanged }
    }

    private func savedCapture(originKey: String, scope: FamiliarWorkScope, textHash: String,
                              in context: ModelContext) async throws -> FamiliarFileRecord? {
        let key = scope.storageKey
        guard let existing = try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate {
            $0.scopeKey == key && $0.originKey == originKey
        })).first else { return nil }
        guard let snapshot = existing.snapshot, existing.latestVersion?.extractedTextHash == textHash,
              let versionID = existing.latestVersion?.id else { throw FamiliarFileImportError.invalidWebCapture }
        let resourceURL = snapshot.storage.kind == .resource ? store.url(for: snapshot.storage.relativePath) : nil
        try await Self.verifyCapture(snapshot, scope: scope, resourceURL: resourceURL)
        try Task.checkCancellation()
        guard !existing.isDeleted, existing.scope == scope, existing.latestVersion?.id == versionID,
              existing.latestVersion?.extractedTextHash == textHash, existing.snapshot == snapshot else { throw FamiliarFileImportError.invalidWebCapture }
        return existing
    }

    private nonisolated struct PreparedResource: Sendable {
        let file: FamiliarStoredResourceFile
        let textHash: String
    }

    @concurrent private static func copyDocument(store: FamiliarProjectResourceStore, source: URL,
        projectID: UUID, fileID: UUID, versionID: UUID, filename: String, text: String) async throws -> PreparedResource {
        try Task.checkCancellation()
        let copied = try store.copyVersion(from: source, projectID: projectID, resourceID: fileID,
            version: 1, versionID: versionID, filename: filename)
        do {
            let hash = FamiliarHash.sha256(text)
            try Task.checkCancellation()
            return .init(file: copied, textHash: hash)
        } catch { try? store.removeVersion(relativePath: copied.relativePath); throw error }
    }

    @concurrent private static func copyText(store: FamiliarProjectResourceStore, text: String,
        projectID: UUID, fileID: UUID, versionID: UUID, filename: String) async throws -> PreparedResource {
        try Task.checkCancellation()
        let copied = try store.copyText(text, projectID: projectID, resourceID: fileID,
            version: 1, versionID: versionID, filename: filename)
        do {
            let hash = FamiliarHash.sha256(text)
            try Task.checkCancellation()
            return .init(file: copied, textHash: hash)
        } catch { try? store.removeVersion(relativePath: copied.relativePath); throw error }
    }

    @concurrent private static func decodeCapture(_ json: String) async throws -> FamiliarWebFetchOutput {
        try Task.checkCancellation()
        guard let envelope = try? JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(json.utf8)),
              let output = try? JSONDecoder().decode(FamiliarWebFetchOutput.self, from: Data(envelope.modelContent.utf8))
        else { throw FamiliarFileImportError.invalidWebCapture }
        return output
    }

    @concurrent private static func validateCapture(_ capture: FamiliarWebCapture) async throws -> String {
        try Task.checkCancellation()
        guard !capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Int64(capture.text.utf8.count) <= FamiliarAttachmentStore.maximumSourceBytes,
              capture.contentHash == FamiliarHash.sha256(capture.text),
              (try? FamiliarWebURLPolicy.normalize(capture.urlString)) != nil
        else { throw FamiliarFileImportError.invalidWebCapture }
        return FamiliarHash.sha256(capture.resourceText)
    }

    @concurrent private static func verifyCapture(_ snapshot: FamiliarFileSnapshot, scope: FamiliarWorkScope,
                                                  resourceURL: URL?) async throws {
        try Task.checkCancellation()
        if snapshot.storage.kind == .resource {
            guard let resourceURL, try FamiliarHash.sha256(contentsOf: resourceURL) == snapshot.contentHash
            else { throw FamiliarProjectResourceStoreError.sourceUnavailable }
        } else { _ = try FamiliarFileByteReader.read(snapshot, scope: scope) }
        try Task.checkCancellation()
    }

    @concurrent private static func writeCaptured(_ text: String, scope: FamiliarWorkScope, id: UUID,
                                                  filename: String) async throws -> (path: String, hash: String, byteSize: Int64) {
        try Task.checkCancellation()
        let data = Data(text.utf8)
        let store = FamiliarFileStore()
        let written = try store.write(data, scope: scope, fileID: id, filename: filename)
        do { try Task.checkCancellation(); return (written.path, written.hash, Int64(data.count)) }
        catch { try? store.remove(scope: scope, fileID: id); throw error }
    }

    private func requireProject(_ project: FamiliarProject, in context: ModelContext) throws {
        guard project.modelContext != nil, !project.isDeleted else { throw FamiliarFileImportError.projectUnavailable }
        let id = project.id
        guard
              try context.fetch(FetchDescriptor<FamiliarProject>(predicate: #Predicate { $0.id == id })).first != nil
        else { throw FamiliarFileImportError.projectUnavailable }
    }

    private func persist(id: UUID, versionID: UUID, name: String, origin: FamiliarFileOrigin, filename: String, mimeType: String,
                         copied: FamiliarStoredResourceFile, text: String, textHash: String, sourceURL: String?, provenance: [String: String],
                         originKey: String? = nil, createdAt: Date = Date(), into project: FamiliarProject, in context: ModelContext) throws -> FamiliarFileRecord {
        let file = FamiliarFileRecord(id: id, scope: .project(project.id), displayName: name, origin: origin,
            isProjectContext: true, createdAt: createdAt, updatedAt: createdAt)
        file.originKey = originKey
        var fields = provenance
        let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        fields["format"] = FamiliarFileFormat.allCases.first { $0.filenameExtension == fileExtension }?.rawValue ?? FamiliarFileFormat.plainText.rawValue
        let version = FamiliarFileVersionRecord(id: versionID, version: 1, filename: filename, mimeType: mimeType,
            byteSize: copied.byteSize, contentHash: copied.contentHash, extractedText: text, extractedTextHash: textHash,
            storage: .init(kind: .resource, relativePath: copied.relativePath), sourceURLString: sourceURL,
            provenanceJSON: String(decoding: try JSONEncoder().encode(fields), as: UTF8.self), createdAt: createdAt, file: file)
        context.insert(file); context.insert(version)
        project.updatedAt = max(project.updatedAt, createdAt)
        try context.save()
        return file
    }
}
