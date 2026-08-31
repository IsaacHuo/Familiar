import Foundation
import Observation

@MainActor
@Observable
final class FamiliarShellRuntimeStatus {
    enum Phase: Equatable {
        case unavailable
        case preparing
        case ready
        case failed(String)
    }

    private(set) var phase: Phase
    private(set) var resetScheduled = false
    private var retryHandler: (@MainActor @Sendable () -> Void)?

    init(phase: Phase) {
        self.phase = phase
    }

    var isReady: Bool { phase == .ready }

    func markReady() { phase = .ready }
    func markFailed(_ message: String) { phase = .failed(message) }
    func markPreparing() { phase = .preparing }
    func configureRetry(_ handler: @escaping @MainActor @Sendable () -> Void) {
        retryHandler = handler
    }
    func retry() {
        guard case .failed = phase else { return }
        markPreparing()
        retryHandler?()
    }
    func scheduleReset() {
        FamiliarShellRuntimeReset.schedule()
        resetScheduled = true
    }
}

nonisolated enum FamiliarShellRuntimeReset {
    private static let key = "familiar.shell.runtime.reset-on-next-launch.v1"

    static var isScheduled: Bool { UserDefaults.standard.bool(forKey: key) }
    static func schedule() { UserDefaults.standard.set(true, forKey: key) }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

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

nonisolated struct FamiliarShellNetworkPolicy: Codable, Equatable, Sendable {
    let enabled: Bool
    let maximumConcurrentConnections: Int
    let maximumTotalConnections: Int
    let maximumBytesReceived: Int64
    let maximumBytesSent: Int64
    let blocksPrivateNetworks: Bool
    let blocksListeningSockets: Bool

    static let disabled = FamiliarShellNetworkPolicy(
        enabled: false,
        maximumConcurrentConnections: 0,
        maximumTotalConnections: 0,
        maximumBytesReceived: 0,
        maximumBytesSent: 0,
        blocksPrivateNetworks: true,
        blocksListeningSockets: true
    )

    static let publicInternet = FamiliarShellNetworkPolicy(
        enabled: true,
        maximumConcurrentConnections: 8,
        maximumTotalConnections: 64,
        maximumBytesReceived: 256 * 1_024 * 1_024,
        maximumBytesSent: 25 * 1_024 * 1_024,
        blocksPrivateNetworks: true,
        blocksListeningSockets: true
    )
}

nonisolated struct FamiliarShellWorkspaceSettings: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var networkEnabled: Bool

    init(networkEnabled: Bool = false) {
        schemaVersion = Self.currentSchemaVersion
        self.networkEnabled = networkEnabled
    }

    var networkPolicy: FamiliarShellNetworkPolicy {
        networkEnabled ? .publicInternet : .disabled
    }
}

nonisolated struct FamiliarShellNetworkStatistics: Codable, Equatable, Sendable {
    let openedConnections: Int
    let peakConcurrentConnections: Int
    let bytesReceived: Int64
    let bytesSent: Int64

    static let zero = FamiliarShellNetworkStatistics(
        openedConnections: 0,
        peakConcurrentConnections: 0,
        bytesReceived: 0,
        bytesSent: 0
    )
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
    let maximumConcurrentNetworkConnections: Int
    let maximumTotalNetworkConnections: Int
    let maximumNetworkReceiveBytes: Int64
    let maximumNetworkSendBytes: Int64

    static let iOS = FamiliarShellLimits(
        defaultTimeout: 60,
        maximumTimeout: 180,
        maximumOutputBytes: 1_048_576,
        maximumFileBytes: 128 * 1_024 * 1_024,
        maximumWorkspaceBytes: FamiliarWorkspaceStore.iOSQuotaBytes,
        maximumProcessCount: 16,
        maximumMemoryBytes: 512 * 1_024 * 1_024,
        cpuCount: nil,
        maximumConcurrentNetworkConnections: 8,
        maximumTotalNetworkConnections: 64,
        maximumNetworkReceiveBytes: 256 * 1_024 * 1_024,
        maximumNetworkSendBytes: 25 * 1_024 * 1_024
    )

    static let macOS = FamiliarShellLimits(
        defaultTimeout: 300,
        maximumTimeout: 900,
        maximumOutputBytes: 1_048_576,
        maximumFileBytes: 128 * 1_024 * 1_024,
        maximumWorkspaceBytes: FamiliarWorkspaceStore.macOSQuotaBytes,
        maximumProcessCount: 64,
        maximumMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
        cpuCount: 2,
        maximumConcurrentNetworkConnections: 8,
        maximumTotalNetworkConnections: 64,
        maximumNetworkReceiveBytes: 256 * 1_024 * 1_024,
        maximumNetworkSendBytes: 25 * 1_024 * 1_024
    )
}

nonisolated struct FamiliarShellRequest: Sendable {
    let taskID: UUID
    let command: String
    let workspaceID: FamiliarWorkspaceID
    let workspaceView: FamiliarWorkspaceTaskView
    let timeout: TimeInterval
    let runID: String
    let toolCallID: String
    let networkPolicy: FamiliarShellNetworkPolicy
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
    let networkStatistics: FamiliarShellNetworkStatistics
}

extension FamiliarWorkspaceStore {
    nonisolated func shellSettings(in id: FamiliarWorkspaceID) throws -> FamiliarShellWorkspaceSettings {
        let url = try shellSettingsURL(in: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return FamiliarShellWorkspaceSettings()
        }
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(FamiliarShellWorkspaceSettings.self, from: data),
              settings.schemaVersion == FamiliarShellWorkspaceSettings.currentSchemaVersion
        else {
            return FamiliarShellWorkspaceSettings()
        }
        return settings
    }

    nonisolated func saveShellSettings(_ settings: FamiliarShellWorkspaceSettings, in id: FamiliarWorkspaceID) throws {
        let url = try shellSettingsURL(in: id)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: url, options: [.atomic])
#if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
#endif
    }

    nonisolated func setShellNetworkEnabled(_ enabled: Bool, in id: FamiliarWorkspaceID) throws {
        try saveShellSettings(.init(networkEnabled: enabled), in: id)
    }
}

nonisolated enum FamiliarShellExecutorError: LocalizedError, Sendable {
    case unavailable
    case alreadyRunning
    case invalidTimeout
    case outputLimitExceeded
    case resourceLimitExceeded(String)
    case networkConfigurationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "Shell Runtime 尚未准备好。"
        case .alreadyRunning: "已有一个 Shell 任务正在运行。"
        case .invalidTimeout: "Shell 超时设置无效。"
        case .outputLimitExceeded: "Shell 输出超过允许的大小。"
        case .resourceLimitExceeded(let reason): "Shell 资源限制：\(reason)"
        case .networkConfigurationFailed: "Linux Environment 无法读取当前网络的 DNS 配置。"
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
