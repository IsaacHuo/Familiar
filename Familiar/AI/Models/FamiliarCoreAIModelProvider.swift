import Foundation

nonisolated enum FamiliarCoreAIError: LocalizedError, Sendable {
    case runtimeUnavailable

    var errorDescription: String? {
        "当前 SDK 不包含 Familiar 所需的 Core AI Runtime。请使用 Xcode 27 并安装受支持的模型资产。"
    }
}

/// Platform adapter implemented by the Core AI target. The actor behind this
/// interface owns and reuses loaded weights/specialization across requests.
nonisolated protocol FamiliarCoreAILanguageModelRuntime: Sendable {
    func stream(
        request: FamiliarModelRequest,
        preparedModelURL: URL
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error>

    func unload() async
}

nonisolated struct FamiliarCoreAIModelProvider: FamiliarModelProvider, Sendable {
    let providerID = "core-ai"
    private let manager: FamiliarModelManager
    private let runtime: any FamiliarCoreAILanguageModelRuntime

    init(
        manager: FamiliarModelManager,
        runtime: any FamiliarCoreAILanguageModelRuntime
    ) {
        self.manager = manager
        self.runtime = runtime
    }

    func stream(
        request: FamiliarModelRequest
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let modelURL = try await manager.installedModelURL()
                    for try await event in runtime.stream(
                        request: request,
                        preparedModelURL: modelURL
                    ) {
                        try Task.checkCancellation()
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

nonisolated struct FamiliarUnavailableCoreAIRuntime: FamiliarCoreAILanguageModelRuntime {
    func stream(
        request _: FamiliarModelRequest,
        preparedModelURL _: URL
    ) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: FamiliarCoreAIError.runtimeUnavailable)
        }
    }

    func unload() async {}
}
