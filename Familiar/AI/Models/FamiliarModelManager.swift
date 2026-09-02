import Foundation

nonisolated struct FamiliarModelManifest: Codable, Equatable, Sendable {
    let modelID: String
    let version: String
    let displayName: String
    let runtime: String
    let downloadURL: URL
    let archiveSHA256: String
    let archiveByteCount: Int64?
    let minimumSystemVersion: String

    var installationKey: String { "\(modelID)-\(version)" }
}

nonisolated enum FamiliarManagedModelState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double)
    case paused(progress: Double)
    case verifying
    case preparing
    case ready
    case failed(String)
}

nonisolated struct FamiliarManagedModelSnapshot: Equatable, Sendable {
    let manifest: FamiliarModelManifest
    let state: FamiliarManagedModelState
    let installedURL: URL?
}

nonisolated enum FamiliarModelManagerError: LocalizedError, Sendable {
    case invalidManifest
    case invalidArchiveSize
    case integrityFailure
    case notReady

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "本地模型清单无效。"
        case .invalidArchiveSize: "本地模型文件大小与清单不一致。"
        case .integrityFailure: "本地模型未通过 SHA-256 校验。"
        case .notReady: "本地模型尚未准备完成。"
        }
    }
}

/// Converts a verified download into the runtime-specific prepared model directory.
/// The Core AI target owns specialization; ModelManager owns lifecycle and storage.
nonisolated protocol FamiliarModelPreparing: Sendable {
    func prepareModel(
        archiveURL: URL,
        destinationURL: URL,
        manifest: FamiliarModelManifest
    ) async throws
}

actor FamiliarModelManager {
    private let manifest: FamiliarModelManifest
    private let rootDirectory: URL
    private let preparer: any FamiliarModelPreparing
    private var state: FamiliarManagedModelState
    private var downloader: FamiliarModelDownloadCoordinator?
    private var progress: Double = 0
    private var observers: [UUID: AsyncStream<FamiliarManagedModelSnapshot>.Continuation] = [:]

    init(
        manifest: FamiliarModelManifest,
        rootDirectory: URL? = nil,
        preparer: any FamiliarModelPreparing
    ) {
        self.manifest = manifest
        self.preparer = preparer
        let base = rootDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Familiar/Models", isDirectory: true)
        self.rootDirectory = base
        state = FileManager.default.fileExists(atPath: Self.installationURL(
            root: base,
            manifest: manifest
        ).path) ? .ready : .notInstalled
    }

    func snapshot() -> FamiliarManagedModelSnapshot {
        FamiliarManagedModelSnapshot(
            manifest: manifest,
            state: state,
            installedURL: isReady ? installationURL : nil
        )
    }

    func snapshots() -> AsyncStream<FamiliarManagedModelSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(snapshot())
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeObserver(id) }
            }
        }
    }

    func install() async throws {
        guard !manifest.modelID.isEmpty,
              !manifest.version.isEmpty,
              manifest.archiveSHA256.count == 64
        else { throw FamiliarModelManagerError.invalidManifest }
        if isReady { return }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: downloadsDirectory,
            withIntermediateDirectories: true
        )
        let archiveURL = downloadArchiveURL
        let coordinator = downloader ?? FamiliarModelDownloadCoordinator(
            destination: archiveURL
        ) { [weak self] progress in
            Task { await self?.updateDownloadProgress(progress) }
        }
        downloader = coordinator
        transition(to: .downloading(progress: progress))

        do {
            let downloaded = try await coordinator.download(from: manifest.downloadURL)
            progress = 1
            transition(to: .verifying)
            if let expected = manifest.archiveByteCount {
                let values = try downloaded.resourceValues(forKeys: [.fileSizeKey])
                guard Int64(values.fileSize ?? -1) == expected else {
                    throw FamiliarModelManagerError.invalidArchiveSize
                }
            }
            guard try Self.sha256(of: downloaded)
                .caseInsensitiveCompare(manifest.archiveSHA256) == .orderedSame
            else { throw FamiliarModelManagerError.integrityFailure }

            transition(to: .preparing)
            let staging = rootDirectory.appendingPathComponent(
                "Staging/\(manifest.installationKey)-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: staging.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            defer {
                try? fileManager.removeItem(at: staging)
                try? fileManager.removeItem(at: downloaded)
            }
            try await preparer.prepareModel(
                archiveURL: downloaded,
                destinationURL: staging,
                manifest: manifest
            )
            guard fileManager.fileExists(atPath: staging.path) else {
                throw FamiliarModelManagerError.notReady
            }
            try fileManager.createDirectory(
                at: installationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: installationURL)
            try fileManager.moveItem(at: staging, to: installationURL)
            downloader = nil
            transition(to: .ready)
        } catch is CancellationError {
            transition(to: coordinator.hasResumeData
                ? .paused(progress: progress)
                : .notInstalled)
            throw CancellationError()
        } catch {
            transition(to: .failed(error.localizedDescription))
            throw error
        }
    }

    func pauseDownload() {
        downloader?.pause()
    }

    func discardDownload() {
        downloader?.cancel()
        downloader = nil
        progress = 0
        try? FileManager.default.removeItem(at: downloadArchiveURL)
        transition(to: .notInstalled)
    }

    func deleteModel() throws {
        downloader?.cancel()
        downloader = nil
        try? FileManager.default.removeItem(at: installationURL)
        progress = 0
        transition(to: .notInstalled)
    }

    func installedModelURL() throws -> URL {
        guard isReady else { throw FamiliarModelManagerError.notReady }
        return installationURL
    }

    private var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    private var installationURL: URL {
        Self.installationURL(root: rootDirectory, manifest: manifest)
    }

    private var downloadsDirectory: URL {
        rootDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    private var downloadArchiveURL: URL {
        downloadsDirectory.appendingPathComponent(manifest.installationKey + ".download")
    }

    private static func installationURL(
        root: URL,
        manifest: FamiliarModelManifest
    ) -> URL {
        root.appendingPathComponent("Installed", isDirectory: true)
            .appendingPathComponent(manifest.installationKey, isDirectory: true)
    }

    private func updateDownloadProgress(_ value: Double) {
        progress = min(max(value, 0), 1)
        transition(to: .downloading(progress: progress))
    }

    private func transition(to newState: FamiliarManagedModelState) {
        state = newState
        let value = snapshot()
        for observer in observers.values { observer.yield(value) }
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        try FamiliarHash.sha256(contentsOf: url)
    }
}
