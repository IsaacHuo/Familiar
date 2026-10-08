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
        workspaceID: FamiliarWorkspaceID,
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
    private let preparation: FamiliarISHPreparation

    init(
        bridge: any FamiliarISHBridge,
        workspaceStore: FamiliarWorkspaceStore = FamiliarWorkspaceStore()
    ) {
        self.bridge = bridge
        self.workspaceStore = workspaceStore
        self.preparation = FamiliarISHPreparation(bridge: bridge, configuration: .init(
            maximumProcessCount: FamiliarShellLimits.iOS.maximumProcessCount,
            maximumMemoryBytes: FamiliarShellLimits.iOS.maximumMemoryBytes))
    }

    func prepare() async throws {
        try await preparation.prepare()
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
                    try Task.checkCancellation()
                    let paths = try workspaceStore.prepare(request.workspaceID)
                    let view = request.workspaceView
                    let taskRoot = paths.tasks.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                    let expectedEnvironment = paths.environment.standardizedFileURL
                    let environmentIsValid = view.environmentIsPersistent
                        ? view.environment.standardizedFileURL == expectedEnvironment
                        : view.environment.standardizedFileURL.path.hasPrefix(view.root.standardizedFileURL.path + "/")
                    guard view.workspaceID == request.workspaceID,
                          view.taskID == request.taskID,
                          view.root.resolvingSymlinksInPath().standardizedFileURL.pathComponents.starts(with: taskRoot),
                          view.outputs.standardizedFileURL == paths.outputs.standardizedFileURL,
                          environmentIsValid,
                          (try? view.environment.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
                    else { throw FamiliarWorkspaceError.invalidTaskView }
                    let home = view.work.appendingPathComponent(".home", isDirectory: true)
                    let temporary = view.work.appendingPathComponent(".tmp", isDirectory: true)
                    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                    let mounts = [
                        FamiliarISHMount(hostURL: home, guestPath: "/root", writable: true),
                        FamiliarISHMount(hostURL: temporary, guestPath: "/tmp", writable: true),
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
                        workspaceID: request.workspaceID,
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
            continuation.onTermination = { @Sendable reason in
                guard case .cancelled = reason else { return }
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
        workspaceID _: FamiliarWorkspaceID,
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

    private static let sharedState = FamiliarRealISHRuntimeState()
    private var state: FamiliarRealISHRuntimeState { Self.sharedState }

    func prepare(configuration: FamiliarISHRuntimeConfiguration) async throws {
        try await state.prepare(configuration: configuration)
    }

    func execute(
        taskID: UUID,
        workspaceID: FamiliarWorkspaceID,
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
                        workspaceID: workspaceID,
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
            continuation.onTermination = { @Sendable reason in
                guard case .cancelled = reason else { return }
                task.cancel()
                Task { await self.state.cancel(taskID: taskID) }
            }
        }
    }

    func openTerminal(taskID: UUID, workspaceID: FamiliarWorkspaceID,
                      mounts: [FamiliarISHMount], command: String,
                      networkPolicy: FamiliarShellNetworkPolicy,
                      columns: Int = 80, rows: Int = 24) -> AsyncThrowingStream<FamiliarTerminalEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await prepare(configuration: .init(maximumProcessCount: FamiliarShellLimits.iOS.maximumProcessCount,
                        maximumMemoryBytes: FamiliarShellLimits.iOS.maximumMemoryBytes))
                    try Task.checkCancellation()
                    try await state.startTerminal(taskID: taskID, workspaceID: workspaceID, mounts: mounts,
                        command: command, networkPolicy: networkPolicy, columns: columns, rows: rows, continuation: continuation)
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable reason in
                guard case .cancelled = reason else { return }
                task.cancel()
                Task { await self.state.closeTerminal(taskID: taskID) }
            }
        }
    }

    func sendTerminalInput(taskID: UUID, data: Data) async throws {
        try await state.sendTerminalInput(taskID: taskID, data: data)
    }
    func resizeTerminal(taskID: UUID, columns: Int, rows: Int) async throws {
        try await state.resizeTerminal(taskID: taskID, columns: columns, rows: rows)
    }
    func interruptTerminal(taskID: UUID) async { await state.interruptTerminal(taskID: taskID) }
    func closeTerminal(taskID: UUID) async { await state.closeTerminal(taskID: taskID) }
    func isIdle() async -> Bool { await state.isIdle }

    func cancel(taskID: UUID) async {
        await state.cancel(taskID: taskID)
    }
}

private actor FamiliarRealISHRuntimeState {
    private typealias Phase = FamiliarShellRuntimePhase

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

    private var preparation: Task<Void, Error>?
    private var lifecycleRevision = 0
    private var phase: Phase = .notPrepared {
        didSet {
            lifecycleRevision += 1
            let revision = lifecycleRevision
            let phase = phase
            Task { @MainActor in FamiliarShellRuntimeStatus.shared.receive(phase, revision: revision) }
        }
    }
    var isIdle: Bool { phase == .ready && activeTaskID == nil }
    private var activeTaskID: UUID?
    private var activePID: Int32?
    private var activeExecutionOwner: UInt64?
    private var activeWorkspaceID: FamiliarWorkspaceID?
    private var activeTerminal: ISHTerminalSession?
    private var terminalContinuation: AsyncThrowingStream<FamiliarTerminalEvent, Error>.Continuation?
    private var activeMounts: [String] = []
    private var completionGate: FamiliarISHCompletionGate?
    private var activeContinuation: AsyncThrowingStream<FamiliarISHProcessEvent, Error>.Continuation?

    func prepare(configuration _: FamiliarISHRuntimeConfiguration) async throws {
        if phase == .ready { return }
        if case .running = phase { return }
        guard activeTaskID == nil else { throw FamiliarShellExecutorError.unavailable }
        if let preparation {
            try await preparation.value
            if phase == .booting { phase = .ready }
            return
        }
        let fileManager = FileManager.default
        do {
            phase = .preparing
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
            // Keep the prior writable guest base intact for inspection. Scoped executions
            // start with a clean base so old root/home/temp content cannot cross Projects.
            let installed = support.appendingPathComponent("alpine-3.24.0-aarch64-scoped-v1", isDirectory: true)
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
            let probe = Task.detached {
                let result = ISHShellExecutor.executeCommandSync("python3 -c 'import ssl, sys; print(\"FAMILIAR_READY\")'", timeout: 30, lineCallback: nil)
                guard result.exitCode == 0, result.output.contains("FAMILIAR_READY") else {
                    throw FamiliarShellExecutorError.preparationFailed("iSH Python readiness probe failed (exit \(result.exitCode)): \(result.errorOutput.prefix(1000))")
                }
            }
            preparation = probe
            try await probe.value
            preparation = nil
            phase = .ready
        } catch {
            preparation = nil
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    func start(
        taskID: UUID,
        workspaceID: FamiliarWorkspaceID,
        command: String,
        workingDirectory: String,
        mounts: [FamiliarISHMount],
        networkPolicy: FamiliarShellNetworkPolicy,
        timeout: TimeInterval,
        continuation: AsyncThrowingStream<FamiliarISHProcessEvent, Error>.Continuation
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        guard activeTerminal == nil else { throw FamiliarShellExecutorError.alreadyRunning }
        while activeTaskID != nil {
            guard activeTerminal == nil else { throw FamiliarShellExecutorError.alreadyRunning }
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw FamiliarShellExecutorError.alreadyRunning }
            try await Task.sleep(for: .milliseconds(25))
        }
        try Task.checkCancellation()
        guard phase == .ready else { throw FamiliarShellExecutorError.unavailable }

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
        activeWorkspaceID = workspaceID
        ISHKernel.shared.setWorkspaceIsolationEnabled(true)
        phase = .running(taskID)
        let wrappedCommand = "ulimit -u 16; ulimit -v 524288; ulimit -f 262144; "
            + "export HOME=/root TMPDIR=/tmp; export VIRTUAL_ENV=/workspace/env; export PATH=/workspace/env/bin:$PATH; "
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
        activeExecutionOwner = ISHShellExecutor.executionOwner(forProcess: pid)

        Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard gate.finish() else { return }
            let stopped = ISHShellExecutor.terminateExecutionOwner(self.activeExecutionOwner ?? 0, timeout: 5)
            continuation.yield(.timedOut)
            if stopped { self.finish(taskID: taskID) }
            else { self.phase = .failed("Timed-out guest processes did not terminate; restart Familiar before retrying.") }
            continuation.finish()
        }
    }

    func cancel(taskID: UUID) {
        guard activeTaskID == taskID else { return }
        if activeTerminal != nil { closeTerminal(taskID: taskID); return }
        let continuation = activeContinuation
        let shouldFinishStream = completionGate?.finish() ?? false
        let stopped = activeExecutionOwner.map { ISHShellExecutor.terminateExecutionOwner($0, timeout: 5) } ?? true
        if stopped { finish(taskID: taskID) }
        else { phase = .failed("Guest processes did not terminate; restart Familiar before retrying.") }
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
        activeExecutionOwner = nil
        activeWorkspaceID = nil
        activeTerminal = nil
        terminalContinuation = nil
        activeTaskID = nil
        ISHKernel.shared.setWorkspaceIsolationEnabled(false)
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

    fileprivate func finishFromCallback(taskID: UUID) -> Bool {
        guard activeTaskID == taskID else { return true }
        guard let owner = activeExecutionOwner,
              ISHShellExecutor.terminateExecutionOwner(owner, timeout: 5) else {
            phase = .failed("Guest descendants did not terminate; restart Familiar before retrying.")
            return false
        }
        finish(taskID: taskID)
        return true
    }

    func startTerminal(taskID: UUID, workspaceID: FamiliarWorkspaceID, mounts: [FamiliarISHMount],
                       command: String, networkPolicy: FamiliarShellNetworkPolicy,
                       columns: Int, rows: Int,
                       continuation: AsyncThrowingStream<FamiliarTerminalEvent, Error>.Continuation) throws {
        try Task.checkCancellation()
        guard case .project = workspaceID, activeTaskID == nil else { throw FamiliarShellExecutorError.alreadyRunning }
        guard phase == .ready else { throw FamiliarShellExecutorError.unavailable }
        guard (2...500).contains(columns), (2...300).contains(rows) else { throw FamiliarWorkspaceError.invalidTaskView }
        if networkPolicy.enabled, !ISHKernel.shared.configureDNS() { throw FamiliarShellExecutorError.networkConfigurationFailed }
        do {
            for mount in mounts {
                guard ISHKernel.shared.bindMountPath(mount.guestPath, toHostPath: mount.hostURL.path, readOnly: !mount.writable) == 0 else {
                    throw FamiliarWorkspaceError.invalidTaskView
                }
                activeMounts.append(mount.guestPath)
            }
        } catch {
            for path in activeMounts.reversed() { _ = ISHKernel.shared.bindUnmountPath(path) }
            activeMounts = []
            throw error
        }
        FamiliarISHNetworkController.configureEnabled(networkPolicy.enabled,
            maximumConcurrentConnections: UInt(networkPolicy.maximumConcurrentConnections),
            maximumTotalConnections: UInt(networkPolicy.maximumTotalConnections),
            maximumBytesReceived: UInt64(max(0, networkPolicy.maximumBytesReceived)),
            maximumBytesSent: UInt64(max(0, networkPolicy.maximumBytesSent)))
        activeTaskID = taskID
        activeWorkspaceID = workspaceID
        terminalContinuation = continuation
        let callbacks = FamiliarTerminalCallbackBox(state: self, taskID: taskID, continuation: continuation)
        let session = ISHTerminalSession(maximumOutputBytes: UInt(FamiliarShellLimits.iOS.maximumOutputBytes),
            output: callbacks.output, exited: callbacks.exited, failed: callbacks.failed)
        activeTerminal = session
        ISHKernel.shared.setWorkspaceIsolationEnabled(true)
        phase = .running(taskID)
        let wrapped = "ulimit -u 16; ulimit -v 524288; ulimit -f 262144; cd /workspace/work && " + command
        let pid = session.start(command: wrapped, columns: UInt(columns), rows: UInt(rows))
        guard pid > 1 else {
            let stopped = session.close()
            if stopped { finish(taskID: taskID) }
            else { phase = .failed("Terminal startup could not be cleaned up; restart Familiar.") }
            throw FamiliarShellExecutorError.unavailable
        }
        activePID = Int32(pid)
        continuation.yield(.started)
    }

    func sendTerminalInput(taskID: UUID, data: Data) async throws {
        guard data.count <= 65_536 else { throw FamiliarWorkspaceError.invalidTaskView }
        var offset = 0
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while offset < data.count {
            try Task.checkCancellation()
            guard activeTaskID == taskID, let session = activeTerminal else { throw FamiliarShellExecutorError.unavailable }
            let size = min(4096, data.count - offset)
            let accepted = session.sendInput(data.subdata(in: offset..<(offset + size)))
            if accepted > 0 { offset += Int(accepted) }
            else {
                guard accepted == -11 || accepted == 0, ContinuousClock.now < deadline else {
                    throw FamiliarShellExecutorError.unavailable
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func resizeTerminal(taskID: UUID, columns: Int, rows: Int) throws {
        guard (2...500).contains(columns), (2...300).contains(rows), activeTaskID == taskID,
              activeTerminal?.resizeColumns(UInt(columns), rows: UInt(rows)) == true else {
            throw FamiliarWorkspaceError.invalidTaskView
        }
    }
    func interruptTerminal(taskID: UUID) {
        guard activeTaskID == taskID else { return }
        activeTerminal?.interrupt()
    }
    func closeTerminal(taskID: UUID) {
        guard activeTaskID == taskID, let session = activeTerminal else { return }
        let continuation = terminalContinuation
        let stopped = session.close()
        if stopped { finish(taskID: taskID); continuation?.yield(.cancelled) }
        else {
            phase = .failed("Terminal processes did not terminate; restart Familiar.")
            continuation?.yield(.failed("Terminal processes did not terminate; restart Familiar."))
        }
        continuation?.finish()
    }
    func terminalDidExit(taskID: UUID, exitCode: Int32?, failure: String?) {
        guard activeTaskID == taskID, let session = activeTerminal else { return }
        let continuation = terminalContinuation
        let stopped = session.close()
        if stopped {
            finish(taskID: taskID)
            if let failure { continuation?.yield(.failed(failure)) }
            else { continuation?.yield(.exited(exitCode ?? -1)) }
        } else {
            phase = .failed("Terminal descendants did not terminate; restart Familiar.")
            continuation?.yield(.failed("Terminal descendants did not terminate; restart Familiar."))
        }
        continuation?.finish()
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
            let report = gate.finish()
            let exitCode = Int32(result.exitCode)
            let continuation = continuation
            let state = state
            let taskID = taskID
            Task.detached {
                if !report {
                    _ = await state.finishFromCallback(taskID: taskID)
                    return
                }
                let counters = FamiliarISHNetworkController.counters()
                continuation.yield(.networkStatistics(.init(
                    openedConnections: Int(counters.openedConnections),
                    peakConcurrentConnections: Int(counters.peakConcurrentConnections),
                    bytesReceived: Int64(clamping: counters.bytesReceived),
                    bytesSent: Int64(clamping: counters.bytesSent)
                )))
                let stopped = await state.finishFromCallback(taskID: taskID)
                if stopped { continuation.yield(.exited(exitCode)) }
                else { continuation.yield(.resourceLimitExceeded("Guest descendants did not terminate; restart Familiar before retrying.")) }
                continuation.finish()
            }
        }
    }
}

private nonisolated final class FamiliarTerminalCallbackBox: @unchecked Sendable {
    let state: FamiliarRealISHRuntimeState
    let taskID: UUID
    let continuation: AsyncThrowingStream<FamiliarTerminalEvent, Error>.Continuation
    init(state: FamiliarRealISHRuntimeState, taskID: UUID, continuation: AsyncThrowingStream<FamiliarTerminalEvent, Error>.Continuation) {
        self.state = state; self.taskID = taskID; self.continuation = continuation
    }
    var output: @Sendable (Data) -> Void { { [self] in continuation.yield(.output($0)) } }
    var exited: @Sendable (Int32) -> Void {
        { [self] code in Task.detached { await self.state.terminalDidExit(taskID: self.taskID, exitCode: code, failure: nil) } }
    }
    var failed: @Sendable (any Error) -> Void {
        { [self] error in
            let detail = error.localizedDescription
            Task.detached { await self.state.terminalDidExit(taskID: self.taskID, exitCode: nil, failure: detail) }
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
