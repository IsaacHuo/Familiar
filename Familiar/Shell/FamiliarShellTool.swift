import Foundation

nonisolated struct FamiliarPythonPackageSource: Identifiable, Equatable, Sendable {
    static let officialID = "pypi"
    static let tunaID = "tuna"
    static let defaultID = officialID

    static let all: [Self] = [
        .init(
            id: officialID,
            displayName: "PyPI",
            indexURL: URL(string: "https://pypi.org/simple")!,
            websiteURL: URL(string: "https://pypi.org/")!
        ),
        .init(
            id: tunaID,
            displayName: "清华大学 TUNA",
            indexURL: URL(string: "https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple")!,
            websiteURL: URL(string: "https://mirrors.tuna.tsinghua.edu.cn/help/pypi/")!
        )
    ]

    let id: String
    let displayName: String
    let indexURL: URL
    let websiteURL: URL

    static func resolved(_ id: String?) -> Self {
        all.first { $0.id == id } ?? all[0]
    }
}

nonisolated final class FamiliarPythonPackageSourceSettingsStore: @unchecked Sendable {
    static let sourceDefaultsKey = "familiar.python-package-source.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedSource: FamiliarPythonPackageSource {
        FamiliarPythonPackageSource.resolved(defaults.string(forKey: Self.sourceDefaultsKey))
    }

    func save(selectedSourceID: String) {
        defaults.set(
            FamiliarPythonPackageSource.resolved(selectedSourceID).id,
            forKey: Self.sourceDefaultsKey
        )
    }
}

nonisolated enum FamiliarRuntimeEnvironmentState: String, Codable, Equatable, Sendable {
    case notPrepared
    case preparing
    case ready
    case failed
}

nonisolated struct FamiliarEnvironmentPlan: Codable, Equatable, Sendable {
    let projectID: UUID
    let packages: [String]
    let packageIndex: String
    let maximumBytes: Int64
}

nonisolated struct FamiliarEnvironmentLock: Codable, Equatable, Sendable {
    let pythonVersion: String
    let resolvedPackages: [String]
    let contentHash: String
}

nonisolated struct FamiliarEnvironmentReceipt: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let projectID: UUID
    let revision: UUID
    let state: FamiliarRuntimeEnvironmentState
    let requestedPackages: [String]
    let packageIndex: String
    let lock: FamiliarEnvironmentLock
    let byteSize: Int64
    let preparedAt: Date
}

nonisolated enum FamiliarEnvironmentError: LocalizedError, FamiliarStructuredToolError, Sendable {
    case projectRequired
    case invalidPackages
    case installationFailed(String)
    case invalidReceipt
    case dnsFailed

    var errorDescription: String? {
        switch self {
        case .projectRequired: "Environment 只能由 Project 长期维护。"
        case .invalidPackages: "Environment 依赖声明无效。"
        case .installationFailed(let detail): "Environment 准备失败：\(detail)"
        case .invalidReceipt: "Environment 安装结果无法验证。"
        case .dnsFailed: "Environment 无法解析 PyPI 域名，请检查当前网络后重试。"
        }
    }

    var code: String {
        switch self {
        case .dnsFailed: "environment_dns_failed"
        case .projectRequired: "environment_project_required"
        case .invalidPackages: "environment_invalid_packages"
        case .installationFailed: "environment_installation_failed"
        case .invalidReceipt: "environment_invalid_receipt"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .dnsFailed, .installationFailed: true
        case .projectRequired, .invalidPackages, .invalidReceipt: false
        }
    }
}

nonisolated struct FamiliarEnvironmentStore: Sendable {
    static let receiptFilename = "familiar-environment.json"

    let workspaceStore: FamiliarWorkspaceStore

    func receipt(projectID: UUID) throws -> FamiliarEnvironmentReceipt? {
        let environment = try workspaceStore.projectEnvironmentURL(projectID)
        let url = environment.appendingPathComponent(Self.receiptFilename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw FamiliarEnvironmentError.invalidReceipt
        }
        return try JSONDecoder().decode(FamiliarEnvironmentReceipt.self, from: Data(contentsOf: url))
    }
}

nonisolated struct FamiliarShellTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let command: String
        let timeoutSeconds: Double?
    }

    private struct Output: Encodable {
        let taskID: UUID
        let runtime: String
        let status: String
        let exitCode: Int32?
        let standardOutput: String
        let standardError: String
        let outputWasTruncated: Bool
        let networkEnabled: Bool
        let networkStatistics: FamiliarShellNetworkStatistics
        let addedFiles: [String]
        let modifiedFiles: [String]
        let removedFiles: [String]
        let checkpointID: UUID?
    }

    private struct UndoOutput: Encodable {
        let restored: Bool
        let checkpointID: UUID
    }

    let executor: any FamiliarShellExecutor
    let workspaceStore: FamiliarWorkspaceStore
    let shellPolicy: FamiliarShellPolicy

    /// High risk is intentional: AgentLoop never applies session/always grants
    /// to high-risk tools, so every shell invocation is approved exactly once.
    let manifest = FamiliarToolManifest(
        name: "shell_execute",
        title: String(localized: "tool.shell_execute"),
        description: "仅当 Native Tool 或专用本地 Tool 无法方便完成任务时，在当前 Familiar Workspace 的受控 Linux 环境中运行命令。每次执行都需要确认。",
        parameters: FamiliarJSONSchema(
            type: .object,
            properties: [
                "command": .init(type: .string, description: "要在当前 Workspace 中执行的 Shell 命令"),
                "timeoutSeconds": .init(type: .number, description: "可选超时秒数，最终由 Familiar 限制")
            ],
            required: ["command"]
        ),
        effect: .reversibleWrite,
        risk: .high,
        requirements: [],
        dataDomains: ["workspace.inputs", "workspace.outputs", "workspace.runtime"],
        networkDomains: ["public-internet"],
        privacyLabels: ["workspace-only", "network-default-off", "one-shot-approval"],
        supportsIdempotency: false,
        supportsCancellation: true,
        supportsRecovery: true,
        supportsParallelism: false,
        requiredScopes: ["workspace"],
        executionClass: .shell,
        maximumExecutionDuration: FamiliarShellLimits.iOS.maximumTimeout
    )

    init(
        executor: any FamiliarShellExecutor,
        workspaceStore: FamiliarWorkspaceStore = FamiliarWorkspaceStore(),
        shellPolicy: FamiliarShellPolicy = FamiliarShellPolicy()
    ) {
        self.executor = executor
        self.workspaceStore = workspaceStore
        self.shellPolicy = shellPolicy
    }

    func preflight(
        _ input: Input,
        context: FamiliarToolContext
    ) async throws -> FamiliarToolAuthorizationAssessment {
        guard let workspaceID = context.workspaceID else { throw FamiliarWorkspaceError.invalidPath }
        let command = input.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let networkPolicy = try workspaceStore.shellSettings(in: workspaceID).networkPolicy
        return switch shellPolicy.evaluate(command: command, networkPolicy: networkPolicy) {
        case .deny(let reason): .init(disposition: .denied(reason), effect: manifest.effect, risk: .high, reason: reason)
        case .requiresConfirmation(let reason): .init(disposition: .requiresApproval, effect: manifest.effect, risk: .high, reason: reason)
        case .allow where networkPolicy.enabled:
            .init(disposition: .requiresApproval, effect: manifest.effect, risk: .sensitive, reason: "当前 Workspace 已开放网络，命令需要确认。")
        case .allow:
            .init(disposition: .automatic, effect: manifest.effect, risk: .low, reason: "离线命令仅访问当前 Workspace，并受 checkpoint 保护。")
        }
    }

    func execute(
        _ input: Input,
        context: FamiliarToolContext
    ) async throws -> FamiliarToolOutcome {
        guard let workspaceID = context.workspaceID else {
            throw FamiliarWorkspaceError.invalidPath
        }
        let command = input.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = try workspaceStore.shellSettings(in: workspaceID)
        let networkPolicy = settings.networkPolicy
        let assessment = try await preflight(input, context: context)
        if case .denied(let reason) = assessment.disposition {
            throw FamiliarShellPolicyError.denied(reason)
        }
        let policyDetail = assessment.reason
        let timeout = boundedTimeout(input.timeoutSeconds)
        return .action(FamiliarActionProposal(
            title: "确认运行 Shell 命令",
            fields: [
                .init(id: "command", label: "Command", type: .text, value: command),
                .init(id: "working_directory", label: "Working Directory", type: .text, value: "/workspace/work"),
                .init(id: "runtime", label: "Runtime", type: .text, value: executor.runtimeKind.rawValue),
                .init(id: "timeout", label: "Timeout", type: .number, value: String(Int(timeout.rounded(.up)))),
                .init(id: "inputs", label: "Read-only Inputs", type: .number, value: String(context.resources.count + context.attachments.count)),
                .init(id: "network", label: "Network", type: .boolean, value: String(networkPolicy.enabled)),
                .init(id: "policy", label: "Policy", type: .text, value: policyDetail)
            ],
            target: workspaceID.directoryName,
            targetKey: "shell-once:\(context.idempotencyKey)",
            effect: manifest.effect,
            risk: assessment.risk,
            consequence: "命令只能读取本次 Context 输入，并可修改当前 Workspace Outputs 与本次临时 Work。",
            undoPolicy: .currentSession,
            idempotencyKey: context.idempotencyKey,
            allowedAuthorizationDurations: [.once],
            commit: {
                try await commit(
                    command: command,
                    timeout: timeout,
                    networkPolicy: networkPolicy,
                    context: context,
                    workspaceID: workspaceID
                )
            }
        ))
    }

    private func commit(
        command: String,
        timeout: TimeInterval,
        networkPolicy: FamiliarShellNetworkPolicy,
        context: FamiliarToolContext,
        workspaceID: FamiliarWorkspaceID
    ) async throws -> FamiliarCommittedAction {
        let taskID = UUID()
        let checkpoint = try workspaceStore.createShellCheckpoint(for: workspaceID)
        let taskView: FamiliarWorkspaceTaskView
        do {
            taskView = try workspaceStore.prepareShellTaskView(
                taskID: taskID,
                workspaceID: workspaceID,
                resources: context.resources,
                attachments: context.attachments
            )
        } catch {
            try? workspaceStore.removeCheckpoint(checkpoint)
            throw error
        }
        defer { try? workspaceStore.removeShellTaskView(taskView) }

        do {
            let shellResult = try await run(
                command: command,
                timeout: timeout,
                networkPolicy: networkPolicy,
                taskView: taskView,
                context: context
            )
            guard shellResult.status == .succeeded else {
                try workspaceStore.restore(checkpoint)
                try? workspaceStore.removeCheckpoint(checkpoint)
                return FamiliarCommittedAction(
                    result: try executionResult(
                        shellResult,
                        command: command,
                        networkEnabled: networkPolicy.enabled,
                        diff: .init(added: [], modified: [], removed: []),
                        checkpointID: nil
                    )
                )
            }

            let entries = try workspaceStore.entries(in: workspaceID)
            let workspaceBytes = entries.reduce(Int64(0)) { $0 + $1.byteSize }
            guard workspaceBytes <= executor.limits.maximumWorkspaceBytes else {
                throw FamiliarShellExecutorError.resourceLimitExceeded("Workspace 超过允许大小。")
            }
            guard !entries.contains(where: { $0.byteSize > executor.limits.maximumFileBytes }) else {
                throw FamiliarShellExecutorError.resourceLimitExceeded("生成了超出单文件限制的文件。")
            }
            let diff = try shellResult.workspaceDiff ?? workspaceStore.diff(from: checkpoint)
            let result = try executionResult(
                shellResult,
                command: command,
                networkEnabled: networkPolicy.enabled,
                diff: diff,
                checkpointID: checkpoint.id
            )
            return FamiliarCommittedAction(result: result) {
                try workspaceStore.restore(checkpoint)
                try? workspaceStore.removeCheckpoint(checkpoint)
                return FamiliarToolExecutionResult(
                    envelope: try FamiliarToolResultEnvelope(
                        model: UndoOutput(restored: true, checkpointID: checkpoint.id),
                        presentation: .mutationReceipt(.init(
                            summary: "已恢复 Shell 执行前的 Workspace Outputs checkpoint。",
                            operation: "restoreShellOutputsCheckpoint",
                            targetIdentifier: checkpoint.id.uuidString,
                            succeeded: true,
                            undoAvailable: false
                        ))
                    )
                )
            }
        } catch {
            try? workspaceStore.restore(checkpoint)
            try? workspaceStore.removeCheckpoint(checkpoint)
            throw error
        }
    }

    private func run(
        command: String,
        timeout: TimeInterval,
        networkPolicy: FamiliarShellNetworkPolicy,
        taskView: FamiliarWorkspaceTaskView,
        context: FamiliarToolContext
    ) async throws -> FamiliarShellResult {
        let request = FamiliarShellRequest(
            taskID: taskView.taskID,
            command: command,
            workspaceID: taskView.workspaceID,
            workspaceView: taskView,
            timeout: timeout,
            runID: context.runID,
            toolCallID: context.toolCallID,
            networkPolicy: networkPolicy
        )
        var finalResult: FamiliarShellResult?
        var remainingOutputProgressBytes = 64 * 1_024
        var remainingErrorProgressBytes = 64 * 1_024
        for try await event in executor.execute(request) {
            try Task.checkCancellation()
            switch event {
            case .started(_, let runtime, _):
                await context.reportProgress(.status("Shell \(runtime.rawValue) 正在运行"))
            case .standardOutput(let chunk):
                let bounded = boundedProgressChunk(chunk, remainingBytes: &remainingOutputProgressBytes)
                if !bounded.isEmpty { await context.reportProgress(.standardOutput(bounded)) }
            case .standardError(let chunk):
                let bounded = boundedProgressChunk(chunk, remainingBytes: &remainingErrorProgressBytes)
                if !bounded.isEmpty { await context.reportProgress(.standardError(bounded)) }
            case .finished(let result):
                finalResult = result
                await context.reportProgress(.status("Shell \(result.status.rawValue)"))
            }
        }
        guard let finalResult else { throw FamiliarShellExecutorError.unavailable }
        return finalResult
    }

    private func executionResult(
        _ result: FamiliarShellResult,
        command: String,
        networkEnabled: Bool,
        diff: FamiliarWorkspaceDiff,
        checkpointID: UUID?
    ) throws -> FamiliarToolExecutionResult {
        let summary = switch result.status {
        case .succeeded: "Shell 命令执行完成。"
        case .cancelled: "Shell 命令已取消，Workspace Outputs 已恢复。"
        case .timedOut: "Shell 命令超时，Workspace Outputs 已恢复。"
        case .queued, .running, .failed: "Shell 命令未成功完成，Workspace Outputs 已恢复。"
        }
        let persistedOutput = boundedTail(result.standardOutput, maximumBytes: 64 * 1_024)
        let persistedError = boundedTail(result.standardError, maximumBytes: 64 * 1_024)
        let terminalOutputWasTruncated = result.outputWasTruncated
            || persistedOutput.utf8.count < result.standardOutput.utf8.count
            || persistedError.utf8.count < result.standardError.utf8.count
        let output = Output(
            taskID: result.taskID,
            runtime: result.runtime.rawValue,
            status: result.status.rawValue,
            exitCode: result.exitCode,
            standardOutput: persistedOutput,
            standardError: persistedError,
            outputWasTruncated: terminalOutputWasTruncated,
            networkEnabled: networkEnabled,
            networkStatistics: result.networkStatistics,
            addedFiles: diff.added,
            modifiedFiles: diff.modified,
            removedFiles: diff.removed,
            checkpointID: checkpointID
        )
        return FamiliarToolExecutionResult(
            envelope: try FamiliarToolResultEnvelope(
                model: output,
                presentation: .shellExecution(.init(
                    summary: summary,
                    taskID: result.taskID,
                    command: command,
                    workingDirectory: "/workspace/work",
                    runtime: result.runtime.rawValue,
                    status: result.status.rawValue,
                    exitCode: result.exitCode,
                    standardOutput: persistedOutput,
                    standardError: persistedError,
                    outputWasTruncated: terminalOutputWasTruncated,
                    networkEnabled: networkEnabled,
                    networkStatistics: .init(
                        openedConnections: result.networkStatistics.openedConnections,
                        peakConcurrentConnections: result.networkStatistics.peakConcurrentConnections,
                        bytesReceived: result.networkStatistics.bytesReceived,
                        bytesSent: result.networkStatistics.bytesSent
                    ),
                    addedFiles: diff.added,
                    modifiedFiles: diff.modified,
                    removedFiles: diff.removed
                ))
            )
        )
    }

    private func boundedTimeout(_ proposed: Double?) -> TimeInterval {
        min(max(proposed ?? executor.limits.defaultTimeout, 1), executor.limits.maximumTimeout)
    }

    private func boundedProgressChunk(_ chunk: String, remainingBytes: inout Int) -> String {
        guard remainingBytes > 0 else { return "" }
        let accepted = Data(chunk.utf8).prefix(remainingBytes)
        remainingBytes -= accepted.count
        return String(decoding: accepted, as: UTF8.self)
    }

    private func boundedTail(_ value: String, maximumBytes: Int) -> String {
        let data = Data(value.utf8)
        guard data.count > maximumBytes else { return value }
        return String(decoding: data.suffix(maximumBytes), as: UTF8.self)
    }
}

nonisolated enum FamiliarShellPolicyError: LocalizedError, Sendable {
    case denied(String)

    var errorDescription: String? {
        switch self {
        case .denied(let reason): reason
        }
    }
}

nonisolated struct FamiliarEnvironmentStatusTool: FamiliarTool {
    struct Input: Decodable, Sendable {}

    private struct Output: Encodable {
        let state: FamiliarRuntimeEnvironmentState
        let revision: UUID?
        let pythonVersion: String?
        let packages: [String]
        let packageIndex: String
        let byteSize: Int64?
        let preparedAt: Date?
    }

    let store: FamiliarEnvironmentStore
    let manifest = FamiliarToolManifest(
        name: "environment_status",
        title: "Inspect Project Environment",
        description: "Inspect the current Project's isolated Linux dependency environment before preparing or using packages.",
        parameters: .init(type: .object, properties: [:], required: []),
        effect: .read,
        risk: .low,
        dataDomains: ["project.environment"],
        privacyLabels: ["project-only", "read-only"],
        supportsParallelism: false,
        requiredScopes: ["project"],
        executionClass: .specializedLocal
    )

    init(workspaceStore: FamiliarWorkspaceStore) {
        store = FamiliarEnvironmentStore(workspaceStore: workspaceStore)
    }

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID else { throw FamiliarEnvironmentError.projectRequired }
        let receipt = try store.receipt(projectID: projectID)
        let output = Output(
            state: receipt?.state ?? .notPrepared,
            revision: receipt?.revision,
            pythonVersion: receipt?.lock.pythonVersion,
            packages: receipt?.lock.resolvedPackages ?? [],
            packageIndex: receipt?.packageIndex
                ?? FamiliarPythonPackageSourceSettingsStore().selectedSource.indexURL.absoluteString,
            byteSize: receipt?.byteSize,
            preparedAt: receipt?.preparedAt
        )
        let records = (receipt?.lock.resolvedPackages ?? []).enumerated().map { index, package in
            FamiliarToolPresentationPayload.Record(
                id: "package-\(index)",
                fields: [.init(name: "package", value: package)]
            )
        }
        return .result(.init(envelope: try .init(
            model: output,
            presentation: .recordCollection(.init(
                summary: receipt == nil ? "Project Environment 尚未准备。" : "Project Environment 已验证。",
                recordType: "environmentPackage",
                records: records
            ))
        )))
    }
}

nonisolated struct FamiliarEnvironmentPrepareTool: FamiliarTool {
    struct Input: Decodable, Sendable {
        let packages: [String]
    }

    private struct Output: Encodable {
        let state: FamiliarRuntimeEnvironmentState
        let revision: UUID
        let pythonVersion: String
        let packages: [String]
        let packageIndex: String
        let lockHash: String
        let byteSize: Int64
    }

    private static let maximumPackageCount = 16
    private static let maximumEnvironmentBytes: Int64 = 300 * 1_024 * 1_024

    let executor: any FamiliarShellExecutor
    let workspaceStore: FamiliarWorkspaceStore
    let environmentStore: FamiliarEnvironmentStore
    let packageSourceSettings: FamiliarPythonPackageSourceSettingsStore
    let manifest = FamiliarToolManifest(
        name: "environment_prepare",
        title: "Prepare Project Environment",
        description: "Install a declarative list of Python packages into the current Project's isolated environment. Do not pass shell commands. Familiar constructs and audits the installation command.",
        parameters: .init(
            type: .object,
            properties: [
                "packages": .stringArray(
                    "PyPI packages to install into the Project Environment.",
                    itemDescription: "PyPI package name, optionally pinned with ==version. Use python-docx for Word document generation.",
                    minItems: 1
                )
            ],
            required: ["packages"]
        ),
        effect: .destructiveWrite,
        risk: .high,
        dataDomains: ["project.environment"],
        networkDomains: ["pypi.org", "files.pythonhosted.org", "mirrors.tuna.tsinghua.edu.cn"],
        privacyLabels: ["project-only", "explicit-package-plan", "one-shot-approval"],
        supportsIdempotency: true,
        supportsCancellation: true,
        supportsRecovery: true,
        supportsParallelism: false,
        requiredScopes: ["project"],
        executionClass: .specializedLocal,
        maximumExecutionDuration: FamiliarShellLimits.iOS.maximumTimeout
    )

    init(
        executor: any FamiliarShellExecutor,
        workspaceStore: FamiliarWorkspaceStore,
        packageSourceSettings: FamiliarPythonPackageSourceSettingsStore = FamiliarPythonPackageSourceSettingsStore()
    ) {
        self.executor = executor
        self.workspaceStore = workspaceStore
        self.packageSourceSettings = packageSourceSettings
        environmentStore = FamiliarEnvironmentStore(workspaceStore: workspaceStore)
    }

    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        guard let projectID = context.projectID,
              context.workspaceID == .project(projectID)
        else { throw FamiliarEnvironmentError.projectRequired }
        let packages = try normalizedPackages(input.packages)
        let packageSource = packageSourceSettings.selectedSource
        if let existing = try environmentStore.receipt(projectID: projectID),
           existing.state == .ready,
           Set(existing.requestedPackages) == Set(packages) {
            return .result(try result(existing))
        }
        let plan = FamiliarEnvironmentPlan(
            projectID: projectID,
            packages: packages,
            packageIndex: packageSource.indexURL.absoluteString,
            maximumBytes: Self.maximumEnvironmentBytes
        )
        return .action(.init(
            title: "准备 Project Environment",
            fields: [
                .init(id: "packages", label: "Packages", type: .text, value: packages.joined(separator: ", ")),
                .init(id: "index", label: "Package Index", type: .url, value: plan.packageIndex),
                .init(id: "network", label: "Public Network", type: .boolean, value: "true"),
                .init(id: "maximum_size", label: "Maximum Size", type: .number, value: String(Self.maximumEnvironmentBytes))
            ],
            target: projectID.uuidString,
            targetKey: "environment:\(projectID.uuidString):\(FamiliarHash.sha256(packages.joined(separator: "\n")))",
            effect: manifest.effect,
            risk: manifest.risk,
            consequence: "将从设置中选择的软件源下载，并在当前 Project 的隔离 Environment 中安装这些依赖；旧 Environment 仅在新环境验证成功后替换。",
            undoPolicy: .unavailable,
            idempotencyKey: context.idempotencyKey,
            allowedAuthorizationDurations: [.once],
            commit: {
                try await prepare(plan: plan, context: context)
            }
        ))
    }

    private func prepare(
        plan: FamiliarEnvironmentPlan,
        context: FamiliarToolContext
    ) async throws -> FamiliarCommittedAction {
        let taskID = UUID()
        let view = try workspaceStore.prepareShellTaskView(
            taskID: taskID,
            workspaceID: .project(plan.projectID),
            resources: [],
            attachments: [],
            useStagingEnvironment: true
        )
        defer { try? workspaceStore.removeShellTaskView(view) }
        let packageArguments = plan.packages.joined(separator: " ")
        let command = "mkdir -p /workspace/env/site-packages && "
            + "python3 -m pip install --isolated --disable-pip-version-check --no-input "
            + "--index-url \(plan.packageIndex) --target /workspace/env/site-packages \(packageArguments) && "
            + "python3 -m pip freeze --path /workspace/env/site-packages > /workspace/env/requirements.lock && "
            + "python3 --version > /workspace/env/python-version.txt"
        let request = FamiliarShellRequest(
            taskID: taskID,
            command: command,
            workspaceID: .project(plan.projectID),
            workspaceView: view,
            timeout: executor.limits.maximumTimeout,
            runID: context.runID,
            toolCallID: context.toolCallID,
            networkPolicy: .publicInternet
        )
        var finalResult: FamiliarShellResult?
        for try await event in executor.execute(request) {
            try Task.checkCancellation()
            switch event {
            case .started:
                await context.reportProgress(.status("正在准备 Project Environment"))
            case .standardOutput(let value):
                await context.reportProgress(.standardOutput(value))
            case .standardError(let value):
                await context.reportProgress(.standardError(value))
            case .finished(let result):
                finalResult = result
            }
        }
        guard let finalResult, finalResult.status == .succeeded else {
            let detail = finalResult?.standardError ?? "iSH 未返回成功终态。"
            if detail.contains("NameResolutionError") || detail.contains("Failed to resolve") {
                throw FamiliarEnvironmentError.dnsFailed
            }
            throw FamiliarEnvironmentError.installationFailed(detail)
        }
        let lockURL = view.environment.appendingPathComponent("requirements.lock", isDirectory: false)
        let versionURL = view.environment.appendingPathComponent("python-version.txt", isDirectory: false)
        guard let lockText = try? String(contentsOf: lockURL, encoding: .utf8),
              let pythonVersion = try? String(contentsOf: versionURL, encoding: .utf8),
              !pythonVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw FamiliarEnvironmentError.invalidReceipt }
        let resolvedPackages = lockText.split(whereSeparator: \.isNewline).map(String.init).sorted()
        let lock = FamiliarEnvironmentLock(
            pythonVersion: pythonVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            resolvedPackages: resolvedPackages,
            contentHash: FamiliarHash.sha256(lockText)
        )
        let byteSize = try directorySize(view.environment)
        guard byteSize > 0, byteSize <= plan.maximumBytes else {
            throw FamiliarShellExecutorError.resourceLimitExceeded("Project Environment 超过允许大小。")
        }
        let receipt = FamiliarEnvironmentReceipt(
            schemaVersion: FamiliarEnvironmentReceipt.currentSchemaVersion,
            projectID: plan.projectID,
            revision: UUID(),
            state: .ready,
            requestedPackages: plan.packages,
            packageIndex: plan.packageIndex,
            lock: lock,
            byteSize: byteSize,
            preparedAt: Date()
        )
        let receiptURL = view.environment.appendingPathComponent(FamiliarEnvironmentStore.receiptFilename, isDirectory: false)
        try JSONEncoder().encode(receipt).write(to: receiptURL, options: [.atomic])
        try workspaceStore.commitProjectEnvironment(from: view, projectID: plan.projectID)
        return .init(result: try result(receipt))
    }

    private func result(_ receipt: FamiliarEnvironmentReceipt) throws -> FamiliarToolExecutionResult {
        let output = Output(
            state: receipt.state,
            revision: receipt.revision,
            pythonVersion: receipt.lock.pythonVersion,
            packages: receipt.lock.resolvedPackages,
            packageIndex: receipt.packageIndex,
            lockHash: receipt.lock.contentHash,
            byteSize: receipt.byteSize
        )
        let records = receipt.lock.resolvedPackages.enumerated().map { index, package in
            FamiliarToolPresentationPayload.Record(id: "package-\(index)", fields: [
                .init(name: "package", value: package)
            ])
        }
        return .init(
            envelope: try .init(
                model: output,
                presentation: .recordCollection(.init(
                    summary: "Project Environment 已准备并验证。",
                    recordType: "environmentPackage",
                    records: records
                ))
            ),
            environmentReceipt: receipt
        )
    }

    private func normalizedPackages(_ values: [String]) throws -> [String] {
        guard !values.isEmpty, values.count <= Self.maximumPackageCount else {
            throw FamiliarEnvironmentError.invalidPackages
        }
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}(==[A-Za-z0-9][A-Za-z0-9._+!-]{0,63})?$"#
        let packages = Array(Set(values.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })).sorted()
        guard packages.count == values.count,
              packages.allSatisfy({ $0.range(of: pattern, options: .regularExpression) != nil })
        else { throw FamiliarEnvironmentError.invalidPackages }
        return packages
    }

    private func directorySize(_ root: URL) throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw FamiliarWorkspaceError.symbolicLinkNotAllowed }
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }

}
