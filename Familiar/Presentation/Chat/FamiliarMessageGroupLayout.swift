import SwiftUI

/// Measure against the actual timeline width, including narrow screens and large type.
struct FamiliarMessageGroupLayout: Layout {
    var accessibilityWide = false
    var trailing: Bool
    private func childWidth(_ width: CGFloat?) -> CGFloat {
        let available = width.flatMap { $0.isFinite ? $0 : nil } ?? 320
        if accessibilityWide { return max(0, available * 0.98) }
        return FamiliarChatAppearance.messageWidth(available)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 320
        let size = subviews.first?.sizeThatFits(.init(width: childWidth(width), height: nil)) ?? .zero
        return .init(width: width, height: size.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = childWidth(bounds.width)
        subviews.first?.place(at: .init(x: trailing ? bounds.maxX - width : bounds.minX, y: bounds.minY),
                              anchor: .topLeading, proposal: .init(width: width, height: nil))
    }

    // This full-width wrapper exports no custom baseline/alignment. The default
    // implementation places descendants again to discover their alignment,
    // needlessly re-entering a potentially very deep Run/Markdown stack.
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? { nil }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? { nil }
}
