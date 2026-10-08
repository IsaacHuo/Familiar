import Foundation

nonisolated struct FamiliarFileWriteTool: FamiliarTool {
    struct Input: Decodable, Sendable { let title: String; let content: String; let format: FamiliarFileFormat? }
    private struct Output: Encodable { let fileIdentifier: String; let contentHash: String }
    private struct UndoOutput: Encodable { let undone: Bool; let fileIdentifier: String }
    let store: FamiliarFileStore
    let manifest = FamiliarToolManifest(
        name: "file_write", title: String(localized: "tool.file_write", defaultValue: "Save file"), description: "Save Markdown or plain text as an output in the current Project, including Daily Chat. Other formats require creating a real file and validating it with file_publish when that capability is enabled.",
        parameters: FamiliarJSONSchema(type: .object, properties: [
            "title": .init(type: .string, description: "文件标题"), "content": .init(type: .string, description: "Markdown 或纯文本正文"),
            "format": .init(type: .string, description: "markdown 或 plainText", enumValues: ["markdown", "plainText"])
        ], required: ["title", "content"]), effect: .reversibleWrite, risk: .low, requirements: [])

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarFileError.projectRequired }
        let format = input.format ?? .markdown
        guard format == .markdown || format == .plainText else { throw FamiliarFileError.unsupportedFormat }
        let id = UUID()
        let filename = input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "file.md" : input.title + (format == .markdown ? ".md" : ".txt")
        let data = Data(input.content.utf8)
        guard !data.isEmpty else { throw FamiliarFileError.emptyFile }
        let identifier = "file_" + id.uuidString
        return .action(FamiliarActionProposal(title: String(localized: "tool.file_write", defaultValue: "Save file"), fields: [
            .init(id: "title", label: String(localized: "file.field.title"), type: .text, value: input.title),
            .init(id: "size", label: String(localized: "file.field.size"), type: .text, value: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
        ], target: filename, targetKey: identifier, effect: manifest.effect, risk: manifest.risk, consequence: String(localized: "file.save.consequence"), undoPolicy: .currentSession,
            idempotencyKey: context.idempotencyKey, commit: {
                let stored = try store.write(data, projectID: projectID, fileID: id, filename: filename)
                let descriptor = FamiliarFileDescriptor(id: id, identifier: identifier, projectID: projectID, title: input.title,
                    format: format, relativePath: stored.path, byteSize: Int64(data.count), contentHash: stored.hash, source: .generated,
                    sourceURLString: nil, sourceResourceID: nil, sourceResourceVersionID: nil, sourceCaptureID: nil, createdByRunID: context.runID)
                let result = FamiliarToolExecutionResult(
                    envelope: try FamiliarToolResultEnvelope(
                        model: Output(fileIdentifier: identifier, contentHash: stored.hash),
                        presentation: .fileMutation(.init(summary: String(format: String(localized: "file.saved"), input.title), operation: "write", identifier: identifier, title: input.title, byteSize: Int64(data.count), contentHash: stored.hash))
                    ),
                    fileIdentifier: identifier,
                    file: descriptor
                )
                return FamiliarCommittedAction(result: result, undo: {
                    return .init(envelope: try FamiliarToolResultEnvelope(
                        model: UndoOutput(undone: true, fileIdentifier: identifier),
                        presentation: .mutationReceipt(.init(summary: String(format: String(localized: "file.removed"), input.title), operation: "undoFileWrite", targetIdentifier: identifier, succeeded: true, undoAvailable: false))
                    ))
                }, rollback: { try store.remove(projectID: projectID, fileID: id) })
            }))
    }
}

nonisolated struct FamiliarFileEditTool: FamiliarTool {
    struct Input: Decodable, Sendable { let identifier: String; let content: String; let title: String? }
    private struct Output: Encodable { let fileIdentifier: String; let contentHash: String }
    private struct UndoOutput: Encodable { let undone: Bool; let fileIdentifier: String }
    let store: FamiliarFileStore
    let manifest = FamiliarToolManifest(
        name: "file_edit", title: String(localized: "tool.file_edit", defaultValue: "Revise file"), description: "Save a new Markdown or text revision of the specified Project File. The previous version remains intact. Undo removes only the new revision.",
        parameters: FamiliarJSONSchema(type: .object, properties: [
            "identifier": .init(type: .string, description: "Predecessor file_ identifier"),
            "content": .init(type: .string, description: "New complete Markdown or plain-text content"),
            "title": .init(type: .string, description: "Optional new title")
        ], required: ["identifier", "content"]), effect: .reversibleWrite, risk: .low, requirements: [])

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarFileError.projectRequired }
        let known = context.files.first { "file_" + $0.reference.versionID.uuidString == input.identifier }
        let original: (id: UUID, filename: String, relativePath: String, data: Data)
        if let known {
            guard known.reference.projectID == projectID else { throw FamiliarFileError.invalidPath }
            original = (known.reference.versionID, known.filename, known.storage.relativePath,
                try FamiliarFileByteReader.read(known, projectID: projectID))
        } else {
            original = try store.editableFile(projectID: projectID, identifier: input.identifier)
        }
        guard ["md", "markdown", "txt"].contains(URL(fileURLWithPath: original.filename).pathExtension.lowercased()) else {
            throw FamiliarFileError.unsupportedFormat
        }
        let originalHash = FamiliarHash.sha256(original.data)
        let originalTitle = URL(fileURLWithPath: original.filename).deletingPathExtension().lastPathComponent
        let proposedTitle = input.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = proposedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? originalTitle
        let format: FamiliarFileFormat = original.filename.lowercased().hasSuffix(".txt") ? .plainText : .markdown
        let filename = title + "." + format.filenameExtension
        let data = Data(input.content.utf8)
        guard !data.isEmpty else { throw FamiliarFileError.emptyFile }
        let fileID = UUID()
        let identifier = "file_" + fileID.uuidString
        return .action(FamiliarActionProposal(title: String(localized: "tool.file_edit", defaultValue: "Revise file"), fields: [
            .init(id: "title", label: String(localized: "file.field.title"), type: .text, value: title),
            .init(id: "size", label: String(localized: "file.field.size"), type: .text, value: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
        ], target: filename, targetKey: input.identifier, effect: manifest.effect, risk: manifest.risk,
            consequence: String(localized: "file.revision.consequence", defaultValue: "Save a new version and keep the previous file."),
            undoPolicy: .currentSession, idempotencyKey: context.idempotencyKey, validateBeforeCommit: {
                let current = try known.map { try FamiliarFileByteReader.read($0, projectID: projectID) }
                    ?? store.read(relativePath: original.relativePath)
                guard FamiliarHash.sha256(current) == originalHash else {
                    throw FamiliarFileError.contentMismatch
                }
            }, commit: {
                let stored = try store.write(data, projectID: projectID, fileID: fileID, filename: filename)
                let descriptor = FamiliarFileDescriptor(id: fileID, identifier: identifier, projectID: projectID, title: title,
                    supersedesFileID: original.id, format: format, relativePath: stored.path, byteSize: Int64(data.count),
                    contentHash: stored.hash, source: .generated, sourceURLString: nil, sourceResourceID: nil,
                    sourceResourceVersionID: nil, sourceCaptureID: nil, createdByRunID: context.runID)
                let result = FamiliarToolExecutionResult(envelope: try .init(model: Output(fileIdentifier: identifier, contentHash: stored.hash),
                    presentation: .fileMutation(.init(summary: String(format: String(localized: "file.revised"), title), operation: "edit", identifier: identifier,
                        title: title, byteSize: Int64(data.count), contentHash: stored.hash))), fileIdentifier: identifier, file: descriptor)
                return FamiliarCommittedAction(result: result, undo: {
                    .init(envelope: try .init(model: UndoOutput(undone: true, fileIdentifier: identifier),
                        presentation: .mutationReceipt(.init(summary: String(format: String(localized: "file.removed"), title), operation: "undoFileEdit",
                            targetIdentifier: identifier, succeeded: true, undoAvailable: false))))
                }, rollback: { try store.remove(projectID: projectID, fileID: fileID) })
            }))
    }
}

nonisolated struct FamiliarFileReadTool: FamiliarTool {
    struct Input: Decodable, Sendable { let identifier: String }

    private struct Output: Encodable {
        let fileIdentifier: String
        let filename: String
        let extractedBy: String
        let characterCount: Int
        let truncated: Bool
        let text: String
    }

    /// Well below the 48k tool-result cap, leaving room for the envelope while still
    /// carrying a full report back to the model.
    static let maximumCharacters = 16_000

    let store: FamiliarFileStore
    let manifest = FamiliarToolManifest(
        name: "file_read",
        title: String(localized: "tool.file_read", defaultValue: "Read file"),
        description: "Read a frozen FileVersion available in this Project, including uploads, Project documents and generated results. DOCX, PDF and XLSX are parsed into Markdown; Markdown, text and HTML are returned as stored. Use this to check or revise a file you produced instead of assuming its contents.",
        parameters: .object(
            ["identifier": .string("File identifier beginning with file_.")],
            required: ["identifier"]
        ),
        effect: .read,
        risk: .low,
        dataDomains: ["project.files"],
        privacyLabels: ["project-only", "read-only"],
        supportsParallelism: true,
        requiredScopes: ["project"],
        executionClass: .specializedLocal
    )

    init(store: FamiliarFileStore = FamiliarFileStore()) { self.store = store }

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarFileError.projectRequired }
        let currentIdentifier = FamiliarStoredToolIdentity.currentFileIdentifier(input.identifier)
        let known = context.files.first { "file_" + $0.reference.versionID.uuidString == currentIdentifier }
        let filename: String
        let data: Data
        if let known {
            filename = known.filename
            data = try FamiliarFileByteReader.read(known, projectID: projectID)
        } else if let attachment = context.attachments.first(where: { "file_" + $0.id.uuidString == currentIdentifier }) {
            guard let url = FamiliarAttachmentStore.url(for: attachment.relativePath) else { throw FamiliarFileError.missingFile }
            filename = attachment.filename
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } else if let resource = context.resources.first(where: { "file_" + $0.versionID.uuidString == currentIdentifier }) {
            filename = resource.filename + ".txt"
            data = Data(resource.extractedText.utf8)
        } else {
            // Standalone storage adapters and historical byte references remain Project-scoped.
            let stored = try store.editableFile(projectID: projectID, identifier: input.identifier)
            filename = stored.filename
            data = stored.data
        }
        let (text, extractedBy) = try Self.extractText(data: data, filename: filename)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = trimmed.count > Self.maximumCharacters
        let bounded = truncated ? String(trimmed.prefix(Self.maximumCharacters)) : trimmed
        let output = Output(
            fileIdentifier: input.identifier,
            filename: filename,
            extractedBy: extractedBy,
            characterCount: trimmed.count,
            // Reported rather than silent: a model that believes it read the whole file
            // would revise a document it has only partly seen.
            truncated: truncated,
            text: bounded
        )
        let summary = truncated
            ? "已读取 \(filename) 的前 \(Self.maximumCharacters) 个字符，共 \(trimmed.count) 个字符。"
            : "已读取 \(filename)，共 \(trimmed.count) 个字符。"
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: output,
            presentation: .document(.init(
                summary: summary,
                title: filename,
                text: bounded,
                mimeType: "text/markdown"
            ))
        )))
    }

    /// Binary Office and PDF payloads go through AnyDoc; text formats are returned as
    /// stored so a Markdown File round-trips byte for byte.
    static func extractText(data: Data, filename: String) throws -> (text: String, extractedBy: String) {
        let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if ["md", "markdown", "txt", "html", "htm"].contains(fileExtension) {
            guard let value = String(data: data, encoding: .utf8) else {
                throw FamiliarFileError.contentMismatch
            }
            return (value, "utf8")
        }
        let conversion = try FamiliarAnyDocService.convert(data: data, filename: filename)
        return (conversion.markdown, FamiliarAnyDocService.engineName)
    }
}

nonisolated struct FamiliarFilePublishTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let path: String
        let title: String
        let format: FamiliarFileFormat
        let requiredText: [String]?
        var minimumSources: Int? = nil
        /// Identifier of the File this file replaces. Supplying it makes the new file
        /// the next version of the same deliverable instead of an unrelated one.
        ///
        /// Declared `var` rather than `let` with a default: a `let` carrying an initial
        /// value is excluded from the synthesized Decodable conformance, so the model's
        /// argument would be silently dropped and the parameter would be dead. As an
        /// optional `var` it is decoded and still defaults to nil for callers.
        var supersedes: String?
    }

    private struct Output: Encodable {
        let fileIdentifier: String
        let format: FamiliarFileFormat
        let byteSize: Int64
        let contentHash: String
        let validation: FamiliarValidationReceipt
    }

    private struct UndoOutput: Encodable {
        let undone: Bool
        let fileIdentifier: String
    }

    let resolver: FamiliarWorkspaceOutputResolver
    let store: FamiliarFileStore
    let manifest = FamiliarToolManifest(
        name: "file_publish",
        title: String(localized: "tool.file_publish", defaultValue: "Save generated file"),
        description: "Validate a real file already created in the current Workspace Outputs and publish it as a Project File. Supports DOCX, PDF, XLSX, HTML, Markdown, and plain text. Never claim delivery before this tool succeeds.",
        parameters: .object(
            [
                "path": .string("Relative Outputs path such as Outputs/北京资料.docx."),
                "title": .string("User-visible File title."),
                "format": .string("File format.", enumValues: FamiliarFileFormat.allCases.map(\.rawValue)),
                "requiredText": .stringArray(
                    "Optional strings that must be present in the parsed document content.",
                    itemDescription: "A short literal string expected in the parsed content."
                ),
                "minimumSources": .integer("Optional minimum distinct fetched source URLs that must be cited in the file.", minimum: 0, maximum: 16),
                "supersedes": .string("Identifier of the File this file replaces, beginning with file_. Supply it when revising a file you already published so the result becomes the next version of the same deliverable.")
            ],
            required: ["path", "title", "format"]
        ),
        effect: .reversibleWrite,
        risk: .low,
        dataDomains: ["workspace.outputs", "project.files"],
        privacyLabels: ["project-only", "validated-file", "content-hash"],
        supportsRecovery: true,
        requiredScopes: ["project", "workspace"],
        executionClass: .specializedLocal
    )

    init(workspaceStore: FamiliarWorkspaceStore, fileStore: FamiliarFileStore = FamiliarFileStore()) {
        resolver = FamiliarWorkspaceOutputResolver(store: workspaceStore)
        store = fileStore
    }

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID,
              let workspaceID = context.workspaceID,
              workspaceID == .project(projectID)
        else { throw FamiliarFileError.projectRequired }
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw FamiliarFileError.invalidPath }
        let output = try resolver.resolveOutput(relativePath: input.path, workspaceID: workspaceID)
        let fetched = context.fetchedSources.filter { $0.kind == .fetchedPage }
        let sourceURLs = Array(Set(fetched.map { $0.url.absoluteString })).sorted()
        let minimumSources = input.minimumSources ?? 0
        guard (0...16).contains(minimumSources), (input.requiredText?.count ?? 0) <= 16 else {
            throw FamiliarFileError.validationFailed("Invalid document validation requirements.")
        }
        guard sourceURLs.count >= minimumSources else { throw FamiliarFileError.validationFailed("Not enough successfully fetched sources.") }
        let required = Array(Set(input.requiredText ?? []))
        let validation = try FamiliarFileValidator.validate(fileURL: output.fileURL, format: input.format, requiredText: required)
        if minimumSources > 0 {
            let text = try FamiliarFileReadTool.extractText(data: Data(contentsOf: output.fileURL), filename: output.fileURL.lastPathComponent).text
            guard sourceURLs.filter({ text.contains($0) }).count >= minimumSources else { throw FamiliarFileError.validationFailed("The document must cite the fetched source URLs.") }
        }
        let id = UUID()
        let identifier = "file_" + id.uuidString
        // A malformed predecessor is rejected rather than ignored: silently publishing an
        // unrelated first version would lose the revision history the caller asked for.
        let supersedesFileID: UUID? = try input.supersedes
            .map { value -> UUID in
                guard value.hasPrefix("file_"),
                      let parsed = UUID(uuidString: String(value.dropFirst("file_".count)))
                else { throw FamiliarFileError.invalidIdentifier }
                return parsed
            }
        let filename = title.hasSuffix("." + input.format.filenameExtension)
            ? title
            : title + "." + input.format.filenameExtension
        return .action(.init(
            title: String(localized: "tool.file_publish", defaultValue: "Save generated file"),
            fields: [
                .init(id: "title", label: String(localized: "file.field.title"), type: .text, value: title),
                .init(id: "format", label: String(localized: "file.field.format"), type: .text, value: input.format.rawValue.uppercased()),
                .init(id: "size", label: String(localized: "file.field.size"), type: .text, value: ByteCountFormatter.string(fromByteCount: output.byteSize, countStyle: .file))
            ],
            target: filename,
            targetKey: identifier,
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: String(localized: "file.save.consequence"),
            undoPolicy: .currentSession,
            idempotencyKey: context.idempotencyKey,
            commit: {
                let imported = try store.importFile(
                    at: output.fileURL,
                    projectID: projectID,
                    fileID: id,
                    filename: filename,
                    maximumBytes: FamiliarFileValidator.maximumFileBytes
                )
                guard imported.hash == output.contentHash else {
                    try? store.remove(projectID: projectID, fileID: id)
                    throw FamiliarFileError.transactionFailed
                }
                let finalValidation = try FamiliarFileValidator.validate(fileURL: store.url(relativePath: imported.path)!, format: input.format, requiredText: required)
                guard finalValidation.extractedTextHash == validation.extractedTextHash else {
                    try? store.remove(projectID: projectID, fileID: id)
                    throw FamiliarFileError.transactionFailed
                }
                let descriptor = FamiliarFileDescriptor(
                    id: id,
                    identifier: identifier,
                    projectID: projectID,
                    title: title,
                    supersedesFileID: supersedesFileID,
                    format: input.format,
                    relativePath: imported.path,
                    byteSize: imported.byteSize,
                    contentHash: imported.hash,
                    source: .generated,
                    sourceURLString: nil,
                    sourceResourceID: nil,
                    sourceResourceVersionID: nil,
                    sourceCaptureID: nil,
                    createdByRunID: context.runID,
                    utiIdentifier: input.format.utiIdentifier,
                    mimeType: input.format.mimeType,
                    validationReceipt: validation
                )
                let result = FamiliarToolExecutionResult(
                    envelope: try .init(
                        model: Output(
                            fileIdentifier: identifier,
                            format: input.format,
                            byteSize: imported.byteSize,
                            contentHash: imported.hash,
                            validation: validation
                        ),
                        presentation: .fileMutation(.init(
                            summary: String(format: String(localized: "file.saved"), title),
                            operation: "publish",
                            identifier: identifier,
                            title: title,
                            byteSize: imported.byteSize,
                            contentHash: imported.hash
                        ))
                    ),
                    fileIdentifier: identifier,
                    file: descriptor
                )
                return FamiliarCommittedAction(result: result, undo: {
                    return .init(envelope: try .init(
                        model: UndoOutput(undone: true, fileIdentifier: identifier),
                        presentation: .mutationReceipt(.init(
                            summary: String(format: String(localized: "file.removed"), title),
                            operation: "undoFilePublish",
                            targetIdentifier: identifier,
                            succeeded: true,
                            undoAvailable: false
                        ))
                    ))
                }, rollback: { try store.remove(projectID: projectID, fileID: id) })
            }
        ))
    }
}
