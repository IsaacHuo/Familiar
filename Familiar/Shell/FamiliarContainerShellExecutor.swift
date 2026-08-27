#if os(macOS) && canImport(Containerization)
import Containerization
import Foundation

actor FamiliarContainerRuntimeSession {
    enum State: Equatable, Sendable {
        case stopped
        case starting
        case ready
        case running(UUID)
        case failed(String)
    }

    let workspaceID: FamiliarWorkspaceID
    private let container: LinuxContainer
    private(set) var state: State = .stopped
    private var activeProcess: LinuxProcess?
    private var idleTask: Task<Void, Never>?
    private let idleTimeout: Duration
    private let executionGate: FamiliarContainerExecutionGate
    private var cancelledTaskIDs: Set<UUID> = []

    init(
        workspaceID: FamiliarWorkspaceID,
        container: LinuxContainer,
        idleTimeout: Duration = .seconds(600),
        executionGate: FamiliarContainerExecutionGate = .shared
    ) {
        self.workspaceID = workspaceID
        self.container = container
        self.idleTimeout = idleTimeout
        self.executionGate = executionGate
    }

    func start() async throws {
        idleTask?.cancel()
        switch state {
        case .ready, .running:
            return
        case .starting:
            throw FamiliarShellExecutorError.alreadyRunning
        case .stopped, .failed:
            break
        }
        guard container.interfaces.isEmpty else {
            throw FamiliarContainerRuntimeError.networkInterfaceConfigured
        }
        state = .starting
        do {
            try await container.create()
            try await container.start()
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func execute(_ request: FamiliarShellRequest) async throws -> FamiliarShellResult {
        await executionGate.acquire()
        defer { Task { await executionGate.release() } }
        try await start()
        guard case .ready = state else { throw FamiliarShellExecutorError.alreadyRunning }
        state = .running(request.taskID)
        let stdout = FamiliarContainerBufferWriter(limit: FamiliarShellLimits.macOS.maximumOutputBytes)
        let stderr = FamiliarContainerBufferWriter(limit: FamiliarShellLimits.macOS.maximumOutputBytes)
        let startedAt = Date()

        let process = try await container.exec(request.taskID.uuidString.lowercased()) { config in
            config.arguments = ["/bin/sh", "-lc", request.command]
            config.workingDirectory = "/workspace/work"
            config.noNewPrivileges = true
            config.capabilities = LinuxCapabilities()
            config.stdout = stdout
            config.stderr = stderr
            config.terminal = false
        }
        activeProcess = process
        do {
            try await process.start()
            let exit = try await process.wait(timeoutInSeconds: Int64(request.timeout.rounded(.up)))
            try await process.delete()
            activeProcess = nil
            state = .ready
            scheduleIdleStop()
            let wasCancelled = cancelledTaskIDs.remove(request.taskID) != nil
            return FamiliarShellResult(
                taskID: request.taskID,
                runtime: .containerization,
                status: wasCancelled ? .cancelled : (exit.exitCode == 0 ? .succeeded : .failed),
                exitCode: exit.exitCode,
                standardOutput: stdout.string,
                standardError: stderr.string,
                outputWasTruncated: stdout.wasTruncated || stderr.wasTruncated,
                startedAt: startedAt,
                finishedAt: exit.exitedAt,
                workspaceDiff: nil
            )
        } catch is CancellationError {
            try? await process.kill(.term)
            try? await process.kill(.kill)
            try? await process.delete()
            activeProcess = nil
            state = .ready
            scheduleIdleStop()
            cancelledTaskIDs.remove(request.taskID)
            return FamiliarShellResult(
                taskID: request.taskID,
                runtime: .containerization,
                status: .cancelled,
                exitCode: nil,
                standardOutput: stdout.string,
                standardError: stderr.string,
                outputWasTruncated: stdout.wasTruncated || stderr.wasTruncated,
                startedAt: startedAt,
                finishedAt: Date(),
                workspaceDiff: nil
            )
        } catch {
            try? await process.kill(.kill)
            try? await process.delete()
            activeProcess = nil
            state = .ready
            scheduleIdleStop()
            let wasCancelled = cancelledTaskIDs.remove(request.taskID) != nil
            return FamiliarShellResult(
                taskID: request.taskID,
                runtime: .containerization,
                status: wasCancelled ? .cancelled : .timedOut,
                exitCode: nil,
                standardOutput: stdout.string,
                standardError: stderr.string.isEmpty ? error.localizedDescription : stderr.string,
                outputWasTruncated: stdout.wasTruncated || stderr.wasTruncated,
                startedAt: startedAt,
                finishedAt: Date(),
                workspaceDiff: nil
            )
        }
    }

    func cancel(taskID: UUID) async {
        guard state == .running(taskID), let activeProcess else { return }
        cancelledTaskIDs.insert(taskID)
        try? await activeProcess.kill(.term)
        try? await Task.sleep(for: .seconds(1))
        try? await activeProcess.kill(.kill)
    }

    func stop() async {
        idleTask?.cancel()
        if let activeProcess {
            try? await activeProcess.kill(.kill)
            try? await activeProcess.delete()
            self.activeProcess = nil
        }
        try? await container.stop()
        state = .stopped
    }

    private func scheduleIdleStop() {
        idleTask?.cancel()
        let idleTimeout = self.idleTimeout
        idleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: idleTimeout)
                await self?.stop()
            } catch {}
        }
    }
}

actor FamiliarContainerExecutionGate {
    static let shared = FamiliarContainerExecutionGate()

    private var isOccupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isOccupied {
            isOccupied = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            isOccupied = false
            return
        }
        waiters.removeFirst().resume()
    }
}

/// Creates a networkless container from assets already downloaded and verified
/// by Familiar. OCI pulling and host command execution are intentionally absent.
nonisolated enum FamiliarContainerRuntimeFactory {
    static func makeSession(
        workspaceID: FamiliarWorkspaceID,
        workspaceStore: FamiliarWorkspaceStore,
        rootFileSystem: Mount,
        writableLayer: Mount,
        virtualMachineManager: any VirtualMachineManager
    ) throws -> FamiliarContainerRuntimeSession {
        let paths = try workspaceStore.prepare(workspaceID)
        let containerID = "familiar-" + workspaceID.rawID.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(40)
        let container = try LinuxContainer(
            String(containerID),
            rootfs: rootFileSystem,
            writableLayer: writableLayer,
            vmm: virtualMachineManager
        ) { config in
            config.process.arguments = ["/bin/sleep", "infinity"]
            config.process.workingDirectory = "/workspace/work"
            config.process.noNewPrivileges = true
            config.process.capabilities = LinuxCapabilities()
            config.cpus = FamiliarShellLimits.macOS.cpuCount ?? 2
            config.memoryInBytes = UInt64(FamiliarShellLimits.macOS.maximumMemoryBytes)
            config.interfaces = []
            config.dns = nil
            config.hosts = nil
            config.sockets = []
            config.mounts = LinuxContainer.defaultMounts() + [
                .share(source: paths.files.path, destination: "/workspace/files"),
                .share(source: paths.outputs.path, destination: "/workspace/outputs"),
                .share(source: paths.work.path, destination: "/workspace/work")
            ]
            config.useInit = true
        }
        return FamiliarContainerRuntimeSession(
            workspaceID: workspaceID,
            container: container
        )
    }
}

nonisolated final class FamiliarContainerShellExecutor: FamiliarShellExecutor, @unchecked Sendable {
    let runtimeKind = FamiliarShellRuntimeKind.containerization
    let limits = FamiliarShellLimits.macOS
    private let session: FamiliarContainerRuntimeSession

    init(session: FamiliarContainerRuntimeSession) {
        self.session = session
    }

    func prepare() async throws {
        try await session.start()
    }

    func execute(
        _ request: FamiliarShellRequest
    ) -> AsyncThrowingStream<FamiliarShellEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.started(taskID: request.taskID, runtime: .containerization, at: Date()))
                    let result = try await session.execute(request)
                    if !result.standardOutput.isEmpty { continuation.yield(.standardOutput(result.standardOutput)) }
                    if !result.standardError.isEmpty { continuation.yield(.standardError(result.standardError)) }
                    continuation.yield(.finished(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func cancel(taskID: UUID) async {
        await session.cancel(taskID: taskID)
    }
}

nonisolated enum FamiliarContainerRuntimeError: LocalizedError, Sendable {
    case networkInterfaceConfigured

    var errorDescription: String? {
        "Familiar Container 必须在无网络接口的配置下运行。"
    }
}

private final class FamiliarContainerBufferWriter: Writer, @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private(set) var wasTruncated = false

    init(limit: Int) {
        self.limit = limit
    }

    func write(_ incoming: Data) throws {
        lock.withLock {
            let remaining = max(0, limit - data.count)
            if incoming.count > remaining { wasTruncated = true }
            data.append(incoming.prefix(remaining))
        }
    }

    func close() throws {}

    var string: String {
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }
}
#endif
