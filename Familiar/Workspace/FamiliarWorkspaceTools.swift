import Foundation

nonisolated struct FamiliarWorkspaceListTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    private struct Item: Encodable {
        let path: String
        let byteSize: Int64
        let contentHash: String
    }

    let store: FamiliarWorkspaceStore
    let manifest = FamiliarToolManifest(
        name: "workspace_list",
        title: "列出 Workspace 文件",
        description: "列出当前 Project 或 Conversation Workspace 中用户导入的文件、生成结果和 Runtime 工作文件。",
        parameters: .init(type: .object, properties: [:], required: []),
        effect: .read,
        risk: .low,
        requirements: [],
        dataDomains: ["workspace.files", "workspace.outputs", "workspace.runtime"],
        supportsParallelism: true,
        requiredScopes: ["workspace"],
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else { throw FamiliarWorkspaceError.invalidPath }
        let items = try store.entries(in: workspaceID).map {
            Item(path: $0.relativePath, byteSize: $0.byteSize, contentHash: $0.contentHash)
        }
        let records = items.map { item in
            FamiliarToolPresentationPayload.Record(id: item.path, fields: [
                .init(name: "path", value: item.path),
                .init(name: "byteSize", value: String(item.byteSize)),
                .init(name: "contentHash", value: item.contentHash)
            ])
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: items,
            presentation: .recordCollection(.init(
                summary: "Workspace 中有 \(items.count) 个文件。",
                recordType: "workspaceFile",
                records: records
            ))
        )))
    }
}

nonisolated struct FamiliarWorkspaceReadTool: FamiliarTool {
    struct Input: Decodable, Sendable { let path: String }
    private struct Output: Encodable { let path: String; let text: String }

    let store: FamiliarWorkspaceStore
    let manifest = FamiliarToolManifest(
        name: "workspace_read",
        title: "读取 Workspace 文件",
        description: "读取当前 Workspace 内的 UTF-8 文本文件。二进制文件应使用专用本地 Tool。",
        parameters: .init(
            type: .object,
            properties: ["path": .init(type: .string, description: "workspace_list 返回的相对路径")],
            required: ["path"]
        ),
        effect: .read,
        risk: .low,
        requirements: [],
        payloadLimit: 48_000,
        dataDomains: ["workspace.files", "workspace.outputs", "workspace.runtime"],
        supportsParallelism: true,
        requiredScopes: ["workspace"],
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else { throw FamiliarWorkspaceError.invalidPath }
        let data = try store.read(relativePath: input.path, in: workspaceID)
        guard data.count <= manifest.payloadLimit,
              let text = String(data: data, encoding: .utf8)
        else {
            throw FamiliarWorkspaceToolError.unsupportedOrTooLarge
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: Output(path: input.path, text: text),
            presentation: .document(.init(
                summary: "已读取 \(input.path)。",
                title: URL(fileURLWithPath: input.path).lastPathComponent,
                text: text,
                mimeType: "text/plain"
            ))
        )))
    }
}

nonisolated struct FamiliarWorkspaceSearchTool: FamiliarTool {
    struct Input: Decodable, Sendable { let query: String }
    private struct Match: Encodable { let path: String; let excerpt: String }

    let store: FamiliarWorkspaceStore
    let manifest = FamiliarToolManifest(
        name: "workspace_search",
        title: "搜索 Workspace 文件",
        description: "在当前 Workspace 的小型 UTF-8 文本文件中搜索关键词。",
        parameters: .init(
            type: .object,
            properties: ["query": .init(type: .string, description: "搜索词")],
            required: ["query"]
        ),
        effect: .read,
        risk: .low,
        requirements: [],
        dataDomains: ["workspace.files", "workspace.outputs", "workspace.runtime"],
        supportsParallelism: true,
        requiredScopes: ["workspace"],
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else { throw FamiliarWorkspaceError.invalidPath }
        let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw FamiliarWorkspaceToolError.emptyQuery }
        var matches: [Match] = []
        for entry in try store.entries(in: workspaceID) where entry.byteSize <= 1_048_576 {
            guard let text = try? String(
                data: store.read(relativePath: entry.relativePath, in: workspaceID),
                encoding: .utf8
            ), let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            let lowerDistance = text.distance(from: text.startIndex, to: range.lowerBound)
            let upperDistance = text.distance(from: range.upperBound, to: text.endIndex)
            let start = text.index(range.lowerBound, offsetBy: -min(160, lowerDistance))
            let end = text.index(range.upperBound, offsetBy: min(320, upperDistance))
            matches.append(.init(path: entry.relativePath, excerpt: String(text[start..<end])))
            if matches.count == 20 { break }
        }
        let presentationMatches = matches.enumerated().map { index, match in
            FamiliarToolPresentationPayload.ContextMatch(
                resourceID: UUID(),
                versionID: UUID(),
                version: 1,
                title: match.path,
                excerpt: match.excerpt
            )
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: matches,
            presentation: .contextMatches(.init(
                summary: "找到 \(matches.count) 个 Workspace 匹配。",
                query: query,
                matches: presentationMatches
            ))
        )))
    }
}

nonisolated struct FamiliarWorkspaceWriteTool: FamiliarTool {
    struct Input: Decodable, Sendable { let path: String; let content: String }
    private struct Output: Encodable { let path: String; let byteSize: Int; let contentHash: String }
    private struct UndoOutput: Encodable { let restored: Bool; let checkpointID: UUID }

    let store: FamiliarWorkspaceStore
    let manifest = FamiliarToolManifest(
        name: "workspace_write",
        title: "写入 Workspace 输出",
        description: "把 UTF-8 文本写入当前 Workspace 的 Outputs 目录。",
        parameters: .init(
            type: .object,
            properties: [
                "path": .init(type: .string, description: "Outputs/ 下的相对路径"),
                "content": .init(type: .string, description: "完整 UTF-8 文本内容")
            ],
            required: ["path", "content"]
        ),
        effect: .reversibleWrite,
        risk: .low,
        requirements: [],
        dataDomains: ["workspace.outputs"],
        supportsIdempotency: true,
        supportsCancellation: true,
        requiredScopes: ["workspace"],
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else { throw FamiliarWorkspaceError.invalidPath }
        let path = input.path.hasPrefix("Outputs/") ? input.path : "Outputs/\(input.path)"
        let checkpoint = try store.createCheckpoint(for: workspaceID)
        let data = Data(input.content.utf8)
        return .action(FamiliarActionProposal(
            title: "写入 Workspace 文件",
            fields: [
                .init(id: "path", label: "Path", type: .text, value: path),
                .init(id: "byteSize", label: "Size", type: .number, value: String(data.count))
            ],
            target: path,
            targetKey: path,
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: "将在当前 Workspace 的 Outputs 目录写入或替换此文件。",
            undoPolicy: .currentSession,
            idempotencyKey: context.idempotencyKey,
            execute: {
                let entry = try store.write(data, relativePath: path, in: workspaceID)
                return FamiliarToolExecutionResult(envelope: try FamiliarToolResultEnvelope(
                    model: Output(path: path, byteSize: data.count, contentHash: entry.contentHash),
                    presentation: .mutationReceipt(.init(
                        summary: "已写入 \(path)。",
                        operation: "workspaceWrite",
                        targetIdentifier: path,
                        succeeded: true,
                        undoAvailable: true
                    ))
                ))
            },
            undo: {
                try store.restore(checkpoint)
                return FamiliarToolExecutionResult(envelope: try FamiliarToolResultEnvelope(
                    model: UndoOutput(restored: true, checkpointID: checkpoint.id),
                    presentation: .mutationReceipt(.init(
                        summary: "已恢复写入前的 Workspace checkpoint。",
                        operation: "restoreWorkspaceCheckpoint",
                        targetIdentifier: checkpoint.id.uuidString,
                        succeeded: true,
                        undoAvailable: false
                    ))
                ))
            }
        ))
    }
}

nonisolated struct FamiliarWorkspaceImageListTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    private struct Item: Encodable { let path: String; let byteSize: Int64 }

    let store: FamiliarWorkspaceStore
    let manifest = FamiliarToolManifest(
        name: "workspace_image_list",
        title: "列出 Workspace 图片",
        description: "列出用户已显式导入当前 Workspace 的图片副本，不访问完整照片库。",
        parameters: .init(type: .object, properties: [:], required: []),
        effect: .read,
        risk: .low,
        requirements: [],
        dataDomains: ["workspace.files"],
        supportsParallelism: true,
        requiredScopes: ["workspace"],
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else { throw FamiliarWorkspaceError.invalidPath }
        let extensions = Set(["jpg", "jpeg", "png", "heic", "gif", "webp", "tiff"])
        let items = try store.entries(in: workspaceID).filter {
            $0.relativePath.hasPrefix("Files/") && extensions.contains(URL(fileURLWithPath: $0.relativePath).pathExtension.lowercased())
        }.map { Item(path: $0.relativePath, byteSize: $0.byteSize) }
        let records = items.map { item in
            FamiliarToolPresentationPayload.Record(id: item.path, fields: [
                .init(name: "path", value: item.path),
                .init(name: "byteSize", value: String(item.byteSize))
            ])
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: items,
            presentation: .recordCollection(.init(
                summary: "Workspace 中有 \(items.count) 张已导入图片。",
                recordType: "workspaceImage",
                records: records
            ))
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
