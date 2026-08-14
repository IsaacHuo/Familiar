import CryptoKit
import Foundation
import SwiftData

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

    func importFetchedWebText(_ capture: FamiliarWebCapture, into project: FamiliarProject, in context: ModelContext) throws -> FamiliarResource {
        let resourceID = UUID()
        let versionID = UUID()
        let filename = "Web-\(capture.captureID).txt"
        let copied = try store.copyText(capture.text, projectID: project.id, resourceID: resourceID, version: 1, versionID: versionID, filename: filename)
        let now = capture.accessedAt
        let resource = FamiliarResource(id: resourceID, displayName: capture.urlString, createdAt: now, updatedAt: now, project: project)
        let version = FamiliarResourceVersion(id: versionID, version: 1, source: .fetchedWeb, sourceURLString: capture.urlString,
            filename: filename, mimeType: "text/plain", originalRelativePath: copied.relativePath, byteSize: copied.byteSize,
            contentHash: copied.contentHash, extractedText: capture.text, extractedTextHash: capture.contentHash,
            extractionEngine: "web_fetch", extractionVersion: "1", detectedFormat: "txt", usedOCR: false, createdAt: now, resource: resource)
        context.insert(resource)
        context.insert(version)
        do { project.updatedAt = now; try context.save(); return resource }
        catch { context.rollback(); try? store.removeVersion(relativePath: copied.relativePath); throw error }
    }

    func quickLookURL(for version: FamiliarResourceVersion) -> URL? {
        store.url(for: version.originalRelativePath)
    }

    nonisolated static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func requireCopied(_ copied: FamiliarStoredResourceFile?) throws -> FamiliarStoredResourceFile {
        guard let copied else { throw FamiliarProjectResourceStoreError.copyFailed }
        return copied
    }
}
