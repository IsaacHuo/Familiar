import Foundation

nonisolated struct FamiliarResourceListTool: FamiliarTool {
    struct Input: Decodable, Sendable {}
    let manifest = FamiliarToolManifest(
        name: "resource_list", title: "列出项目资料", description: "列出当前项目可用的资料及版本。普通聊天没有项目资料。",
        parameters: FamiliarJSONSchema(type: .object, properties: [:], required: []), effect: .read, risk: .low, requirements: []
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard context.projectID != nil else { throw FamiliarArtifactError.projectRequired }
        struct Item: Encodable { let id: UUID; let version: UUID; let name: String; let filename: String; let mimeType: String }
        let items = context.resources.map { Item(id: $0.id, version: $0.versionID, name: $0.displayName, filename: $0.filename, mimeType: $0.mimeType) }
        let data = try JSONEncoder().encode(items)
        return .result(.init(modelContent: String(decoding: data, as: UTF8.self), displayContent: "已列出项目资料。"))
    }
}

nonisolated struct FamiliarResourceReadTool: FamiliarTool {
    struct Input: Decodable, Sendable { let resourceID: UUID; let versionID: UUID? }
    let manifest = FamiliarToolManifest(
        name: "resource_read", title: "读取项目资料", description: "读取当前项目指定资料版本的提取文本。",
        parameters: FamiliarJSONSchema(type: .object, properties: [
            "resourceID": .init(type: .string, description: "资料 ID"),
            "versionID": .init(type: .string, description: "可选的资料版本 ID")
        ], required: ["resourceID"]), effect: .read, risk: .low, requirements: []
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard context.projectID != nil else { throw FamiliarArtifactError.projectRequired }
        guard let resource = context.resources.first(where: { $0.id == input.resourceID && (input.versionID == nil || $0.versionID == input.versionID) }) else {
            throw FamiliarArtifactError.missingArtifact
        }
        return .result(.init(
            modelContent: resource.extractedText,
            displayContent: "已读取资料：\(resource.displayName)（第 \(resource.version) 版）。"
        ))
    }
}

nonisolated struct FamiliarResourceSearchTool: FamiliarTool {
    struct Input: Decodable, Sendable { let query: String }
    let manifest = FamiliarToolManifest(
        name: "resource_search", title: "搜索项目资料", description: "在当前项目资料的提取文本中搜索关键词。",
        parameters: FamiliarJSONSchema(type: .object, properties: ["query": .init(type: .string, description: "搜索关键词")], required: ["query"]), effect: .read, risk: .low, requirements: []
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard context.projectID != nil else { throw FamiliarArtifactError.projectRequired }
        let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .result(.init(modelContent: "[]", displayContent: "搜索词为空。")) }
        struct Match: Encodable { let resourceID: UUID; let versionID: UUID; let name: String; let excerpt: String }
        let matches = context.resources.compactMap { resource -> Match? in
            guard let range = resource.extractedText.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
            let start = resource.extractedText.index(range.lowerBound, offsetBy: -min(160, resource.extractedText.distance(from: resource.extractedText.startIndex, to: range.lowerBound)))
            let end = resource.extractedText.index(range.upperBound, offsetBy: min(320, resource.extractedText.distance(from: range.upperBound, to: resource.extractedText.endIndex)))
            return Match(resourceID: resource.id, versionID: resource.versionID, name: resource.displayName, excerpt: String(resource.extractedText[start..<end]))
        }
        let data = try JSONEncoder().encode(matches)
        return .result(.init(modelContent: String(decoding: data, as: UTF8.self), displayContent: "找到 \(matches.count) 个资料匹配。"))
    }
}
