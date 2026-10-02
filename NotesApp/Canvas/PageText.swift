import UIKit

extension TextBox.Tint {
    var displayName: String {
        switch self {
        case .ink: String(localized: "Ink")
        case .tomato: String(localized: "Tomato")
        case .cobalt: String(localized: "Cobalt")
        case .moss: String(localized: "Moss")
        case .plum: String(localized: "Plum")
        }
    }

    /// Lighter on Charcoal and Chalkboard, so typed text stays readable there.
    func color(onDark: Bool) -> UIColor {
        switch self {
        case .ink: UIColor(hex: onDark ? 0xF7F1E3 : 0x1B2230)
        case .tomato: UIColor(hex: onDark ? 0xFF9A86 : 0xC9452F)
        case .cobalt: UIColor(hex: onDark ? 0xA6BBFF : 0x2F4DA0)
        case .moss: UIColor(hex: onDark ? 0xA9D6AD : 0x3D5A40)
        case .plum: UIColor(hex: onDark ? 0xE5B1DB : 0x5A2F52)
        }
    }
}

extension TextBox.Alignment {
    var displayName: String {
        switch self {
        case .leading: String(localized: "Left")
        case .center: String(localized: "Centre")
        case .trailing: String(localized: "Right")
        }
    }

    var symbol: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }

    var textAlignment: NSTextAlignment {
        switch self {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
    }
}

/// Laying out and drawing typed text, the same way in the editor, thumbnails and exported PDFs. Thread-safe.
extension TextBox {
    static let sizes: [(name: String, points: CGFloat)] = [
        (String(localized: "Small"), 13), (String(localized: "Body"), 17), (String(localized: "Large"), 24), (String(localized: "Title"), 34),
    ]

    func font(scale: CGFloat = 1) -> UIFont {
        .systemFont(ofSize: fontSize * scale, weight: isBold ? .bold : .regular)
    }

    private func attributed(_ string: String, color: UIColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment.textAlignment
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: string, attributes: [.font: font(), .foregroundColor: color, .paragraphStyle: paragraph])
    }

    /// An empty box, or one ending in a return, is as tall as the line the caret sits on.
    func height(width: CGFloat) -> CGFloat {
        let measured = string.isEmpty || string.hasSuffix("\n") ? string + " " : string
        let bounds = attributed(measured, color: .black).boundingRect(with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
                                                                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return max(bounds.height, font().lineHeight).rounded(.up)
    }

    /// The width its longest line wants, for a box that hasn't been given one.
    func naturalWidth(limit: CGFloat) -> CGFloat {
        let bounds = attributed(string, color: .black).boundingRect(with: CGSize(width: limit, height: .greatestFiniteMagnitude),
                                                                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return min(bounds.width.rounded(.up) + 2, limit)
    }

    /// Draws in page points, in a y-down context.
    func draw(in ctx: CGContext, rect: CGRect, onDark: Bool) {
        guard !string.isEmpty else { return }
        UIGraphicsPushContext(ctx)
        attributed(string, color: tint.color(onDark: onDark)).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        UIGraphicsPopContext()
    }
}

/// What a link calls the page it opens: its own label, the page's bookmark name, or the page number.
struct LinkTitles: Sendable, Equatable {
    private var titles: [UUID: String] = [:]

    init(pages: [NotebookPage] = []) {
        for (index, page) in pages.enumerated() {
            titles[page.id] = page.bookmark.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Page \(index + 1)")
        }
    }

    func resolves(_ link: PageLink) -> Bool { titles[link.target] != nil }

    func title(for link: PageLink) -> String {
        link.label.isEmpty ? titles[link.target] ?? String(localized: "Missing page") : link.label
    }
}

/// The index tab a link is drawn as. Thread-safe.
enum PageLinkArt {
    static let height: CGFloat = 30
    private static let ink = UIColor(hex: 0x1B2230)
    private static let cream = UIColor(hex: 0xF7F1E3)
    private static let mustard = UIColor(hex: 0xE8B023)
    private static let faded = UIColor(hex: 0xB9B4A8)

    private static func label(_ title: String, size: CGFloat, color: UIColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color,
                                                              .paragraphStyle: paragraph])
    }

    /// The size a new link is placed at, wide enough for its title.
    static func size(for title: String) -> CGSize {
        let text = label(title, size: 14, color: ink).size().width.rounded(.up)
        return CGSize(width: min(max(height + 8 + text + 12, 84), 320), height: height)
    }

    /// Draws in a y-down context. The tab is as wide as the chip is tall; the title shrinks before it is cut short.
    static func draw(title: String, resolved: Bool, in ctx: CGContext, rect: CGRect) {
        let unit = rect.height / height
        let chip = CGPath(roundedRect: rect.insetBy(dx: unit, dy: unit), cornerWidth: 6 * unit, cornerHeight: 6 * unit, transform: nil)
        ctx.saveGState()
        ctx.addPath(chip)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2 * unit)
        ctx.strokePath()
        ctx.addPath(chip)
        ctx.clip()
        ctx.setFillColor(cream.cgColor)
        ctx.fill(rect)
        let tab = CGRect(x: rect.minX, y: rect.minY, width: rect.height, height: rect.height)
        ctx.setFillColor((resolved ? mustard : faded).cgColor)
        ctx.fill(tab)
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(2.2 * unit)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let y = tab.midY
        ctx.addLines(between: [CGPoint(x: tab.minX + 9.5 * unit, y: y), CGPoint(x: tab.maxX - 9 * unit, y: y)])
        ctx.addLines(between: [CGPoint(x: tab.maxX - 14 * unit, y: y - 5 * unit), CGPoint(x: tab.maxX - 9 * unit, y: y), CGPoint(x: tab.maxX - 14 * unit, y: y + 5 * unit)])
        ctx.strokePath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(chip)
        ctx.setStrokeColor(ink.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(unit)
        ctx.strokePath()
        ctx.restoreGState()

        let room = rect.maxX - tab.maxX - 18 * unit
        guard room > 4 else { return }
        var size = 14 * unit
        let natural = label(title, size: size, color: ink).size().width
        if natural > room { size *= max(room / natural, 0.7) }
        let text = label(title, size: size, color: resolved ? ink : ink.withAlphaComponent(0.6))
        let line = text.size().height
        UIGraphicsPushContext(ctx)
        text.draw(with: CGRect(x: tab.maxX + 8 * unit, y: rect.midY - line / 2, width: room, height: line),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        UIGraphicsPopContext()
    }
}

extension PageItem {
    /// The upright rectangle that holds the item however it is turned.
    var boundingBox: CGRect {
        let w = abs(size.width * cos(rotation)) + abs(size.height * sin(rotation))
        let h = abs(size.width * sin(rotation)) + abs(size.height * cos(rotation))
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    }
}
