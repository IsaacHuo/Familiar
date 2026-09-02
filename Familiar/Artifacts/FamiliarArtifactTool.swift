import Foundation

nonisolated struct FamiliarArtifactWriteTool: FamiliarTool {
    struct Input: Decodable, Sendable { let title: String; let content: String; let format: FamiliarArtifactFormat? }
    private struct Output: Encodable { let artifactIdentifier: String; let contentHash: String }
    private struct UndoOutput: Encodable { let undone: Bool; let artifactIdentifier: String }
    let store: FamiliarArtifactStore
    let manifest = FamiliarToolManifest(
        name: "artifact_write", title: "写入 Artifact", description: "将 Markdown 或纯文本保存到当前项目的 Artifact 目录。普通聊天没有项目作用域，不能使用此工具。",
        parameters: FamiliarJSONSchema(type: .object, properties: [
            "title": .init(type: .string, description: "文件标题"), "content": .init(type: .string, description: "Markdown 或纯文本正文"),
            "format": .init(type: .string, description: "markdown 或 plainText")
        ], required: ["title", "content"]), effect: .reversibleWrite, risk: .low, requirements: [])

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarArtifactError.projectRequired }
        let format = input.format ?? .markdown
        let id = UUID()
        let filename = input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "artifact.md" : input.title + (format == .markdown ? ".md" : ".txt")
        let data = Data(input.content.utf8)
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
                return FamiliarCommittedAction(result: result) {
                    try store.remove(projectID: projectID, artifactID: id)
                    return .init(envelope: try FamiliarToolResultEnvelope(
                        model: UndoOutput(undone: true, artifactIdentifier: identifier),
                        presentation: .mutationReceipt(.init(summary: "已撤销写入 \(input.title)", operation: "undoArtifactWrite", targetIdentifier: identifier, succeeded: true, undoAvailable: false))
                    ))
                }
            }))
    }
}

nonisolated struct FamiliarArtifactEditTool: FamiliarTool {
    struct Input: Decodable, Sendable { let identifier: String; let content: String; let title: String? }
    private struct Output: Encodable { let artifactIdentifier: String; let contentHash: String }
    private struct UndoOutput: Encodable { let undone: Bool; let artifactIdentifier: String; let contentHash: String }
    let store: FamiliarArtifactStore
    let manifest = FamiliarToolManifest(
        name: "artifact_edit", title: "编辑 Artifact", description: "修改当前项目中指定 Artifact 的内容或标题。编辑会显示写入卡，并可在当前 App 会话中撤销。",
        parameters: FamiliarJSONSchema(type: .object, properties: [
            "identifier": .init(type: .string, description: "artifact_ 开头的 Artifact 标识"),
            "content": .init(type: .string, description: "替换后的完整 Markdown 或纯文本内容"),
            "title": .init(type: .string, description: "可选的新标题")
        ], required: ["identifier", "content"]), effect: .reversibleWrite, risk: .low, requirements: []
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarArtifactError.projectRequired }
        let original = try store.editableArtifact(projectID: projectID, identifier: input.identifier)
        let originalTitle = URL(fileURLWithPath: original.filename).deletingPathExtension().lastPathComponent
        let title = input.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? input.title! : originalTitle
        let format: FamiliarArtifactFormat = original.filename.hasSuffix(".txt") ? .plainText : .markdown
        let filename = title + (format == .markdown ? ".md" : ".txt")
        let data = Data(input.content.utf8)
        let artifactID = original.id
        return .action(FamiliarActionProposal(
            title: "编辑 Artifact",
            fields: [
                .init(id: "title", label: "标题", type: .text, value: title),
                .init(id: "size", label: "大小", type: .number, value: String(data.count))
            ],
            target: input.identifier,
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: "将替换此 Artifact 的完整内容。",
            undoPolicy: .currentSession,
            idempotencyKey: context.idempotencyKey,
            commit: {
                let stored = try store.write(data, projectID: projectID, artifactID: artifactID, filename: filename)
                if stored.path != original.relativePath { try? FileManager.default.removeItem(at: store.rootURL.appendingPathComponent(original.relativePath)) }
                let descriptor = FamiliarArtifactDescriptor(
                    id: artifactID, identifier: input.identifier, projectID: projectID, title: title, format: format,
                    relativePath: stored.path, byteSize: Int64(data.count), contentHash: stored.hash, source: .generated,
                    sourceURLString: nil, sourceResourceID: nil, sourceResourceVersionID: nil, sourceCaptureID: nil, createdByRunID: context.runID
                )
                let result = FamiliarToolExecutionResult(
                    envelope: try FamiliarToolResultEnvelope(
                        model: Output(artifactIdentifier: input.identifier, contentHash: stored.hash),
                        presentation: .artifactMutation(.init(summary: "已编辑 \(title)", operation: "edit", identifier: input.identifier, title: title, byteSize: Int64(data.count), contentHash: stored.hash))
                    ),
                    artifactIdentifier: input.identifier,
                    artifact: descriptor
                )
                return FamiliarCommittedAction(result: result) {
                    let replacementPath = "Projects/\(projectID.uuidString)/Artifacts/\(artifactID.uuidString)/\(filename)"
                    if replacementPath != original.relativePath {
                        try? FileManager.default.removeItem(at: store.rootURL.appendingPathComponent(replacementPath))
                    }
                    let stored = try store.write(original.data, projectID: projectID, artifactID: artifactID, filename: original.filename)
                    let descriptor = FamiliarArtifactDescriptor(
                        id: artifactID, identifier: input.identifier, projectID: projectID, title: originalTitle, format: format,
                        relativePath: stored.path, byteSize: Int64(original.data.count), contentHash: stored.hash, source: .generated,
                        sourceURLString: nil, sourceResourceID: nil, sourceResourceVersionID: nil, sourceCaptureID: nil, createdByRunID: context.runID
                    )
                    return .init(
                        envelope: try FamiliarToolResultEnvelope(
                            model: UndoOutput(undone: true, artifactIdentifier: input.identifier, contentHash: stored.hash),
                            presentation: .artifactMutation(.init(summary: "已撤销编辑 \(originalTitle)", operation: "undoEdit", identifier: input.identifier, title: originalTitle, byteSize: Int64(original.data.count), contentHash: stored.hash))
                        ),
                        artifactIdentifier: input.identifier,
                        artifact: descriptor
                    )
                }
            }
        ))
    }
}

nonisolated struct FamiliarArtifactPublishTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let path: String
        let title: String
        let format: FamiliarArtifactFormat
        let requiredText: [String]?
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
                )
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
        let validation = try FamiliarArtifactValidator.validate(
            fileURL: output.fileURL,
            format: input.format,
            requiredText: input.requiredText ?? []
        )
        let id = UUID()
        let identifier = "artifact_" + id.uuidString
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
                let descriptor = FamiliarArtifactDescriptor(
                    id: id,
                    identifier: identifier,
                    projectID: projectID,
                    title: title,
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
                return FamiliarCommittedAction(result: result) {
                    try store.remove(projectID: projectID, artifactID: id)
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
                }
            }
        ))
    }
}
