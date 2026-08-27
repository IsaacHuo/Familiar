#if os(iOS)
import Foundation

nonisolated struct FamiliarISHRuntimeConfiguration: Equatable, Sendable {
    let distribution = "Alpine"
    let architecture = "x86"
    let networkEnabled = false
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
                    let mounts = [
                        FamiliarISHMount(
                            hostURL: paths.files,
                            guestPath: "/workspace/files",
                            writable: true
                        ),
                        FamiliarISHMount(
                            hostURL: paths.outputs,
                            guestPath: "/workspace/outputs",
                            writable: true
                        ),
                        FamiliarISHMount(
                            hostURL: paths.work,
                            guestPath: "/workspace/work",
                            writable: true
                        )
                    ]
                    continuation.yield(.started(
                        taskID: request.taskID,
                        runtime: .ish,
                        at: startedAt
                    ))
                    var stdout = FamiliarISHOutputBuffer(limit: limits.maximumOutputBytes)
                    var stderr = FamiliarISHOutputBuffer(limit: limits.maximumOutputBytes)
                    var status = FamiliarShellTaskStatus.failed
                    var exitCode: Int32?
                    let processEvents = bridge.execute(
                        taskID: request.taskID,
                        command: request.command,
                        workingDirectory: "/workspace/work",
                        mounts: mounts,
                        timeout: request.timeout
                    )
                    for try await event in processEvents {
                        try Task.checkCancellation()
                        switch event {
                        case .standardOutput(let data):
                            let chunk = stdout.append(data)
                            if !chunk.isEmpty { continuation.yield(.standardOutput(chunk)) }
                        case .standardError(let data):
                            let chunk = stderr.append(data)
                            if !chunk.isEmpty { continuation.yield(.standardError(chunk)) }
                        case .exited(let code):
                            exitCode = code
                            status = code == 0 ? .succeeded : .failed
                        case .timedOut:
                            status = .timedOut
                        case .cancelled:
                            status = .cancelled
                        case .resourceLimitExceeded(let reason):
                            status = .failed
                            _ = stderr.append(Data(reason.utf8))
                        }
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
                        workspaceDiff: nil
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
        timeout _: TimeInterval
    ) -> AsyncThrowingStream<FamiliarISHProcessEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: FamiliarShellExecutorError.unavailable)
        }
    }

    func cancel(taskID _: UUID) async {}
}

private nonisolated struct FamiliarISHOutputBuffer {
    private let limit: Int
    private var data = Data()
    private(set) var wasTruncated = false

    init(limit: Int) {
        self.limit = limit
    }

    mutating func append(_ incoming: Data) -> String {
        let remaining = max(0, limit - data.count)
        if incoming.count > remaining { wasTruncated = true }
        let accepted = incoming.prefix(remaining)
        data.append(accepted)
        return String(decoding: accepted, as: UTF8.self)
    }

    var string: String { String(decoding: data, as: UTF8.self) }
}
#endif
