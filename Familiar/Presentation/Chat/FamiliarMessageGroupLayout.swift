import SwiftUI

/// Measure against the actual timeline width, including narrow screens and large type.
struct FamiliarMessageGroupLayout: Layout {
    var fraction: CGFloat
    var trailing: Bool
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let size = subviews.first?.sizeThatFits(.init(width: width * fraction, height: nil)) ?? .zero
        return .init(width: width, height: size.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width * fraction
        subviews.first?.place(at: .init(x: trailing ? bounds.maxX - width : bounds.minX, y: bounds.minY),
                              anchor: .topLeading, proposal: .init(width: width, height: bounds.height))
    }
}
