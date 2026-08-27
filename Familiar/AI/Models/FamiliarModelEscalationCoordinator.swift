import Foundation

nonisolated struct FamiliarModelEscalationApproval: Identifiable, Sendable {
    let id: UUID
    let request: FamiliarModelEscalationRequest
}

actor FamiliarModelEscalationCoordinator {
    private struct Pending {
        let approval: FamiliarModelEscalationApproval
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var pending: [UUID: Pending] = [:]
    private var observers: [UUID: AsyncStream<[FamiliarModelEscalationApproval]>.Continuation] = [:]

    func requestApproval(_ request: FamiliarModelEscalationRequest) async -> Bool {
        let approval = FamiliarModelEscalationApproval(id: UUID(), request: request)
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                pending[approval.id] = Pending(
                    approval: approval,
                    continuation: continuation
                )
                publish()
            }
        }, onCancel: {
            Task { await self.resolve(id: approval.id, approved: false) }
        })
    }

    @discardableResult
    func resolve(id: UUID, approved: Bool) -> Bool {
        guard let value = pending.removeValue(forKey: id) else { return false }
        value.continuation.resume(returning: approved)
        publish()
        return true
    }

    func cancelAll() {
        let values = pending.values
        pending.removeAll()
        for value in values { value.continuation.resume(returning: false) }
        publish()
    }

    func updates() -> AsyncStream<[FamiliarModelEscalationApproval]> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(currentApprovals)
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeObserver(id) }
            }
        }
    }

    private var currentApprovals: [FamiliarModelEscalationApproval] {
        pending.values.map(\.approval).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func publish() {
        let values = currentApprovals
        for observer in observers.values { observer.yield(values) }
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
}
