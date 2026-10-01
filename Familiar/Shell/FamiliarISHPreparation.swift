#if os(iOS)
import Foundation

/// One shared preparation flight, with separately cancellable Run waiters. Cancelling
/// a waiter never starts its command and does not tear down another Run's setup.
actor FamiliarISHPreparation {
    private let bridge: any FamiliarISHBridge
    private let configuration: FamiliarISHRuntimeConfiguration
    private var flight: (id: UUID, task: Task<Void, Error>)?
    private var ready = false

    init(bridge: any FamiliarISHBridge, configuration: FamiliarISHRuntimeConfiguration) {
        self.bridge = bridge
        self.configuration = configuration
    }

    func prepare() async throws {
        try Task.checkCancellation()
        if ready { return }
        if flight == nil {
            let bridge = bridge
            let configuration = configuration
            flight = (UUID(), Task { try await bridge.prepare(configuration: configuration) })
        }
        guard let current = flight else { throw FamiliarShellExecutorError.unavailable }
        let waiter = FamiliarISHPreparationWaiter()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiter.install(continuation)
                    Task {
                        do { try await current.task.value; waiter.finish(.success(())) }
                        catch { waiter.finish(.failure(error)) }
                    }
                }
            } onCancel: {
                waiter.finish(.failure(CancellationError()))
            }
            try Task.checkCancellation()
            ready = true
            if flight?.id == current.id { flight = nil }
        } catch {
            if !(error is CancellationError), flight?.id == current.id { flight = nil }
            throw error
        }
    }
}
/// The cancellation handler and preparation observer can finish in either order.
private nonisolated final class FamiliarISHPreparationWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func install(_ continuation: CheckedContinuation<Void, Error>) {
        let ready: Result<Void, Error>? = lock.withLock {
            if let ready = self.result { return ready }
            self.continuation = continuation
            return nil
        }
        if let ready { continuation.resume(with: ready) }
    }

    func finish(_ result: Result<Void, Error>) {
        let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
            guard self.result == nil else { return nil }
            self.result = result
            let value = self.continuation
            self.continuation = nil
            return value
        }
        continuation?.resume(with: result)
    }
}
#endif
