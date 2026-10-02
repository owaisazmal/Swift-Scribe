import UIKit
import CoreText

/// The built-in stickers, drawn as vectors so they stay sharp at any zoom and in exported PDFs. Thread-safe.
enum Sticker: String, CaseIterable, Identifiable, Sendable {
    case star, heart, check, exclaim, question, arrow, flag, ring, underline
    case noteYellow, notePink, noteBlue, tapeMustard, tapeTeal, tapePink, label, bubble
    case stampImportant, stampToDo, stampDone, stampIdea

    var id: String { rawValue }

    enum Family: String, CaseIterable, Identifiable {
        case marks, paper, stamps
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .marks: String(localized: "Marks")
            case .paper: String(localized: "Notes and Tape")
            case .stamps: String(localized: "Stamps")
            }
        }

        var stickers: [Sticker] { Sticker.allCases.filter { $0.family == self } }
    }

    var family: Family {
        switch self {
        case .star, .heart, .check, .exclaim, .question, .arrow, .flag, .ring, .underline: .marks
        case .noteYellow, .notePink, .noteBlue, .tapeMustard, .tapeTeal, .tapePink, .label, .bubble: .paper
        case .stampImportant, .stampToDo, .stampDone, .stampIdea: .stamps
        }
    }

    var displayName: String {
        switch self {
        case .star: String(localized: "Star")
        case .heart: String(localized: "Heart")
        case .check: String(localized: "Check Mark")
        case .exclaim: String(localized: "Exclamation Mark")
        case .question: String(localized: "Question Mark")
        case .arrow: String(localized: "Arrow")
        case .flag: String(localized: "Flag")
        case .ring: String(localized: "Ring")
        case .underline: String(localized: "Highlighter Line")
        case .noteYellow: String(localized: "Yellow Sticky Note")
        case .notePink: String(localized: "Pink Sticky Note")
        case .noteBlue: String(localized: "Blue Sticky Note")
        case .tapeMustard: String(localized: "Mustard Tape")
        case .tapeTeal: String(localized: "Teal Tape")
        case .tapePink: String(localized: "Pink Tape")
        case .label: String(localized: "Label")
        case .bubble: String(localized: "Speech Bubble")
        case .stampImportant: String(localized: "Important Stamp")
        case .stampToDo: String(localized: "To Do Stamp")
        case .stampDone: String(localized: "Done Stamp")
        case .stampIdea: String(localized: "Idea Stamp")
        }
    }

    /// Width over height.
    var aspect: CGFloat {
        switch self {
        case .star, .heart, .check, .exclaim, .question, .flag, .noteYellow, .notePink, .noteBlue: 1
        case .arrow: 100 / 56
        case .ring: 100 / 64
        case .underline: 100 / 22
        case .tapeMustard, .tapeTeal, .tapePink: 100 / 28
        case .label: 100 / 52
        case .bubble: 100 / 78
        case .stampImportant, .stampToDo, .stampDone, .stampIdea: 100 / 36
        }
    }

    /// The size a new one is placed at, in page points.
    var defaultSize: CGSize {
        let width: CGFloat = switch self {
        case .star, .heart, .check, .exclaim, .question, .flag: 64
        case .arrow: 110
        case .ring: 170
        case .underline, .tapeMustard, .tapeTeal, .tapePink: 190
        case .noteYellow, .notePink, .noteBlue: 200
        case .label, .bubble: 220
        case .stampImportant, .stampToDo, .stampDone, .stampIdea: 150
        }
        return CGSize(width: width, height: (width / aspect).rounded())
    }

    func image(width: CGFloat, scale: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: width / aspect)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(in: context.cgContext, rect: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: Drawing

    private static let ink = UIColor(hex: 0x1B2230)
    private static let tomato = UIColor(hex: 0xC9452F)
    private static let mustard = UIColor(hex: 0xE8B023)
    private static let moss = UIColor(hex: 0x3D5A40)
    private static let cobalt = UIColor(hex: 0x2F4DA0)
    private static let cream = UIColor(hex: 0xF7F1E3)

    /// Draws in a y-down context. The art is laid out 100 units wide.
    func draw(in ctx: CGContext, rect: CGRect) {
        let textMatrix = ctx.textMatrix
        ctx.saveGState()
        defer {
            ctx.restoreGState()
            ctx.textMatrix = textMatrix
        }
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / 100, y: rect.width / 100)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        let height = 100 / aspect
        switch self {
        case .star: dieCut(Self.starPath(), fill: Self.mustard, in: ctx)
        case .heart: dieCut(Self.heartPath(), fill: Self.tomato, in: ctx)
        case .check:
            dieCut(CGPath(ellipseIn: CGRect(x: 8, y: 8, width: 84, height: 84), transform: nil), fill: Self.moss, in: ctx)
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(10)
            ctx.addLines(between: [CGPoint(x: 30, y: 52), CGPoint(x: 44, y: 66), CGPoint(x: 70, y: 36)])
            ctx.strokePath()
        case .exclaim:
            dieCut(CGPath(ellipseIn: CGRect(x: 8, y: 8, width: 84, height: 84), transform: nil), fill: Self.tomato, in: ctx)
            glyph("!", size: 62, color: .white, centre: CGPoint(x: 50, y: 50), in: ctx)
        case .question:
            dieCut(CGPath(ellipseIn: CGRect(x: 8, y: 8, width: 84, height: 84), transform: nil), fill: Self.cobalt, in: ctx)
            glyph("?", size: 62, color: .white, centre: CGPoint(x: 50, y: 50), in: ctx)
        case .arrow:
            let path = CGMutablePath()
            path.addLines(between: [CGPoint(x: 10, y: 28), CGPoint(x: 86, y: 28)])
            path.addLines(between: [CGPoint(x: 64, y: 10), CGPoint(x: 88, y: 28), CGPoint(x: 64, y: 46)])
            stroked(path, width: 10, color: Self.cobalt, in: ctx)
        case .flag:
            let pennant = CGMutablePath()
            pennant.addLines(between: [CGPoint(x: 26, y: 12), CGPoint(x: 90, y: 20), CGPoint(x: 72, y: 36), CGPoint(x: 90, y: 54), CGPoint(x: 26, y: 58)])
            pennant.closeSubpath()
            dieCut(pennant, fill: Self.tomato, in: ctx)
            let pole = CGMutablePath()
            pole.addLines(between: [CGPoint(x: 24, y: 10), CGPoint(x: 24, y: 92)])
            stroked(pole, width: 7, color: Self.ink, in: ctx)
        case .ring:
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: 1, startAngle: -1.9, endAngle: 4.2, clockwise: false,
                        transform: CGAffineTransform(translationX: 50, y: height / 2).scaledBy(x: 44, y: height / 2 - 7))
            ctx.addPath(path)
            ctx.setStrokeColor(Self.tomato.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(4.5)
            ctx.strokePath()
        case .underline:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 6, y: 13))
            path.addCurve(to: CGPoint(x: 52, y: 10), control1: CGPoint(x: 20, y: 7), control2: CGPoint(x: 36, y: 15))
            path.addCurve(to: CGPoint(x: 94, y: 10), control1: CGPoint(x: 66, y: 6), control2: CGPoint(x: 80, y: 14))
            ctx.addPath(path)
            ctx.setStrokeColor(Self.mustard.withAlphaComponent(0.75).cgColor)
            ctx.setLineWidth(11)
            ctx.strokePath()
        case .noteYellow: note(UIColor(hex: 0xFFE27A), fold: UIColor(hex: 0xE8C552), in: ctx)
        case .notePink: note(UIColor(hex: 0xF9B9CD), fold: UIColor(hex: 0xE594AE), in: ctx)
        case .noteBlue: note(UIColor(hex: 0xB4D8F3), fold: UIColor(hex: 0x8DBADD), in: ctx)
        case .tapeMustard: tape(Self.mustard, in: ctx)
        case .tapeTeal: tape(UIColor(hex: 0x2FA39A), in: ctx)
        case .tapePink: tape(UIColor(hex: 0xF07FA8), in: ctx)
        case .label:
            let outer = CGRect(x: 3, y: 3, width: 94, height: height - 6)
            dieCut(CGPath(roundedRect: outer, cornerWidth: 3, cornerHeight: 3, transform: nil), fill: Self.cream, in: ctx)
            ctx.setStrokeColor(Self.ink.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(0.9)
            ctx.stroke(outer.insetBy(dx: 4, dy: 4))
            ctx.setLineWidth(0.45)
            ctx.stroke(outer.insetBy(dx: 6, dy: 6))
        case .bubble:
            let path = CGMutablePath()
            path.addRoundedRect(in: CGRect(x: 5, y: 5, width: 90, height: 54), cornerWidth: 16, cornerHeight: 16)
            path.addLines(between: [CGPoint(x: 24, y: 57), CGPoint(x: 18, y: 74), CGPoint(x: 40, y: 57)])
            ctx.addPath(path)
            ctx.setFillColor(Self.cream.cgColor)
            ctx.fillPath()
            let outline = CGMutablePath()
            outline.addRoundedRect(in: CGRect(x: 5, y: 5, width: 90, height: 54), cornerWidth: 16, cornerHeight: 16)
            ctx.addPath(outline)
            ctx.setStrokeColor(Self.ink.cgColor)
            ctx.setLineWidth(2.4)
            ctx.strokePath()
            ctx.setFillColor(Self.cream.cgColor)
            ctx.fill(CGRect(x: 25.5, y: 55, width: 13, height: 6))
            ctx.addLines(between: [CGPoint(x: 24, y: 59), CGPoint(x: 18, y: 74), CGPoint(x: 40, y: 59)])
            ctx.strokePath()
        case .stampImportant: stamp("IMPORTANT", color: Self.tomato, height: height, in: ctx)
        case .stampToDo: stamp("TO DO", color: Self.cobalt, height: height, in: ctx)
        case .stampDone: stamp("DONE", color: Self.moss, height: height, in: ctx)
        case .stampIdea: stamp("IDEA", color: UIColor(hex: 0xA8760B), height: height, in: ctx)
        }
    }

    /// A white border round the shape, like a sticker cut from its sheet.
    private func dieCut(_ path: CGPath, fill: UIColor, in ctx: CGContext) {
        ctx.addPath(path)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(7)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
    }

    private func stroked(_ path: CGPath, width: CGFloat, color: UIColor, in ctx: CGContext) {
        ctx.addPath(path)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(width + 6)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    private func note(_ color: UIColor, fold: UIColor, in ctx: CGContext) {
        let corner: CGFloat = 20
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.1).cgColor)
        ctx.fill(CGRect(x: 6, y: 8, width: 90, height: 90))
        ctx.addLines(between: [CGPoint(x: 4, y: 4), CGPoint(x: 96, y: 4), CGPoint(x: 96, y: 96 - corner), CGPoint(x: 96 - corner, y: 96), CGPoint(x: 4, y: 96)])
        ctx.closePath()
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
        ctx.addLines(between: [CGPoint(x: 96, y: 96 - corner), CGPoint(x: 96 - corner, y: 96), CGPoint(x: 96 - corner, y: 96 - corner)])
        ctx.closePath()
        ctx.setFillColor(fold.cgColor)
        ctx.fillPath()
    }

    private func tape(_ color: UIColor, in ctx: CGContext) {
        let top: CGFloat = 4, bottom: CGFloat = 24
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4, y: top))
        path.addLine(to: CGPoint(x: 96, y: top))
        for (index, y) in stride(from: top, through: bottom, by: 4).enumerated().dropFirst() { path.addLine(to: CGPoint(x: index % 2 == 1 ? 93.5 : 96, y: y)) }
        path.addLine(to: CGPoint(x: 4, y: bottom))
        for (index, y) in stride(from: bottom, through: top, by: -4).enumerated().dropFirst() { path.addLine(to: CGPoint(x: index % 2 == 1 ? 6.5 : 4, y: y)) }
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(color.withAlphaComponent(0.82).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 28))
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.38).cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.butt)
        for x in stride(from: -20 as CGFloat, to: 110, by: 10) {
            ctx.move(to: CGPoint(x: x, y: bottom + 2))
            ctx.addLine(to: CGPoint(x: x + 24, y: top - 2))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func stamp(_ text: String, color: UIColor, height: CGFloat, in ctx: CGContext) {
        let ink = color.withAlphaComponent(0.88)
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(2.6)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 3, y: 3, width: 94, height: height - 6), cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.strokePath()
        ctx.setLineWidth(0.8)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 6.5, y: 6.5, width: 87, height: height - 13), cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
        ctx.strokePath()
        glyph(text, size: 15, color: ink, centre: CGPoint(x: 50, y: height / 2), fitting: 78, kern: 1.6, in: ctx)
    }

    private func glyph(_ text: String, size: CGFloat, color: UIColor, centre: CGPoint, fitting width: CGFloat? = nil, kern: CGFloat = 0, in ctx: CGContext) {
        func line(_ size: CGFloat) -> CTLine {
            let font = UIFont.systemFont(ofSize: size, weight: .heavy) as CTFont
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
                .kern: kern,
            ]
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        }
        var set = line(size)
        if let width {
            let natural = CTLineGetTypographicBounds(set, nil, nil, nil) - Double(kern)
            if natural > Double(width) { set = line(size * width / CGFloat(natural)) }
        }
        let bounds = CTLineGetBoundsWithOptions(set, .useGlyphPathBounds)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.setFillColor(color.cgColor)
        ctx.textPosition = CGPoint(x: centre.x - bounds.midX + kern / 2, y: centre.y + bounds.midY)
        CTLineDraw(set, ctx)
    }

    private static func starPath() -> CGPath {
        let path = CGMutablePath()
        let centre = CGPoint(x: 50, y: 53)
        for index in 0..<10 {
            let radius: CGFloat = index % 2 == 0 ? 42 : 18
            let angle = CGFloat(index) * .pi / 5 - .pi / 2
            let point = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func heartPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 50, y: 88))
        path.addCurve(to: CGPoint(x: 10, y: 38), control1: CGPoint(x: 30, y: 74), control2: CGPoint(x: 10, y: 58))
        path.addCurve(to: CGPoint(x: 50, y: 28), control1: CGPoint(x: 10, y: 12), control2: CGPoint(x: 42, y: 8))
        path.addCurve(to: CGPoint(x: 90, y: 38), control1: CGPoint(x: 58, y: 8), control2: CGPoint(x: 90, y: 12))
        path.addCurve(to: CGPoint(x: 50, y: 88), control1: CGPoint(x: 90, y: 58), control2: CGPoint(x: 70, y: 74))
        path.closeSubpath()
        return path
    }
}

/// Draws everything placed on a page, back to front, in a y-down context scaled to `size`. Thread-safe.
enum PageItemRenderer {
    /// Without `links`, a link shows its own label or a plain "Page": enough for a thumbnail.
    static func draw(_ items: [PageItem], pageSize: CGSize, assets: URL, in ctx: CGContext, size: CGSize, onDark: Bool = false, links: LinkTitles? = nil) {
        guard !items.isEmpty, pageSize.width > 0 else { return }
        let scale = size.width / pageSize.width
        for item in items {
            ctx.saveGState()
            ctx.translateBy(x: item.center.x * scale, y: item.center.y * scale)
            ctx.rotate(by: item.rotation)
            let rect = CGRect(x: -item.size.width * scale / 2, y: -item.size.height * scale / 2, width: item.size.width * scale, height: item.size.height * scale)
            switch item.content {
            case .sticker:
                item.sticker?.draw(in: ctx, rect: rect)
            case .image(let file):
                if let image = image(file, assets: assets) {
                    ctx.translateBy(x: 0, y: rect.maxY + rect.minY)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.interpolationQuality = .high
                    ctx.draw(image, in: rect)
                }
            case .text(let box):
                ctx.scaleBy(x: scale, y: scale)
                box.draw(in: ctx, rect: CGRect(x: -item.size.width / 2, y: -item.size.height / 2, width: item.size.width, height: item.size.height), onDark: onDark)
            case .link(let link):
                let title = links?.title(for: link) ?? (link.label.isEmpty ? String(localized: "Page") : link.label)
                PageLinkArt.draw(title: title, resolved: links?.resolves(link) ?? true, in: ctx, rect: rect)
            case .unknown:
                break
            }
            ctx.restoreGState()
        }
    }

    static func image(_ file: String, assets: URL) -> CGImage? {
        let url = assets.appending(path: file)
        return PageRenderer.images.value(url.path(percentEncoded: false)) {
            UIImage(contentsOfFile: url.path(percentEncoded: false))?.cgImage.map(SharedImage.init)
        }?.image
    }
}
