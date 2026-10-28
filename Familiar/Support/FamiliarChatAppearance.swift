import SwiftUI
import UIKit

/// Telegram-iOS f1dd7a2: PresentationThemeSettings (Classic / system Night),
/// DefaultDay/DarkPresentationTheme and ChatMessageItemCommon. Presentation only.
nonisolated enum FamiliarChatAppearance {
    static func color(_ light: UInt32, _ dark: UInt32, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255,
                           alpha: traits.userInterfaceStyle == .dark ? darkAlpha : 1)
        })
    }

    static let incomingFill = color(0xffffff, 0x1d1d1d, darkAlpha: 0.9)
    static let outgoingTop = color(0xe1ffc7, 0x61bcf9)
    static let outgoingBottom = color(0xe1ffc7, 0x0088ff)
    static let incomingText = color(0x000000, 0xffffff)
    static let outgoingText = color(0x000000, 0xffffff)
    static let incomingTime = color(0x77828c, 0xffffff, darkAlpha: 0.5)
    static let outgoingTime = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.5)
            : UIColor(red: 0, green: 140 / 255, blue: 9 / 255, alpha: 0.8)
    })
    static let link = color(0x004bad, 0xffffff)
    static let serviceFill = Color.black.opacity(0.2)
    static let serviceText = Color.white
    /// ChatMessageItemWidthFill.widthFor and compact.maximumWidthFill.
    static func messageWidth(_ width: CGFloat) -> CGFloat {
        width <= 500 ? max(1, width - 36) : max(1, floor(width * 0.85))
    }
    static let cornerRadius: CGFloat = 16
    static let mergedRadius: CGFloat = 8
    static let mediaCornerRadius: CGFloat = 15
    static let mediaMergedCornerRadius: CGFloat = 7
    /// Separate media viewports use BubbleNeighbour (7pt); the tail-side edge
    /// alone merges between different messages. Shared-content 0pt joins await
    /// a unified media/caption container, rather than faking one across widths.
    static func mediaShape(outgoing: Bool, neighbors: FamiliarMessageNeighbors,
                           contentAbove: Bool, contentBelow: Bool) -> UnevenRoundedRectangle {
        .init(topLeadingRadius: contentAbove || (!outgoing && neighbors.top) ? mediaMergedCornerRadius : mediaCornerRadius,
              bottomLeadingRadius: contentBelow || (!outgoing && neighbors.bottom) ? mediaMergedCornerRadius : mediaCornerRadius,
              bottomTrailingRadius: contentBelow || (outgoing && neighbors.bottom) ? mediaMergedCornerRadius : mediaCornerRadius,
              topTrailingRadius: contentAbove || (outgoing && neighbors.top) ? mediaMergedCornerRadius : mediaCornerRadius,
              style: .continuous)
    }
    static let edgeInset: CGFloat = 3
    static let tailInset: CGFloat = 6
    static let attachmentSpacing: CGFloat = 2
    static let mediaStatusInset: CGFloat = 6
}

nonisolated struct FamiliarMessageNeighbors: Equatable, Hashable {
    var top = false
    var bottom = false
}

extension EnvironmentValues {
    @Entry var familiarMessageNeighbors = FamiliarMessageNeighbors()
    @Entry var familiarOutgoingMessage = false
}

/// Exact upstream pattern, rendered from the bundled fixed-commit .tgv vector.
/// Static system MeshGradient replaces Telegram's node renderer; scrolling does
/// not drive it and no asset is fetched on device.
struct FamiliarChatWallpaper: View {
    @Environment(\.colorScheme) private var scheme
    private var colors: [Color] {
        let values: [UInt32] = scheme == .dark
            ? [0x598bf6, 0x7a5eef, 0xd67cff, 0xf38b58]
            : [0xdbddbb, 0x6ba587, 0xd5d88d, 0x88b884]
        return values.map { FamiliarChatAppearance.color($0, $0) }
    }
    private var gradient: some View {
        MeshGradient(width: 2, height: 2,
            points: [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)], colors: colors)
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if scheme == .dark {
                    Color.black
                    gradient.opacity(0.34)
                    Image("TelegramChatPattern").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    gradient
                    Image("TelegramChatPattern").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blendMode(.softLight).opacity(0.5)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// GPL-3.0 adaptation of TelegramPresentationData/ChatMessageBubbleImages.swift
/// (f1dd7a2, 92–246): 33pt body, 6pt tail, neighbor radii, ellipse subtraction.
/// Only a small alpha mask is cached; no text, view, message or pixel snapshot.
@MainActor private enum FamiliarBubbleMask {
    private struct Key: Hashable {
        let outgoing: Bool
        let neighbors: FamiliarMessageNeighbors
        let scale: CGFloat
    }
    private static var masks: [Key: UIImage] = [:]
    static func image(outgoing: Bool, neighbors: FamiliarMessageNeighbors, scale: CGFloat) -> UIImage {
        let key = Key(outgoing: outgoing, neighbors: neighbors, scale: scale)
        if let image = masks[key] { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: .init(width: 43, height: 37), format: format).image { renderer in
            let context = renderer.cgContext
            if !outgoing { context.translateBy(x: 43, y: 0); context.scaleBy(x: -1, y: 1) }
            context.translateBy(x: 2, y: 2)
            let topRight: CGFloat = neighbors.top ? FamiliarChatAppearance.mergedRadius : FamiliarChatAppearance.cornerRadius
            let bottomRight: CGFloat = neighbors.bottom ? FamiliarChatAppearance.mergedRadius : FamiliarChatAppearance.cornerRadius
            let body = UIBezierPath()
            body.move(to: .init(x: 0, y: 16))
            body.addArc(withCenter: .init(x: 16, y: 16), radius: 16, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
            body.addLine(to: .init(x: 33 - topRight, y: 0))
            body.addArc(withCenter: .init(x: 33 - topRight, y: topRight), radius: topRight, startAngle: .pi * 1.5, endAngle: 0, clockwise: true)
            body.addLine(to: .init(x: 33, y: 33 - bottomRight))
            body.addArc(withCenter: .init(x: 33 - bottomRight, y: 33 - bottomRight), radius: bottomRight, startAngle: 0, endAngle: .pi * 0.5, clockwise: true)
            body.addLine(to: .init(x: 16, y: 33))
            body.addArc(withCenter: .init(x: 16, y: 17), radius: 16, startAngle: .pi * 0.5, endAngle: .pi, clockwise: true)
            body.close()
            UIColor.black.setFill(); body.fill()
            if !neighbors.bottom {
                let tail = UIBezierPath()
                tail.move(to: .init(x: 24, y: 24.5))
                tail.addQuadCurve(to: .init(x: 37.5, y: 33), controlPoint: .init(x: 24, y: 33))
                tail.addQuadCurve(to: .init(x: 51, y: 24.5), controlPoint: .init(x: 51, y: 33))
                tail.fill()
                context.fill(CGRect(x: 16.5, y: 16, width: 16.5, height: 9))
                context.setBlendMode(.clear)
                context.fillEllipse(in: .init(x: 33, y: 14, width: 23, height: 21))
            }
        }
        masks[key] = image
        return image
    }
}

struct FamiliarMessageBubbleBackground: View {
    @Environment(\.displayScale) private var scale
    @Environment(\.familiarMessageNeighbors) private var neighbors
    @Environment(\.colorSchemeContrast) private var contrast
    let isUser: Bool
    var body: some View {
        // SwiftUI's zero-inset resizable() stretches the entire UIImage, even
        // when UIKit cap insets were set. Keep the 1pt stretch center explicit.
        let left: CGFloat = isUser ? 18 : 24
        let mask = Image(uiImage: FamiliarBubbleMask.image(outgoing: isUser, neighbors: neighbors, scale: max(1, scale)))
            .renderingMode(.template)
            .resizable(capInsets: .init(top: 19, leading: left, bottom: 17, trailing: 42 - left), resizingMode: .stretch)
        Group {
            if isUser {
                LinearGradient(colors: [FamiliarChatAppearance.outgoingTop, FamiliarChatAppearance.outgoingBottom], startPoint: .top, endPoint: .bottom)
            } else { FamiliarChatAppearance.incomingFill }
        }
        .mask(mask)
        .overlay {
            if contrast == .increased { mask.foregroundStyle(FamiliarTheme.ink.opacity(0.12)).blendMode(.plusDarker) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FamiliarMessageBubble: ViewModifier {
    @Environment(\.displayScale) private var scale
    let isUser: Bool
    func body(content: Content) -> some View {
        content
            .environment(\.familiarOutgoingMessage, isUser)
            .foregroundStyle(isUser ? FamiliarChatAppearance.outgoingText : FamiliarChatAppearance.incomingText)
            .padding(.horizontal, 11)
            .padding(.top, 6 + 1 / max(1, scale))
            .padding(.bottom, 6 - 1 / max(1, scale))
            .padding(isUser ? .trailing : .leading, FamiliarChatAppearance.tailInset)
            .frame(minWidth: 40, minHeight: 35, alignment: .leading)
            .background { FamiliarMessageBubbleBackground(isUser: isUser) }
    }
}

extension View {
    func familiarMessageBubble(isUser: Bool) -> some View {
        modifier(FamiliarMessageBubble(isUser: isUser))
    }
}
