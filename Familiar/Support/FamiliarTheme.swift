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
