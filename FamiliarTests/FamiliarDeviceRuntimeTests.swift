import Foundation
import XCTest
@testable import Familiar

/// Opt-in real guest tests. Never substitutes a fixture for the device runtime.
final class FamiliarDeviceRuntimeTests: XCTestCase {
    func testRealGuestPythonAndWorkspace() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Requires the signed physical device host")
#else
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarWorkspaceStore(rootURL: root)
        let executor = FamiliarISHShellExecutor(bridge: FamiliarRealISHBridge(), workspaceStore: store)
        try await executor.prepare()
        let id = UUID()
        let view = try store.prepareShellTaskView(taskID: id, workspaceID: .project(UUID()), resources: [], attachments: [])
        defer { try? store.removeShellTaskView(view) }
        let request = FamiliarShellRequest(taskID: id,
            command: "python3 -c 'import sys, ssl, pathlib; print(sys.version); pathlib.Path(\"/workspace/outputs/probe.txt\").write_text(\"北京 runtime probe\"); print(\"FAMILIAR_PROBE_OK\")'",
            workspaceID: view.workspaceID, workspaceView: view, timeout: 30,
            runID: "device-probe", toolCallID: "python", networkPolicy: .disabled)
        var result: FamiliarShellResult?
        for try await event in executor.execute(request) {
            if case .finished(let value) = event { result = value }
        }
        let value = try XCTUnwrap(result)
        let attachment = XCTAttachment(string: "status=\(value.status) exit=\(String(describing: value.exitCode))\n\(value.standardOutput)\n\(value.standardError)")
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(value.status, .succeeded)
        XCTAssertTrue(value.standardOutput.contains("FAMILIAR_PROBE_OK"))
        XCTAssertEqual(try String(contentsOf: view.outputs.appendingPathComponent("probe.txt"), encoding: .utf8), "北京 runtime probe")
#endif
    }
}
