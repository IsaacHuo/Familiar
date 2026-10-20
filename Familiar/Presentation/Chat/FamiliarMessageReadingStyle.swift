import Foundation
import SwiftUI
import UIKit

nonisolated enum FamiliarMessageReadingStyle {
    static func isShortPlainText(_ text: String) -> Bool {
        guard !text.isEmpty && text.count <= 160 &&
        text.rangeOfCharacter(from: CharacterSet(charactersIn: "\n\r_*`[]<>~#|$=\\")) == nil &&
        text.range(of: "https?://|www\\.|mailto:|^\\s*(?:[-+]|[0-9]+[.)])\\s", options: [.regularExpression, .caseInsensitive]) == nil else { return false }
        // Keep automatic links/emails on the production Markdown interaction path.
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return detector?.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) == nil
    }

    static func startsDay(_ date: Date, after previous: Date?, calendar: Calendar = .current) -> Bool {
        previous.map { !calendar.isDate($0, inSameDayAs: date) } ?? true
    }
}

struct FamiliarMessageTimestamp: View {
    let date: Date
    var body: some View {
        Text(date, style: .time).font(.caption2).foregroundStyle(.secondary)
            .fixedSize().accessibilityLabel(date.formatted(date: .abbreviated, time: .shortened))
    }
}

/// Single-line text shares its last line with the time when the real measured
/// widths fit. Multiline/native selection and complex Markdown keep a safe row.
struct FamiliarTextAndTimeLayout: Layout {
    var lineHeight: CGFloat
    var text: String
    struct Cache { var width: CGFloat?; var result: (CGSize, CGSize, Bool, CGFloat)? }
    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }
    private func metrics(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGSize, CGSize, Bool, CGFloat) {
        guard subviews.count == 2 else { return (.zero, .zero, false, 0) }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 320
        let body = subviews[0].sizeThatFits(.init(width: width, height: nil))
        let time = subviews[1].sizeThatFits(.unspecified)
        let font = UIFont.systemFont(ofSize: lineHeight / UIFont.systemFont(ofSize: 17).lineHeight * 17)
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let manager = NSLayoutManager(), container = NSTextContainer(size: .init(width: max(1, body.width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0; storage.addLayoutManager(manager); manager.addTextContainer(container); manager.ensureLayout(for: container)
        let lastWidth = manager.numberOfGlyphs > 0 ? manager.lineFragmentUsedRect(forGlyphAt: manager.numberOfGlyphs - 1, effectiveRange: nil).width : 0
        let letter = text.unicodeScalars.first { CharacterSet.letters.contains($0) }
        let rtl = letter.map { (0x0590...0x08FF).contains(Int($0.value)) } ?? false
        let inline = !rtl && !text.hasSuffix("\n") && lastWidth + time.width + 8 <= width
        return (body, time, inline, inline ? max(body.width, lastWidth + time.width + 8) : max(body.width, time.width))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let value = metrics(proposal, subviews); cache.width = proposal.width; cache.result = value
        return .init(width: value.3, height: value.2 ? max(value.0.height, value.1.height) : value.0.height + value.1.height + 4)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard subviews.count == 2 else { return }
        let (body, time, inline, _) = cache.width == proposal.width ? (cache.result ?? metrics(proposal, subviews)) : metrics(proposal, subviews)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .init(body))
        subviews[1].place(at: .init(x: bounds.maxX, y: inline ? bounds.minY + max(body.height, time.height) : bounds.maxY), anchor: .bottomTrailing, proposal: .init(time))
    }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
}

struct FamiliarMessageDateDivider: View {
    let date: Date
    var body: some View {
        Text(date, format: .dateTime.year().month().day())
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(FamiliarTheme.elevatedFill, in: Capsule())
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .accessibilityAddTraits(.isHeader)
    }
}
