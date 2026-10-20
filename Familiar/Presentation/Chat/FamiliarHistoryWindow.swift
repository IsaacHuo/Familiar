import Foundation

/// Presentation paging only. Runtime/compaction/editing continue to receive
/// the complete durable conversation; an old search hit need not render its tail.
nonisolated enum FamiliarHistoryWindow {
    static let pageSize = 80
    static func range(total: Int, center: Int?, size: Int = pageSize) -> Range<Int> {
        let count = max(0, total), size = max(1, size)
        guard let center else { return max(0, count - size)..<count }
        let target = min(max(0, center), max(0, count - 1))
        let start = min(max(0, target - size / 2), max(0, count - size))
        return start..<min(count, start + size)
    }
}
