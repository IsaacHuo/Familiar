#if os(iOS)
import Foundation
#if canImport(FamiliarISHRuntime)
@preconcurrency import FamiliarISHRuntime
#endif

nonisolated struct FamiliarISHRuntimeConfiguration: Equatable, Sendable {
    let distribution = "Alpine"
    let architecture = "arm64"
    let maximumProcessCount: Int
    let maximumMemoryBytes: Int64
}

nonisolated struct FamiliarISHMount: Equatable, Sendable {
    let hostURL: URL
    let guestPath: String
    let writable: Bool
}

nonisolated enum FamiliarISHProcessEvent: Sendable {
    case standardOutput(Data)
    case standardError(Data)
    case exited(Int32)
    case timedOut
    case cancelled
    case resourceLimitExceeded(String)
    case networkStatistics(FamiliarShellNetworkStatistics)
}

/// Narrow bridge implemented inside the vendored iSH fork. It intentionally has
/// no host-directory, pasteboard, location, file-provider, or socket API.
nonisolated protocol FamiliarISHBridge: Sendable {
    func prepare(configuration: FamiliarISHRuntimeConfiguration) async throws

    func execute(
        taskID: UUID,
        command: String,
        workingDirectory: String,
        mounts: [FamiliarISHMount],
        networkPolicy: FamiliarShellNetworkPolicy,
        timeout: TimeInterval
    ) -> AsyncThrowingStream<FamiliarISHProcessEvent, Error>

    func cancel(taskID: UUID) async
}

nonisolated final class FamiliarISHShellExecutor: FamiliarShellExecutor, @unchecked Sendable {
    let runtimeKind = FamiliarShellRuntimeKind.ish
    let limits = FamiliarShellLimits.iOS
    private let bridge: any FamiliarISHBridge
    private let workspaceStore: FamiliarWorkspaceStore

    init(
        bridge: any FamiliarISHBridge,
        workspaceStore: FamiliarWorkspaceStore = FamiliarWorkspaceStore()
    ) {
        self.bridge = bridge
        self.workspaceStore = workspaceStore
    }

    func prepare() async throws {
        try await bridge.prepare(configuration: .init(
            maximumProcessCount: limits.maximumProcessCount,
            maximumMemoryBytes: limits.maximumMemoryBytes
        ))
    }

    func execute(
        _ request: FamiliarShellRequest
    ) -> AsyncThrowingStream<FamiliarShellEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let startedAt = Date()
                do {
                    guard request.timeout > 0,
                          request.timeout <= limits.maximumTimeout
                    else { throw FamiliarShellExecutorError.invalidTimeout }
                    try await prepare()
                    let paths = try workspaceStore.prepare(request.workspaceID)
                    let view = request.workspaceView
                    let taskRoot = paths.tasks.standardizedFileURL.path + "/"
                    let expectedEnvironment = paths.environment.standardizedFileURL
                    let environmentIsValid = view.environmentIsPersistent
                        ? view.environment.standardizedFileURL == expectedEnvironment
                        : view.environment.standardizedFileURL.path.hasPrefix(view.root.standardizedFileURL.path + "/")
                    guard view.workspaceID == request.workspaceID,
                          view.taskID == request.taskID,
                          view.root.standardizedFileURL.path.hasPrefix(taskRoot),
                          view.outputs.standardizedFileURL == paths.outputs.standardizedFileURL,
                          environmentIsValid,
                          (try? view.environment.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
                    else { throw FamiliarWorkspaceError.invalidTaskView }
                    let mounts = [
                        FamiliarISHMount(
                            hostURL: view.files,
                            guestPath: "/workspace/files",
                            writable: false
                        ),
                        FamiliarISHMount(
                            hostURL: view.outputs,
                            guestPath: "/workspace/outputs",
                            writable: true
                        ),
                        FamiliarISHMount(
                            hostURL: view.work,
                            guestPath: "/workspace/work",
                            writable: true
                        ),
                        FamiliarISHMount(
                            hostURL: view.environment,
                            guestPath: "/workspace/env",
                            writable: true
                        )
                    ]
                    continuation.yield(.started(
                        taskID: request.taskID,
                        runtime: .ish,
                        at: startedAt
                    ))
                    var stdout = FamiliarISHOutputBuffer()
                    var stderr = FamiliarISHOutputBuffer()
                    let safetyMessageBudget = min(512, limits.maximumOutputBytes)
                    var remainingOutputBytes = limits.maximumOutputBytes - safetyMessageBudget
                    var outputLimitReached = false
                    var resourceLimitReason: String?
                    var status = FamiliarShellTaskStatus.failed
                    var exitCode: Int32?
                    var networkStatistics = FamiliarShellNetworkStatistics.zero
                    let resourceState = FamiliarShellResourceLimitState()
                    let resourceMonitor = Task {
                        while !Task.isCancelled {
                            do {
                                let usage = try workspaceStore.shellWritableUsage(for: view)
                                if usage.largestFileBytes > limits.maximumFileBytes {
                                    resourceState.setReason("Shell 单文件超过允许大小。")
                                    await bridge.cancel(taskID: request.taskID)
                                    return
                                }
                                if usage.totalBytes > limits.maximumWorkspaceBytes {
                                    resourceState.setReason("Shell Workspace 超过允许大小。")
                                    await bridge.cancel(taskID: request.taskID)
                                    return
                                }
                            } catch {
                                resourceState.setReason("Shell Workspace 使用量检查失败。")
                                await bridge.cancel(taskID: request.taskID)
                                return
                            }
                            try? await Task.sleep(for: .milliseconds(250))
                        }
                    }
                    defer { resourceMonitor.cancel() }
                    let processEvents = bridge.execute(
                        taskID: request.taskID,
                        command: request.command,
                        workingDirectory: "/workspace/work",
                        mounts: mounts,
                        networkPolicy: request.networkPolicy,
                        timeout: request.timeout
                    )
                    for try await event in processEvents {
                        try Task.checkCancellation()
                        switch event {
                        case .standardOutput(let data):
                            let acceptedCount = min(data.count, remainingOutputBytes)
                            let chunk = stdout.append(data, maximumAccepted: remainingOutputBytes)
                            remainingOutputBytes -= acceptedCount
                            if !chunk.isEmpty { continuation.yield(.standardOutput(chunk)) }
                            if data.count > acceptedCount {
                                outputLimitReached = true
                                resourceLimitReason = "Shell 输出超过允许大小，任务已终止。"
                                await bridge.cancel(taskID: request.taskID)
                            }
                        case .standardError(let data):
                            let acceptedCount = min(data.count, remainingOutputBytes)
                            let chunk = stderr.append(data, maximumAccepted: remainingOutputBytes)
                            remainingOutputBytes -= acceptedCount
                            if !chunk.isEmpty { continuation.yield(.standardError(chunk)) }
                            if data.count > acceptedCount {
                                outputLimitReached = true
                                resourceLimitReason = "Shell 输出超过允许大小，任务已终止。"
                                await bridge.cancel(taskID: request.taskID)
                            }
                        case .exited(let code):
                            exitCode = code
                            status = code == 0 ? .succeeded : .failed
                        case .timedOut:
                            status = .timedOut
                        case .cancelled:
                            status = .cancelled
                        case .resourceLimitExceeded(let reason):
                            status = .failed
                            resourceLimitReason = reason
                        case .networkStatistics(let statistics):
                            networkStatistics = statistics
                        }
                    }
                    resourceMonitor.cancel()
                    if let monitoredReason = resourceState.reason {
                        status = .failed
                        resourceLimitReason = monitoredReason
                    }
                    if outputLimitReached {
                        status = .failed
                    }
                    if request.networkPolicy.enabled,
                       networkStatistics.openedConnections > request.networkPolicy.maximumTotalConnections
                        || networkStatistics.peakConcurrentConnections > request.networkPolicy.maximumConcurrentConnections
                        || networkStatistics.bytesReceived > request.networkPolicy.maximumBytesReceived
                        || networkStatistics.bytesSent > request.networkPolicy.maximumBytesSent {
                        status = .failed
                        resourceLimitReason = "Shell 网络用量超过当前任务预算。"
                        await bridge.cancel(taskID: request.taskID)
                    }
                    if !request.networkPolicy.enabled,
                       networkStatistics.openedConnections > 0
                        || networkStatistics.bytesReceived > 0
                        || networkStatistics.bytesSent > 0 {
                        status = .failed
                        resourceLimitReason = "当前 Workspace 未授权 Shell 网络访问。"
                        await bridge.cancel(taskID: request.taskID)
                    }
                    if let resourceLimitReason {
                        let message = Data(((stderr.string.isEmpty ? "" : "\n") + resourceLimitReason).utf8)
                        _ = stderr.append(message, maximumAccepted: safetyMessageBudget)
                    }
                    let result = FamiliarShellResult(
                        taskID: request.taskID,
                        runtime: .ish,
                        status: status,
                        exitCode: exitCode,
                        standardOutput: stdout.string,
                        standardError: stderr.string,
                        outputWasTruncated: stdout.wasTruncated || stderr.wasTruncated,
                        startedAt: startedAt,
                        finishedAt: Date(),
                        workspaceDiff: nil,
                        networkStatistics: networkStatistics
                    )
                    continuation.yield(.finished(result))
                    continuation.finish()
                } catch is CancellationError {
                    await bridge.cancel(taskID: request.taskID)
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { await self.bridge.cancel(taskID: request.taskID) }
            }
        }
    }

    func cancel(taskID: UUID) async {
        await bridge.cancel(taskID: taskID)
    }
}

nonisolated struct FamiliarUnavailableISHBridge: FamiliarISHBridge {
    func prepare(configuration _: FamiliarISHRuntimeConfiguration) async throws {
        throw FamiliarShellExecutorError.unavailable
    }

    func execute(
        taskID _: UUID,
        command _: String,
        workingDirectory _: String,
        mounts _: [FamiliarISHMount],
        networkPolicy _: FamiliarShellNetworkPolicy,
        timeout _: TimeInterval
    ) -> AsyncThrowingStream<FamiliarISHProcessEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: FamiliarShellExecutorError.unavailable)
        }
    }

    func cancel(taskID _: UUID) async {}
}

#if canImport(FamiliarISHRuntime)
nonisolated final class FamiliarRealISHBridge: FamiliarISHBridge, @unchecked Sendable {
    static var isBundledRuntimeAvailable: Bool {
        Bundle.main.url(forResource: "alpine-3.24.0-aarch64-fakefs", withExtension: "tar.gz") != nil
    }

    private let state = FamiliarRealISHRuntimeState()

    func prepare(configuration: FamiliarISHRuntimeConfiguration) async throws {
        try await state.prepare(configuration: configuration)
    }

    func execute(
        taskID: UUID,
        command: String,
        workingDirectory: String,
        mounts: [FamiliarISHMount],
        networkPolicy: FamiliarShellNetworkPolicy,
        timeout: TimeInterval
    ) -> AsyncThrowingStream<FamiliarISHProcessEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await state.start(
                        taskID: taskID,
                        command: command,
                        workingDirectory: workingDirectory,
                        mounts: mounts,
                        networkPolicy: networkPolicy,
                        timeout: timeout,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { await self.state.cancel(taskID: taskID) }
            }
        }
    }

    func cancel(taskID: UUID) async {
        await state.cancel(taskID: taskID)
    }
}

private actor FamiliarRealISHRuntimeState {
    private enum Phase: Equatable {
        case notInstalled
        case installing
        case booting
        case ready
        case running(UUID)
        case failed(String)
    }

    private struct InstallationMarker: Codable, Equatable {
        static let schemaVersion = 1

        let schemaVersion: Int
        let distribution: String
        let architecture: String
        let rootfsVersion: String
        let ishCommit: String
        let archiveHash: String
    }

    private static let rootfsVersion = "3.24.0"
    private static let ishCommit = "54ca185b77f170e12fd353fcd7443232f6cb73fd"

    private var phase: Phase = .notInstalled
    private var activeTaskID: UUID?
    private var activePID: Int32?
    private var activeMounts: [String] = []
    private var completionGate: FamiliarISHCompletionGate?
    private var activeContinuation: AsyncThrowingStream<FamiliarISHProcessEvent, Error>.Continuation?

    func prepare(configuration _: FamiliarISHRuntimeConfiguration) throws {
        if phase == .ready { return }
        if case .running = phase { return }
        let fileManager = FileManager.default
        do {
            guard let archive = Bundle.main.url(
                forResource: "alpine-3.24.0-aarch64-fakefs",
                withExtension: "tar.gz"
            ) else {
                throw FamiliarShellExecutorError.unavailable
            }
            let archiveHash = try Self.sha256(of: archive)
            let expectedMarker = InstallationMarker(
                schemaVersion: InstallationMarker.schemaVersion,
                distribution: "Alpine",
                architecture: "arm64",
                rootfsVersion: Self.rootfsVersion,
                ishCommit: Self.ishCommit,
                archiveHash: archiveHash
            )
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Familiar/ShellRuntime", isDirectory: true)
            let installed = support.appendingPathComponent("alpine-3.24.0-aarch64", isDirectory: true)
            let installationMarker = installed.appendingPathComponent("familiar-installation.json", isDirectory: false)
            let fakeFSMarker = installed.appendingPathComponent("meta.db", isDirectory: false)
            let dataDirectory = installed.appendingPathComponent("data", isDirectory: true)
            let storedMarker = try? JSONDecoder().decode(
                InstallationMarker.self,
                from: Data(contentsOf: installationMarker)
            )
            let installationIsValid = storedMarker == expectedMarker
                && fileManager.fileExists(atPath: fakeFSMarker.path)
                && fileManager.fileExists(atPath: dataDirectory.path)
            if FamiliarShellRuntimeReset.isScheduled || !installationIsValid {
                phase = .installing
                let staging = support.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
                defer { try? fileManager.removeItem(at: staging) }
                try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
                try ISHKernel.shared.installRootfsArchive(
                    archive.path,
                    destination: staging.path
                )
                let markerData = try JSONEncoder().encode(expectedMarker)
                try markerData.write(
                    to: staging.appendingPathComponent("familiar-installation.json", isDirectory: false),
                    options: [.atomic]
                )
                if fileManager.fileExists(atPath: installed.path) {
                    try fileManager.removeItem(at: installed)
                }
                try fileManager.moveItem(at: staging, to: installed)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var installedURL = installed
                try? installedURL.setResourceValues(values)
                FamiliarShellRuntimeReset.clear()
            }
            phase = .booting
            guard ISHKernel.shared.boot(withRootPath: installed.path) == 0 else {
                throw FamiliarShellExecutorError.unavailable
            }
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    func start(
        taskID: UUID,
        command: String,
        workingDirectory: String,
        mounts: [FamiliarISHMount],
        networkPolicy: FamiliarShellNetworkPolicy,
        timeout: TimeInterval,
        continuation: AsyncThrowingStream<FamiliarISHProcessEvent, Error>.Continuation
    ) throws {
        guard phase == .ready else { throw FamiliarShellExecutorError.unavailable }
        guard activeTaskID == nil else { throw FamiliarShellExecutorError.alreadyRunning }

        if networkPolicy.enabled, !ISHKernel.shared.configureDNS() {
            throw FamiliarShellExecutorError.networkConfigurationFailed
        }

        for mount in mounts {
            let result = ISHKernel.shared.bindMountPath(
                mount.guestPath,
                toHostPath: mount.hostURL.path,
                readOnly: !mount.writable
            )
            guard result == 0 else {
                for guestPath in activeMounts.reversed() {
                    _ = ISHKernel.shared.bindUnmountPath(guestPath)
                }
                activeMounts = []
                throw FamiliarWorkspaceError.invalidTaskView
            }
            activeMounts.append(mount.guestPath)
        }

        FamiliarISHNetworkController.configureEnabled(
            networkPolicy.enabled,
            maximumConcurrentConnections: UInt(networkPolicy.maximumConcurrentConnections),
            maximumTotalConnections: UInt(networkPolicy.maximumTotalConnections),
            maximumBytesReceived: UInt64(max(0, networkPolicy.maximumBytesReceived)),
            maximumBytesSent: UInt64(max(0, networkPolicy.maximumBytesSent))
        )

        let gate = FamiliarISHCompletionGate()
        completionGate = gate
        activeContinuation = continuation
        activeTaskID = taskID
        phase = .running(taskID)
        let wrappedCommand = "ulimit -u 16; ulimit -v 524288; ulimit -f 262144; "
            + "export VIRTUAL_ENV=/workspace/env; export PATH=/workspace/env/bin:$PATH; "
            + "export PYTHONPATH=/workspace/env/site-packages${PYTHONPATH:+:$PYTHONPATH}; "
            + "cd -- \(Self.shellQuote(workingDirectory)) && \(command)"
        let callbacks = FamiliarISHProcessCallbackBox(
            gate: gate,
            continuation: continuation,
            state: self,
            taskID: taskID
        )
        let pid = ISHShellExecutor.executeCommand(
            wrappedCommand,
            lineCallback: callbacks.lineCallback,
            completion: callbacks.completion
        )
        guard pid > 0 else {
            gate.finish()
            finish(taskID: taskID)
            throw FamiliarShellExecutorError.unavailable
        }
        activePID = Int32(pid)

        Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard gate.finish() else { return }
            ISHShellExecutor.killProcessGroup(pid)
            continuation.yield(.timedOut)
            self.finish(taskID: taskID)
            continuation.finish()
        }
    }

    func cancel(taskID: UUID) {
        guard activeTaskID == taskID else { return }
        let continuation = activeContinuation
        if let activePID {
            ISHShellExecutor.killProcessGroup(activePID)
        }
        let shouldFinishStream = completionGate?.finish() ?? false
        finish(taskID: taskID)
        if shouldFinishStream {
            continuation?.yield(.cancelled)
            continuation?.finish()
        }
    }

    private func finish(taskID: UUID) {
        guard activeTaskID == taskID else { return }
        for guestPath in activeMounts.reversed() {
            _ = ISHKernel.shared.bindUnmountPath(guestPath)
        }
        activeMounts = []
        activePID = nil
        activeTaskID = nil
        completionGate = nil
        activeContinuation = nil
        phase = .ready
        FamiliarISHNetworkController.configureEnabled(
            false,
            maximumConcurrentConnections: 0,
            maximumTotalConnections: 0,
            maximumBytesReceived: 0,
            maximumBytesSent: 0
        )
    }

    fileprivate func finishFromCallback(taskID: UUID) {
        finish(taskID: taskID)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Streams the bundled rootfs archive instead of mapping it whole; the digest
    /// is identical.
    private static func sha256(of url: URL) throws -> String {
        try FamiliarHash.sha256(contentsOf: url)
    }
}

/// Objective-C invokes iSH callbacks on queues it owns. Constructing those
/// blocks inside an actor-isolated method makes Swift 6 attach the actor's
/// executor precondition to the block itself, which aborts before the block can
/// hop back to the actor. This nonisolated box owns truly nonisolated blocks and
/// uses a detached task as the explicit trampoline back to runtime state.
private nonisolated final class FamiliarISHProcessCallbackBox: @unchecked Sendable {
    private let gate: FamiliarISHCompletionGate
    private let continuation: AsyncThrowingStream<FamiliarISHProcessEvent, Error>.Continuation
    private let state: FamiliarRealISHRuntimeState
    private let taskID: UUID

    init(
        gate: FamiliarISHCompletionGate,
        continuation: AsyncThrowingStream<FamiliarISHProcessEvent, Error>.Continuation,
        state: FamiliarRealISHRuntimeState,
        taskID: UUID
    ) {
        self.gate = gate
        self.continuation = continuation
        self.state = state
        self.taskID = taskID
    }

    var lineCallback: ISHShellLineCallback {
        { [self] line, isStandardError in
            guard !gate.isFinished else { return }
            let data = Data((line + "\n").utf8)
            continuation.yield(isStandardError ? .standardError(data) : .standardOutput(data))
        }
    }

    var completion: ISHShellCompletionCallback {
        { [self] result in
            guard gate.finish() else { return }
            let exitCode = Int32(result.exitCode)
            let continuation = continuation
            let state = state
            let taskID = taskID
            Task.detached {
                let counters = FamiliarISHNetworkController.counters()
                continuation.yield(.networkStatistics(.init(
                    openedConnections: Int(counters.openedConnections),
                    peakConcurrentConnections: Int(counters.peakConcurrentConnections),
                    bytesReceived: Int64(clamping: counters.bytesReceived),
                    bytesSent: Int64(clamping: counters.bytesSent)
                )))
                continuation.yield(.exited(exitCode))
                await state.finishFromCallback(taskID: taskID)
                continuation.finish()
            }
        }
    }
}

private nonisolated final class FamiliarISHCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    var isFinished: Bool { lock.withLock { finished } }

    @discardableResult
    func finish() -> Bool {
        lock.withLock {
            guard !finished else { return false }
            finished = true
            return true
        }
    }
}

private nonisolated final class FamiliarShellResourceLimitState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedReason: String?

    var reason: String? { lock.withLock { storedReason } }

    func setReason(_ reason: String) {
        lock.withLock {
            if storedReason == nil { storedReason = reason }
        }
    }
}
#endif

private nonisolated struct FamiliarISHOutputBuffer {
    private var data = Data()
    private(set) var wasTruncated = false

    mutating func append(_ incoming: Data, maximumAccepted: Int) -> String {
        let acceptedCount = max(0, maximumAccepted)
        if incoming.count > acceptedCount { wasTruncated = true }
        let accepted = incoming.prefix(acceptedCount)
        data.append(accepted)
        return String(decoding: accepted, as: UTF8.self)
    }

    var string: String { String(decoding: data, as: UTF8.self) }
}
#endif
