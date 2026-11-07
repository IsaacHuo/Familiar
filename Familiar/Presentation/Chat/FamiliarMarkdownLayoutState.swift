import CoreGraphics

/// One value publishes both measured height and placeholder handoff. Publishing
/// readiness in a later onChange creates a second layout and overlapping text.
nonisolated struct FamiliarMarkdownLayoutState: Equatable {
    private(set) var height: CGFloat = 1
    private(set) var isMeasured = false

    mutating func receive(_ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        height = max(1, min(value, 1_000_000))
        if value > 1 { isMeasured = true }
    }
}
