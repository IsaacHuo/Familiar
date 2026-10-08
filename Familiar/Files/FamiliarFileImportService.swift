import Foundation
import SwiftData

enum FamiliarFileImportError: LocalizedError {
    case emptyText, textTooLarge, invalidWebCapture, projectUnavailable
    var errorDescription: String? {
        switch self {
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
        let draft = try await FamiliarAttachmentStore.importDocument(from: sourceURL)
        defer { FamiliarAttachmentStore.remove(relativePath: draft.relativePath) }
        try Task.checkCancellation()
        try requireProject(project, in: context)
        guard let stagedURL = FamiliarAttachmentStore.url(for: draft.relativePath) else { throw FamiliarAttachmentStoreError.sourceUnavailable }
        let fileID = UUID(), versionID = UUID()
        let copied = try store.copyVersion(from: stagedURL, projectID: project.id, resourceID: fileID,
            version: 1, versionID: versionID, filename: draft.filename)
        do {
            try Task.checkCancellation()
            return try persist(id: fileID, versionID: versionID, name: draft.filename, origin: .projectImport,
                filename: draft.filename, mimeType: draft.mimeType, copied: copied, text: draft.extractedText,
                sourceURL: sourceURL.absoluteString, provenance: ["extractionEngine": draft.extractionEngine,
                    "extractionVersion": draft.extractionVersion, "detectedFormat": draft.detectedFormat,
                    "usedOCR": String(draft.usedOCR), "source": FamiliarFileSource.projectResource.rawValue],
                into: project, in: context)
        } catch { context.rollback(); try? store.removeVersion(relativePath: copied.relativePath); throw error }
    }

    @discardableResult
    func importPastedText(_ text: String, title: String? = nil, into project: FamiliarProject, in context: ModelContext) throws -> FamiliarFileRecord {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw FamiliarFileImportError.emptyText }
        guard Int64(body.utf8.count) <= FamiliarAttachmentStore.maximumSourceBytes else { throw FamiliarFileImportError.textTooLarge }
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.flatMap { $0.isEmpty ? nil : String($0.prefix(240)) } ?? String(localized: "resource.pasted_text")
        let stem = URL(fileURLWithPath: displayName).lastPathComponent
        let filename = stem.lowercased().hasSuffix(".txt") ? stem : stem + ".txt"
        return try saveText(body, name: displayName, filename: filename, origin: .projectImport,
            sourceURL: nil, provenance: ["extractionEngine": "user_paste", "extractionVersion": "1", "detectedFormat": "txt",
                "usedOCR": "false", "source": FamiliarFileSource.projectResource.rawValue], into: project, in: context)
    }

    @discardableResult
    func importWebPage(from urlString: String, into project: FamiliarProject, in context: ModelContext,
                       webContentService: FamiliarWebContentService = FamiliarWebContentService()) async throws -> FamiliarFileRecord {
        let (output, _) = try await webContentService.fetch(url: urlString)
        try Task.checkCancellation()
        return try importFetchedWebText(output.capture, displayName: output.title, into: project, in: context)
    }

    @discardableResult
    func saveFetchedWebResult(runtimeID: String, toolCallID: String, in context: ModelContext) throws -> FamiliarFileRecord {
        let activityID = FamiliarRunPersistenceRecorder.toolActivityID(runtimeID: runtimeID, toolCallID: toolCallID)
        guard let activity = try context.fetch(FetchDescriptor<FamiliarActivityRecord>(predicate: #Predicate { $0.activityID == activityID })).first,
              activity.toolName == "web_fetch", activity.phase == .succeeded,
              let result = try context.fetch(FetchDescriptor<FamiliarToolResultRecord>(predicate: #Predicate { $0.activityID == activityID })).first,
              activity.resultRecordID == result.id,
              let project = try context.fetch(FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.runtimeID == runtimeID })).first?.conversation?.project,
              let envelope = try? JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(result.envelopeJSON.utf8)),
              let output = try? JSONDecoder().decode(FamiliarWebFetchOutput.self, from: Data(envelope.modelContent.utf8))
        else { throw FamiliarFileImportError.invalidWebCapture }
        return try importFetchedWebText(output.capture, displayName: output.title, into: project, in: context)
    }

    func importFetchedWebText(_ capture: FamiliarWebCapture, displayName: String? = nil, into project: FamiliarProject,
                              in context: ModelContext) throws -> FamiliarFileRecord {
        try requireProject(project, in: context)
        guard !capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Int64(capture.text.utf8.count) <= FamiliarAttachmentStore.maximumSourceBytes,
              capture.contentHash == FamiliarHash.sha256(capture.text),
              (try? FamiliarWebURLPolicy.normalize(capture.urlString)) != nil else { throw FamiliarFileImportError.invalidWebCapture }
        let projectID = project.id, textHash = FamiliarHash.sha256(capture.resourceText)
        let originKey = capture.fileOriginKey
        let candidates = try context.fetch(FetchDescriptor<FamiliarFileRecord>(predicate: #Predicate { $0.projectID == projectID && $0.originKey == originKey }))
        if let existing = candidates.first, let version = existing.latestVersion {
            guard version.extractedTextHash == textHash, let url = store.url(for: version.storageRelativePath),
                  FamiliarHash.sha256(try Data(contentsOf: url)) == version.contentHash else { throw FamiliarProjectResourceStoreError.sourceUnavailable }
            return existing
        }
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try saveText(capture.resourceText, name: name.flatMap { $0.isEmpty ? nil : String($0.prefix(300)) } ?? capture.urlString,
            filename: "Web-" + capture.captureID + ".txt", origin: .webCapture, sourceURL: capture.urlString,
            provenance: ["source": FamiliarFileSource.webCapture.rawValue, "sourceCaptureID": capture.captureID,
                "capturedBodyHash": capture.contentHash, "capturedAt": capture.accessedAt.ISO8601Format(),
                "truncated": String(capture.truncated), "extractionEngine": "web_fetch", "extractionVersion": "1"],
            originKey: originKey, createdAt: capture.accessedAt, into: project, in: context)
    }

    func quickLookURL(for version: FamiliarFileVersionRecord) -> URL? { store.url(for: version.storageRelativePath) }

    private func saveText(_ text: String, name: String, filename: String, origin: FamiliarFileOrigin,
                          sourceURL: String?, provenance: [String: String], originKey: String? = nil, createdAt: Date = Date(),
                          into project: FamiliarProject, in context: ModelContext) throws -> FamiliarFileRecord {
        try requireProject(project, in: context)
        let fileID = UUID(), versionID = UUID()
        let copied = try store.copyText(text, projectID: project.id, resourceID: fileID, version: 1, versionID: versionID, filename: filename)
        do {
            return try persist(id: fileID, versionID: versionID, name: name, origin: origin, filename: filename, mimeType: "text/plain",
                copied: copied, text: text, sourceURL: sourceURL, provenance: provenance, originKey: originKey,
                createdAt: createdAt, into: project, in: context)
        } catch { context.rollback(); try? store.removeVersion(relativePath: copied.relativePath); throw error }
    }

    private func requireProject(_ project: FamiliarProject, in context: ModelContext) throws {
        guard project.modelContext != nil, !project.isDeleted else { throw FamiliarFileImportError.projectUnavailable }
        let id = project.id
        guard
              try context.fetch(FetchDescriptor<FamiliarProject>(predicate: #Predicate { $0.id == id })).first != nil
        else { throw FamiliarFileImportError.projectUnavailable }
    }

    private func persist(id: UUID, versionID: UUID, name: String, origin: FamiliarFileOrigin, filename: String, mimeType: String,
                         copied: FamiliarStoredResourceFile, text: String, sourceURL: String?, provenance: [String: String],
                         originKey: String? = nil, createdAt: Date = Date(), into project: FamiliarProject, in context: ModelContext) throws -> FamiliarFileRecord {
        let file = FamiliarFileRecord(id: id, projectID: project.id, displayName: name, origin: origin,
            isProjectContext: true, createdAt: createdAt, updatedAt: createdAt)
        file.originKey = originKey
        var fields = provenance
        let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        fields["format"] = FamiliarFileFormat.allCases.first { $0.filenameExtension == fileExtension }?.rawValue ?? FamiliarFileFormat.plainText.rawValue
        let version = FamiliarFileVersionRecord(id: versionID, version: 1, filename: filename, mimeType: mimeType,
            byteSize: copied.byteSize, contentHash: copied.contentHash, extractedText: text, extractedTextHash: FamiliarHash.sha256(text),
            storage: .init(kind: .resource, relativePath: copied.relativePath), sourceURLString: sourceURL,
            provenanceJSON: String(decoding: try JSONEncoder().encode(fields), as: UTF8.self), createdAt: createdAt, file: file)
        context.insert(file); context.insert(version)
        project.updatedAt = max(project.updatedAt, createdAt)
        try context.save()
        return file
    }
}
