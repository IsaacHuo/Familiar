import Foundation

nonisolated struct FamiliarArtifactWriteTool: FamiliarTool {
    struct Input: Decodable, Sendable { let title: String; let content: String; let format: FamiliarArtifactFormat? }
    private struct Output: Encodable { let artifactIdentifier: String; let contentHash: String }
    private struct UndoOutput: Encodable { let undone: Bool; let artifactIdentifier: String }
    let store: FamiliarArtifactStore
    let manifest = FamiliarToolManifest(
        name: "artifact_write", title: "写入 Artifact", description: "Save Markdown or plain text as an output in the current Project, including Daily Chat. Other formats require creating a real file and validating it with artifact_publish when that capability is enabled.",
        parameters: FamiliarJSONSchema(type: .object, properties: [
            "title": .init(type: .string, description: "文件标题"), "content": .init(type: .string, description: "Markdown 或纯文本正文"),
            "format": .init(type: .string, description: "markdown 或 plainText", enumValues: ["markdown", "plainText"])
        ], required: ["title", "content"]), effect: .reversibleWrite, risk: .low, requirements: [])

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarArtifactError.projectRequired }
        let format = input.format ?? .markdown
        guard format == .markdown || format == .plainText else { throw FamiliarArtifactError.unsupportedFormat }
        let id = UUID()
        let filename = input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "artifact.md" : input.title + (format == .markdown ? ".md" : ".txt")
        let data = Data(input.content.utf8)
        guard !data.isEmpty else { throw FamiliarArtifactError.emptyFile }
        let identifier = "artifact_" + id.uuidString
        return .action(FamiliarActionProposal(title: "写入 Artifact", fields: [
            .init(id: "title", label: "标题", type: .text, value: input.title),
            .init(id: "size", label: "大小", type: .number, value: String(data.count))
        ], target: identifier, effect: manifest.effect, risk: manifest.risk, consequence: "将在当前项目中写入新的 Artifact。", undoPolicy: .currentSession,
            idempotencyKey: context.idempotencyKey, commit: {
                let stored = try store.write(data, projectID: projectID, artifactID: id, filename: filename)
                let descriptor = FamiliarArtifactDescriptor(id: id, identifier: identifier, projectID: projectID, title: input.title,
                    format: format, relativePath: stored.path, byteSize: Int64(data.count), contentHash: stored.hash, source: .generated,
                    sourceURLString: nil, sourceResourceID: nil, sourceResourceVersionID: nil, sourceCaptureID: nil, createdByRunID: context.runID)
                let result = FamiliarToolExecutionResult(
                    envelope: try FamiliarToolResultEnvelope(
                        model: Output(artifactIdentifier: identifier, contentHash: stored.hash),
                        presentation: .artifactMutation(.init(summary: "已写入 \(input.title)", operation: "write", identifier: identifier, title: input.title, byteSize: Int64(data.count), contentHash: stored.hash))
                    ),
                    artifactIdentifier: identifier,
                    artifact: descriptor
                )
                return FamiliarCommittedAction(result: result, undo: {
                    return .init(envelope: try FamiliarToolResultEnvelope(
                        model: UndoOutput(undone: true, artifactIdentifier: identifier),
                        presentation: .mutationReceipt(.init(summary: "已撤销写入 \(input.title)", operation: "undoArtifactWrite", targetIdentifier: identifier, succeeded: true, undoAvailable: false))
                    ))
                }, rollback: { try store.remove(projectID: projectID, artifactID: id) })
            }))
    }
}

nonisolated struct FamiliarArtifactEditTool: FamiliarTool {
    struct Input: Decodable, Sendable { let identifier: String; let content: String; let title: String? }
    private struct Output: Encodable { let artifactIdentifier: String; let contentHash: String }
    private struct UndoOutput: Encodable { let undone: Bool; let artifactIdentifier: String }
    let store: FamiliarArtifactStore
    let manifest = FamiliarToolManifest(
        name: "artifact_edit", title: "编辑 Artifact", description: "Save a new Markdown or text revision of the specified Project Artifact. The previous version remains intact. Undo removes only the new revision.",
        parameters: FamiliarJSONSchema(type: .object, properties: [
            "identifier": .init(type: .string, description: "Predecessor artifact_ identifier"),
            "content": .init(type: .string, description: "New complete Markdown or plain-text content"),
            "title": .init(type: .string, description: "Optional new title")
        ], required: ["identifier", "content"]), effect: .reversibleWrite, risk: .low, requirements: [])

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarArtifactError.projectRequired }
        let original = try store.editableArtifact(projectID: projectID, identifier: input.identifier)
        guard ["md", "markdown", "txt"].contains(URL(fileURLWithPath: original.filename).pathExtension.lowercased()) else {
            throw FamiliarArtifactError.unsupportedFormat
        }
        let originalTitle = URL(fileURLWithPath: original.filename).deletingPathExtension().lastPathComponent
        let proposedTitle = input.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = proposedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? originalTitle
        let format: FamiliarArtifactFormat = original.filename.lowercased().hasSuffix(".txt") ? .plainText : .markdown
        let filename = title + "." + format.filenameExtension
        let data = Data(input.content.utf8)
        guard !data.isEmpty else { throw FamiliarArtifactError.emptyFile }
        let artifactID = UUID()
        let identifier = "artifact_" + artifactID.uuidString
        return .action(FamiliarActionProposal(title: "编辑 Artifact", fields: [
            .init(id: "title", label: "标题", type: .text, value: title),
            .init(id: "size", label: "大小", type: .number, value: String(data.count))
        ], target: input.identifier, effect: manifest.effect, risk: manifest.risk,
            consequence: String(localized: "artifact.revision.consequence", defaultValue: "Save a new version and keep the previous file."),
            undoPolicy: .currentSession, idempotencyKey: context.idempotencyKey, commit: {
                let stored = try store.write(data, projectID: projectID, artifactID: artifactID, filename: filename)
                let descriptor = FamiliarArtifactDescriptor(id: artifactID, identifier: identifier, projectID: projectID, title: title,
                    supersedesArtifactID: original.id, format: format, relativePath: stored.path, byteSize: Int64(data.count),
                    contentHash: stored.hash, source: .generated, sourceURLString: nil, sourceResourceID: nil,
                    sourceResourceVersionID: nil, sourceCaptureID: nil, createdByRunID: context.runID)
                let result = FamiliarToolExecutionResult(envelope: try .init(model: Output(artifactIdentifier: identifier, contentHash: stored.hash),
                    presentation: .artifactMutation(.init(summary: "已保存新版本 \(title)", operation: "edit", identifier: identifier,
                        title: title, byteSize: Int64(data.count), contentHash: stored.hash))), artifactIdentifier: identifier, artifact: descriptor)
                return FamiliarCommittedAction(result: result, undo: {
                    .init(envelope: try .init(model: UndoOutput(undone: true, artifactIdentifier: identifier),
                        presentation: .mutationReceipt(.init(summary: "已撤销新版本 \(title)", operation: "undoArtifactEdit",
                            targetIdentifier: identifier, succeeded: true, undoAvailable: false))))
                }, rollback: { try store.remove(projectID: projectID, artifactID: artifactID) })
            }))
    }
}

nonisolated struct FamiliarArtifactReadTool: FamiliarTool {
    struct Input: Decodable, Sendable { let identifier: String }

    private struct Output: Encodable {
        let artifactIdentifier: String
        let filename: String
        let extractedBy: String
        let characterCount: Int
        let truncated: Bool
        let text: String
    }

    /// Well below the 48k tool-result cap, leaving room for the envelope while still
    /// carrying a full report back to the model.
    static let maximumCharacters = 16_000

    let store: FamiliarArtifactStore
    let manifest = FamiliarToolManifest(
        name: "artifact_read",
        title: "Read published Artifact",
        description: "Read the current text of an Artifact already published in this Project. DOCX, PDF and XLSX are parsed into Markdown; Markdown, text and HTML are returned as stored. Use this to check or revise a file you produced instead of assuming its contents.",
        parameters: .object(
            ["identifier": .string("Artifact identifier beginning with artifact_.")],
            required: ["identifier"]
        ),
        effect: .read,
        risk: .low,
        dataDomains: ["project.artifacts"],
        privacyLabels: ["project-only", "read-only"],
        supportsParallelism: true,
        requiredScopes: ["project"],
        executionClass: .specializedLocal
    )

    init(store: FamiliarArtifactStore = FamiliarArtifactStore()) { self.store = store }

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarArtifactError.projectRequired }
        let artifact = try store.editableArtifact(projectID: projectID, identifier: input.identifier)
        let (text, extractedBy) = try Self.extractText(data: artifact.data, filename: artifact.filename)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FamiliarArtifactError.missingArtifact }
        let truncated = trimmed.count > Self.maximumCharacters
        let bounded = truncated ? String(trimmed.prefix(Self.maximumCharacters)) : trimmed
        let output = Output(
            artifactIdentifier: input.identifier,
            filename: artifact.filename,
            extractedBy: extractedBy,
            characterCount: trimmed.count,
            // Reported rather than silent: a model that believes it read the whole file
            // would revise a document it has only partly seen.
            truncated: truncated,
            text: bounded
        )
        let summary = truncated
            ? "已读取 \(artifact.filename) 的前 \(Self.maximumCharacters) 个字符，共 \(trimmed.count) 个字符。"
            : "已读取 \(artifact.filename)，共 \(trimmed.count) 个字符。"
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: output,
            presentation: .document(.init(
                summary: summary,
                title: artifact.filename,
                text: bounded,
                mimeType: "text/markdown"
            ))
        )))
    }

    /// Binary Office and PDF payloads go through AnyDoc; text formats are returned as
    /// stored so a Markdown Artifact round-trips byte for byte.
    static func extractText(data: Data, filename: String) throws -> (text: String, extractedBy: String) {
        let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if ["md", "markdown", "txt", "html", "htm"].contains(fileExtension) {
            guard let value = String(data: data, encoding: .utf8) else {
                throw FamiliarArtifactError.contentMismatch
            }
            return (value, "utf8")
        }
        let conversion = try FamiliarAnyDocService.convert(data: data, filename: filename)
        return (conversion.markdown, FamiliarAnyDocService.engineName)
    }
}

nonisolated struct FamiliarArtifactPublishTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let path: String
        let title: String
        let format: FamiliarArtifactFormat
        let requiredText: [String]?
        var minimumSources: Int? = nil
        /// Identifier of the Artifact this file replaces. Supplying it makes the new file
        /// the next version of the same deliverable instead of an unrelated one.
        ///
        /// Declared `var` rather than `let` with a default: a `let` carrying an initial
        /// value is excluded from the synthesized Decodable conformance, so the model's
        /// argument would be silently dropped and the parameter would be dead. As an
        /// optional `var` it is decoded and still defaults to nil for callers.
        var supersedes: String?
    }

    private struct Output: Encodable {
        let artifactIdentifier: String
        let format: FamiliarArtifactFormat
        let byteSize: Int64
        let contentHash: String
        let validation: FamiliarValidationReceipt
    }

    private struct UndoOutput: Encodable {
        let undone: Bool
        let artifactIdentifier: String
    }

    let resolver: FamiliarWorkspaceOutputResolver
    let store: FamiliarArtifactStore
    let manifest = FamiliarToolManifest(
        name: "artifact_publish",
        title: "Publish validated Artifact",
        description: "Validate a real file already created in the current Workspace Outputs and publish it as a Project Artifact. Supports DOCX, PDF, XLSX, HTML, Markdown, and plain text. Never claim delivery before this tool succeeds.",
        parameters: .object(
            [
                "path": .string("Relative Outputs path such as Outputs/北京资料.docx."),
                "title": .string("User-visible Artifact title."),
                "format": .string("Artifact format.", enumValues: FamiliarArtifactFormat.allCases.map(\.rawValue)),
                "requiredText": .stringArray(
                    "Optional strings that must be present in the parsed document content.",
                    itemDescription: "A short literal string expected in the parsed content."
                ),
                "minimumSources": .integer("Optional minimum distinct fetched source URLs that must be cited in the file.", minimum: 0, maximum: 16),
                "supersedes": .string("Identifier of the Artifact this file replaces, beginning with artifact_. Supply it when revising a file you already published so the result becomes the next version of the same deliverable.")
            ],
            required: ["path", "title", "format"]
        ),
        effect: .reversibleWrite,
        risk: .low,
        dataDomains: ["workspace.outputs", "project.artifacts"],
        privacyLabels: ["project-only", "validated-file", "content-hash"],
        supportsRecovery: true,
        requiredScopes: ["project", "workspace"],
        executionClass: .specializedLocal
    )

    init(workspaceStore: FamiliarWorkspaceStore, artifactStore: FamiliarArtifactStore = FamiliarArtifactStore()) {
        resolver = FamiliarWorkspaceOutputResolver(store: workspaceStore)
        store = artifactStore
    }

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID,
              let workspaceID = context.workspaceID,
              workspaceID == .project(projectID)
        else { throw FamiliarArtifactError.projectRequired }
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw FamiliarArtifactError.invalidPath }
        let output = try resolver.resolveOutput(relativePath: input.path, workspaceID: workspaceID)
        let fetched = context.fetchedSources.filter { $0.kind == .fetchedPage }
        let sourceURLs = Array(Set(fetched.map { $0.url.absoluteString })).sorted()
        let minimumSources = input.minimumSources ?? 0
        guard (0...16).contains(minimumSources), (input.requiredText?.count ?? 0) <= 16 else {
            throw FamiliarArtifactError.validationFailed("Invalid document validation requirements.")
        }
        guard sourceURLs.count >= minimumSources else { throw FamiliarArtifactError.validationFailed("Not enough successfully fetched sources.") }
        let required = Array(Set(input.requiredText ?? []))
        let validation = try FamiliarArtifactValidator.validate(fileURL: output.fileURL, format: input.format, requiredText: required)
        if minimumSources > 0 {
            let text = try FamiliarArtifactReadTool.extractText(data: Data(contentsOf: output.fileURL), filename: output.fileURL.lastPathComponent).text
            guard sourceURLs.filter({ text.contains($0) }).count >= minimumSources else { throw FamiliarArtifactError.validationFailed("The document must cite the fetched source URLs.") }
        }
        let id = UUID()
        let identifier = "artifact_" + id.uuidString
        // A malformed predecessor is rejected rather than ignored: silently publishing an
        // unrelated first version would lose the revision history the caller asked for.
        let supersedesArtifactID: UUID? = try input.supersedes
            .map { value -> UUID in
                guard value.hasPrefix("artifact_"),
                      let parsed = UUID(uuidString: String(value.dropFirst("artifact_".count)))
                else { throw FamiliarArtifactError.invalidIdentifier }
                return parsed
            }
        let filename = title.hasSuffix("." + input.format.filenameExtension)
            ? title
            : title + "." + input.format.filenameExtension
        return .action(.init(
            title: "发布已验证 Artifact",
            fields: [
                .init(id: "title", label: "Title", type: .text, value: title),
                .init(id: "format", label: "Format", type: .text, value: input.format.rawValue.uppercased()),
                .init(id: "size", label: "Size", type: .number, value: String(output.byteSize)),
                .init(id: "validator", label: "Validator", type: .text, value: "\(validation.validator) \(validation.validatorVersion)"),
                .init(id: "hash", label: "SHA-256", type: .text, value: output.contentHash)
            ],
            target: identifier,
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: "将经过验证的真实文件复制到当前 Project Artifacts，并提供系统预览和分享。",
            undoPolicy: .currentSession,
            idempotencyKey: context.idempotencyKey,
            commit: {
                let imported = try store.importFile(
                    at: output.fileURL,
                    projectID: projectID,
                    artifactID: id,
                    filename: filename,
                    maximumBytes: FamiliarArtifactValidator.maximumArtifactBytes
                )
                guard imported.hash == output.contentHash else {
                    try? store.remove(projectID: projectID, artifactID: id)
                    throw FamiliarArtifactError.transactionFailed
                }
                let finalValidation = try FamiliarArtifactValidator.validate(fileURL: store.url(relativePath: imported.path)!, format: input.format, requiredText: required)
                guard finalValidation.extractedTextHash == validation.extractedTextHash else {
                    try? store.remove(projectID: projectID, artifactID: id)
                    throw FamiliarArtifactError.transactionFailed
                }
                let descriptor = FamiliarArtifactDescriptor(
                    id: id,
                    identifier: identifier,
                    projectID: projectID,
                    title: title,
                    supersedesArtifactID: supersedesArtifactID,
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
                            artifactIdentifier: identifier,
                            format: input.format,
                            byteSize: imported.byteSize,
                            contentHash: imported.hash,
                            validation: validation
                        ),
                        presentation: .artifactMutation(.init(
                            summary: "已发布并验证 \(title)",
                            operation: "publish",
                            identifier: identifier,
                            title: title,
                            byteSize: imported.byteSize,
                            contentHash: imported.hash
                        ))
                    ),
                    artifactIdentifier: identifier,
                    artifact: descriptor
                )
                return FamiliarCommittedAction(result: result, undo: {
                    return .init(envelope: try .init(
                        model: UndoOutput(undone: true, artifactIdentifier: identifier),
                        presentation: .mutationReceipt(.init(
                            summary: "已撤销发布 \(title)",
                            operation: "undoArtifactPublish",
                            targetIdentifier: identifier,
                            succeeded: true,
                            undoAvailable: false
                        ))
                    ))
                }, rollback: { try store.remove(projectID: projectID, artifactID: id) })
            }
        ))
    }
}
