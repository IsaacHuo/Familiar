import Foundation

nonisolated struct FamiliarArtifactWriteTool: FamiliarTool {
    struct Input: Decodable, Sendable { let title: String; let content: String; let format: FamiliarArtifactFormat? }
    let store: FamiliarArtifactStore
    let manifest = FamiliarToolManifest(
        name: "artifact.write", title: "写入 Artifact", description: "将 Markdown 或纯文本保存到当前项目的 Artifact 目录。普通聊天没有项目作用域，不能使用此工具。",
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
        return .action(FamiliarActionProposal(title: "写入 Artifact", fields: ["标题": input.title, "大小": "\(data.count) 字节"], target: identifier,
            idempotencyKey: context.idempotencyKey, execute: {
                let stored = try store.write(data, projectID: projectID, artifactID: id, filename: filename)
                let descriptor = FamiliarArtifactDescriptor(id: id, identifier: identifier, projectID: projectID, title: input.title,
                    format: format, relativePath: stored.path, byteSize: Int64(data.count), contentHash: stored.hash, source: .generated,
                    sourceURLString: nil, sourceResourceID: nil, sourceResourceVersionID: nil, sourceCaptureID: nil, createdByRunID: context.runID)
                let payload = "{\"artifactIdentifier\":\"\(identifier)\",\"contentHash\":\"\(stored.hash)\"}"
                return .init(modelContent: payload, displayContent: "已写入 \(input.title)", artifactIdentifier: identifier, artifact: descriptor)
            }, undo: nil))
    }
}
