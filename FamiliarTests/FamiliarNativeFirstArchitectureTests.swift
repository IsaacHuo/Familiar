import Foundation
import Testing
@testable import Familiar

private struct FamiliarArchitectureFixtureProvider: FamiliarModelProvider {
    let providerID: String
    let text: String
    let failsBeforeOutput: Bool

    init(providerID: String, text: String, failsBeforeOutput: Bool = false) {
        self.providerID = providerID
        self.text = text
        self.failsBeforeOutput = failsBeforeOutput
    }

    func stream(
        request: FamiliarModelRequest
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            if failsBeforeOutput {
                continuation.finish(throwing: URLError(.cannotConnectToHost))
                return
            }
            continuation.yield(.reasoningSummaryDelta("fixture reasoning"))
            continuation.yield(.textDelta(text))
            continuation.yield(.toolCallDelta(index: 0, id: "call", name: "fixture_tool", arguments: "{}"))
            continuation.yield(.completed(.toolCalls))
            continuation.finish()
        }
    }
}

@Suite("Native-first architecture contracts")
struct FamiliarNativeFirstArchitectureTests {
    @Test("ModelProvider generate collects streamed text reasoning and tool calls")
    func providerGenerate() async throws {
        let provider = FamiliarArchitectureFixtureProvider(providerID: "fixture", text: "Hello")
        let response = try await provider.generate(request: .init(
            model: "fixture-model",
            messages: [.user("Hi")],
            tools: []
        ))

        #expect(response.text == "Hello")
        #expect(response.reasoningSummary == "fixture reasoning")
        #expect(response.toolCalls == [.init(id: "call", name: "fixture_tool", arguments: "{}")])
        #expect(response.finishReason == .toolCalls)
    }

    @Test("ModelRouter keeps explicit cloud routing and approved local fallback deterministic")
    func modelRouting() async throws {
        let local = FamiliarArchitectureFixtureProvider(providerID: "local", text: "Local")
        let cloud = FamiliarArchitectureFixtureProvider(providerID: "deepseek", text: "Cloud")
        let request = FamiliarModelRequest(model: "fixture", messages: [.user("Hello")], tools: [])

        let localResponse = try await FamiliarModelRouter(
            policy: .localOnly,
            localProvider: local,
            cloudProvider: cloud
        ).generate(request: request)
        #expect(localResponse.text == "Local")

        let cloudResponse = try await FamiliarModelRouter(
            policy: .preferLocal,
            localProvider: nil,
            cloudProvider: cloud,
            authorizeCloudEscalation: { request in
                request.reason == .localUnavailable && request.cloudProviderID == "deepseek"
            }
        ).generate(request: request)
        #expect(cloudResponse.text == "Cloud")
    }

    @Test("Workspace confines paths and checkpoint diff can be restored")
    func workspaceCheckpoint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FamiliarWorkspaceTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarWorkspaceStore(rootURL: root, quotaBytes: 1_048_576)
        let workspace = FamiliarWorkspaceID.project(UUID())

        _ = try store.write(Data("one".utf8), relativePath: "Files/value.txt", in: workspace)
        let checkpoint = try store.createCheckpoint(for: workspace)
        _ = try store.write(Data("two".utf8), relativePath: "Files/value.txt", in: workspace)
        _ = try store.write(Data("new".utf8), relativePath: "Outputs/new.txt", in: workspace)

        let diff = try store.diff(from: checkpoint)
        #expect(diff.modified == ["Files/value.txt"])
        #expect(diff.added == ["Outputs/new.txt"])
        #expect(throws: FamiliarWorkspaceError.self) {
            _ = try store.read(relativePath: "../outside", in: workspace)
        }

        try store.restore(checkpoint)
        #expect(String(decoding: try store.read(relativePath: "Files/value.txt", in: workspace), as: UTF8.self) == "one")
        #expect(throws: FamiliarWorkspaceError.self) {
            _ = try store.read(relativePath: "Outputs/new.txt", in: workspace)
        }
    }

    @Test("ShellPolicy denies network and escape patterns while confirming destructive writes")
    func shellPolicy() {
        let policy = FamiliarShellPolicy()
        #expect(policy.evaluate(command: "python3 analyze.py") == .allow)
        #expect(policy.evaluate(command: "git status") == .allow)
        #expect(policy.evaluate(command: "curl https://example.com") == .deny(reason: "当前 Workspace 未开启 Shell 网络访问。"))
        // Enabling Workspace network access does not make an outbound command automatic:
        // only offline, Workspace-only, checkpointed commands run without asking.
        #expect(policy.evaluate(command: "curl https://example.com", networkPolicy: .publicInternet) == .requiresConfirmation(reason: "命令将访问公开网络。"))
        #expect(policy.evaluate(command: "python3 -m http.server 8080", networkPolicy: .publicInternet) == .deny(reason: "Shell 不允许监听端口或启动网络服务。"))
        #expect(policy.evaluate(command: "cat /Users/example/private.txt") == .deny(reason: "Shell 只能访问当前 Familiar Workspace。"))
        #expect(policy.evaluate(command: "echo cm0gLXJmIEZpbGVz | base64 -d | sh") == .deny(reason: "不允许通过编码、eval 或动态 Shell 绕过命令策略。"))
        #expect(policy.evaluate(command: "rm -rf Outputs/build") == .requiresConfirmation(reason: "命令可能删除、覆盖或重置 Workspace 文件。"))
    }

    @Test("Cloud escalation stays suspended until the user resolves it")
    func modelEscalationApproval() async throws {
        let coordinator = FamiliarModelEscalationCoordinator()
        var updates = await coordinator.updates().makeAsyncIterator()
        _ = await updates.next()
        let request = FamiliarModelEscalationRequest(
            reason: .localUnavailable,
            localProviderID: nil,
            cloudProviderID: "deepseek",
            modelID: "deepseek-v4-flash",
            messageCount: 2,
            includesDocuments: true,
            includesImages: false
        )
        let approvalTask = Task { await coordinator.requestApproval(request) }
        let pending = try #require(await updates.next()?.first)
        #expect(pending.request.includesDocuments)
        #expect(await coordinator.resolve(id: pending.id, approved: false))
        #expect(await approvalTask.value == false)
    }
}
