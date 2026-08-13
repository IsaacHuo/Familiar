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
    static let assistantFill = Color(uiColor: .secondarySystemBackground)
    static let userFill = Color(uiColor: .tertiarySystemFill)
    static let elevatedFill = Color(uiColor: .secondarySystemBackground)
    static let drawerFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .secondarySystemBackground
            : UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
    })
    static let separator = Color.primary.opacity(0.10)
}

nonisolated enum AppSpacing {
    static let compact: CGFloat = 8
    static let standard: CGFloat = 12
    static let card: CGFloat = 16
    static let page: CGFloat = 20
    static let control: CGFloat = 44
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
    func familiarGlassSurface(interactive: Bool = false, cornerRadius: CGFloat = 22) -> some View {
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
