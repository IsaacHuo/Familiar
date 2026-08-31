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

nonisolated struct FamiliarPhotoAssetMetadata: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let mediaType: String
    let createdAtISO8601: String?
    let latitude: Double?
    let longitude: Double?
    let pixelWidth: Int
    let pixelHeight: Int
    let isFavorite: Bool
}

nonisolated protocol FamiliarPhotoLibraryReading: Sendable {
    func readAvailability() async -> FamiliarCapabilityAvailability
    func requestReadAccess() async throws
    func recentAssets(limit: Int, imagesOnly: Bool) async throws -> [FamiliarPhotoAssetMetadata]
}

#if os(iOS)
actor FamiliarPhotoLibraryService: FamiliarPhotoLibrarySaving, FamiliarPhotoLibraryReading {
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

    func readAvailability() -> FamiliarCapabilityAvailability {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: .available
        case .notDetermined: .requestable
        case .denied, .restricted: .unavailable(reason: "照片读取权限不可用，请在系统设置中允许访问或选择有限照片。")
        @unknown default: .unavailable(reason: "照片读取权限状态未知。")
        }
    }

    func requestReadAccess() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw FamiliarToolRegistryError.capabilityUnavailable("用户未允许读取照片。")
        }
    }

    func recentAssets(limit: Int, imagesOnly: Bool) async throws -> [FamiliarPhotoAssetMetadata] {
        guard case .available = readAvailability() else {
            throw FamiliarToolRegistryError.capabilityUnavailable("照片读取权限尚未授予。")
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = min(max(limit, 1), 50)
        let result = imagesOnly
            ? PHAsset.fetchAssets(with: .image, options: options)
            : PHAsset.fetchAssets(with: options)
        var values: [FamiliarPhotoAssetMetadata] = []
        result.enumerateObjects { asset, _, stop in
            let mediaType: String = switch asset.mediaType {
            case .image: "image"
            case .video: "video"
            case .audio: "audio"
            case .unknown: "unknown"
            @unknown default: "unknown"
            }
            values.append(.init(
                id: asset.localIdentifier,
                mediaType: mediaType,
                createdAtISO8601: asset.creationDate?.ISO8601Format(),
                latitude: asset.location?.coordinate.latitude,
                longitude: asset.location?.coordinate.longitude,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                isFavorite: asset.isFavorite
            ))
            if values.count >= options.fetchLimit { stop.pointee = true }
        }
        return values
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

nonisolated struct FamiliarPhotosRecentMetadataTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let limit: Int?
        let imagesOnly: Bool?
    }

    let photos: any FamiliarPhotoLibraryReading
    let manifest = FamiliarToolManifest(
        name: "photos_recent_metadata",
        title: "读取最近照片信息",
        description: "经明确授权后读取照片图库中最近项目的时间、媒体类型、尺寸及可用的位置元数据。不会读取图片像素、导出原图或遍历超过 50 项；有限照片权限会被尊重。",
        parameters: .init(type: .object, properties: [
            "limit": .init(type: .integer, description: "返回 1 到 50 项，默认 10"),
            "imagesOnly": .init(type: .boolean, description: "是否只返回图片，默认 true")
        ], required: []),
        effect: .read,
        risk: .high,
        requirements: [.photoLibraryRead],
        dataDomains: ["photos.metadata"],
        privacyLabels: ["photos", "location-metadata"],
        supportsParallelism: false,
        executionClass: .native
    )

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        let assets = try await photos.recentAssets(
            limit: input.limit ?? 10,
            imagesOnly: input.imagesOnly ?? true
        )
        let records = assets.map { asset in
            var fields: [FamiliarToolPresentationPayload.RecordField] = [
                .init(name: "mediaType", value: asset.mediaType),
                .init(name: "dimensions", value: "\(asset.pixelWidth)×\(asset.pixelHeight)"),
                .init(name: "favorite", value: String(asset.isFavorite))
            ]
            if let date = asset.createdAtISO8601 { fields.append(.init(name: "createdAt", value: date)) }
            if let latitude = asset.latitude, let longitude = asset.longitude {
                fields.append(.init(name: "latitude", value: String(latitude)))
                fields.append(.init(name: "longitude", value: String(longitude)))
            }
            return FamiliarToolPresentationPayload.Record(id: asset.id, fields: fields)
        }
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: assets,
            presentation: .recordCollection(.init(
                summary: "已读取 \(assets.count) 项照片元数据。",
                recordType: "photoAssetMetadata",
                records: records
            ))
        )))
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
