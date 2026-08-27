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
        let addedFiles: [String]
        let modifiedFiles: [String]
        let removedFiles: [String]
        let checkpointID: UUID
    }

    private struct UndoOutput: Encodable {
        let restored: Bool
        let checkpointID: UUID
    }

    let executor: any FamiliarShellExecutor
    let workspaceStore: FamiliarWorkspaceStore
    let shellPolicy: FamiliarShellPolicy

    let manifest = FamiliarToolManifest(
        name: "shell_execute",
        title: "运行 Workspace Shell",
        description: "仅当 Native Tool 或专用本地 Tool 无法方便完成任务时，在当前 Familiar Workspace 的受控 Linux 环境中运行命令。Shell 默认禁网，不能访问其他 Workspace 或系统敏感数据。",
        parameters: FamiliarJSONSchema(
            type: .object,
            properties: [
                "command": .init(type: .string, description: "要在当前 Workspace 中执行的 Shell 命令"),
                "timeoutSeconds": .init(type: .number, description: "可选超时秒数，最终由 Familiar 限制")
            ],
            required: ["command"]
        ),
        effect: .reversibleWrite,
        risk: .sensitive,
        requirements: [],
        dataDomains: ["workspace.files", "workspace.outputs", "workspace.runtime"],
        networkDomains: [],
        privacyLabels: ["workspace-only", "network-disabled"],
        supportsIdempotency: false,
        supportsCancellation: true,
        supportsRecovery: false,
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
        switch shellPolicy.evaluate(command: command) {
        case .deny(let reason):
            throw FamiliarShellPolicyError.denied(reason)
        case .allow:
            return .result(try await run(command: command, timeoutSeconds: input.timeoutSeconds, context: context, workspaceID: workspaceID).result)
        case .requiresConfirmation(let reason):
            return .action(FamiliarActionProposal(
                title: "确认运行 Shell 命令",
                fields: [
                    .init(id: "command", label: "Command", type: .text, value: command),
                    .init(id: "runtime", label: "Runtime", type: .text, value: executor.runtimeKind.rawValue),
                    .init(id: "reason", label: "Risk", type: .text, value: reason)
                ],
                target: workspaceID.directoryName,
                targetKey: "shell:\(workspaceID.directoryName)",
                effect: manifest.effect,
                risk: manifest.risk,
                consequence: reason,
                undoPolicy: .currentSession,
                idempotencyKey: context.idempotencyKey,
                commit: {
                    let checkpoint = try workspaceStore.createCheckpoint(for: workspaceID)
                    let result = try await run(
                        command: command,
                        timeoutSeconds: input.timeoutSeconds,
                        context: context,
                        workspaceID: workspaceID,
                        checkpoint: checkpoint
                    ).result
                    return FamiliarCommittedAction(result: result) {
                        try workspaceStore.restore(checkpoint)
                        return FamiliarToolExecutionResult(
                            envelope: try FamiliarToolResultEnvelope(
                                model: UndoOutput(restored: true, checkpointID: checkpoint.id),
                                presentation: .mutationReceipt(.init(
                                    summary: "已恢复 Shell 执行前的 Workspace checkpoint。",
                                    operation: "restoreWorkspaceCheckpoint",
                                    targetIdentifier: checkpoint.id.uuidString,
                                    succeeded: true,
                                    undoAvailable: false
                                ))
                            )
                        )
                    }
                }
            ))
        }
    }

    private func run(
        command: String,
        timeoutSeconds: Double?,
        context: FamiliarToolContext,
        workspaceID: FamiliarWorkspaceID,
        checkpoint suppliedCheckpoint: FamiliarWorkspaceCheckpoint? = nil
    ) async throws -> (result: FamiliarToolExecutionResult, shellResult: FamiliarShellResult) {
        let checkpoint = try suppliedCheckpoint ?? workspaceStore.createCheckpoint(for: workspaceID)
        let timeout = min(
            max(timeoutSeconds ?? executor.limits.defaultTimeout, 1),
            executor.limits.maximumTimeout
        )
        let request = FamiliarShellRequest(
            taskID: UUID(),
            command: command,
            workspaceID: workspaceID,
            timeout: timeout,
            runID: context.runID,
            toolCallID: context.toolCallID
        )
        var finalResult: FamiliarShellResult?
        for try await event in executor.execute(request) {
            try Task.checkCancellation()
            if case .finished(let result) = event {
                finalResult = result
            }
        }
        guard let rawResult = finalResult else {
            throw FamiliarShellExecutorError.unavailable
        }
        let entries = try workspaceStore.entries(in: workspaceID)
        let workspaceBytes = entries.reduce(Int64(0)) { $0 + $1.byteSize }
        if workspaceBytes > executor.limits.maximumWorkspaceBytes {
            try workspaceStore.restore(checkpoint)
            throw FamiliarShellExecutorError.resourceLimitExceeded("Workspace 超过允许大小，已恢复执行前 checkpoint。")
        }
        if entries.contains(where: { $0.byteSize > executor.limits.maximumFileBytes }) {
            try workspaceStore.restore(checkpoint)
            throw FamiliarShellExecutorError.resourceLimitExceeded("生成了超出单文件限制的文件，已恢复执行前 checkpoint。")
        }
        let diff = try rawResult.workspaceDiff ?? workspaceStore.diff(from: checkpoint)
        let result = FamiliarShellResult(
            taskID: rawResult.taskID,
            runtime: rawResult.runtime,
            status: rawResult.status,
            exitCode: rawResult.exitCode,
            standardOutput: rawResult.standardOutput,
            standardError: rawResult.standardError,
            outputWasTruncated: rawResult.outputWasTruncated,
            startedAt: rawResult.startedAt,
            finishedAt: rawResult.finishedAt,
            workspaceDiff: diff
        )
        let output = Output(
            taskID: result.taskID,
            runtime: result.runtime.rawValue,
            status: result.status.rawValue,
            exitCode: result.exitCode,
            standardOutput: result.standardOutput,
            standardError: result.standardError,
            outputWasTruncated: result.outputWasTruncated,
            addedFiles: diff.added,
            modifiedFiles: diff.modified,
            removedFiles: diff.removed,
            checkpointID: checkpoint.id
        )
        let summary = result.status == .succeeded
            ? "Shell 命令执行完成。"
            : "Shell 命令未成功完成。"
        let executionResult = FamiliarToolExecutionResult(
            envelope: try FamiliarToolResultEnvelope(
                model: output,
                presentation: .code(.init(
                    summary: summary,
                    language: "shell",
                    filename: nil,
                    code: result.standardOutput.isEmpty ? result.standardError : result.standardOutput
                ))
            )
        )
        return (executionResult, result)
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
