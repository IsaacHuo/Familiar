import Foundation
import XCTest
@preconcurrency import FamiliarISHRuntime
@testable import Familiar

/// Opt-in actual arm64 guest execution, separate from deterministic fixtures
/// and physical-device signing/hardware acceptance.
final class FamiliarISHSimulatorRuntimeTests: XCTestCase {
    private func run(_ command: String, workspaceID: FamiliarWorkspaceID, store: FamiliarWorkspaceStore) async throws -> FamiliarShellResult {
        let id = UUID()
        let view = try store.prepareShellTaskView(taskID: id, workspaceID: workspaceID, resources: [], attachments: [])
        defer { try? store.removeShellTaskView(view) }
        let request = FamiliarShellRequest(taskID: id, command: command, workspaceID: workspaceID, workspaceView: view,
            timeout: 25, runID: "fc-guest-regression", toolCallID: id.uuidString, networkPolicy: .disabled)
        var result: FamiliarShellResult?
        for try await event in FamiliarISHShellExecutor(bridge: FamiliarRealISHBridge(), workspaceStore: store).execute(request) {
            if case .finished(let value) = event { result = value }
        }
        return try XCTUnwrap(result)
    }

    func testRealGuestScopeRootProtectionAndReparentedBackgroundCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FC-scope-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarWorkspaceStore(rootURL: root)
        let a = FamiliarWorkspaceID.project(UUID()), b = FamiliarWorkspaceID.project(UUID())
        let first = try await run("printf private > /root/fc-home; printf temp > /tmp/fc-temp; if printf bad > /etc/fc-escape; then exit 99; fi; setsid sh -c 'sleep 8' & echo FC_CHILD_PID:$!", workspaceID: a, store: store)
        XCTAssertEqual(first.status, .succeeded)
        let pidLine = try XCTUnwrap(first.standardOutput.split(separator: "\n").first { $0.hasPrefix("FC_CHILD_PID:") })
        let pid = try XCTUnwrap(Int32(pidLine.dropFirst("FC_CHILD_PID:".count)))
        XCTAssertEqual(ISHShellExecutor.executionOwner(forProcess: pid), 0, "Stopped/reparented children must be reaped before the result is delivered")
        let next = try await run("test ! -e /root/fc-home && test ! -e /tmp/fc-temp && test ! -e /etc/fc-escape && echo FC_SCOPE_OK", workspaceID: b, store: store)
        XCTAssertEqual(next.status, .succeeded)
        XCTAssertTrue(next.standardOutput.contains("FC_SCOPE_OK"))
    }

    func testRealGuestBoundedMemoryFileProcessAndNoNewlineOutputFailuresRecover() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FC-limits-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarWorkspaceStore(rootURL: root), workspace = FamiliarWorkspaceID.project(UUID())
        let script = """
        import mmap, os, time
        try:
            mapping = mmap.mmap(-1, 600 * 1024 * 1024, prot=mmap.PROT_READ | mmap.PROT_WRITE)
        except OSError:
            print('FC_MEMORY_LIMIT_OK')
        else:
            mapping.close()
            raise SystemExit('memory limit missing')
        try:
            with open('/workspace/work/oversized.bin', 'wb') as output:
                output.truncate(128 * 1024 * 1024 + 1)
        except OSError:
            print('FC_FILE_LIMIT_OK')
        else:
            raise SystemExit('file limit missing')
        children = []
        for _ in range(32):
            try:
                pid = os.fork()
            except OSError:
                break
            if pid == 0:
                time.sleep(1)
                os._exit(0)
            children.append(pid)
        assert len(children) <= 14, len(children)
        for pid in children:
            os.waitpid(pid, 0)
        print('FC_PROCESS_LIMIT_OK')
        try:
            os.kill(1, 0)
        except PermissionError:
            print('FC_INIT_PROTECTED')
        else:
            raise SystemExit('init not isolated')
        try:
            os.killpg(999999, 0)
        except ProcessLookupError:
            print('FC_MISSING_GROUP_OK')
        """
        let limits = try await run("python3 <<'FC_PY'\n" + script + "\nFC_PY\n", workspaceID: workspace, store: store)
        XCTAssertEqual(limits.status, .succeeded, limits.standardError)
        for marker in ["FC_MEMORY_LIMIT_OK", "FC_FILE_LIMIT_OK", "FC_PROCESS_LIMIT_OK", "FC_INIT_PROTECTED", "FC_MISSING_GROUP_OK"] {
            XCTAssertTrue(limits.standardOutput.contains(marker), limits.standardOutput)
        }
        let output = try await run("python3 -c 'import sys; sys.stdout.write(\"x\" * 1200000)'", workspaceID: workspace, store: store)
        XCTAssertEqual(output.status, .failed)
        XCTAssertTrue(output.outputWasTruncated)
        XCTAssertLessThanOrEqual(output.standardOutput.utf8.count + output.standardError.utf8.count, FamiliarShellLimits.iOS.maximumOutputBytes)
        let recovered = try await run("echo FC_AFTER_LIMITS", workspaceID: workspace, store: store)
        XCTAssertEqual(recovered.status, .succeeded)
        XCTAssertTrue(recovered.standardOutput.contains("FC_AFTER_LIMITS"))
    }
    func testRealInteractivePTYInputResizeInterruptExitAndExecutionOwnership() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FC-pty-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarWorkspaceStore(rootURL: root)
        let bridge = FamiliarRealISHBridge()
        let id = UUID(), projectID = UUID()
        let view = try store.prepareShellTaskView(taskID: id, workspaceID: .project(projectID), resources: [], attachments: [])
        defer { try? store.removeShellTaskView(view) }
        let home = view.work.appendingPathComponent("Home"), tmp = view.work.appendingPathComponent("Tmp")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let mounts: [FamiliarISHMount] = [
            .init(hostURL: view.files, guestPath: "/workspace/files", writable: false),
            .init(hostURL: view.outputs, guestPath: "/workspace/outputs", writable: true),
            .init(hostURL: view.work, guestPath: "/workspace/work", writable: true),
            .init(hostURL: view.environment, guestPath: "/workspace/env", writable: true),
            .init(hostURL: home, guestPath: "/root", writable: true),
            .init(hostURL: tmp, guestPath: "/tmp", writable: true),
        ]
        let stream = bridge.openTerminal(taskID: id, workspaceID: view.workspaceID, mounts: mounts,
            command: "exec /bin/sh -i", networkPolicy: .disabled)
        let deadline = Task { try? await Task.sleep(for: .seconds(20)); if !Task.isCancelled { await bridge.closeTerminal(taskID: id) } }
        defer { deadline.cancel() }
        var bytes = Data(), sentInterrupt = false, sentEOF = false, exited = false
        for try await event in stream {
            switch event {
            case .started:
                print("FC_PTY started")
                let otherID = UUID()
                let other = try store.prepareShellTaskView(taskID: otherID, workspaceID: view.workspaceID, resources: [], attachments: [])
                defer { try? store.removeShellTaskView(other) }
                let request = FamiliarShellRequest(taskID: otherID, command: "echo SHOULD_NOT_RUN", workspaceID: other.workspaceID,
                    workspaceView: other, timeout: 3, runID: "fc-busy", toolCallID: "blocked", networkPolicy: .disabled)
                do {
                    for try await result in FamiliarISHShellExecutor(bridge: bridge, workspaceStore: store).execute(request) {
                        if case .finished = result { XCTFail("A manual guest owner must reject the Agent command") }
                    }
                    XCTFail("Expected busy rejection")
                } catch FamiliarShellExecutorError.alreadyRunning { }
                print("FC_PTY busy_rejected")
                try await bridge.resizeTerminal(taskID: id, columns: 97, rows: 33)
                try await bridge.sendTerminalInput(taskID: id,
                    data: Data("stty -echo; stty size; printf '\\033[31m北京\\033[0m\\n'; printf '\\nFC_TTY_END\\n'\n".utf8))
            case .output(let data):
                bytes.append(data)
                let text = String(decoding: bytes, as: UTF8.self)
                if !sentInterrupt, text.contains("\r\nFC_TTY_END\r\n") {
                    print("FC_PTY resize_ansi_chinese_verified")
                    sentInterrupt = true
                    XCTAssertTrue(text.contains("33 97"))
                    XCTAssertTrue(text.contains("\u{1B}[31m北京\u{1B}[0m"))
                    try await bridge.sendTerminalInput(taskID: id, data: Data("sleep 8\n".utf8))
                    try await Task.sleep(for: .milliseconds(200))
                    await bridge.interruptTerminal(taskID: id)
                    try await Task.sleep(for: .milliseconds(100))
                    try await bridge.sendTerminalInput(taskID: id, data: Data("printf 'FC_AFTER_INTERRUPT\\n'\n".utf8))
                }
                if !sentEOF, text.contains("FC_AFTER_INTERRUPT\r\n") {
                    print("FC_PTY interrupt_verified")
                    sentEOF = true
                    try await bridge.sendTerminalInput(taskID: id, data: Data([4]))
                }
            case .exited(let code): XCTAssertEqual(code, 0); exited = true
            case .failed(let detail): XCTFail(detail)
            case .cancelled: XCTFail("PTY deadline/cancellation ended the session before Ctrl-D")
            }
        }
        XCTAssertTrue(exited && sentEOF && sentInterrupt)
        let receipt = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.data")
        receipt.name = "FC-real-PTY-bytes"; receipt.lifetime = .keepAlways; add(receipt)
    }
    func testRealGuestColdPreparePythonAndWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FC-guest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarWorkspaceStore(rootURL: root)
        let executor = FamiliarISHShellExecutor(bridge: FamiliarRealISHBridge(), workspaceStore: store)
        try await executor.prepare()
        let id = UUID()
        let view = try store.prepareShellTaskView(taskID: id, workspaceID: .project(UUID()), resources: [], attachments: [])
        defer { try? store.removeShellTaskView(view) }
        let request = FamiliarShellRequest(taskID: id,
            command: "python3 -c 'import ssl, pathlib; pathlib.Path(\"/workspace/outputs/probe.txt\").write_text(\"北京 runtime probe\"); print(\"FC_GUEST_OK\")'",
            workspaceID: view.workspaceID, workspaceView: view, timeout: 30,
            runID: "fc-simulator-guest", toolCallID: "python", networkPolicy: .disabled)
        var result: FamiliarShellResult?
        for try await event in executor.execute(request) {
            if case .finished(let value) = event { result = value }
        }
        let value = try XCTUnwrap(result)
        let receipt = XCTAttachment(string: "Actual iSH guest: status=\(value.status), exit=\(String(describing: value.exitCode))\n\(value.standardOutput)\n\(value.standardError)")
        receipt.lifetime = .keepAlways; add(receipt)
        XCTAssertEqual(value.status, .succeeded)
        XCTAssertTrue(value.standardOutput.contains("FC_GUEST_OK"))
        XCTAssertEqual(try String(contentsOf: view.outputs.appendingPathComponent("probe.txt"), encoding: .utf8), "北京 runtime probe")
        // A second prepare must use the hot guest rather than reinstall/reboot it.
        try await executor.prepare()
    }
}
