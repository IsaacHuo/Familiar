import SwiftUI

enum FamiliarAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "familiar.appearance.v1"
    static var current: FamiliarAppearancePreference {
        FamiliarAppearancePreference(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "system") ?? .system
    }

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var localizedTitle: String {
        switch self {
        case .system: String(localized: "settings.appearance.system", defaultValue: "System")
        case .light: String(localized: "settings.appearance.light", defaultValue: "Light")
        case .dark: String(localized: "settings.appearance.dark", defaultValue: "Dark")
        }
    }
}

struct FamiliarAppearanceSettingsView: View {
    @AppStorage(FamiliarAppearancePreference.storageKey) private var selection = FamiliarAppearancePreference.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "settings.hub.appearance", defaultValue: "Appearance"), selection: $selection) {
                    ForEach(FamiliarAppearancePreference.allCases) { preference in
                        Text(preference.localizedTitle).tag(preference.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(String(localized: "settings.appearance.footer", defaultValue: "This setting overrides the iPhone appearance for Familiar."))
            }
        }
        .navigationTitle(String(localized: "settings.hub.appearance", defaultValue: "Appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

nonisolated enum FamiliarTheme {
    static let accent = Color(red: 0.10, green: 0.53, blue: 0.98)
    static let displayCornerRadius: CGFloat = 62
    static let brandViolet = Color(red: 0.55, green: 0.44, blue: 0.98)
    static let brandGlow = LinearGradient(
        colors: [accent.opacity(0.18), brandViolet.opacity(0.12), .clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let userFill = Color(uiColor: .tertiarySystemFill)
    static let elevatedFill = Color(uiColor: .secondarySystemBackground)
    static let drawerFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .secondarySystemBackground
            : UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
    })
    static let separator = Color.primary.opacity(0.10)
}

/// Beautiful UI's semantic palette translated to dynamic iOS colors. These
/// tokens are intentionally scoped to AI response surfaces; navigation and
/// system controls continue to use native materials and Liquid Glass.
@MainActor
enum FamiliarAISurfaceColor {
    static let page = dynamic(light: 0xFAFAFB, dark: 0x17181A)
    static let canvas = dynamic(light: 0xF1F2F3, dark: 0x1C1D1F)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x232427)
    static let inset = dynamic(light: 0xF7F8F9, dark: 0x1F2022)
    static let hover = dynamic(light: 0xF4F5F6, dark: 0x2A2B2E)
    static let hoverStrong = dynamic(light: 0xE7E9EB, dark: 0x313236)
    static let ink = dynamic(light: 0x1F2124, dark: 0xF2F3F4)
    static let inkSecondary = dynamic(light: 0x62656B, dark: 0xA5A8AD)
    static let inkTertiary = dynamic(light: 0x9A9DA3, dark: 0x6C6F75)
    static let line = dynamic(light: 0xECEDEF, dark: 0x2E3033)
    static let lineStrong = dynamic(light: 0xE0E2E5, dark: 0x3A3C40)
    static let field = dynamic(light: 0xF2F2F3, dark: 0x2B2C2F)
    static let accent = dynamic(light: 0x0285FF, dark: 0x3D9AFF)
    static let accentInk = dynamic(light: 0x0170DD, dark: 0x7EC0FF)
    static let accentTint = dynamic(light: 0xE9F3FF, dark: 0x253E59)
    static let success = dynamic(light: 0x189A4D, dark: 0x3DBB72)
    static let successTint = dynamic(light: 0xE8F5ED, dark: 0x203D2C)
    static let warning = dynamic(light: 0xEF720C, dark: 0xF68F3C)
    static let warningTint = dynamic(light: 0xFDF1E5, dark: 0x46301F)
    static let failure = dynamic(light: 0xE3474C, dark: 0xEE5C61)
    static let failureTint = dynamic(light: 0xFCECEC, dark: 0x462629)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

nonisolated enum FamiliarAISurfaceRadius {
    static let chip: CGFloat = 6
    static let control: CGFloat = 8
    static let card: CGFloat = 10
    static let window: CGFloat = 14
}

nonisolated enum FamiliarAISurfaceMetric {
    static let hairline: CGFloat = 1
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24
    static let cardPadding: CGFloat = 12
    static let rowHeight: CGFloat = 44
    static let icon: CGFloat = 18
    static let compactIcon: CGFloat = 14
    static let traceIndent: CGFloat = 18
    static let timelineWidth: CGFloat = 780
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// A deliberately small spacing scale for the app's core surfaces.
/// Names describe relative rhythm so layout code does not invent one-off values.
nonisolated enum FamiliarSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 20
    static let section: CGFloat = 24
}

/// Semantic Dynamic Type roles used by high-frequency product surfaces.
nonisolated enum FamiliarTypography {
    static let largeTitle = Font.largeTitle.bold()
    static let screenTitle = Font.title2.bold()
    static let sectionTitle = Font.headline
    static let body = Font.body
    static let secondary = Font.subheadline
    static let caption = Font.caption
    static let button = Font.body.weight(.semibold)
    static let metadata = Font.caption.monospacedDigit()
}

nonisolated enum FamiliarRadius {
    static let compact: CGFloat = 10
    static let control: CGFloat = 14
    static let card: CGFloat = 18
    static let overlay: CGFloat = 24
}

nonisolated enum FamiliarIconSize {
    static let compact: CGFloat = 13
    static let standard: CGFloat = 17
    static let prominent: CGFloat = 22
}

nonisolated enum FamiliarControlSize {
    /// Accessibility hit target. Visual content can remain smaller inside it.
    static let minimumHitTarget: CGFloat = 44
    static let compactVisual: CGFloat = 28
    static let standardVisual: CGFloat = 36
    static let prominentVisual: CGFloat = 44
}

/// Kept for renderer call sites that predate the semantic scale.
nonisolated enum AppSpacing {
    static let compact = FamiliarSpacing.small
    static let standard = FamiliarSpacing.medium
    static let card = FamiliarSpacing.large
    static let page = FamiliarSpacing.xLarge
    static let control = FamiliarControlSize.minimumHitTarget
}

struct FamiliarIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(
                minWidth: FamiliarControlSize.minimumHitTarget,
                minHeight: FamiliarControlSize.minimumHitTarget
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(FamiliarMotion.micro, value: configuration.isPressed)
    }
}

struct FamiliarPillButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let prominence: Prominence

    enum Prominence: Equatable {
        case primary
        case secondary
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FamiliarTypography.button)
            .foregroundStyle(prominence == .primary ? Color.white : Color.primary)
            .padding(.horizontal, FamiliarSpacing.large)
            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
            .background(
                prominence == .primary ? FamiliarTheme.accent : FamiliarTheme.elevatedFill,
                in: Capsule()
            )
            .overlay {
                if prominence == .secondary {
                    Capsule().stroke(FamiliarTheme.separator, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(FamiliarMotion.micro, value: configuration.isPressed)
    }
}

private struct FamiliarGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let interactive: Bool
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(FamiliarTheme.separator, lineWidth: 1)
                }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(FamiliarTheme.separator, lineWidth: 1)
                }
        }
    }
}

extension View {
    func familiarGlassSurface(
        interactive: Bool = false,
        cornerRadius: CGFloat = FamiliarRadius.overlay
    ) -> some View {
        modifier(FamiliarGlassSurface(interactive: interactive, cornerRadius: cornerRadius))
    }
}

private struct FamiliarGlassCircle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(FamiliarTheme.elevatedFill, in: Circle())
                .overlay {
                    Circle().stroke(FamiliarTheme.separator, lineWidth: 1)
                }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: .circle)
        } else {
            content
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle().stroke(FamiliarTheme.separator, lineWidth: 1)
                }
        }
    }
}

extension View {
    func familiarGlassCircle(interactive: Bool = false) -> some View {
        modifier(FamiliarGlassCircle(interactive: interactive))
    }
}
