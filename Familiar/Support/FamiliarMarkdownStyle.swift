import SwiftUI
import UIKit

/// The bundled renderer receives the same semantic colors and Dynamic Type as
/// native content. This is presentation input, never model-controlled CSS.
@MainActor
enum FamiliarMarkdownStyle {
    static func json(colorScheme: ColorScheme, size: DynamicTypeSize, contrast: ColorSchemeContrast) -> String {
        let traits = UITraitCollection(mutations: {
            $0.userInterfaceStyle = colorScheme == .dark ? .dark : .light
            $0.preferredContentSizeCategory = category(size)
            $0.accessibilityContrast = contrast == .increased ? .high : .normal
        })
        func color(_ value: Color) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(value).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "rgba(%d,%d,%d,%.3f)", locale: Locale(identifier: "en_US_POSIX"),
                          Int(r * 255), Int(g * 255), Int(b * 255), Double(a))
        }
        let colors: [String: Color] = [
            "ink": Color(uiColor: .label), "secondary": Color(uiColor: .secondaryLabel), "tertiary": FamiliarTheme.inkTertiary,
            "surface": FamiliarTheme.surface, "inset": FamiliarTheme.inset, "line": FamiliarTheme.line,
            "line-strong": FamiliarTheme.lineStrong, "accent": FamiliarTheme.accent, "accent-tint": FamiliarTheme.accentTint,
            "code-fill": FamiliarTheme.userFill, "success": FamiliarTheme.success, "failure": FamiliarTheme.failure,
            "warning": FamiliarTheme.warning, "keyword": Color(uiColor: .systemPurple)
        ]
        var variables = Dictionary(uniqueKeysWithValues: colors.map { ("--familiar-" + $0.key, color($0.value)) })
        variables["--familiar-body-size"] = "\(UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits).pointSize)px"
        variables["--familiar-caption-size"] = "\(UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits).pointSize)px"
        variables["--familiar-radius-compact"] = "\(FamiliarRadius.compact)px"
        variables["--familiar-radius-control"] = "\(FamiliarRadius.control)px"
        variables["--familiar-width"] = "\(FamiliarAISurfaceMetric.timelineWidth)px"
        variables["--familiar-content-duration"] = "\(FamiliarMotion.contentAppearDuration * 1000)ms"
        variables["--familiar-content-offset"] = "\(FamiliarMotion.contentAppearOffset)px"
        let data = try? JSONSerialization.data(withJSONObject: variables, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private static func category(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
