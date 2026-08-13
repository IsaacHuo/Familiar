import Social
import UniformTypeIdentifiers
import UIKit

@objc(FamiliarShareViewController)
final class FamiliarShareViewController: SLComposeServiceViewController {
    private var isSaving = false

    override func isContentValid() -> Bool {
        let hasText = !(contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .contains(where: { !($0.attachments ?? []).isEmpty }) == true
        return !isSaving && (hasText || hasAttachments)
    }

    override func didSelectPost() {
        guard !isSaving else { return }
        isSaving = true
        validateContent()

        Task { @MainActor in
            do {
                let collected = try await collectInput()
                defer { try? FileManager.default.removeItem(at: collected.temporaryDirectoryURL) }
                try FamiliarSharedInbox.enqueue(text: collected.text, fileURLs: collected.fileURLs)
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                isSaving = false
                validateContent()
                presentFailure(error)
            }
        }
    }

    override func configurationItems() -> [Any]! { [] }

    override func presentationAnimationDidFinish() {
        super.presentationAnimationDidFinish()
        textView.accessibilityLabel = String(localized: "share.comment.accessibility_label")
    }

    private func collectInput() async throws -> FamiliarCollectedShare {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FamiliarShare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)

        var textParts: [String] = []
        appendText(contentText, to: &textParts)
        var fileURLs: [URL] = []

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for item in items {
            appendText(item.attributedContentText?.string, to: &textParts)
            for provider in item.attachments ?? [] {
                if fileURLs.count >= FamiliarSharedInbox.maximumFiles { break }
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    let value = try await loadItem(from: provider, typeIdentifier: UTType.fileURL.identifier)
                    if case .url(let sourceURL) = value,
                       FamiliarShareTemporaryFiles.isSupportedDocument(sourceURL) {
                        fileURLs.append(try FamiliarShareTemporaryFiles.copy(
                            from: sourceURL,
                            suggestedName: provider.suggestedName,
                            into: temporaryDirectoryURL
                        ))
                    }
                    continue
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    let value = try await loadItem(from: provider, typeIdentifier: UTType.url.identifier)
                    if case .url(let url) = value { appendText(url.absoluteString, to: &textParts) }
                    continue
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let value = try await loadItem(from: provider, typeIdentifier: UTType.plainText.identifier)
                    if case .text(let string) = value {
                        appendText(string, to: &textParts)
                    }
                    continue
                }
                if let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
                    guard let type = UTType(identifier) else { return false }
                    return type.conforms(to: .data) && !type.conforms(to: .image) && !type.conforms(to: .movie)
                }) {
                    fileURLs.append(try await loadFile(
                        from: provider,
                        typeIdentifier: typeIdentifier,
                        into: temporaryDirectoryURL
                    ))
                }
            }
        }

        let text = textParts.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !fileURLs.isEmpty else {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
            throw FamiliarSharedInboxError.noContent
        }
        return FamiliarCollectedShare(text: text, fileURLs: fileURLs, temporaryDirectoryURL: temporaryDirectoryURL)
    }

    private func loadItem(from provider: NSItemProvider, typeIdentifier: String) async throws -> FamiliarLoadedShareItem? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = value as? URL {
                    continuation.resume(returning: .url(url))
                } else if let string = value as? String {
                    continuation.resume(returning: .text(string))
                } else if let attributed = value as? NSAttributedString {
                    continuation.resume(returning: .text(attributed.string))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadFile(
        from provider: NSItemProvider,
        typeIdentifier: String,
        into directoryURL: URL
    ) async throws -> URL {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { sourceURL, error in
                do {
                    if let error { throw error }
                    guard let sourceURL else { throw FamiliarSharedInboxError.sourceUnavailable }
                    let destinationURL = try FamiliarShareTemporaryFiles.copy(
                        from: sourceURL,
                        suggestedName: suggestedName,
                        into: directoryURL
                    )
                    continuation.resume(returning: destinationURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func appendText(_ text: String?, to parts: inout [String]) {
        guard let text else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !parts.contains(trimmed) else { return }
        parts.append(trimmed)
    }

    private func presentFailure(_ error: Error) {
        let alert = UIAlertController(
            title: String(localized: "share.error.title"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "share.retry"), style: .default))
        present(alert, animated: true)
    }
}

private struct FamiliarCollectedShare {
    let text: String
    let fileURLs: [URL]
    let temporaryDirectoryURL: URL
}

private nonisolated enum FamiliarLoadedShareItem: Sendable {
    case text(String)
    case url(URL)
}

private nonisolated enum FamiliarShareTemporaryFiles {
    static func isSupportedDocument(_ sourceURL: URL) -> Bool {
        let resourceType = try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        let inferredType = UTType(filenameExtension: sourceURL.pathExtension)
        guard let contentType = resourceType ?? inferredType else { return true }
        return !contentType.conforms(to: .image) && !contentType.conforms(to: .movie)
    }

    static func copy(from sourceURL: URL, suggestedName: String?, into directoryURL: URL) throws -> URL {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let suggested = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalName = (suggested?.isEmpty == false ? suggested : nil) ?? sourceURL.lastPathComponent
        var filename = URL(fileURLWithPath: originalName).lastPathComponent
        if URL(fileURLWithPath: filename).pathExtension.isEmpty,
           !sourceURL.pathExtension.isEmpty {
            filename += ".\(sourceURL.pathExtension)"
        }
        let destinationURL = directoryURL.appendingPathComponent(UUID().uuidString + "-" + filename)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
}
