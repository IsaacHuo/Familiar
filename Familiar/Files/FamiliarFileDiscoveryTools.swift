import Foundation

nonisolated struct FamiliarFileListTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let offset: Int?
        let limit: Int?
        init(offset: Int? = nil, limit: Int? = nil) { self.offset = offset; self.limit = limit }
    }
    private struct Item: Encodable {
        let fileID: UUID
        let versionID: UUID
        let identifier: String
        let version: Int
        let name: String
        let filename: String
        let mimeType: String
        let byteSize: Int64
    }
    private struct Output: Encodable { let files: [Item]; let totalCount: Int; let nextOffset: Int? }
    let manifest = FamiliarToolManifest(name: "file_list", title: "列出文件",
        description: "List the frozen Project file directory, including uploads, saved web pages and generated files. Use the returned identifier with file_read. File contents are loaded only when requested.",
        parameters: .object(["offset": .integer("Page offset", minimum: 0, defaultValue: 0),
                             "limit": .integer("Maximum files", minimum: 1, maximum: 100, defaultValue: 50)]),
        effect: .read, risk: .low, supportsParallelism: true, requiredScopes: ["project"])

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarFileError.projectRequired }
        var latest: [UUID: Item] = [:]
        for file in context.files where file.reference.projectID == projectID {
            let item = Item(fileID: file.reference.fileID, versionID: file.reference.versionID,
                identifier: "file_" + file.reference.versionID.uuidString, version: file.version,
                name: file.name, filename: file.filename, mimeType: file.mimeType, byteSize: file.byteSize)
            if latest[item.fileID].map({ $0.version < item.version }) ?? true { latest[item.fileID] = item }
        }
        // The pending message is frozen before its attachment commit; its identity is already known.
        for attachment in context.attachments where !context.files.contains(where: { $0.reference.versionID == attachment.id }) {
            latest[attachment.id] = Item(fileID: attachment.id, versionID: attachment.id,
                identifier: "file_" + attachment.id.uuidString, version: 1, name: attachment.filename,
                filename: attachment.filename, mimeType: attachment.mimeType, byteSize: attachment.byteSize)
        }
        for resource in context.resources where !context.files.contains(where: { $0.reference.versionID == resource.versionID }) {
            latest[resource.id] = Item(fileID: resource.id, versionID: resource.versionID,
                identifier: "file_" + resource.versionID.uuidString, version: resource.version,
                name: resource.displayName, filename: resource.filename, mimeType: resource.mimeType, byteSize: Int64(resource.extractedText.utf8.count))
        }
        let all = latest.values.sorted { $0.fileID.uuidString < $1.fileID.uuidString }
        let offset = max(0, input.offset ?? 0), limit = min(100, max(1, input.limit ?? 50))
        let page = Array(all.dropFirst(offset).prefix(limit))
        let next = offset + page.count < all.count ? offset + page.count : nil
        let records = page.map { item in
            FamiliarToolPresentationPayload.Record(id: item.fileID.uuidString, fields: [
                .init(name: "name", value: item.name), .init(name: "identifier", value: item.identifier),
                .init(name: "filename", value: item.filename), .init(name: "version", value: String(item.version))])
        }
        return .result(.init(envelope: try .init(model: Output(files: page, totalCount: all.count, nextOffset: next),
            presentation: .recordCollection(.init(summary: "已列出文件。", recordType: "file", records: records)))))
    }
}

nonisolated struct FamiliarFileSearchTool: FamiliarTool {
    struct Input: Decodable, Sendable { let query: String }
    private struct Match: Encodable { let fileID: UUID; let versionID: UUID; let identifier: String; let name: String; let matchedField: String }
    let manifest = FamiliarToolManifest(name: "file_search", title: "搜索文件",
        description: "Search Project filenames and the already-selected text in this frozen Run. This does not read every file body; use file_read for content.",
        parameters: .object(["query": .string("Search text")], required: ["query"]),
        effect: .read, risk: .low, supportsParallelism: true, requiredScopes: ["project"])

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarFileError.projectRequired }
        let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches: [Match] = []
        if !query.isEmpty {
            for file in context.files where file.reference.projectID == projectID &&
                (file.name.localizedCaseInsensitiveContains(query) || file.filename.localizedCaseInsensitiveContains(query)) {
                matches.append(.init(fileID: file.reference.fileID, versionID: file.reference.versionID,
                    identifier: "file_" + file.reference.versionID.uuidString, name: file.name, matchedField: "filename"))
            }
            for resource in context.resources where resource.extractedText.localizedCaseInsensitiveContains(query) &&
                !matches.contains(where: { $0.versionID == resource.versionID }) {
                matches.append(.init(fileID: resource.id, versionID: resource.versionID,
                    identifier: "file_" + resource.versionID.uuidString, name: resource.displayName, matchedField: "selectedText"))
            }
        }
        let bounded = Array(matches.prefix(100))
        return .result(.init(envelope: try .init(model: bounded,
            presentation: .recordCollection(.init(summary: "找到 \(bounded.count) 个文件匹配。", recordType: "file",
                records: bounded.map { .init(id: $0.fileID.uuidString, fields: [.init(name: "name", value: $0.name), .init(name: "identifier", value: $0.identifier)]) })))))
    }
}
