import Foundation
import SwiftData

enum FamiliarProjectResourceServiceError: LocalizedError {
    case emptyText
    case textTooLarge
    case invalidWebCapture

    var errorDescription: String? {
        switch self {
        case .emptyText:
            String(localized: "resource.error.empty_text", defaultValue: "Enter some text to import.")
        case .textTooLarge:
            String(localized: "resource.error.text_too_large", defaultValue: "The pasted text is too large to import.")
        case .invalidWebCapture:
            String(localized: "resource.error.invalid_web_capture", defaultValue: "This captured page is unavailable or could not be verified.")
        }
    }
}

@MainActor
struct FamiliarProjectResourceService {
    let store: FamiliarProjectResourceStore

    init(store: FamiliarProjectResourceStore = FamiliarProjectResourceStore()) {
        self.store = store
    }

    @discardableResult
    func importDocument(
        from sourceURL: URL,
        into project: FamiliarProject,
        in context: ModelContext
    ) async throws -> FamiliarResource {
        let draft = try await FamiliarAttachmentStore.importDocument(from: sourceURL)
        let resourceID = UUID()
        let versionID = UUID()
        var copied: FamiliarStoredResourceFile?
        defer { FamiliarAttachmentStore.remove(relativePath: draft.relativePath) }
        do {
            guard let stagedURL = FamiliarAttachmentStore.url(for: draft.relativePath) else {
                throw FamiliarAttachmentStoreError.sourceUnavailable
            }
            copied = try store.copyVersion(
                from: stagedURL,
                projectID: project.id,
                resourceID: resourceID,
                version: 1,
                versionID: versionID,
                filename: draft.filename
            )
            let now = Date()
            let resource = FamiliarResource(
                id: resourceID,
                displayName: draft.filename,
                createdAt: now,
                updatedAt: now,
                project: project
            )
            let version = FamiliarResourceVersion(
                id: versionID,
                version: 1,
                source: .importedFile,
                sourceURLString: sourceURL.absoluteString,
                filename: draft.filename,
                mimeType: draft.mimeType,
                originalRelativePath: try requireCopied(copied).relativePath,
                byteSize: try requireCopied(copied).byteSize,
                contentHash: try requireCopied(copied).contentHash,
                extractedText: draft.extractedText,
                extractedTextHash: Self.sha256(draft.extractedText),
                extractionEngine: draft.extractionEngine,
                extractionVersion: draft.extractionVersion,
                detectedFormat: draft.detectedFormat,
                usedOCR: draft.usedOCR,
                createdAt: now,
                resource: resource
            )
            context.insert(resource)
            context.insert(version)
            project.updatedAt = now
            try context.save()
            return resource
        } catch {
            context.rollback()
            if let copied { try? store.removeVersion(relativePath: copied.relativePath) }
            throw error
        }
    }

    func delete(_ resource: FamiliarResource, in context: ModelContext) throws {
        guard let projectID = resource.project?.id else {
            throw FamiliarProjectResourceStoreError.invalidRelativePath
        }
        let staged = try store.stageResourceDirectory(projectID: projectID, resourceID: resource.id)
        context.delete(resource)
        do {
            try context.save()
            if let staged { try store.discard(staged) }
        } catch {
            context.rollback()
            if let staged { try? store.restore(staged) }
            throw error
        }
    }

    func deleteAll(from project: FamiliarProject, in context: ModelContext) throws {
        let resources = project.resources
        guard !resources.isEmpty else { return }
        var staged: [FamiliarStagedResourceDirectory] = []
        do {
            for resource in resources {
                if let directory = try store.stageResourceDirectory(projectID: project.id, resourceID: resource.id) {
                    staged.append(directory)
                }
            }
            resources.forEach(context.delete)
            try context.save()
            for directory in staged { try store.discard(directory) }
        } catch {
            context.rollback()
            for directory in staged.reversed() { try? store.restore(directory) }
            throw error
        }
    }

    @discardableResult
    func importPastedText(
        _ text: String,
        title: String? = nil,
        into project: FamiliarProject,
        in context: ModelContext
    ) throws -> FamiliarResource {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { throw FamiliarProjectResourceServiceError.emptyText }
        guard Int64(Data(normalizedText.utf8).count) <= FamiliarAttachmentStore.maximumSourceBytes else {
            throw FamiliarProjectResourceServiceError.textTooLarge
        }
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = normalizedTitle.flatMap { $0.isEmpty ? nil : String($0.prefix(240)) }
            ?? String(localized: "resource.pasted_text", defaultValue: "Pasted Text")
        return try persistText(
            normalizedText,
            displayName: displayName,
            filename: Self.textFilename(for: displayName),
            source: .importedFile,
            sourceURLString: nil,
            extractionEngine: "user_paste",
            extractionVersion: "1",
            createdAt: Date(),
            into: project,
            in: context
        )
    }

    @discardableResult
    func importWebPage(
        from urlString: String,
        into project: FamiliarProject,
        in context: ModelContext,
        webContentService: FamiliarWebContentService = FamiliarWebContentService()
    ) async throws -> FamiliarResource {
        // Fetching finishes before any file or model is created. The web service applies
        // Familiar's HTTPS-only, public-address, redirect, type and response-size policy.
        let (output, _) = try await webContentService.fetch(url: urlString)
        return try importFetchedWebText(
            output.capture,
            displayName: output.title,
            into: project,
            in: context
        )
    }

    /// Invoked only by the user's Save button. Resolve ownership and bytes from the
    /// persisted successful tool result, never from model-provided UI arguments.
    @discardableResult
    func saveFetchedWebResult(runtimeID: String, toolCallID: String, in context: ModelContext) throws -> FamiliarResource {
        let activityID = FamiliarRunPersistenceRecorder.toolActivityID(runtimeID: runtimeID, toolCallID: toolCallID)
        let activities = FetchDescriptor<FamiliarActivityRecord>(predicate: #Predicate { $0.activityID == activityID })
        let results = FetchDescriptor<FamiliarToolResultRecord>(predicate: #Predicate { $0.activityID == activityID })
        let runs = FetchDescriptor<FamiliarAgentRun>(predicate: #Predicate { $0.runtimeID == runtimeID })
        guard let activity = try context.fetch(activities).first,
              activity.toolName == "web_fetch", activity.phase == .succeeded,
              let result = try context.fetch(results).first, activity.resultRecordID == result.id,
              let project = try context.fetch(runs).first?.conversation?.project,
              let envelope = try? JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(result.envelopeJSON.utf8)),
              let output = try? JSONDecoder().decode(FamiliarWebFetchOutput.self, from: Data(envelope.modelContent.utf8))
        else { throw FamiliarProjectResourceServiceError.invalidWebCapture }
        return try importFetchedWebText(output.capture, displayName: output.title, into: project, in: context)
    }

    func importFetchedWebText(
        _ capture: FamiliarWebCapture,
        displayName: String? = nil,
        into project: FamiliarProject,
        in context: ModelContext
    ) throws -> FamiliarResource {
        guard !capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Int64(capture.text.utf8.count) <= FamiliarAttachmentStore.maximumSourceBytes,
              capture.contentHash == Self.sha256(capture.text),
              (try? FamiliarWebURLPolicy.normalize(capture.urlString)) != nil else {
            throw FamiliarProjectResourceServiceError.invalidWebCapture
        }
        let text = capture.resourceText
        let textHash = Self.sha256(text)
        // Saving the same immutable capture twice must not grow Project context.
        let url = capture.urlString
        let versions = FetchDescriptor<FamiliarResourceVersion>(predicate: #Predicate {
            $0.sourceURLString == url && $0.extractedTextHash == textHash
        })
        if let version = try context.fetch(versions).first(where: { $0.source == .fetchedWeb && $0.resource?.project?.id == project.id }),
           let resource = version.resource {
            guard let file = store.url(for: version.originalRelativePath),
                  FamiliarHash.sha256(try Data(contentsOf: file)) == version.contentHash else {
                throw FamiliarProjectResourceStoreError.sourceUnavailable
            }
            return resource
        }
        let resourceID = UUID()
        let versionID = UUID()
        let filename = "Web-\(capture.captureID).txt"
        let copied = try store.copyText(text, projectID: project.id, resourceID: resourceID, version: 1, versionID: versionID, filename: filename)
        let now = capture.accessedAt
        let normalizedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resource = FamiliarResource(
            id: resourceID,
            displayName: normalizedDisplayName.flatMap { $0.isEmpty ? nil : String($0.prefix(300)) } ?? capture.urlString,
            createdAt: now,
            updatedAt: now,
            project: project
        )
        let version = FamiliarResourceVersion(id: versionID, version: 1, source: .fetchedWeb, sourceURLString: capture.urlString,
            filename: filename, mimeType: "text/plain", originalRelativePath: copied.relativePath, byteSize: copied.byteSize,
            contentHash: copied.contentHash, extractedText: text, extractedTextHash: textHash,
            extractionEngine: "web_fetch", extractionVersion: "1", detectedFormat: "txt", usedOCR: false, createdAt: now, resource: resource)
        context.insert(resource)
        context.insert(version)
        do { project.updatedAt = max(project.updatedAt, now); try context.save(); return resource }
        catch { context.rollback(); try? store.removeVersion(relativePath: copied.relativePath); throw error }
    }

    func quickLookURL(for version: FamiliarResourceVersion) -> URL? {
        store.url(for: version.originalRelativePath)
    }

    nonisolated static func sha256(_ text: String) -> String {
        FamiliarHash.sha256(text)
    }

    private func requireCopied(_ copied: FamiliarStoredResourceFile?) throws -> FamiliarStoredResourceFile {
        guard let copied else { throw FamiliarProjectResourceStoreError.copyFailed }
        return copied
    }

    private func persistText(
        _ text: String,
        displayName: String,
        filename: String,
        source: FamiliarResourceVersionSource,
        sourceURLString: String?,
        extractionEngine: String,
        extractionVersion: String,
        createdAt: Date,
        into project: FamiliarProject,
        in context: ModelContext
    ) throws -> FamiliarResource {
        let resourceID = UUID()
        let versionID = UUID()
        let copied = try store.copyText(
            text,
            projectID: project.id,
            resourceID: resourceID,
            version: 1,
            versionID: versionID,
            filename: filename
        )
        let resource = FamiliarResource(
            id: resourceID,
            displayName: displayName,
            createdAt: createdAt,
            updatedAt: createdAt,
            project: project
        )
        let version = FamiliarResourceVersion(
            id: versionID,
            version: 1,
            source: source,
            sourceURLString: sourceURLString,
            filename: filename,
            mimeType: "text/plain",
            originalRelativePath: copied.relativePath,
            byteSize: copied.byteSize,
            contentHash: copied.contentHash,
            extractedText: text,
            extractedTextHash: Self.sha256(text),
            extractionEngine: extractionEngine,
            extractionVersion: extractionVersion,
            detectedFormat: "txt",
            usedOCR: false,
            createdAt: createdAt,
            resource: resource
        )
        context.insert(resource)
        context.insert(version)
        do {
            project.updatedAt = createdAt
            try context.save()
            return resource
        } catch {
            context.rollback()
            try? store.removeVersion(relativePath: copied.relativePath)
            throw error
        }
    }

    private static func textFilename(for title: String) -> String {
        let value = URL(fileURLWithPath: title).lastPathComponent
        let stem = value.isEmpty || value == "." || value == ".." ? "Pasted Text" : value
        return stem.lowercased().hasSuffix(".txt") ? stem : stem + ".txt"
    }
}
