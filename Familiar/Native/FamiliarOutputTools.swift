import Foundation
#if os(iOS)
import Photos
#endif

nonisolated struct FamiliarResolvedWorkspaceOutput: Equatable, Sendable {
    let relativePath: String
    let filename: String
    let fileURL: URL
    let byteSize: Int64
    let contentHash: String
}

nonisolated protocol FamiliarWorkspaceOutputResolving: Sendable {
    func resolveOutput(relativePath: String, workspaceID: FamiliarWorkspaceID) throws -> FamiliarResolvedWorkspaceOutput
}

nonisolated struct FamiliarWorkspaceOutputResolver: FamiliarWorkspaceOutputResolving {
    let store: FamiliarWorkspaceStore

    func resolveOutput(relativePath: String, workspaceID: FamiliarWorkspaceID) throws -> FamiliarResolvedWorkspaceOutput {
        let path = try FamiliarNativeOutputPath.normalized(relativePath)
        guard let entry = try store.entries(in: workspaceID).first(where: { $0.relativePath == path }) else {
            throw FamiliarWorkspaceError.missingFile
        }
        let paths = try store.prepare(workspaceID)
        return FamiliarResolvedWorkspaceOutput(
            relativePath: path,
            filename: URL(fileURLWithPath: path).lastPathComponent,
            fileURL: paths.root.appendingPathComponent(path, isDirectory: false),
            byteSize: entry.byteSize,
            contentHash: entry.contentHash
        )
    }
}

nonisolated enum FamiliarPhotoLibraryAddAuthorization: String, Codable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

nonisolated protocol FamiliarPhotoLibrarySaving: Sendable {
    func addAuthorization() async -> FamiliarPhotoLibraryAddAuthorization
    func requestAddAuthorization() async -> FamiliarPhotoLibraryAddAuthorization
    func saveImage(at fileURL: URL) async throws -> String?
}

#if os(iOS)
actor FamiliarPhotoLibraryService: FamiliarPhotoLibrarySaving {
    func addAuthorization() -> FamiliarPhotoLibraryAddAuthorization {
        Self.authorization(PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }

    func requestAddAuthorization() async -> FamiliarPhotoLibraryAddAuthorization {
        Self.authorization(await PHPhotoLibrary.requestAuthorization(for: .addOnly))
    }

    func saveImage(at fileURL: URL) async throws -> String? {
        var localIdentifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            localIdentifier = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)?.placeholderForCreatedAsset?.localIdentifier
        }
        return localIdentifier
    }

    private static func authorization(_ status: PHAuthorizationStatus) -> FamiliarPhotoLibraryAddAuthorization {
        switch status {
        case .authorized, .limited: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}
#endif

nonisolated enum FamiliarNativeOutputToolError: LocalizedError, Sendable {
    case workspaceRequired
    case invalidOutputPath
    case unsupportedImage
    case photoAddPermissionDenied

    var errorDescription: String? {
        switch self {
        case .workspaceRequired: "当前 Run 没有可用的 Workspace。"
        case .invalidOutputPath: "只能处理当前 Workspace 的 Outputs 文件。"
        case .unsupportedImage: "该输出不是支持保存到照片图库的图片格式。"
        case .photoAddPermissionDenied: "未获得向照片图库添加图片的权限。"
        }
    }
}

nonisolated struct FamiliarPhotosSaveOutputTool: FamiliarTool {
    struct Input: Decodable, Sendable { let path: String }
    private struct Output: Encodable { let saved: Bool; let sourcePath: String; let assetIdentifier: String? }

    let resolver: any FamiliarWorkspaceOutputResolving
    let photos: any FamiliarPhotoLibrarySaving
    let manifest = FamiliarToolManifest(
        name: "photos_save_output",
        title: String(localized: "tool.photos_save_output"),
        description: "把当前 Workspace Outputs 中的一张图片添加到系统照片图库。只请求 add-only 权限，不读取或遍历图库；执行前逐次确认。",
        parameters: .init(type: .object, properties: [
            "path": .init(type: .string, description: "workspace_list 返回的 Outputs 图片路径")
        ], required: ["path"]),
        effect: .destructiveWrite,
        risk: .sensitive,
        requirements: [],
        dataDomains: ["workspace.outputs", "photos.add-only"],
        privacyLabels: ["photos"],
        supportsIdempotency: true,
        supportsCancellation: true,
        requiredScopes: ["workspace"],
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else { throw FamiliarNativeOutputToolError.workspaceRequired }
        let output = try resolver.resolveOutput(relativePath: input.path, workspaceID: workspaceID)
        guard FamiliarNativeOutputPath.isSupportedImage(output.filename) else { throw FamiliarNativeOutputToolError.unsupportedImage }
        return .action(FamiliarActionProposal(
            title: manifest.title,
            fields: [
                .init(id: "path", label: "Path", type: .text, value: output.relativePath),
                .init(id: "byteSize", label: "Size", type: .number, value: String(output.byteSize))
            ],
            target: output.filename,
            targetKey: output.relativePath,
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: "会向系统照片图库新增一张图片；Familiar 不会读取图库，也无法用 add-only 权限自动撤销。",
            undoPolicy: .unavailable,
            idempotencyKey: context.idempotencyKey,
            allowedAuthorizationDurations: [.once],
            commit: {
                try Task.checkCancellation()
                var status = await photos.addAuthorization()
                if status == .notDetermined { status = await photos.requestAddAuthorization() }
                guard status == .authorized else { throw FamiliarNativeOutputToolError.photoAddPermissionDenied }
                let identifier = try await photos.saveImage(at: output.fileURL)
                return FamiliarCommittedAction(result: .init(
                    envelope: try FamiliarToolResultEnvelope(
                        model: Output(saved: true, sourcePath: output.relativePath, assetIdentifier: identifier),
                        presentation: .mutationReceipt(.init(
                            summary: "已将 \(output.filename) 添加到照片图库。",
                            operation: "photosSaveOutput",
                            targetIdentifier: identifier,
                            succeeded: true,
                            undoAvailable: false
                        ))
                    ),
                    artifactIdentifier: identifier
                ))
            }
        ))
    }
}

/// Typed hand-off contract for the UI layer. The tool only resolves and audits the
/// local output; a SwiftUI surface must present ShareLink/UIActivityViewController.
nonisolated struct FamiliarPreparedFileExport: Codable, Equatable, Sendable {
    let relativePath: String
    let filename: String
    let fileURLString: String
    let byteSize: Int64
    let contentHash: String
    let requiresUserAction: Bool
}

nonisolated struct FamiliarPrepareFileExportTool: FamiliarTool {
    struct Input: Decodable, Sendable { let path: String }
    private struct ModelOutput: Encodable {
        let relativePath: String
        let filename: String
        let byteSize: Int64
        let contentHash: String
        let requiresUserAction: Bool
    }
    let resolver: any FamiliarWorkspaceOutputResolving
    let manifest = FamiliarToolManifest(
        name: "prepare_file_export",
        title: String(localized: "tool.prepare_file_export"),
        description: "准备当前 Workspace Outputs 中的文件供 Quick Look、系统分享或存储到 Files。不会自动发送或写入外部目录。",
        parameters: .init(type: .object, properties: [
            "path": .init(type: .string, description: "workspace_list 返回的 Outputs 文件路径")
        ], required: ["path"]),
        effect: .read,
        risk: .low,
        requirements: [],
        dataDomains: ["workspace.outputs", "share.payload"],
        supportsParallelism: true,
        requiredScopes: ["workspace"],
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else { throw FamiliarNativeOutputToolError.workspaceRequired }
        let output = try resolver.resolveOutput(relativePath: input.path, workspaceID: workspaceID)
        let prepared = FamiliarPreparedFileExport(
            relativePath: output.relativePath,
            filename: output.filename,
            fileURLString: output.fileURL.absoluteString,
            byteSize: output.byteSize,
            contentHash: output.contentHash,
            requiresUserAction: true
        )
        let modelOutput = ModelOutput(
            relativePath: prepared.relativePath,
            filename: prepared.filename,
            byteSize: prepared.byteSize,
            contentHash: prepared.contentHash,
            requiresUserAction: prepared.requiresUserAction
        )
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: modelOutput,
            presentation: .document(.init(
                summary: "已准备 \(output.filename)，仍需用户主动打开系统分享或 Files 导出。",
                title: output.filename,
                text: "",
                url: output.fileURL.absoluteString
            ))
        )))
    }
}

nonisolated private enum FamiliarNativeOutputPath {
    static func normalized(_ rawValue: String) throws -> String {
        let normalized = rawValue.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.first == "Outputs",
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else { throw FamiliarNativeOutputToolError.invalidOutputPath }
        return normalized
    }

    static func isSupportedImage(_ filename: String) -> Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff"].contains(
            URL(fileURLWithPath: filename).pathExtension.lowercased()
        )
    }
}
