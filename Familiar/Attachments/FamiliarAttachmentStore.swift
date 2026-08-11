import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision

nonisolated enum FamiliarAttachmentStoreError: LocalizedError, Sendable {
    case sourceUnavailable
    case unsupportedFile
    case fileTooLarge
    case malformedDocument
    case unreadableDocument
    case emptyDocument
    case invalidRelativePath
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            return String(localized: "attachment.error.source_unavailable", defaultValue: "The selected file is unavailable.")
        case .unsupportedFile:
            return String(localized: "attachment.error.unsupported_file", defaultValue: "Only PDF, TXT, and Markdown files are supported.")
        case .fileTooLarge:
            return String(localized: "attachment.error.file_too_large", defaultValue: "The file is larger than the 25 MiB limit.")
        case .malformedDocument:
            return String(localized: "attachment.error.malformed_document", defaultValue: "The document is malformed and cannot be read.")
        case .unreadableDocument:
            return String(localized: "attachment.error.unreadable_document", defaultValue: "The document could not be read.")
        case .emptyDocument:
            return String(localized: "attachment.error.empty_document", defaultValue: "The document is empty.")
        case .invalidRelativePath:
            return String(localized: "attachment.error.invalid_path", defaultValue: "The attachment path is invalid.")
        case .copyFailed:
            return String(localized: "attachment.error.copy_failed", defaultValue: "The attachment could not be copied.")
        }
    }
}

nonisolated enum FamiliarAttachmentStore {
    private static let maximumSourceBytes: Int64 = 25 * 1024 * 1024
    private static let fileManager = FileManager.default

    private static var attachmentsURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Familiar", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
    }

    private static var draftsURL: URL {
        attachmentsURL.appendingPathComponent("Drafts", isDirectory: true)
    }

    private static func messagesURL(for messageID: UUID) -> URL {
        attachmentsURL.appendingPathComponent("Messages", isDirectory: true)
            .appendingPathComponent(messageID.uuidString, isDirectory: true)
    }

    static func importDocument(from sourceURL: URL) async throws -> FamiliarAttachmentDraft {
        let task = Task.detached(priority: .userInitiated) {
            try await importDocumentOffMain(from: sourceURL)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func importDocumentOffMain(from sourceURL: URL) async throws -> FamiliarAttachmentDraft {
        try Task.checkCancellation()
        let filename = sanitizedFilename(sourceURL.lastPathComponent)
        guard isSupported(filename) else { throw FamiliarAttachmentStoreError.unsupportedFile }

        let draftURL = try makeDraftURL(filename: filename)
        let sourceSize: Int64
        do {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            }
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw FamiliarAttachmentStoreError.sourceUnavailable
            }
            sourceSize = try fileSize(of: sourceURL)
            guard sourceSize <= maximumSourceBytes else {
                throw FamiliarAttachmentStoreError.fileTooLarge
            }
            do {
                try fileManager.copyItem(at: sourceURL, to: draftURL)
            } catch let error as FamiliarAttachmentStoreError {
                throw error
            } catch {
                throw FamiliarAttachmentStoreError.copyFailed
            }
            try verifyCopiedFile(draftURL, expectedSize: sourceSize)
        } catch {
            try? fileManager.removeItem(at: draftURL)
            throw error
        }
        do {
            try Task.checkCancellation()
            let conversion = try await extractDocument(from: draftURL, filename: filename)
            return try makeDraft(
                filename: filename,
                relativePath: relativePath(for: draftURL),
                conversion: conversion,
                byteSize: sourceSize
            )
        } catch {
            try? fileManager.removeItem(at: draftURL)
            throw error
        }
    }

    static func stageCopy(of attachment: FamiliarAttachmentSnapshot) throws -> FamiliarAttachmentDraft {
        let sourceURL = try validatedStoreURL(for: attachment.relativePath)
        guard fileManager.fileExists(atPath: sourceURL.path) else { throw FamiliarAttachmentStoreError.sourceUnavailable }
        let size = try fileSize(of: sourceURL)
        guard size <= maximumSourceBytes else { throw FamiliarAttachmentStoreError.fileTooLarge }
        let filename = sanitizedFilename(attachment.filename)
        guard isSupported(filename) else { throw FamiliarAttachmentStoreError.unsupportedFile }
        let destinationURL = try makeDraftURL(filename: filename)
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try verifyCopiedFile(destinationURL, expectedSize: size)
        } catch let error as FamiliarAttachmentStoreError {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw FamiliarAttachmentStoreError.copyFailed
        }
        return FamiliarAttachmentDraft(
            id: UUID(),
            kind: .document,
            filename: filename,
            mimeType: attachment.mimeType,
            relativePath: relativePath(for: destinationURL),
            extractedText: attachment.extractedText,
            byteSize: size,
            extractionEngine: attachment.extractionEngine,
            extractionVersion: attachment.extractionVersion,
            detectedFormat: attachment.detectedFormat,
            usedOCR: attachment.usedOCR
        )
    }

    static func committedCopy(of draft: FamiliarAttachmentDraft, messageID: UUID) throws -> String {
        let sourceURL = try validatedStoreURL(for: draft.relativePath)
        guard fileManager.fileExists(atPath: sourceURL.path) else { throw FamiliarAttachmentStoreError.sourceUnavailable }
        let size = try fileSize(of: sourceURL)
        guard size <= maximumSourceBytes else { throw FamiliarAttachmentStoreError.fileTooLarge }
        let directory = messagesURL(for: messageID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destinationURL = directory.appendingPathComponent(
            draft.id.uuidString + "-" + sanitizedFilename(draft.filename),
            isDirectory: false
        )
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try verifyCopiedFile(destinationURL, expectedSize: size)
        } catch let error as FamiliarAttachmentStoreError {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw FamiliarAttachmentStoreError.copyFailed
        }
        return relativePath(for: destinationURL)
    }

    static func url(for relativePath: String) -> URL? {
        guard let url = try? validatedStoreURL(for: relativePath),
              fileManager.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    static func remove(relativePath: String) {
        guard let url = try? validatedStoreURL(for: relativePath) else { return }
        try? fileManager.removeItem(at: url)
    }

    static func remove(relativePaths: [String]) {
        for path in relativePaths { remove(relativePath: path) }
    }

    static func pruneDrafts(keeping relativePaths: Set<String>) {
        guard let entries = try? fileManager.contentsOfDirectory(at: draftsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        for entry in entries where !relativePaths.contains(relativePath(for: entry)) {
            try? fileManager.removeItem(at: entry)
        }
    }

    private static func isSupported(_ filename: String) -> Bool {
        FamiliarAnyDocService.supportedExtensions.contains(
            URL(fileURLWithPath: filename).pathExtension.lowercased()
        )
    }

    private static func mimeType(for filename: String) -> String {
        let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if fileExtension == "md" || fileExtension == "markdown" { return "text/markdown" }
        return UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    private static func sanitizedFilename(_ filename: String) -> String {
        let base = URL(fileURLWithPath: filename).lastPathComponent
        let allowed = base.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            return (value >= 32 && value != 47 && value != 92 && value != 127) ? Character(String(scalar)) : "_"
        }
        let result = String(allowed).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty || result == "." || result == ".." ? "attachment" : String(result.prefix(240))
    }

    private static func makeDraftURL(filename: String) throws -> URL {
        try fileManager.createDirectory(at: draftsURL, withIntermediateDirectories: true)
        return draftsURL.appendingPathComponent(UUID().uuidString + "-" + sanitizedFilename(filename), isDirectory: false)
    }

    private static func relativePath(for url: URL) -> String {
        let prefix = attachmentsURL.standardizedFileURL.path + "/"
        return String(url.standardizedFileURL.path.dropFirst(prefix.count))
    }

    private static func validatedStoreURL(for relativePath: String) throws -> URL {
        let path = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains(where: { $0 == ".." || $0.isEmpty }) else { throw FamiliarAttachmentStoreError.invalidRelativePath }
        let url = attachmentsURL.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(attachmentsURL.standardizedFileURL.path + "/") else { throw FamiliarAttachmentStoreError.invalidRelativePath }
        return url
    }

    private static func fileSize(of url: URL) throws -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true, let size = values.fileSize else { throw FamiliarAttachmentStoreError.sourceUnavailable }
        return Int64(size)
    }

    private static func verifyCopiedFile(_ url: URL, expectedSize: Int64) throws {
        guard try fileSize(of: url) == expectedSize else { throw FamiliarAttachmentStoreError.copyFailed }
    }

    private static func makeDraft(
        filename: String,
        relativePath: String,
        conversion: FamiliarAnyDocConversion,
        byteSize: Int64
    ) throws -> FamiliarAttachmentDraft {
        guard !conversion.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FamiliarAttachmentStoreError.emptyDocument
        }
        return FamiliarAttachmentDraft(
            id: UUID(),
            kind: .document,
            filename: filename,
            mimeType: mimeType(for: filename),
            relativePath: relativePath,
            extractedText: conversion.markdown,
            byteSize: byteSize,
            extractionEngine: FamiliarAnyDocService.engineName,
            extractionVersion: conversion.engineVersion,
            detectedFormat: conversion.formatID,
            usedOCR: conversion.usedOCR
        )
    }

    private static func extractDocument(
        from url: URL,
        filename: String
    ) async throws -> FamiliarAnyDocConversion {
        try Task.checkCancellation()
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw FamiliarAttachmentStoreError.unreadableDocument
        }

        do {
            let conversion = try FamiliarAnyDocService.convert(data: data, filename: filename)
            guard url.pathExtension.lowercased() == "pdf" else { return conversion }
            let scannedPages = try await extractScannedPDFPages(from: url)
            guard !scannedPages.isEmpty else { return conversion }
            return FamiliarAnyDocConversion(
                markdown: conversion.markdown + "\n\n---\n\n# OCR text from scanned pages\n\n" + scannedPages,
                formatID: conversion.formatID,
                engineVersion: conversion.engineVersion,
                usedOCR: true
            )
        } catch let error as FamiliarAnyDocError {
            guard url.pathExtension.lowercased() == "pdf",
                  case .unsupported = error
            else { throw error }
            let markdown = try await extractPDFWithVisionFallback(from: url)
            return FamiliarAnyDocConversion(
                markdown: markdown,
                formatID: "pdf",
                engineVersion: FamiliarAnyDocService.engineVersion,
                usedOCR: true
            )
        }
    }

    private static func extractPDFWithVisionFallback(from url: URL) async throws -> String {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw FamiliarAttachmentStoreError.malformedDocument
        }
        var pageTexts: [String] = []
        pageTexts.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else {
                pageTexts.append("")
                continue
            }
            let embeddedText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !embeddedText.isEmpty {
                pageTexts.append(embeddedText)
                continue
            }

            pageTexts.append(try recognizeText(on: page))
        }
        let text = pageTexts.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FamiliarAttachmentStoreError.emptyDocument
        }
        return text
    }

    private static func extractScannedPDFPages(from url: URL) async throws -> String {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw FamiliarAttachmentStoreError.malformedDocument
        }
        var sections: [String] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            let embeddedText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard embeddedText.isEmpty else { continue }
            let recognized = try recognizeText(on: page)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recognized.isEmpty else { continue }
            sections.append("## Page \(index + 1)\n\n\(recognized)")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func recognizeText(on page: PDFPage) throws -> String {
        guard let image = page.thumbnail(
            of: CGSize(width: 1800, height: 2400),
            for: .mediaBox
        ).cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
