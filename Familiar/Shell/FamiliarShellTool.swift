import Foundation

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
        executionClass: .shell
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
        let policyDetail: String
        switch shellPolicy.evaluate(command: command, networkPolicy: networkPolicy) {
        case .deny(let reason):
            throw FamiliarShellPolicyError.denied(reason)
        case .allow:
            policyDetail = "命令通过 ShellPolicy 检查，但仍需要本次单独确认。"
        case .requiresConfirmation(let reason):
            policyDetail = reason
        }
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
            risk: manifest.risk,
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
