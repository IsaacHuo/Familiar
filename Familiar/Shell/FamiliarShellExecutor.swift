import Foundation

nonisolated enum FamiliarShellRuntimeKind: String, Codable, Sendable {
    case ish
    case containerization
    case unavailable
}

nonisolated enum FamiliarShellTaskStatus: String, Codable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
    case timedOut
}

nonisolated struct FamiliarShellLimits: Equatable, Sendable {
    let defaultTimeout: TimeInterval
    let maximumTimeout: TimeInterval
    let maximumOutputBytes: Int
    let maximumFileBytes: Int64
    let maximumWorkspaceBytes: Int64
    let maximumProcessCount: Int
    let maximumMemoryBytes: Int64
    let cpuCount: Int?

    static let iOS = FamiliarShellLimits(
        defaultTimeout: 60,
        maximumTimeout: 180,
        maximumOutputBytes: 1_048_576,
        maximumFileBytes: 128 * 1_024 * 1_024,
        maximumWorkspaceBytes: FamiliarWorkspaceStore.iOSQuotaBytes,
        maximumProcessCount: 16,
        maximumMemoryBytes: 512 * 1_024 * 1_024,
        cpuCount: nil
    )

    static let macOS = FamiliarShellLimits(
        defaultTimeout: 300,
        maximumTimeout: 900,
        maximumOutputBytes: 1_048_576,
        maximumFileBytes: 128 * 1_024 * 1_024,
        maximumWorkspaceBytes: FamiliarWorkspaceStore.macOSQuotaBytes,
        maximumProcessCount: 64,
        maximumMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
        cpuCount: 2
    )
}

nonisolated struct FamiliarShellRequest: Sendable {
    let taskID: UUID
    let command: String
    let workspaceID: FamiliarWorkspaceID
    let timeout: TimeInterval
    let runID: String
    let toolCallID: String
}

nonisolated enum FamiliarShellEvent: Sendable {
    case started(taskID: UUID, runtime: FamiliarShellRuntimeKind, at: Date)
    case standardOutput(String)
    case standardError(String)
    case finished(FamiliarShellResult)
}

nonisolated struct FamiliarShellResult: Equatable, Sendable {
    let taskID: UUID
    let runtime: FamiliarShellRuntimeKind
    let status: FamiliarShellTaskStatus
    let exitCode: Int32?
    let standardOutput: String
    let standardError: String
    let outputWasTruncated: Bool
    let startedAt: Date
    let finishedAt: Date
    let workspaceDiff: FamiliarWorkspaceDiff?
}

nonisolated enum FamiliarShellExecutorError: LocalizedError, Sendable {
    case unavailable
    case alreadyRunning
    case invalidTimeout
    case outputLimitExceeded
    case resourceLimitExceeded(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Shell Runtime 尚未准备好。"
        case .alreadyRunning: "已有一个 Shell 任务正在运行。"
        case .invalidTimeout: "Shell 超时设置无效。"
        case .outputLimitExceeded: "Shell 输出超过允许的大小。"
        case .resourceLimitExceeded(let reason): "Shell 资源限制：\(reason)"
        }
    }
}

nonisolated protocol FamiliarShellExecutor: Sendable {
    var runtimeKind: FamiliarShellRuntimeKind { get }
    var limits: FamiliarShellLimits { get }

    func prepare() async throws

    func execute(
        _ request: FamiliarShellRequest
    ) -> AsyncThrowingStream<FamiliarShellEvent, Error>

    func cancel(taskID: UUID) async
}

nonisolated struct FamiliarUnavailableShellExecutor: FamiliarShellExecutor {
    let runtimeKind = FamiliarShellRuntimeKind.unavailable
    let limits: FamiliarShellLimits

    init(limits: FamiliarShellLimits = .iOS) {
        self.limits = limits
    }

    func prepare() async throws {
        throw FamiliarShellExecutorError.unavailable
    }

    func execute(
        _ request: FamiliarShellRequest
    ) -> AsyncThrowingStream<FamiliarShellEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: FamiliarShellExecutorError.unavailable)
        }
    }

    func cancel(taskID: UUID) async {}
}
