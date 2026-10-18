import SwiftUI

/// Brand identity for a model provider. Built-in providers show their real brand
/// mark — colored marks keep their brand colors, monochrome marks render as
/// templates so they follow the interface style — while custom endpoints keep a
/// protocol-symbol fallback. Marks identify the service the user selected and are
/// never used as a data source.
struct FamiliarProviderIcon: View {
    let provider: FamiliarProviderDescriptor
    var size: CGFloat = 36

    private enum Kind {
        case brand(asset: String, color: Color, template: Bool)
        case symbol(name: String, color: Color)
    }

    private var kind: Kind {
        switch provider.baseURL.host {
        case "api.deepseek.com":
            .brand(asset: "ProviderDeepSeek", color: Color(red: 0.30, green: 0.42, blue: 1.00), template: false)
        case "api.moonshot.cn", "api.kimi.com":
            .brand(asset: "ProviderKimi", color: Color(red: 0.09, green: 0.51, blue: 1.00), template: true)
        case "openrouter.ai":
            .brand(asset: "ProviderOpenRouter", color: Color(red: 0.78, green: 1.00, blue: 0.00), template: false)
        case "generativelanguage.googleapis.com":
            .brand(asset: "ProviderGemini", color: Color(red: 0.19, green: 0.53, blue: 1.00), template: true)
        case "api.x.ai":
            .brand(asset: "ProviderXAI", color: .gray, template: true)
        case "api.openai.com", "chatgpt.com":
            .brand(asset: "ProviderOpenAI", color: Color(red: 0.06, green: 0.64, blue: 0.50), template: true)
        case "api.anthropic.com":
            .brand(asset: "ProviderAnthropic", color: Color(red: 0.85, green: 0.47, blue: 0.34), template: true)
        default:
            switch provider.protocolKind {
            case .anthropic: .symbol(name: "sparkles", color: .purple)
            case .gemini: .symbol(name: "diamond", color: .blue)
            case .openAIResponses: .symbol(name: "arrow.triangle.2.circlepath", color: .mint)
            case .openAIChat: .symbol(name: "circle.hexagongrid", color: .green)
            }
        }
    }

    var body: some View {
        Group {
            switch kind {
            case .brand(let asset, let color, let template):
                Image(asset)
                    .renderingMode(template ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
                    .frame(width: size * 0.56, height: size * 0.56)
                    .frame(width: size, height: size)
                    .background(
                        color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: FamiliarRadius.compact, style: .continuous)
                    )
            case .symbol(let name, let color):
                Image(systemName: name)
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(color)
                    .frame(width: size, height: size)
                    .background(
                        color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: FamiliarRadius.compact, style: .continuous)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}
