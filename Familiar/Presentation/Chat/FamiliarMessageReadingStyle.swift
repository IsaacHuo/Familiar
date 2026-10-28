import Foundation
import CoreText
import SwiftUI
import UIKit

nonisolated enum FamiliarMessageReadingStyle {
    /// Length and plain paragraph breaks do not require a WebView. Keep the
    /// gate conservative so Markdown structure and detected links retain theirs.
    static func canUseNativeText(_ text: String) -> Bool {
        let richSyntax = #"(?m)https?://|www\.|mailto:|^\s*(?:[-+]|[0-9]+[.)])\s|^[\t ]*[+-]+[\t ]*\r?$|^(?: {4}|\t)"#
        guard !text.isEmpty,
              text.rangeOfCharacter(from: CharacterSet(charactersIn: "_*`[]<>~#|$=\\")) == nil,
              text.range(of: richSyntax, options: [.regularExpression, .caseInsensitive]) == nil else { return false }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return detector?.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) == nil
    }

    static func hasRightToLeftRun(_ text: String) -> Bool {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text) as CFAttributedString)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        return runs.contains { CTRunGetStatus($0).contains(.rightToLeft) }
    }

    static func startsDay(_ date: Date, after previous: Date?, calendar: Calendar = .current) -> Bool {
        previous.map { !calendar.isDate($0, inSameDayAs: date) } ?? true
    }
}

struct FamiliarMessageTimestamp: View {
    @Environment(\.familiarOutgoingMessage) private var outgoing
    @ScaledMetric(relativeTo: .body) private var timeSize: CGFloat = 11
    let date: Date
    var onMedia = false
    var body: some View {
        Text(date, style: .time).font(.system(size: floor(timeSize))).foregroundStyle(onMedia ? FamiliarChatAppearance.serviceText : outgoing ? FamiliarChatAppearance.outgoingTime : FamiliarChatAppearance.incomingTime)
            .fixedSize().accessibilityLabel(date.formatted(date: .abbreviated, time: .shortened))
    }
}

/// Telegram measures the trailing text line before settling the status width.
/// Keep the native child's width-only proposal identical in measure and place;
/// imposing a measured height during placement re-enters TextKit under new constraints.
struct FamiliarTextAndTimeLayout: Layout {
    var fontSize: CGFloat
    var text: String

    struct Measurement {
        let textSize: CGSize
        let timeSize: CGSize
        let textProposal: ProposedViewSize
        let isInline: Bool
        let size: CGSize

        init(textSize: CGSize, timeSize: CGSize, availableWidth: CGFloat,
             lastLineWidth: CGFloat, requiresSeparateLine: Bool) {
            self.textSize = textSize
            self.timeSize = timeSize
            textProposal = .init(width: availableWidth, height: nil)
            isInline = !requiresSeparateLine && lastLineWidth + timeSize.width + 8 <= availableWidth
            size = .init(width: max(textSize.width, isInline ? lastLineWidth + timeSize.width + 8 : timeSize.width),
                         height: isInline ? max(textSize.height, timeSize.height) : textSize.height + timeSize.height + 4)
        }
    }

    struct Cache {
        var width: CGFloat?
        var fontSize: CGFloat?
        var text: String?
        var timeSize: CGSize?
        var measurement: Measurement?
    }
    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    private func measure(_ proposal: ProposedViewSize, _ subviews: Subviews, cache: inout Cache) -> Measurement {
        let width = max(0, proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 320)
        let time = subviews[1].sizeThatFits(.unspecified)
        if cache.width == width, cache.fontSize == fontSize, cache.text == text,
           cache.timeSize == time, let measured = cache.measurement { return measured }

        let body = subviews[0].sizeThatFits(.init(width: width, height: nil))
        let storage = NSTextStorage(string: text, attributes: [.font: UIFont.systemFont(ofSize: fontSize)])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .init(width: max(1, body.width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        var lastGlyphs = NSRange(location: 0, length: 0)
        let lastWidth = manager.numberOfGlyphs > 0
            ? manager.lineFragmentUsedRect(forGlyphAt: manager.numberOfGlyphs - 1, effectiveRange: &lastGlyphs).width : 0
        let characters = manager.characterRange(forGlyphRange: lastGlyphs, actualGlyphRange: nil)
        let lastLine = (text as NSString).substring(with: characters)
        let standalone = text.last?.isNewline == true || FamiliarMessageReadingStyle.hasRightToLeftRun(lastLine)
        let value = Measurement(textSize: body, timeSize: time, availableWidth: width,
                                lastLineWidth: lastWidth, requiresSeparateLine: standalone)
        cache.width = width; cache.fontSize = fontSize; cache.text = text
        cache.timeSize = time; cache.measurement = value
        return value
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        if let width = proposal.width, width <= 0 { return .zero }
        return measure(proposal, subviews, cache: &cache).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard subviews.count == 2, bounds.width > 0 else { return }
        if let width = proposal.width, width <= 0 { return }
        let value = measure(proposal, subviews, cache: &cache)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: value.textProposal)
        let timeY = value.isInline ? bounds.minY + max(value.textSize.height, value.timeSize.height) : bounds.maxY
        subviews[1].place(at: .init(x: bounds.maxX, y: timeY), anchor: .bottomTrailing, proposal: .unspecified)
    }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
}

struct FamiliarMessageDateDivider: View {
    @ScaledMetric(relativeTo: .body) private var dateSize: CGFloat = 13
    let date: Date
    private var label: String {
        if Calendar.current.isDateInToday(date) { return String(localized: "message.date.today") }
        let currentYear = Calendar.current.component(.year, from: Date())
        if Calendar.current.component(.year, from: date) == currentYear {
            return date.formatted(.dateTime.month().day())
        }
        return date.formatted(.dateTime.year().month().day())
    }
    var body: some View {
        Text(label)
            .font(.system(size: min(18, floor(dateSize)), weight: .medium)).foregroundStyle(FamiliarChatAppearance.serviceText)
            .padding(.horizontal, 6).frame(minHeight: 22)
            .background(FamiliarChatAppearance.serviceFill, in: Capsule())
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .accessibilityAddTraits(.isHeader)
    }
}
