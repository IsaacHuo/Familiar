import SwiftUI

/// The one tinted row icon shared by Settings and Project context rows. The
/// container scales with the label beside it so large Dynamic Type does not
/// leave the glyph visually detached.
struct FamiliarSettingsRowIcon: View {
    let symbol: String
    let color: Color

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = FamiliarIconSize.standard
    @ScaledMetric(relativeTo: .body) private var container: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: iconSize, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: container, height: container)
            .background(
                color.gradient,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
