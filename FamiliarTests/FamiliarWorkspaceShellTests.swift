import Foundation
import Testing
@testable import Familiar

private struct FamiliarShellFixtureExecutor: FamiliarShellExecutor {
    let runtimeKind = FamiliarShellRuntimeKind.ish
    let limits = FamiliarShellLimits.iOS
    let status: FamiliarShellTaskStatus
    let output: String
    let writesOutput: Bool

    func prepare() async throws {}

    func execute(_ request: FamiliarShellRequest) -> AsyncThrowingStream<FamiliarShellEvent, Error> {
        AsyncThrowingStream { continuation in
            do {
                continuation.yield(.started(taskID: request.taskID, runtime: runtimeKind, at: Date()))
                if writesOutput {
                    try Data("generated".utf8).write(
                        to: request.workspaceView.outputs.appendingPathComponent("generated.txt"),
                        options: [.atomic]
                    )
                }
                if !output.isEmpty { continuation.yield(.standardOutput(output)) }
                continuation.yield(.finished(.init(
                    taskID: request.taskID,
                    runtime: runtimeKind,
                    status: status,
                    exitCode: status == .succeeded ? 0 : 1,
                    standardOutput: output,
                    standardError: status == .succeeded ? "" : "fixture failed",
                    outputWasTruncated: false,
                    startedAt: Date(),
                    finishedAt: Date(),
                    workspaceDiff: nil,
                    networkStatistics: .zero
                )))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func cancel(taskID _: UUID) async {}
}

private actor FamiliarShellProgressRecorder {
    private var events: [FamiliarToolContext.Progress] = []

    func append(_ event: FamiliarToolContext.Progress) { events.append(event) }
    func snapshot() -> [FamiliarToolContext.Progress] { events }
}

@Suite("Workspace shell isolation")
struct FamiliarWorkspaceShellTests {
    @Test("Task input projection is physical read-only and isolated")
    func taskInputProjection() throws {
        let (root, store, workspaceID) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let resourceID = UUID()
        let attachmentID = UUID()
        let first = try store.prepareShellTaskView(
            taskID: UUID(),
            workspaceID: workspaceID,
            resources: [.init(
                id: resourceID,
                versionID: UUID(),
                version: 1,
                displayName: "Data",
                filename: "data.csv",
                mimeType: "text/csv",
                contentHash: "fixture",
                extractedText: "value\n42"
            )],
            attachments: [.init(
                id: attachmentID,
                kind: .document,
                filename: "brief.txt",
                mimeType: "text/plain",
                relativePath: "Messages/missing/brief.txt",
                extractedText: "brief body",
                byteSize: 10
            )]
        )
        let second = try store.prepareShellTaskView(
            taskID: UUID(),
            workspaceID: workspaceID,
            resources: [],
            attachments: []
        )
        defer {
            try? store.removeShellTaskView(first)
            try? store.removeShellTaskView(second)
        }

        let resourceURL = first.files
            .appendingPathComponent("Resources/\(resourceID.uuidString.lowercased())/data.csv")
        let attachmentURL = first.files
            .appendingPathComponent("Attachments/\(attachmentID.uuidString.lowercased())/brief.txt")
        #expect(try String(contentsOf: resourceURL, encoding: .utf8) == "value\n42")
        #expect(try String(contentsOf: attachmentURL, encoding: .utf8) == "brief body")
        let permissions = try #require(
            FileManager.default.attributesOfItem(atPath: resourceURL.path)[.posixPermissions] as? NSNumber
        )
        #expect(permissions.intValue & 0o222 == 0)
        #expect(first.work != second.work)
        #expect(!FileManager.default.fileExists(
            atPath: second.files.appendingPathComponent("Resources/\(resourceID.uuidString.lowercased())").path
        ))
    }

    @Test("Final symbolic links are rejected for reads writes and enumeration")
    func finalSymbolicLinkRejected() throws {
        let (root, store, workspaceID) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try store.prepare(workspaceID)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("secret".utf8).write(to: outside)
        let link = paths.outputs.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        #expect(throws: FamiliarWorkspaceError.self) {
            _ = try store.read(relativePath: "Outputs/link.txt", in: workspaceID)
        }
        #expect(throws: FamiliarWorkspaceError.self) {
            _ = try store.write(Data("overwrite".utf8), relativePath: "Outputs/link.txt", in: workspaceID)
        }
        #expect(throws: FamiliarWorkspaceError.self) {
            _ = try store.entries(in: workspaceID)
        }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "secret")
    }

    @Test("Workspace deletion staging restores on rollback and discards on commit")
    func workspaceDeletionStaging() throws {
        let (root, store, workspaceID) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.write(Data("keep".utf8), relativePath: "Outputs/keep.txt", in: workspaceID)

        let rollbackStage = try store.stageWorkspace(workspaceID)
        #expect(!FileManager.default.fileExists(atPath: rollbackStage.originalURL.path))
        try store.restore(rollbackStage)
        #expect(try store.contains(relativePath: "Outputs/keep.txt", in: workspaceID))

        let committedStage = try store.stageWorkspace(workspaceID)
        try store.discard(committedStage)
        #expect(!FileManager.default.fileExists(atPath: committedStage.originalURL.path))
    }

    @Test("Shell network settings default off and persist per workspace")
    func shellNetworkSettings() throws {
        let (root, store, workspaceID) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let otherID = FamiliarWorkspaceID.project(UUID())

        #expect(try !store.shellSettings(in: workspaceID).networkEnabled)
        try store.saveShellSettings(.init(networkEnabled: true), in: workspaceID)
        #expect(try store.shellSettings(in: workspaceID).networkEnabled)
        #expect(try !store.shellSettings(in: otherID).networkEnabled)
        #expect(try !store.shellSettingsURL(in: workspaceID).path.contains("Runtime"))
    }

    @Test("Python package source setting defaults to PyPI and accepts only catalog sources")
    func pythonPackageSourceSettings() throws {
        let suiteName = "FamiliarPythonPackageSourceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = FamiliarPythonPackageSourceSettingsStore(defaults: defaults)

        #expect(settings.selectedSource.id == FamiliarPythonPackageSource.officialID)
        settings.save(selectedSourceID: FamiliarPythonPackageSource.tunaID)
        #expect(settings.selectedSource.id == FamiliarPythonPackageSource.tunaID)
        #expect(settings.selectedSource.indexURL.absoluteString == "https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple")
        settings.save(selectedSourceID: "untrusted-custom-source")
        #expect(settings.selectedSource.id == FamiliarPythonPackageSource.officialID)
    }

    @Test("Project environments persist while ordinary chat environments are task scoped")
    func environmentLifetime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FamiliarEnvironmentLifetime-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarWorkspaceStore(rootURL: root, quotaBytes: 2 * 1_024 * 1_024)
        let projectID = UUID()
        let projectView = try store.prepareShellTaskView(
            taskID: UUID(),
            workspaceID: .project(projectID),
            resources: [],
            attachments: []
        )
        try Data("project".utf8).write(to: projectView.environment.appendingPathComponent("marker.txt"))
        try store.removeShellTaskView(projectView)
        #expect(FileManager.default.fileExists(
            atPath: try store.projectEnvironmentURL(projectID).appendingPathComponent("marker.txt").path
        ))

        let conversationView = try store.prepareShellTaskView(
            taskID: UUID(),
            workspaceID: .conversation(UUID()),
            resources: [],
            attachments: []
        )
        let ephemeralEnvironment = conversationView.environment
        try Data("temporary".utf8).write(to: ephemeralEnvironment.appendingPathComponent("marker.txt"))
        try store.removeShellTaskView(conversationView)
        #expect(!FileManager.default.fileExists(atPath: ephemeralEnvironment.path))
    }

    @Test("Staged Project environment replaces the old environment atomically")
    func environmentCommit() throws {
        let (root, store, workspaceID) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        guard case .project(let projectID) = workspaceID else { return }
        let original = try store.projectEnvironmentURL(projectID)
        try Data("old".utf8).write(to: original.appendingPathComponent("version.txt"))
        let staging = try store.prepareShellTaskView(
            taskID: UUID(),
            workspaceID: workspaceID,
            resources: [],
            attachments: [],
            useStagingEnvironment: true
        )
        try Data("new".utf8).write(to: staging.environment.appendingPathComponent("version.txt"))
        try store.commitProjectEnvironment(from: staging, projectID: projectID)
        #expect(try String(contentsOf: original.appendingPathComponent("version.txt"), encoding: .utf8) == "new")
        try store.removeShellTaskView(staging)
        #expect(try String(contentsOf: original.appendingPathComponent("version.txt"), encoding: .utf8) == "new")
    }

    @Test("Shell preflight automatically allows only offline checkpointed commands")
    func shellPreflight() async throws {
        let (root, store, workspaceID) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = FamiliarShellTool(
            executor: FamiliarShellFixtureExecutor(status: .succeeded, output: "", writesOutput: false),
            workspaceStore: store
        )
        let context = FamiliarToolContext(workspaceID: workspaceID)
        let offline = try await tool.preflight(.init(command: "python3 analyze.py", timeoutSeconds: nil), context: context)
        #expect(offline.disposition == .automatic)
        let install = try await tool.preflight(.init(command: "pip install python-docx", timeoutSeconds: nil), context: context)
        guard case .denied = install.disposition else {
            Issue.record("Package installation must be denied from shell_execute")
            return
        }
        try store.setShellNetworkEnabled(true, in: workspaceID)
        let networkEnabled = try await tool.preflight(.init(command: "python3 analyze.py", timeoutSeconds: nil), context: context)
        #expect(networkEnabled.disposition == .requiresApproval)
    }

    @Test("Writable task usage tracks Outputs and Work without exposing other directories")
    func writableTaskUsage() throws {
        let (root, store, workspaceID) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let view = try store.prepareShellTaskView(
            taskID: UUID(),
            workspaceID: workspaceID,
            resources: [],
            attachments: []
        )
        defer { try? store.removeShellTaskView(view) }
        try Data(repeating: 1, count: 32).write(to: view.outputs.appendingPathComponent("output.bin"))
        try Data(repeating: 2, count: 48).write(to: view.work.appendingPathComponent("scratch.bin"))

        let usage = try store.shellWritableUsage(for: view)
        #expect(usage.totalBytes == 80)
        #expect(usage.largestFileBytes == 48)
    }

    @Test("Tool registry adds Shell only after explicit registration")
    func dynamicShellRegistration() async throws {
        let registry = try FamiliarToolRegistry(tools: [])
        #expect(await registry.snapshot().isEmpty)
        let (root, store, _) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = AnyFamiliarTool(FamiliarShellTool(
            executor: FamiliarShellFixtureExecutor(status: .succeeded, output: "", writesOutput: false),
            workspaceStore: store
        ))
        try await registry.register(tool)
        #expect(await registry.snapshot().map(\.name) == ["shell_execute"])
    }

    @Test("Every shell call requires one-shot action approval and success reports a typed diff")
    func shellApprovalAndSuccess() async throws {
        let (root, store, workspaceID) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = FamiliarShellProgressRecorder()
        let output = String(repeating: "x", count: 70 * 1_024)
        let context = FamiliarToolContext(
            runID: "run",
            toolCallID: "call",
            workspaceID: workspaceID,
            progressReporter: { await recorder.append($0) }
        )
        let tool = FamiliarShellTool(
            executor: FamiliarShellFixtureExecutor(status: .succeeded, output: output, writesOutput: true),
            workspaceStore: store
        )

        let outcome = try await tool.execute(.init(command: "python3 analyze.py", timeoutSeconds: nil), context: context)
        guard case .action(let proposal) = outcome else {
            Issue.record("Expected a one-shot shell action proposal")
            return
        }
        #expect(tool.manifest.risk == .high)
        #expect(proposal.allowedAuthorizationDurations == [.once])
        let committed = try await proposal.commit()
        #expect(committed.undo != nil)
        guard case .shellExecution(let presentation) = committed.result.envelope.presentation.content else {
            Issue.record("Expected typed shell presentation")
            return
        }
        #expect(presentation.status == FamiliarShellTaskStatus.succeeded.rawValue)
        #expect(presentation.addedFiles == ["Outputs/generated.txt"])
        #expect(try store.contains(relativePath: "Outputs/generated.txt", in: workspaceID))
        let progress = await recorder.snapshot()
        let progressBytes = progress.reduce(0) { total, event in
            switch event {
            case .standardOutput(let value), .standardError(let value): total + value.utf8.count
            case .status: total
            }
        }
        #expect(progressBytes == 64 * 1_024)
        #expect(try store.prepare(workspaceID).tasksDirectoryIsEmpty)
    }

    @Test("Failed shell execution restores Outputs and removes task work")
    func shellFailureRestores() async throws {
        let (root, store, workspaceID) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.write(Data("keep".utf8), relativePath: "Outputs/keep.txt", in: workspaceID)
        let tool = FamiliarShellTool(
            executor: FamiliarShellFixtureExecutor(status: .failed, output: "", writesOutput: true),
            workspaceStore: store
        )
        let outcome = try await tool.execute(
            .init(command: "python3 analyze.py", timeoutSeconds: 5),
            context: .init(runID: "run", toolCallID: "failed", workspaceID: workspaceID)
        )
        guard case .action(let proposal) = outcome else {
            Issue.record("Expected action proposal")
            return
        }
        let committed = try await proposal.commit()
        #expect(committed.undo == nil)
        #expect(try !store.contains(relativePath: "Outputs/generated.txt", in: workspaceID))
        #expect(String(decoding: try store.read(relativePath: "Outputs/keep.txt", in: workspaceID), as: UTF8.self) == "keep")
        #expect(try store.prepare(workspaceID).tasksDirectoryIsEmpty)
    }

    @Test("The configured Shell timeout is both the default and the ceiling")
    func shellTimeoutSetting() throws {
        // An isolated suite so the test cannot read or write the real app settings.
        let suiteName = "FamiliarShellTimeoutTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let limits = FamiliarShellLimits.iOS
        let store = FamiliarShellTimeoutSettingsStore(defaults: defaults)

        // With nothing stored the executor default applies.
        #expect(store.timeout(limits: limits) == limits.defaultTimeout)

        store.save(45, limits: limits)
        #expect(store.timeout(limits: limits) == 45)

        // A stored or hand-edited value must never widen the timeout past what the
        // executor enforces, in either direction.
        store.save(limits.maximumTimeout + 10_000, limits: limits)
        #expect(store.timeout(limits: limits) == limits.maximumTimeout)
        store.save(0, limits: limits)
        #expect(store.timeout(limits: limits) == 1)

        // Values written by an older build bypass save(), so read must clamp too.
        defaults.set(9_999.0, forKey: FamiliarShellTimeoutSettingsStore.defaultsKey)
        #expect(store.timeout(limits: limits) == limits.maximumTimeout)
    }

    private func makeWorkspace() -> (URL, FamiliarWorkspaceStore, FamiliarWorkspaceID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FamiliarWorkspaceShell-\(UUID().uuidString)",
            isDirectory: true
        )
        return (root, FamiliarWorkspaceStore(rootURL: root, quotaBytes: 2 * 1_024 * 1_024), .project(UUID()))
    }
}

private extension FamiliarWorkspacePaths {
    var tasksDirectoryIsEmpty: Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: tasks.path)) ?? []).isEmpty
    }
}
