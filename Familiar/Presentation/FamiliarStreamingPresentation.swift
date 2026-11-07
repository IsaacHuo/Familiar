import Foundation
import Observation

/// Pure presentation pacing. Runtime text and persisted checkpoints never use this buffer.
nonisolated struct FamiliarStreamingBuffer {
    private(set) var received = ""
    private(set) var visible = ""
    private var pending = ""
    private var firstPendingAt: TimeInterval?
    private var firstReleaseAt: TimeInterval?

    var hasPending: Bool { !pending.isEmpty }

    mutating func receive(_ text: String, streaming: Bool, at now: TimeInterval) {
        guard streaming, text.hasPrefix(received) else {
            received = text
            flush()
            return
        }
        append(String(text.dropFirst(received.count)), at: now)
    }

    /// Runtime deltas are already ordered; do not compare or traverse the old prefix.
    mutating func append(_ delta: String, at now: TimeInterval) {
        guard !delta.isEmpty else { return }
        received += delta
        pending += delta
        if firstPendingAt == nil { firstPendingAt = now }
        if firstReleaseAt == nil { firstReleaseAt = now + 0.06 }
    }

    mutating func advance(at now: TimeInterval) {
        guard let firstReleaseAt, now >= firstReleaseAt, !pending.isEmpty else { return }
        if let firstPendingAt, now - firstPendingAt >= 0.5 {
            flush()
            return
        }
        let count = max(8, Int(ceil(Double(pending.count) / 8)))
        var chunk = String(pending.prefix(count))
        if let boundary = chunk.lastIndex(where: { $0.isWhitespace || ".,!?，。！？；".contains($0) }),
           chunk.distance(from: chunk.startIndex, to: boundary) >= count / 2 {
            chunk = String(chunk[...boundary])
        }
        visible += chunk
        pending.removeFirst(chunk.count)
        if pending.isEmpty { firstPendingAt = nil }
    }

    mutating func flush() {
        visible = received
        pending = ""
        firstPendingAt = nil
        firstReleaseAt = nil
    }
}

@MainActor @Observable
final class FamiliarStreamingPresentation {
    private(set) var text: String
    private(set) var isStreaming: Bool
    private(set) var hasNonWhitespaceContent: Bool
    @ObservationIgnored private var buffer = FamiliarStreamingBuffer()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var owners: Set<UUID> = []

    init(text: String = "", streaming: Bool = false) {
        self.text = streaming ? "" : text
        self.isStreaming = streaming
        self.hasNonWhitespaceContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        buffer.receive(text, streaming: streaming, at: ProcessInfo.processInfo.systemUptime)
    }

    func activate(owner: UUID) { owners.insert(owner); schedule() }
    func deactivate(owner: UUID) {
        owners.remove(owner)
        if owners.isEmpty { stopScheduler() }
    }

    func append(_ delta: String) {
        isStreaming = true
        if !hasNonWhitespaceContent, !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasNonWhitespaceContent = true
        }
        buffer.append(delta, at: ProcessInfo.processInfo.systemUptime)
        schedule()
    }

    /// Full snapshots are for binding, replacement, restoration and terminal flush.
    func receive(_ value: String, streaming: Bool) {
        isStreaming = streaming
        hasNonWhitespaceContent = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        buffer.receive(value, streaming: streaming, at: ProcessInfo.processInfo.systemUptime)
        text = buffer.visible
        schedule()
    }

    private func schedule() {
        guard isStreaming, buffer.hasPending, !owners.isEmpty else { stopScheduler(); return }
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
                guard let self else { return }
                self.buffer.advance(at: ProcessInfo.processInfo.systemUptime)
                self.text = self.buffer.visible
                if !self.buffer.hasPending { self.task = nil; return }
            }
        }
    }

    private func stopScheduler() { task?.cancel(); task = nil }
    func stop() { owners.removeAll(); stopScheduler() }
    isolated deinit { task?.cancel() }
}
