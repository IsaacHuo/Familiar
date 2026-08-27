import CryptoKit
import Foundation

nonisolated struct FamiliarWorkspaceListTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    private struct Item: Encodable { let path: String; let byteSize: Int64; let contentHash: String }

    let store: FamiliarWorkspaceStore
    let manifest = FamiliarToolManifest(
        name: "workspace_list", title: "列出 Workspace 文件",
        description: "列出当前 Project 或 Conversation Workspace 中的资料、附件、生成结果和 Runtime 工作文件。",
        parameters: .init(type: .object, properties: [:], required: []), effect: .read, risk: .low, requirements: [],
        dataDomains: ["workspace.files", "workspace.outputs", "workspace.runtime"], supportsParallelism: true,
        requiredScopes: ["workspace"], executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else { throw FamiliarWorkspaceError.invalidPath }
        let stored = try store.entries(in: workspaceID)
            .filter(FamiliarWorkspaceProjection.isAgentVisibleStoredEntry)
            .map { FamiliarWorkspaceProjectedFile(path: $0.relativePath, byteSize: $0.byteSize, contentHash: $0.contentHash, text: nil, identity: .stored) }
        let items = (FamiliarWorkspaceProjection.files(in: context) + stored)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map { Item(path: $0.path, byteSize: $0.byteSize, contentHash: $0.contentHash) }
        let records = items.map { item in
            FamiliarToolPresentationPayload.Record(id: item.path, fields: [
                .init(name: "path", value: item.path), .init(name: "byteSize", value: String(item.byteSize)),
                .init(name: "contentHash", value: item.contentHash)
            ])
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: items,
            presentation: .recordCollection(.init(summary: "Workspace 中有 \(items.count) 个文件。", recordType: "workspaceFile", records: records))
        )))
    }
}

nonisolated struct FamiliarWorkspaceReadTool: FamiliarTool {
    struct Input: Decodable, Sendable { let path: String }
    private struct Output: Encodable { let path: String; let text: String }

    let store: FamiliarWorkspaceStore
    let manifest = FamiliarToolManifest(
        name: "workspace_read", title: "读取 Workspace 文件",
        description: "读取当前 Workspace 的资料、附件抽取文本或 UTF-8 输出文件。",
        parameters: .init(type: .object, properties: ["path": .init(type: .string, description: "workspace_list 返回的相对路径")], required: ["path"]),
        effect: .read, risk: .low, requirements: [], payloadLimit: 48_000,
        dataDomains: ["workspace.files", "workspace.outputs", "workspace.runtime"], supportsParallelism: true,
        requiredScopes: ["workspace"], executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else { throw FamiliarWorkspaceError.invalidPath }
        let text: String
        if let projected = FamiliarWorkspaceProjection.file(at: input.path, in: context) {
            guard let value = projected.text else { throw FamiliarWorkspaceToolError.unsupportedOrTooLarge }
            text = value
        } else {
            let data = try store.read(relativePath: input.path, in: workspaceID)
            guard FamiliarWorkspaceProjection.isAgentVisibleStoredPath(input.path),
                  data.count <= manifest.payloadLimit, let value = String(data: data, encoding: .utf8)
            else { throw FamiliarWorkspaceToolError.unsupportedOrTooLarge }
            text = value
        }
        guard text.utf8.count <= manifest.payloadLimit else { throw FamiliarWorkspaceToolError.unsupportedOrTooLarge }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: Output(path: input.path, text: text),
            presentation: .document(.init(summary: "已读取 \(input.path)。", title: URL(fileURLWithPath: input.path).lastPathComponent, text: text, mimeType: "text/plain"))
        )))
    }
}

nonisolated struct FamiliarWorkspaceSearchTool: FamiliarTool {
    struct Input: Decodable, Sendable { let query: String }
    private struct Match: Encodable { let path: String; let excerpt: String }

    let store: FamiliarWorkspaceStore
    let manifest = FamiliarToolManifest(
        name: "workspace_search", title: "搜索 Workspace 文件",
        description: "在当前 Workspace 的资料、附件抽取文本和小型 UTF-8 输出文件中搜索关键词。",
        parameters: .init(type: .object, properties: ["query": .init(type: .string, description: "搜索词")], required: ["query"]),
        effect: .read, risk: .low, requirements: [], dataDomains: ["workspace.files", "workspace.outputs", "workspace.runtime"],
        supportsParallelism: true, requiredScopes: ["workspace"], executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else { throw FamiliarWorkspaceError.invalidPath }
        let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw FamiliarWorkspaceToolError.emptyQuery }
        var searchable = FamiliarWorkspaceProjection.files(in: context).compactMap { file in file.text.map { (file, $0) } }
        for entry in try store.entries(in: workspaceID)
            where FamiliarWorkspaceProjection.isAgentVisibleStoredEntry(entry) && entry.byteSize <= 1_048_576 {
            guard let text = try? String(data: store.read(relativePath: entry.relativePath, in: workspaceID), encoding: .utf8) else { continue }
            searchable.append((.init(path: entry.relativePath, byteSize: entry.byteSize, contentHash: entry.contentHash, text: text, identity: .stored), text))
        }

        var matches: [(Match, FamiliarWorkspaceProjectedFile)] = []
        for (file, text) in searchable {
            guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: range.upperBound, to: text.endIndex)
            let start = text.index(range.lowerBound, offsetBy: -min(160, lower))
            let end = text.index(range.upperBound, offsetBy: min(320, upper))
            matches.append((.init(path: file.path, excerpt: String(text[start..<end])), file))
            if matches.count == 20 { break }
        }
        let presentationMatches = matches.map { match, file in
            let identity = file.contextIdentity
            return FamiliarToolPresentationPayload.ContextMatch(
                resourceID: identity.resourceID, versionID: identity.versionID, version: identity.version,
                title: match.path, excerpt: match.excerpt
            )
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: matches.map(\.0),
            presentation: .contextMatches(.init(summary: "找到 \(matches.count) 个 Workspace 匹配。", query: query, matches: presentationMatches))
        )))
    }
}

nonisolated struct FamiliarWorkspaceWriteTool: FamiliarTool {
    struct Input: Decodable, Sendable { let path: String; let content: String }
    private struct Output: Encodable { let path: String; let byteSize: Int; let contentHash: String }
    private struct UndoOutput: Encodable { let restored: Bool; let path: String }

    let store: FamiliarWorkspaceStore
    let manifest = FamiliarToolManifest(
        name: "workspace_write", title: "写入 Workspace 输出", description: "把 UTF-8 文本写入当前 Workspace 的 Outputs 目录。",
        parameters: .init(type: .object, properties: [
            "path": .init(type: .string, description: "Outputs/ 下的相对路径"),
            "content": .init(type: .string, description: "完整 UTF-8 文本内容")
        ], required: ["path", "content"]),
        effect: .reversibleWrite, risk: .low, requirements: [], dataDomains: ["workspace.outputs"],
        supportsIdempotency: true, supportsCancellation: true, requiredScopes: ["workspace"], executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else { throw FamiliarWorkspaceError.invalidPath }
        let path = input.path.hasPrefix("Outputs/") ? input.path : "Outputs/\(input.path)"
        guard FamiliarWorkspaceProjection.isWritableOutputPath(path) else { throw FamiliarWorkspaceError.invalidPath }
        let data = Data(input.content.utf8)
        return .action(FamiliarActionProposal(
            title: "写入 Workspace 文件",
            fields: [.init(id: "path", label: "Path", type: .text, value: path), .init(id: "byteSize", label: "Size", type: .number, value: String(data.count))],
            target: path, targetKey: path, effect: manifest.effect, risk: manifest.risk,
            consequence: "将在当前 Workspace 的 Outputs 目录写入或替换此文件。", undoPolicy: .currentSession,
            idempotencyKey: context.idempotencyKey,
            commit: {
                let existed = try store.contains(relativePath: path, in: workspaceID)
                let previous = existed ? try store.read(relativePath: path, in: workspaceID) : nil
                let entry = try store.write(data, relativePath: path, in: workspaceID)
                let result = FamiliarToolExecutionResult(envelope: try FamiliarToolResultEnvelope(
                    model: Output(path: path, byteSize: data.count, contentHash: entry.contentHash),
                    presentation: .mutationReceipt(.init(summary: "已写入 \(path)。", operation: "workspaceWrite", targetIdentifier: path, succeeded: true, undoAvailable: true))
                ))
                return FamiliarCommittedAction(result: result) {
                    if let previous { _ = try store.write(previous, relativePath: path, in: workspaceID) }
                    else if try store.contains(relativePath: path, in: workspaceID) { try store.remove(relativePath: path, in: workspaceID) }
                    return FamiliarToolExecutionResult(envelope: try FamiliarToolResultEnvelope(
                        model: UndoOutput(restored: true, path: path),
                        presentation: .mutationReceipt(.init(summary: "已恢复写入前的 \(path)。", operation: "workspaceWriteUndo", targetIdentifier: path, succeeded: true, undoAvailable: false))
                    ))
                }
            }
        ))
    }
}

nonisolated struct FamiliarWorkspaceImageListTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    private struct Item: Encodable { let path: String; let byteSize: Int64 }

    let store: FamiliarWorkspaceStore
    let manifest = FamiliarToolManifest(
        name: "workspace_image_list", title: "列出 Workspace 图片",
        description: "列出用户已显式添加到当前对话的图片，不访问完整照片库。",
        parameters: .init(type: .object, properties: [:], required: []), effect: .read, risk: .low, requirements: [],
        dataDomains: ["workspace.files"], supportsParallelism: true, requiredScopes: ["workspace"], executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let items = FamiliarWorkspaceProjection.files(in: context).compactMap { file -> Item? in
            guard case .attachment(_, let isImage) = file.identity, isImage else { return nil }
            return Item(path: file.path, byteSize: file.byteSize)
        }
        let records = items.map { item in
            FamiliarToolPresentationPayload.Record(id: item.path, fields: [.init(name: "path", value: item.path), .init(name: "byteSize", value: String(item.byteSize))])
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: items,
            presentation: .recordCollection(.init(summary: "Workspace 中有 \(items.count) 张已添加图片。", recordType: "workspaceImage", records: records))
        )))
    }
}

nonisolated enum FamiliarWorkspaceToolError: LocalizedError, Sendable {
    case unsupportedOrTooLarge
    case emptyQuery
    var errorDescription: String? {
        switch self {
        case .unsupportedOrTooLarge: "文件不是受支持的小型 UTF-8 文本。"
        case .emptyQuery: "Workspace 搜索词不能为空。"
        }
    }
}

private nonisolated struct FamiliarWorkspaceProjectedFile: Sendable {
    enum Identity: Sendable {
        case resource(resourceID: UUID, versionID: UUID, version: Int)
        case attachment(id: UUID, isImage: Bool)
        case stored
    }
    let path: String
    let byteSize: Int64
    let contentHash: String
    let text: String?
    let identity: Identity

    var contextIdentity: (resourceID: UUID, versionID: UUID, version: Int) {
        switch identity {
        case .resource(let resourceID, let versionID, let version): return (resourceID, versionID, version)
        case .attachment(let id, _): return (id, id, 1)
        case .stored:
            let id = FamiliarWorkspaceProjection.stableUUID(path)
            return (id, id, 1)
        }
    }
}

private nonisolated enum FamiliarWorkspaceProjection {
    static func files(in context: FamiliarToolContext) -> [FamiliarWorkspaceProjectedFile] {
        let resources = context.resources.map { resource in
            FamiliarWorkspaceProjectedFile(
                path: "Files/Resources/\(resource.id.uuidString.lowercased())/\(filename(resource.filename))",
                byteSize: Int64(resource.extractedText.utf8.count), contentHash: resource.contentHash, text: resource.extractedText,
                identity: .resource(resourceID: resource.id, versionID: resource.versionID, version: resource.version)
            )
        }
        let attachments = context.attachments.map { attachment in
            let isImage = attachment.kind == .image
            let hash: String
            if let url = FamiliarAttachmentStore.url(for: attachment.relativePath), let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) { hash = sha256(data) }
            else { hash = sha256(Data(attachment.extractedText.utf8)) }
            return FamiliarWorkspaceProjectedFile(
                path: "Files/Attachments/\(attachment.id.uuidString.lowercased())/\(filename(attachment.filename))",
                byteSize: attachment.byteSize, contentHash: hash, text: isImage ? nil : attachment.extractedText,
                identity: .attachment(id: attachment.id, isImage: isImage)
            )
        }
        return resources + attachments
    }

    static func file(at path: String, in context: FamiliarToolContext) -> FamiliarWorkspaceProjectedFile? { files(in: context).first { $0.path == path } }
    static func isAgentVisibleStoredEntry(_ entry: FamiliarWorkspaceEntry) -> Bool { isAgentVisibleStoredPath(entry.relativePath) }
    static func isAgentVisibleStoredPath(_ path: String) -> Bool { path.hasPrefix("Outputs/") || path.hasPrefix("Runtime/Work/") }
    static func isWritableOutputPath(_ path: String) -> Bool {
        guard path.hasPrefix("Outputs/") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.count >= 2 && !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
    static func stableUUID(_ value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    private static func filename(_ value: String) -> String {
        let name = URL(fileURLWithPath: value).lastPathComponent
        return name.isEmpty ? "file" : name
    }
    private static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
