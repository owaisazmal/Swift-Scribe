import CoreGraphics
import CoreText

enum IconVariant: String, CaseIterable {
    case light, dark, tinted
}

enum IconCloth: String, CaseIterable {
    case cobalt, tomato, moss, oxblood, mustard, print

    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var setName: String { self == .cobalt ? "AppIcon" : "AppIcon-\(name)" }
}

/// The Clothbound app icon, drawn in a 1024-unit square: a cloth notebook with a cream label, page block and ribbon.
enum IconArt {
    static let book = CGRect(x: 512 - 260, y: 470 - 347, width: 520, height: 694)
    /// The book is laid out at 520 × 694 and drawn a little larger, so it holds its own beside full-bleed icons.
    static let zoom: CGFloat = 1.08

    static func draw(in ctx: CGContext, size: CGFloat, variant: IconVariant, cloth: IconCloth) {
        let scale = size / 1024
        let palette = Palette(variant: variant, cloth: cloth)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size)
        ctx.scaleBy(x: scale, y: -scale)

        if let desk = palette.desk { drawDesk(ctx, desk) }
        ctx.translateBy(x: book.midX, y: book.midY)
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -book.midX, y: -book.midY)
        drawRibbon(ctx, palette)
        drawBook(ctx, palette, scale: scale * zoom)
        ctx.restoreGState()
    }

    // MARK: Parts

    private static let front = CGRect(x: book.minX, y: book.minY, width: book.width - 29, height: book.height - 21)
    private static let pages = CGRect(x: book.minX + 40, y: book.minY + 8, width: book.width - 47, height: book.height - 15)

    private static func drawDesk(_ ctx: CGContext, _ desk: Desk) {
        ctx.setFillColor(desk.base)
        ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let gradient = CGGradient(colorsSpace: sRGB, colors: [desk.light, desk.base, desk.shade] as CFArray, locations: [0, 0.55, 1])!
        ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 512, y: 360), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 360), endRadius: 820, options: [.drawsAfterEndLocation])
    }

    private static func drawRibbon(_ ctx: CGContext, _ palette: Palette) {
        let width: CGFloat = 72, length: CGFloat = 320
        let rect = CGRect(x: book.minX + book.width * 0.7 - width / 2, y: book.maxY + 110 - length, width: width, height: length)
        let path = ribbonPath(rect)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(palette.ribbon)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.clip()
        ctx.setStrokeColor(gray(0, 0.07))
        ctx.setLineWidth(2)
        var y = rect.minY
        while y < rect.maxY {
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += 7
        }
        ctx.strokePath()
        let fold = CGGradient(colorsSpace: sRGB, colors: [gray(0, 0.14), gray(0, 0), gray(1, 0.08), gray(0, 0.1)] as CFArray,
                              locations: [0, 0.3, 0.55, 1])!
        ctx.drawLinearGradient(fold, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
        ctx.addPath(path)
        ctx.setStrokeColor(palette.ribbonEdge)
        ctx.setLineWidth(9)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawBook(_ ctx: CGContext, _ palette: Palette, scale: CGFloat) {
        let silhouette = roundedBook(book, spine: 12, edge: 26)
        ctx.setFillColor(palette.board)
        if palette.shadow {
            for (offset, blur, alpha) in [(18.0, 36.0, 0.22), (3.0, 6.0, 0.18)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -offset * scale), blur: blur * scale, color: rgb(0x2A2016, alpha))
                ctx.addPath(silhouette)
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
        ctx.addPath(silhouette)
        ctx.fillPath()

        drawPages(ctx, palette)

        let cover = roundedBook(front, spine: 12, edge: 22)
        ctx.saveGState()
        ctx.addPath(silhouette)
        ctx.clip()
        ctx.setShadow(offset: CGSize(width: 3 * scale, height: -3 * scale), blur: 7 * scale, color: gray(0, palette.variant == .light ? 0.3 : 0.4))
        ctx.addPath(cover)
        ctx.setFillColor(palette.cloth)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(cover)
        ctx.clip()
        if palette.isPrint {
            drawPrintPattern(ctx, palette)
        } else {
            drawWeave(ctx)
        }
        let light = CGGradient(colorsSpace: sRGB, colors: [gray(1, 0.07), gray(1, 0), gray(0, 0.08)] as CFArray, locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(light, start: CGPoint(x: front.minX, y: front.minY), end: CGPoint(x: front.maxX, y: front.maxY), options: [])
        drawSpine(ctx)
        ctx.addPath(cover)
        ctx.setStrokeColor(gray(0, palette.isPrint ? 0.22 : 0.12))
        ctx.setLineWidth(4)
        ctx.strokePath()
        ctx.restoreGState()

        if palette.isPrint {
            drawKnockout(ctx, palette)
        } else {
            drawLabel(ctx, palette, scale: scale)
        }
    }

    private static func drawPages(_ ctx: CGContext, _ palette: Palette) {
        let path = roundedBook(pages, spine: 0, edge: 16)
        ctx.addPath(path)
        ctx.setFillColor(palette.pages)
        ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setStrokeColor(palette.leaves)
        ctx.setLineWidth(2.5)
        for step in 1...3 {
            let dx = 22 * CGFloat(step) / 4, dy = 14 * CGFloat(step) / 4
            let right = pages.maxX - dx, bottom = pages.maxY - dy, radius = max(4, 16 - dx * 0.6)
            ctx.move(to: CGPoint(x: right, y: pages.minY))
            ctx.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: pages.minX, y: bottom), radius: radius)
            ctx.addLine(to: CGPoint(x: pages.minX, y: bottom))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawWeave(_ ctx: CGContext) {
        let period: CGFloat = 14
        ctx.setLineWidth(6)
        for (color, direction) in [(gray(1, 0.05), 1.0), (gray(0, 0.06), -1.0)] as [(CGColor, CGFloat)] {
            ctx.setStrokeColor(color)
            var offset = front.minX - front.height
            while offset < front.maxX + front.height {
                if direction > 0 {
                    ctx.move(to: CGPoint(x: offset, y: front.minY))
                    ctx.addLine(to: CGPoint(x: offset + front.height, y: front.maxY))
                } else {
                    ctx.move(to: CGPoint(x: offset + front.height, y: front.minY))
                    ctx.addLine(to: CGPoint(x: offset, y: front.maxY))
                }
                offset += period
            }
            ctx.strokePath()
        }
    }

    private static func drawSpine(_ ctx: CGContext) {
        let spine = CGRect(x: front.minX, y: front.minY, width: book.width * 0.08, height: front.height)
        let shade = CGGradient(colorsSpace: sRGB, colors: [gray(0, 0.42), gray(0, 0.2), gray(1, 0.04), gray(0, 0.16), gray(0, 0.3)] as CFArray,
                               locations: [0, 0.3, 0.55, 0.85, 1])!
        ctx.saveGState()
        ctx.clip(to: spine)
        ctx.drawLinearGradient(shade, start: CGPoint(x: spine.minX, y: 0), end: CGPoint(x: spine.maxX, y: 0), options: [])
        ctx.restoreGState()
        let hinge = front.minX + book.width * 0.11
        ctx.setFillColor(gray(0, 0.26))
        ctx.fill(CGRect(x: hinge - 2, y: front.minY, width: 4, height: front.height))
        ctx.setFillColor(gray(1, 0.12))
        ctx.fill(CGRect(x: hinge + 2, y: front.minY, width: 2.5, height: front.height))
    }

    private static var labelRect: CGRect {
        CGRect(x: book.minX + book.width * 0.17, y: book.minY + book.height * 0.22,
               width: book.width * (0.91 - 0.17), height: book.height * (0.62 - 0.22))
    }

    private static func drawLabel(_ ctx: CGContext, _ palette: Palette, scale: CGFloat) {
        let label = labelRect
        ctx.saveGState()
        if palette.shadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -2 * scale), blur: 4 * scale, color: rgb(0x1B2230, 0.25))
        }
        ctx.setFillColor(palette.label)
        ctx.fill(label)
        ctx.restoreGState()
        ctx.setStrokeColor(palette.rule(0.3))
        ctx.setLineWidth(3)
        ctx.stroke(label.insetBy(dx: 5, dy: 5))
        ctx.setStrokeColor(palette.rule(0.18))
        ctx.setLineWidth(2)
        ctx.stroke(label.insetBy(dx: 14, dy: 14))
        drawLetter(ctx, font: IconFonts.coverLabel(size: 300), color: palette.letter,
                   centre: CGPoint(x: label.midX, y: label.midY - label.height * 0.012))
    }

    // MARK: Print

    private static func drawPrintPattern(_ ctx: CGContext, _ palette: Palette) {
        ctx.saveGState()
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(palette.yellow)
        let cell: CGFloat = 30
        let direction = CGPoint(x: -0.34, y: 0.94)
        var y = front.minY + cell / 2
        while y < front.maxY + cell {
            var x = front.minX + cell / 2
            while x < front.maxX + cell {
                let t = ((x - front.midX) * direction.x + (y - front.midY) * direction.y) / (front.height * 0.75) + 0.55
                let radius = cell * 0.5 * max(0, min(1, t))
                if radius > cell * 0.06 {
                    ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }
                x += cell
            }
            y += cell
        }
        ctx.translateBy(x: 2.5, y: -2)
        ctx.setFillColor(palette.pink)
        let radius = front.width * 0.44
        let centre = CGPoint(x: front.minX + front.width * 0.7, y: front.minY + front.height * 0.3)
        ctx.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        ctx.restoreGState()
    }

    private static func drawKnockout(_ ctx: CGContext, _ palette: Palette) {
        let font = IconFonts.printTitle(size: 340)
        let line = letterLine(font: font, color: palette.letter)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let pad: CGFloat = 30
        let label = labelRect
        let box = CGRect(x: label.minX, y: label.midY - ink.height / 2 - pad, width: ink.width + pad * 2, height: ink.height + pad * 2)
        ctx.setFillColor(palette.paperStock)
        ctx.fill(box)
        drawLetter(ctx, font: font, color: palette.letter, centre: CGPoint(x: box.midX, y: box.midY))
    }

    // MARK: Helpers

    private static func letterLine(font: CTFont, color: CGColor) -> CTLine {
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "S" as CFString, attributes))
    }

    private static func drawLetter(_ ctx: CGContext, font: CTFont, color: CGColor, centre: CGPoint) {
        let line = letterLine(font: font, color: color)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.saveGState()
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: -ink.midX, y: -ink.midY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    static func ribbonPath(_ rect: CGRect, notch: CGFloat = 0.28) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY),
                                CGPoint(x: rect.midX, y: rect.maxY - rect.width * notch), CGPoint(x: rect.minX, y: rect.maxY)])
        path.closeSubpath()
        return path
    }

    /// A board with tight corners on the spine side and softer ones on the fore-edge.
    static func roundedBook(_ rect: CGRect, spine: CGFloat, edge: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + spine, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: edge)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: edge)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: spine)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: spine)
        path.closeSubpath()
        return path
    }
}

// MARK: Colour

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                           CGFloat(hex & 0xFF) / 255, alpha])!
}

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [white, white, white, alpha])!
}

private struct Desk {
    var base: CGColor
    var light: CGColor
    var shade: CGColor
}

private struct Palette {
    var variant: IconVariant
    var desk: Desk?
    var cloth: CGColor
    var board: CGColor
    var pages: CGColor
    var leaves: CGColor
    var label: CGColor
    var letter: CGColor
    var ribbon: CGColor
    var ribbonEdge: CGColor
    var paperStock: CGColor
    var pink: CGColor
    var yellow: CGColor
    private var ruleBase: CGColor

    var isPrint: Bool
    var shadow: Bool { variant == .light }

    func rule(_ alpha: CGFloat) -> CGColor { ruleBase.copy(alpha: alpha * (variant == .tinted ? 1.6 : 1))! }

    init(variant: IconVariant, cloth: IconCloth) {
        self.variant = variant
        isPrint = cloth == .print
        switch variant {
        case .light:
            desk = Desk(base: rgb(0xE7E2D7), light: rgb(0xEEEAE1), shade: rgb(0xDDD6C8))
            paperStock = rgb(0xF7F4EC)
            self.cloth = isPrint ? paperStock : rgb(cloth.lightHex)
            board = isPrint ? rgb(0x1C1C21) : rgb(cloth.boardHex)
            pages = rgb(0xF7F1E3)
            leaves = rgb(0x8A7A5C, 0.4)
            label = rgb(0xF7F1E3)
            letter = isPrint ? rgb(0x1C1C21) : rgb(0x1B2230)
            ribbon = rgb(cloth.ribbonHex(dark: false))
            ribbonEdge = rgb(0xF7F1E3)
            pink = rgb(0xFF48B0)
            yellow = rgb(0xFFE800)
            ruleBase = rgb(0x1B2230)
        case .dark:
            desk = nil
            paperStock = rgb(0xDEDBD3)
            self.cloth = isPrint ? paperStock : rgb(cloth.darkHex)
            board = isPrint ? rgb(0x2A2A31) : rgb(cloth.darkBoardHex)
            pages = rgb(0xD9D0BC)
            leaves = rgb(0x6E6250, 0.45)
            label = rgb(0xE9E1CE)
            letter = isPrint ? rgb(0x1C1C21) : rgb(0x1B2230)
            ribbon = rgb(cloth.ribbonHex(dark: true))
            ribbonEdge = rgb(0xE9E1CE)
            pink = rgb(0xFF48B0)
            yellow = rgb(0xFFE800)
            ruleBase = rgb(0x1B2230)
        case .tinted:
            desk = nil
            paperStock = gray(0.96)
            self.cloth = isPrint ? paperStock : gray(0.52)
            board = gray(isPrint ? 0.2 : 0.3)
            pages = gray(0.9)
            leaves = gray(0, 0.35)
            label = gray(1)
            letter = gray(0.08)
            ribbon = gray(0.82)
            ribbonEdge = gray(1)
            pink = gray(0.62)
            yellow = gray(0.84)
            ruleBase = gray(0)
        }
    }
}

private extension IconCloth {
    var lightHex: UInt32 {
        switch self {
        case .cobalt: 0x2F4DA0
        case .tomato: 0xC9452F
        case .moss: 0x3D5A40
        case .oxblood: 0x6E2A2A
        case .mustard: 0xD6A02A
        case .print: 0xF7F4EC
        }
    }

    var boardHex: UInt32 {
        switch self {
        case .cobalt: 0x1F3372
        case .tomato: 0x8E2E20
        case .moss: 0x283D2B
        case .oxblood: 0x4A1B1B
        case .mustard: 0x9C7119
        case .print: 0x1C1C21
        }
    }

    var darkHex: UInt32 {
        switch self {
        case .cobalt: 0x3A5BB8
        case .tomato: 0xD65A43
        case .moss: 0x4F7453
        case .oxblood: 0x8C3A38
        case .mustard: 0xDDAA3A
        case .print: 0xDEDBD3
        }
    }

    var darkBoardHex: UInt32 {
        switch self {
        case .cobalt: 0x263E85
        case .tomato: 0x9A3A2A
        case .moss: 0x33503A
        case .oxblood: 0x5E2525
        case .mustard: 0xA67A22
        case .print: 0x2A2A31
        }
    }

    func ribbonHex(dark: Bool) -> UInt32 {
        switch self {
        case .tomato: dark ? 0xF0BE45 : 0xE8B023
        case .print: dark ? 0x4DA3E0 : 0x0078BF
        default: dark ? 0xFF7B61 : 0xC9452F
        }
    }
}
