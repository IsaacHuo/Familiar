import SwiftUI

nonisolated enum FamiliarTheme {
    static let accent = Color(red: 0.267, green: 0.565, blue: 0.510)
    static let assistantFill = Color(uiColor: .secondarySystemBackground)
    static let userFill = accent.opacity(0.16)
    static let separator = Color.primary.opacity(0.10)
}

nonisolated enum AppSpacing {
    static let compact: CGFloat = 8
    static let standard: CGFloat = 12
    static let card: CGFloat = 16
    static let page: CGFloat = 20
}

private struct FamiliarGlassSurface: ViewModifier {
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: 22))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(FamiliarTheme.separator, lineWidth: 1)
                }
        }
    }
}

extension View {
    func familiarGlassSurface(interactive: Bool = false) -> some View {
        modifier(FamiliarGlassSurface(interactive: interactive))
    }
}
