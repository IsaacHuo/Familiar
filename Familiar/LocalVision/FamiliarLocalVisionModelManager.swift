import CoreML
import CryptoKit
import FastVLMRuntime
import Foundation
import Metal
import Observation
import UIKit

nonisolated enum FamiliarLocalVisionState: Equatable, Sendable {
    case notInstalled
    case downloading
    case paused
    case installing
    case installed
    case unavailable(String)
    case failed(String)
}

nonisolated enum FamiliarLocalVisionError: LocalizedError, Sendable {
    case unsupportedDevice
    case insufficientStorage
    case invalidArchive
    case integrityFailure
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice: String(localized: "local_vision.error.device", defaultValue: "This device did not pass the FastVLM device check.")
        case .insufficientStorage: String(localized: "local_vision.error.storage", defaultValue: "At least 3.5 GB of free storage is required.")
        case .invalidArchive: String(localized: "local_vision.error.archive", defaultValue: "The downloaded FastVLM archive is incomplete.")
        case .integrityFailure: String(localized: "local_vision.error.integrity", defaultValue: "The FastVLM archive failed integrity verification.")
        case .timedOut: String(localized: "local_vision.error.timeout", defaultValue: "FastVLM exceeded the 60 second limit.")
        }
    }
}

@MainActor
@Observable
final class FamiliarLocalVisionModelManager {
    static let shared = FamiliarLocalVisionModelManager()

    static let modelID = "llava-fastvithd_0.5b_stage3_llm.fp16"
    static let archiveSize: Int64 = 1_232_152_649
    static let archiveSHA256 = "661506b66e9101463165b2834a99c89868b0d65fe7b1debbd46bdbd3b4f98d13"
    static let downloadURL = URL(string: "https://ml-site.cdn-apple.com/datasets/fastvlm/llava-fastvithd_0.5b_stage3_llm.fp16.zip")!

    private(set) var state: FamiliarLocalVisionState = .notInstalled
    private(set) var progress: Double = 0
    private(set) var lastBenchmarkDuration: TimeInterval?
    private var operation: Task<Void, Never>?
    private var downloader: FamiliarModelDownloadCoordinator?
    private let runtime = FastVLMLocalRuntime()
    private static let benchmarkPassedKey = "familiar.localVision.fastvlm.0_5b.benchmarkPassed"
    private static let benchmarkDurationKey = "familiar.localVision.fastvlm.0_5b.benchmarkDuration"

    private init() {
        let installed = Self.hasInstalledModel(at: modelDirectory)
        let benchmarkPassed = UserDefaults.standard.bool(forKey: Self.benchmarkPassedKey)
        state = installed && benchmarkPassed ? .installed : (installed ? .unavailable(String(localized: "local_vision.error.benchmark_required", defaultValue: "Run the device benchmark before using FastVLM.")) : .notInstalled)
        let duration = UserDefaults.standard.double(forKey: Self.benchmarkDurationKey)
        lastBenchmarkDuration = duration > 0 ? duration : nil
    }

    var modelDirectory: URL {
        Self.rootDirectory.appendingPathComponent("installed", isDirectory: true).appendingPathComponent(Self.modelID, isDirectory: true)
    }

    var isInstalled: Bool { state == .installed }

    func install() {
        guard operation == nil else { return }
        operation = Task {
            defer { operation = nil }
            do {
                try checkDeviceEligibility()
                try FileManager.default.createDirectory(at: Self.rootDirectory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                state = .downloading
                let archiveURL = Self.rootDirectory.appendingPathComponent("download.zip")
                let coordinator = downloader ?? FamiliarModelDownloadCoordinator(destination: archiveURL) { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
                downloader = coordinator
                let temporaryURL = try await coordinator.download(from: Self.downloadURL)
                let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
                guard Int64(values.fileSize ?? 0) == Self.archiveSize else { throw FamiliarLocalVisionError.invalidArchive }
                progress = 1
                state = .installing
                try await installArchive(at: temporaryURL)
                downloader = nil
                state = .installed
                await benchmark()
            } catch is CancellationError {
                state = downloader?.hasResumeData == true ? .paused : .notInstalled
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    state = downloader?.hasResumeData == true ? .paused : .notInstalled
                } else if downloader?.hasResumeData == true {
                    state = .paused
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelInstall() {
        downloader?.pause()
    }

    func discardDownload() {
        downloader?.cancel()
        downloader = nil
        operation?.cancel()
        operation = nil
        progress = 0
        try? FileManager.default.removeItem(at: Self.rootDirectory.appendingPathComponent("download.zip"))
        state = .notInstalled
    }

    func deleteModel() async {
        operation?.cancel()
        operation = nil
        downloader?.cancel()
        downloader = nil
        await runtime.unload()
        try? FileManager.default.removeItem(at: modelDirectory)
        progress = 0
        lastBenchmarkDuration = nil
        UserDefaults.standard.removeObject(forKey: Self.benchmarkPassedKey)
        UserDefaults.standard.removeObject(forKey: Self.benchmarkDurationKey)
        state = .notInstalled
    }

    func answer(imageURL: URL, prompt: String) async throws -> String {
        guard isInstalled else { throw FamiliarLocalVisionError.unsupportedDevice }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [runtime, modelDirectory] in
                try await runtime.answer(modelDirectory: modelDirectory, imageURL: imageURL, prompt: prompt)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                throw FamiliarLocalVisionError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw FamiliarLocalVisionError.timedOut }
            return result
        }
    }

    func benchmark(imageURL: URL) async {
        guard isInstalled else { return }
        let start = Date()
        do {
            _ = try await answer(imageURL: imageURL, prompt: "Describe this image briefly and factually.")
            let duration = Date().timeIntervalSince(start)
            lastBenchmarkDuration = duration
            UserDefaults.standard.set(true, forKey: Self.benchmarkPassedKey)
            UserDefaults.standard.set(duration, forKey: Self.benchmarkDurationKey)
        } catch {
            UserDefaults.standard.set(false, forKey: Self.benchmarkPassedKey)
            state = .unavailable(error.localizedDescription)
        }
    }

    func benchmark() async {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256))
        let image = renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor.label.setFill()
            "Familiar".draw(at: CGPoint(x: 64, y: 112), withAttributes: [.font: UIFont.systemFont(ofSize: 24, weight: .semibold)])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fastvlm-benchmark.jpg")
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        do {
            try data.write(to: url, options: .atomic)
            await benchmark(imageURL: url)
            try? FileManager.default.removeItem(at: url)
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func markInstalledForRetry() {
        state = Self.hasInstalledModel(at: modelDirectory) ? .installed : .notInstalled
    }

    private func checkDeviceEligibility() throws {
        guard #available(iOS 18.2, *) else { throw FamiliarLocalVisionError.unsupportedDevice }
#if targetEnvironment(simulator)
        throw FamiliarLocalVisionError.unsupportedDevice
#else
        guard ProcessInfo.processInfo.physicalMemory >= 6_000_000_000,
              MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7) == true
        else { throw FamiliarLocalVisionError.unsupportedDevice }
        let values = try Self.rootDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard (values.volumeAvailableCapacityForImportantUsage ?? 0) >= 3_500_000_000 else { throw FamiliarLocalVisionError.insufficientStorage }
#endif
    }

    private func installArchive(at sourceURL: URL) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Self.rootDirectory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let archiveURL = sourceURL
        guard try Self.sha256(of: archiveURL) == Self.archiveSHA256 else {
            try? fileManager.removeItem(at: archiveURL)
            throw FamiliarLocalVisionError.integrityFailure
        }

        let staging = Self.rootDirectory.appendingPathComponent("staging-" + UUID().uuidString, isDirectory: true)
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: archiveURL)
        }
        try FastVLMArchiveInstaller.extract(archiveURL: archiveURL, to: staging)
        let extracted = staging.appendingPathComponent(Self.modelID, isDirectory: true)
        for name in ["config.json", "preprocessor_config.json", "processor_config.json", "tokenizer_config.json", "fastvithd.mlpackage"] {
            guard fileManager.fileExists(atPath: extracted.appendingPathComponent(name).path) else { throw FamiliarLocalVisionError.invalidArchive }
        }
        try fileManager.removeItem(at: archiveURL)
        let compiled = try await MLModel.compileModel(at: extracted.appendingPathComponent("fastvithd.mlpackage", isDirectory: true))
        try fileManager.moveItem(at: compiled, to: extracted.appendingPathComponent("fastvithd.mlmodelc", isDirectory: true))
        try fileManager.removeItem(at: extracted.appendingPathComponent("fastvithd.mlpackage", isDirectory: true))
        let installedRoot = modelDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: installedRoot, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: modelDirectory)
        try fileManager.moveItem(at: extracted, to: modelDirectory)
    }

    private static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Familiar/LocalModels/FastVLM", isDirectory: true)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func hasInstalledModel(at directory: URL) -> Bool {
        ["config.json", "model.safetensors", "tokenizer.json", "fastvithd.mlmodelc"].allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }
}

private nonisolated final class FamiliarModelDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progressHandler: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?
    private var completedURL: URL?
    private var pausing = false

    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        progressHandler = progress
    }

    var hasResumeData: Bool { lock.withLock { resumeData != nil } }

    func download(from url: URL) async throws -> URL {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    self.continuation = continuation
                    completedURL = nil
                    pausing = false
                    let configuration = URLSessionConfiguration.default
                    configuration.allowsCellularAccess = true
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                    self.session = session
                    let task = resumeData.map(session.downloadTask(withResumeData:)) ?? session.downloadTask(with: url)
                    self.task = task
                    task.resume()
                }
            }
        }, onCancel: { self.cancel() })
    }

    func pause() {
        lock.withLock { pausing = true }
        task?.cancel { data in
            self.lock.withLock { self.resumeData = data }
        }
    }

    func cancel() {
        lock.withLock {
            pausing = false
            resumeData = nil
        }
        task?.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            lock.withLock {
                completedURL = destination
                resumeData = nil
            }
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            let nsError = error as NSError
            if let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                lock.withLock { resumeData = data }
            }
            finish(.failure(lock.withLock { pausing } ? CancellationError() : error))
        } else if let url = lock.withLock({ completedURL }) {
            finish(.success(url))
        }
        session.finishTasksAndInvalidate()
    }

    private func finish(_ result: Result<URL, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<URL, Error>? in
            defer { self.continuation = nil; task = nil; session = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }
}
