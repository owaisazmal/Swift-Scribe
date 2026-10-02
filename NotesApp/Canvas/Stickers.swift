import UIKit
import CoreText

/// The built-in stickers, drawn as vectors so they stay sharp at any zoom and in exported PDFs. Thread-safe.
/// Raw values are stored in notebooks: a case can be redrawn, never renamed.
enum Sticker: String, CaseIterable, Identifiable, Sendable {
    case noteYellow, notePink, noteBlue, noteMint, noteLavender, notePeach
    case indexCard, gridNote, tornPaper, kraftTag, label, bubble, banner
    case tapeMustard, tapeTeal, tapePink, tapeDots, tapeGingham
    case sparkles, daisy, sprig, cloud, sun, moon, rainbow, paperclip, pin
    case star, heart, check, exclaim, question, arrow, flag, ring, underline
    case stampImportant, stampToDo, stampDone, stampIdea

    var id: String { rawValue }

    enum Family: String, CaseIterable, Identifiable {
        case paper, doodles, marks, stamps
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .paper: String(localized: "Notes and Tape")
            case .doodles: String(localized: "Doodles")
            case .marks: String(localized: "Marks")
            case .stamps: String(localized: "Tags")
            }
        }

        var stickers: [Sticker] { Sticker.allCases.filter { $0.family == self } }
    }

    var family: Family {
        switch self {
        case .noteYellow, .notePink, .noteBlue, .noteMint, .noteLavender, .notePeach, .indexCard, .gridNote, .tornPaper, .kraftTag, .label, .bubble,
             .banner, .tapeMustard, .tapeTeal, .tapePink, .tapeDots, .tapeGingham: .paper
        case .sparkles, .daisy, .sprig, .cloud, .sun, .moon, .rainbow, .paperclip, .pin: .doodles
        case .star, .heart, .check, .exclaim, .question, .arrow, .flag, .ring, .underline: .marks
        case .stampImportant, .stampToDo, .stampDone, .stampIdea: .stamps
        }
    }

    var displayName: String {
        switch self {
        case .noteYellow: String(localized: "Yellow Sticky Note")
        case .notePink: String(localized: "Pink Sticky Note")
        case .noteBlue: String(localized: "Blue Sticky Note")
        case .noteMint: String(localized: "Mint Sticky Note")
        case .noteLavender: String(localized: "Lavender Sticky Note")
        case .notePeach: String(localized: "Peach Sticky Note")
        case .indexCard: String(localized: "Index Card")
        case .gridNote: String(localized: "Taped Grid Note")
        case .tornPaper: String(localized: "Torn Paper")
        case .kraftTag: String(localized: "Kraft Tag")
        case .label: String(localized: "Label")
        case .bubble: String(localized: "Speech Bubble")
        case .banner: String(localized: "Ribbon Banner")
        case .tapeMustard: String(localized: "Mustard Tape")
        case .tapeTeal: String(localized: "Teal Tape")
        case .tapePink: String(localized: "Pink Tape")
        case .tapeDots: String(localized: "Dotted Tape")
        case .tapeGingham: String(localized: "Gingham Tape")
        case .sparkles: String(localized: "Sparkles")
        case .daisy: String(localized: "Daisy")
        case .sprig: String(localized: "Leaf Sprig")
        case .cloud: String(localized: "Cloud")
        case .sun: String(localized: "Sun")
        case .moon: String(localized: "Moon")
        case .rainbow: String(localized: "Rainbow")
        case .paperclip: String(localized: "Paperclip")
        case .pin: String(localized: "Pushpin")
        case .star: String(localized: "Star")
        case .heart: String(localized: "Heart")
        case .check: String(localized: "Check Mark")
        case .exclaim: String(localized: "Exclamation Mark")
        case .question: String(localized: "Question Mark")
        case .arrow: String(localized: "Arrow")
        case .flag: String(localized: "Flag")
        case .ring: String(localized: "Ring")
        case .underline: String(localized: "Highlighter Line")
        case .stampImportant: String(localized: "Important Tag")
        case .stampToDo: String(localized: "To Do Tag")
        case .stampDone: String(localized: "Done Tag")
        case .stampIdea: String(localized: "Idea Tag")
        }
    }

    /// Width over height.
    var aspect: CGFloat {
        switch self {
        case .noteYellow, .notePink, .noteBlue, .noteMint, .noteLavender, .notePeach, .gridNote: 1
        case .star, .heart, .check, .exclaim, .question, .flag, .sparkles, .daisy, .sun, .moon, .pin: 1
        case .indexCard, .ring, .cloud: 100 / 64
        case .tornPaper: 100 / 40
        case .kraftTag, .label: 100 / 52
        case .bubble: 100 / 78
        case .banner: 100 / 34
        case .tapeMustard, .tapeTeal, .tapePink, .tapeDots, .tapeGingham: 100 / 28
        case .sprig: 100 / 70
        case .rainbow: 100 / 58
        case .paperclip: 100 / 42
        case .arrow: 100 / 56
        case .underline: 100 / 22
        case .stampImportant, .stampToDo, .stampDone, .stampIdea: 100 / 36
        }
    }

    /// The size a new one is placed at, in page points.
    var defaultSize: CGSize {
        let width: CGFloat = switch self {
        case .star, .heart, .check, .exclaim, .question, .flag, .pin: 64
        case .daisy, .moon: 72
        case .sparkles, .sun: 84
        case .arrow, .paperclip: 110
        case .sprig, .cloud: 130
        case .rainbow, .stampImportant, .stampToDo, .stampDone, .stampIdea: 150
        case .ring: 170
        case .underline, .tapeMustard, .tapeTeal, .tapePink, .tapeDots, .tapeGingham: 190
        case .noteYellow, .notePink, .noteBlue, .noteMint, .noteLavender, .notePeach, .gridNote, .kraftTag: 200
        case .label, .bubble, .banner: 220
        case .indexCard, .tornPaper: 240
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

    // MARK: Palette

    /// A soft fill with the deeper shade of the same hue for its edge and anything drawn on it.
    private struct Tone {
        let fill: UIColor
        let deep: UIColor

        init(_ fill: UInt32, _ deep: UInt32) {
            self.fill = UIColor(hex: fill)
            self.deep = UIColor(hex: deep)
        }
    }

    private static let butter = Tone(0xFFE08A, 0xC08A12)
    private static let rose = Tone(0xF6AFBD, 0xC2536E)
    private static let peach = Tone(0xFBCBA7, 0xC9642A)
    private static let sky = Tone(0xBCDDF5, 0x2F6DA8)
    private static let mint = Tone(0xBFE3C8, 0x3E8A5C)
    private static let kraft = Tone(0xD9BE94, 0x9A774A)
    private static let ink = UIColor(hex: 0x1B2230)
    private static let mustard = UIColor(hex: 0xE8B023)
    private static let cream = UIColor(hex: 0xF7F1E3)

    // MARK: Drawing

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
        case .noteYellow: note(UIColor(hex: 0xFFE27A), fold: UIColor(hex: 0xE8C552), in: ctx)
        case .notePink: note(UIColor(hex: 0xF9B9CD), fold: UIColor(hex: 0xE594AE), in: ctx)
        case .noteBlue: note(UIColor(hex: 0xB4D8F3), fold: UIColor(hex: 0x8DBADD), in: ctx)
        case .noteMint: note(UIColor(hex: 0xC6EAD0), fold: UIColor(hex: 0x9CD0AC), in: ctx)
        case .noteLavender: note(UIColor(hex: 0xDCD1F5), fold: UIColor(hex: 0xB9A8E4), in: ctx)
        case .notePeach: note(UIColor(hex: 0xFCD7BC), fold: UIColor(hex: 0xEFB189), in: ctx)
        case .indexCard: indexCard(height: height, in: ctx)
        case .gridNote: gridNote(in: ctx)
        case .tornPaper: tornPaper(in: ctx)
        case .kraftTag: kraftTag(in: ctx)
        case .label:
            let outer = CGRect(x: 3, y: 3, width: 94, height: height - 6)
            let path = CGPath(roundedRect: outer, cornerWidth: 3, cornerHeight: 3, transform: nil)
            shadow(path, in: ctx)
            ctx.addPath(path)
            ctx.setFillColor(Self.cream.cgColor)
            ctx.fillPath()
            ctx.setStrokeColor(Self.ink.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(0.9)
            ctx.stroke(outer.insetBy(dx: 4, dy: 4))
            ctx.setLineWidth(0.45)
            ctx.stroke(outer.insetBy(dx: 6, dy: 6))
        case .bubble: bubble(in: ctx)
        case .banner: banner(in: ctx)
        case .tapeMustard: tape(Self.mustard.withAlphaComponent(0.82), in: ctx) { self.stripes(in: ctx) }
        case .tapeTeal: tape(UIColor(hex: 0x2FA39A, alpha: 0.82), in: ctx) { self.stripes(in: ctx) }
        case .tapePink: tape(UIColor(hex: 0xF07FA8, alpha: 0.82), in: ctx) { self.stripes(in: ctx) }
        case .tapeDots:
            tape(UIColor(hex: 0x9CC9EA, alpha: 0.9), in: ctx) {
                ctx.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
                for (row, y) in [9.5 as CGFloat, 18.5].enumerated() {
                    for x in stride(from: row == 0 ? 9 as CGFloat : 14, to: 96, by: 10) {
                        ctx.fillEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                    }
                }
            }
        case .tapeGingham:
            tape(UIColor(hex: 0xD8EFDD, alpha: 0.95), in: ctx) {
                ctx.setFillColor(Self.mint.deep.withAlphaComponent(0.28).cgColor)
                for x in stride(from: 4 as CGFloat, to: 100, by: 10) { ctx.fill(CGRect(x: x, y: 0, width: 5, height: 28)) }
                for y in stride(from: 4 as CGFloat, to: 28, by: 10) { ctx.fill(CGRect(x: 0, y: y, width: 100, height: 5)) }
            }
        case .sparkles:
            cutout(Self.sparkle(at: CGPoint(x: 42, y: 56), radius: 34), Self.butter, in: ctx)
            cutout(Self.sparkle(at: CGPoint(x: 79, y: 24), radius: 15), Self.butter, in: ctx)
            cutout(Self.sparkle(at: CGPoint(x: 82, y: 80), radius: 9), Self.butter, in: ctx)
        case .daisy:
            let petals = CGMutablePath()
            for index in 0..<8 {
                let turn = CGAffineTransform(translationX: 50, y: 50).rotated(by: CGFloat(index) * .pi / 4)
                petals.addEllipse(in: CGRect(x: -8, y: -42, width: 16, height: 32), transform: turn)
            }
            cutout(petals, Tone(0xFFFDF8, 0xC9A9B4), gloss: false, in: ctx)
            cutout(CGPath(ellipseIn: CGRect(x: 38, y: 38, width: 24, height: 24), transform: nil), Self.butter, shadowed: false, in: ctx)
        case .sprig: sprig(in: ctx)
        case .cloud:
            var path = CGPath(roundedRect: CGRect(x: 12, y: 34, width: 76, height: 22), cornerWidth: 11, cornerHeight: 11, transform: nil)
            for (x, y, r) in [(30, 37, 15), (49, 28, 20), (69, 35, 15)] as [(CGFloat, CGFloat, CGFloat)] {
                path = path.union(CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), transform: nil))
            }
            cutout(path, Tone(0xEEF6FC, 0x6FA3CF), in: ctx)
        case .sun:
            ctx.setStrokeColor(UIColor(hex: 0xF0B43C).cgColor)
            ctx.setLineWidth(5.5)
            for index in 0..<8 {
                let angle = CGFloat(index) * .pi / 4
                ctx.move(to: CGPoint(x: 50 + cos(angle) * 31, y: 50 + sin(angle) * 31))
                ctx.addLine(to: CGPoint(x: 50 + cos(angle) * 41, y: 50 + sin(angle) * 41))
            }
            ctx.strokePath()
            cutout(CGPath(ellipseIn: CGRect(x: 27, y: 27, width: 46, height: 46), transform: nil), Tone(0xFFD27A, 0xC9861A), in: ctx)
        case .moon:
            let disc = CGPath(ellipseIn: CGRect(x: 14, y: 16, width: 68, height: 68), transform: nil)
            let bite = CGPath(ellipseIn: CGRect(x: 36, y: 10, width: 60, height: 60), transform: nil)
            cutout(disc.subtracting(bite), Self.butter, in: ctx)
            cutout(Self.sparkle(at: CGPoint(x: 70, y: 36), radius: 10), Self.butter, shadowed: false, in: ctx)
        case .rainbow:
            ctx.setLineWidth(7.5)
            for (radius, color) in [(38, 0xF29CB0), (29.5, 0xFBBE8F), (21, 0xFFDD7A), (12.5, 0xA9DDB8)] as [(CGFloat, UInt32)] {
                ctx.addArc(center: CGPoint(x: 50, y: 50), radius: radius, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
                ctx.setStrokeColor(UIColor(hex: color).cgColor)
                ctx.strokePath()
            }
        case .paperclip: paperclip(in: ctx)
        case .pin:
            ctx.translateBy(x: 50, y: 50)
            ctx.rotate(by: 0.5)
            ctx.translateBy(x: -50, y: -50)
            brush(CGMutablePath.line(from: CGPoint(x: 50, y: 52), to: CGPoint(x: 50, y: 92)), width: 2.6, color: UIColor(hex: 0x8C96A6), in: ctx)
            let neck = CGMutablePath()
            neck.addLines(between: [CGPoint(x: 42, y: 17), CGPoint(x: 58, y: 17), CGPoint(x: 56, y: 44), CGPoint(x: 44, y: 44)])
            neck.closeSubpath()
            let head = CGPath(roundedRect: CGRect(x: 34, y: 8, width: 32, height: 11), cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)
            let flange = CGPath(roundedRect: CGRect(x: 29, y: 42, width: 42, height: 11), cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)
            cutout(head.union(neck).union(flange), Self.rose, in: ctx)
        case .star:
            let star = Self.starPath()
            cutout(star.union(star.copy(strokingWithWidth: 9, lineCap: .round, lineJoin: .round, miterLimit: 1)), Self.butter, in: ctx)
        case .heart: cutout(Self.heartPath(), Self.rose, in: ctx)
        case .check:
            cutout(CGPath(ellipseIn: CGRect(x: 8, y: 8, width: 84, height: 84), transform: nil), Self.mint, in: ctx)
            ctx.setStrokeColor(Self.mint.deep.cgColor)
            ctx.setLineWidth(9)
            ctx.addLines(between: [CGPoint(x: 30, y: 52), CGPoint(x: 44, y: 66), CGPoint(x: 70, y: 36)])
            ctx.strokePath()
        case .exclaim:
            cutout(CGPath(ellipseIn: CGRect(x: 8, y: 8, width: 84, height: 84), transform: nil), Self.peach, in: ctx)
            glyph("!", size: 60, color: Self.peach.deep, centre: CGPoint(x: 50, y: 50), in: ctx)
        case .question:
            cutout(CGPath(ellipseIn: CGRect(x: 8, y: 8, width: 84, height: 84), transform: nil), Self.sky, in: ctx)
            glyph("?", size: 60, color: Self.sky.deep, centre: CGPoint(x: 50, y: 50), in: ctx)
        case .arrow:
            let path = CGMutablePath()
            let end = CGPoint(x: 88, y: 30), control = CGPoint(x: 44, y: 2)
            path.move(to: CGPoint(x: 10, y: 44))
            path.addQuadCurve(to: end, control: control)
            let heading = atan2(end.y - control.y, end.x - control.x)
            path.move(to: CGPoint(x: end.x + cos(heading + .pi - 0.6) * 15, y: end.y + sin(heading + .pi - 0.6) * 15))
            path.addLine(to: end)
            path.addLine(to: CGPoint(x: end.x + cos(heading + .pi + 0.6) * 15, y: end.y + sin(heading + .pi + 0.6) * 15))
            brush(path, width: 5, color: Self.sky.deep, in: ctx)
        case .flag:
            let pennant = CGMutablePath()
            pennant.move(to: CGPoint(x: 28, y: 15))
            pennant.addCurve(to: CGPoint(x: 90, y: 22), control1: CGPoint(x: 48, y: 8), control2: CGPoint(x: 68, y: 28))
            pennant.addLine(to: CGPoint(x: 76, y: 38))
            pennant.addLine(to: CGPoint(x: 90, y: 54))
            pennant.addCurve(to: CGPoint(x: 28, y: 59), control1: CGPoint(x: 68, y: 62), control2: CGPoint(x: 48, y: 50))
            pennant.closeSubpath()
            cutout(pennant, Self.rose, in: ctx)
            brush(CGMutablePath.line(from: CGPoint(x: 26, y: 12), to: CGPoint(x: 26, y: 92)), width: 5, color: UIColor(hex: 0x8A6A4F), in: ctx)
        case .ring:
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: 5, y: 5, width: 90, height: height - 10))
            path.addEllipse(in: CGRect(x: 11.5, y: 10.5, width: 80, height: height - 19))
            ctx.addPath(path)
            ctx.setFillColor(Self.rose.deep.withAlphaComponent(0.85).cgColor)
            ctx.fillPath(using: .evenOdd)
        case .underline:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 5, y: 12))
            path.addCurve(to: CGPoint(x: 95, y: 10), control1: CGPoint(x: 35, y: 6), control2: CGPoint(x: 65, y: 16))
            ctx.setLineCap(.butt)
            ctx.addPath(path)
            ctx.setStrokeColor(UIColor(hex: 0xFFD84D, alpha: 0.6).cgColor)
            ctx.setLineWidth(13)
            ctx.strokePath()
            ctx.addPath(path)
            ctx.setStrokeColor(UIColor(hex: 0xFFC61A, alpha: 0.28).cgColor)
            ctx.setLineWidth(6)
            ctx.strokePath()
        case .stampImportant: tag("IMPORTANT", Self.rose, height: height, in: ctx)
        case .stampToDo: tag("TO DO", Self.sky, height: height, in: ctx)
        case .stampDone: tag("DONE", Self.mint, height: height, in: ctx)
        case .stampIdea: tag("IDEA", Self.butter, height: height, in: ctx)
        }
    }

    /// The look every solid sticker shares: a soft shadow, a matte fill with a little light on it, and a darker edge.
    private func cutout(_ path: CGPath, _ tone: Tone, gloss: Bool = true, shadowed: Bool = true, in ctx: CGContext) {
        if shadowed { shadow(path, in: ctx) }
        ctx.addPath(path)
        ctx.setFillColor(tone.fill.cgColor)
        ctx.fillPath()
        if gloss {
            let box = path.boundingBoxOfPath
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.3).cgColor)
            ctx.fillEllipse(in: CGRect(x: box.minX - box.width * 0.2, y: box.minY - box.height * 0.4, width: box.width, height: box.height * 0.8))
            ctx.restoreGState()
        }
        ctx.addPath(path)
        ctx.setStrokeColor(tone.deep.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(1.3)
        ctx.strokePath()
    }

    /// Layered tints, not a blur, so it stays vector in an exported PDF.
    private func shadow(_ path: CGPath, in ctx: CGContext) {
        let tint = UIColor.black.withAlphaComponent(0.05).cgColor
        ctx.setFillColor(tint)
        ctx.setStrokeColor(tint)
        for (offset, spread) in [(1.2, 3), (1.8, 1.4), (2.2, 0)] as [(CGFloat, CGFloat)] {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: offset)
            ctx.addPath(path)
            ctx.fillPath()
            if spread > 0 {
                ctx.addPath(path)
                ctx.setLineWidth(spread)
                ctx.strokePath()
            }
            ctx.restoreGState()
        }
    }

    /// A drawn line with the faint shadow of something resting on the page.
    private func brush(_ path: CGPath, width: CGFloat, color: UIColor, in ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: 1.4)
        ctx.addPath(path)
        ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.1).cgColor)
        ctx.setLineWidth(width + 1)
        ctx.strokePath()
        ctx.restoreGState()
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

    private func indexCard(height: CGFloat, in ctx: CGContext) {
        let card = CGRect(x: 4, y: 4, width: 92, height: height - 9)
        let path = CGPath(roundedRect: card, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        shadow(path, in: ctx)
        ctx.addPath(path)
        ctx.setFillColor(UIColor(hex: 0xFFFDF6).cgColor)
        ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setLineCap(.butt)
        ctx.setStrokeColor(UIColor(hex: 0xE07A7A, alpha: 0.85).cgColor)
        ctx.setLineWidth(0.8)
        ctx.strokeLineSegments(between: [CGPoint(x: card.minX, y: 17), CGPoint(x: card.maxX, y: 17)])
        ctx.setStrokeColor(UIColor(hex: 0x9CB8D9, alpha: 0.75).cgColor)
        ctx.setLineWidth(0.6)
        for y in stride(from: 25 as CGFloat, to: card.maxY - 3, by: 8) {
            ctx.strokeLineSegments(between: [CGPoint(x: card.minX, y: y), CGPoint(x: card.maxX, y: y)])
        }
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(UIColor(hex: 0xB9B09A, alpha: 0.8).cgColor)
        ctx.setLineWidth(0.7)
        ctx.strokePath()
    }

    private func gridNote(in ctx: CGContext) {
        let sheet = CGRect(x: 6, y: 11, width: 88, height: 83)
        let path = CGPath(roundedRect: sheet, cornerWidth: 2, cornerHeight: 2, transform: nil)
        shadow(path, in: ctx)
        ctx.addPath(path)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setLineCap(.butt)
        ctx.setStrokeColor(UIColor(hex: 0xA9C0DC, alpha: 0.6).cgColor)
        ctx.setLineWidth(0.5)
        for x in stride(from: sheet.minX + 8, to: sheet.maxX, by: 8) { ctx.strokeLineSegments(between: [CGPoint(x: x, y: sheet.minY), CGPoint(x: x, y: sheet.maxY)]) }
        for y in stride(from: sheet.minY + 8, to: sheet.maxY, by: 8) { ctx.strokeLineSegments(between: [CGPoint(x: sheet.minX, y: y), CGPoint(x: sheet.maxX, y: y)]) }
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(UIColor(hex: 0xB8BCC4, alpha: 0.8).cgColor)
        ctx.setLineWidth(0.7)
        ctx.strokePath()
        ctx.saveGState()
        ctx.translateBy(x: 50, y: 11)
        ctx.rotate(by: -0.07)
        ctx.setFillColor(UIColor(hex: 0xF4A7B9, alpha: 0.82).cgColor)
        ctx.fill(CGRect(x: -19, y: -7, width: 38, height: 13))
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.35).cgColor)
        for x in stride(from: -15 as CGFloat, to: 19, by: 8) { ctx.fill(CGRect(x: x, y: -7, width: 3, height: 13)) }
        ctx.restoreGState()
    }

    private func tornPaper(in ctx: CGContext) {
        let tear: [CGFloat] = [0, 1.6, -0.8, 1.9, 0.4, -1.4, 1.1, -0.3, 1.8, -1.2, 0.7, 1.5, -0.9, 0.2, 1.7, -1.5, 0.9, -0.4, 1.3, -1.1, 0.5, 1.9, -0.7, 0]
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4, y: 5))
        path.addLine(to: CGPoint(x: 96, y: 5))
        for (index, offset) in tear.enumerated().reversed() {
            path.addLine(to: CGPoint(x: 4 + CGFloat(index) * 4, y: 32 + offset))
        }
        path.closeSubpath()
        shadow(path, in: ctx)
        ctx.addPath(path)
        ctx.setFillColor(UIColor(hex: 0xFFFEFA).cgColor)
        ctx.fillPath()
        ctx.setLineCap(.butt)
        ctx.setStrokeColor(UIColor(hex: 0x9CB8D9, alpha: 0.6).cgColor)
        ctx.setLineWidth(0.5)
        for y in [14, 23] as [CGFloat] { ctx.strokeLineSegments(between: [CGPoint(x: 4, y: y), CGPoint(x: 96, y: y)]) }
        ctx.addPath(path)
        ctx.setStrokeColor(UIColor(hex: 0xB8B4A8, alpha: 0.7).cgColor)
        ctx.setLineWidth(0.6)
        ctx.strokePath()
    }

    private func kraftTag(in ctx: CGContext) {
        let outline = CGMutablePath()
        outline.addLines(between: [CGPoint(x: 24, y: 7), CGPoint(x: 93, y: 7), CGPoint(x: 93, y: 45), CGPoint(x: 24, y: 45), CGPoint(x: 8, y: 32), CGPoint(x: 8, y: 20)])
        outline.closeSubpath()
        let hole = CGPath(ellipseIn: CGRect(x: 15.5, y: 23.5, width: 5, height: 5), transform: nil)
        let body = outline.union(outline.copy(strokingWithWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 1)).subtracting(hole)
        shadow(body, in: ctx)
        ctx.addPath(body)
        ctx.setFillColor(Self.kraft.fill.cgColor)
        ctx.fillPath()
        ctx.addPath(body)
        ctx.setStrokeColor(Self.kraft.deep.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(0.9)
        ctx.strokePath()
        let washer = CGMutablePath()
        washer.addEllipse(in: CGRect(x: 12, y: 20, width: 12, height: 12))
        washer.addEllipse(in: CGRect(x: 15.5, y: 23.5, width: 5, height: 5))
        ctx.addPath(washer)
        ctx.setFillColor(UIColor(hex: 0xF3E7CF).cgColor)
        ctx.fillPath(using: .evenOdd)
        let string = CGMutablePath()
        string.move(to: CGPoint(x: 18, y: 26))
        string.addCurve(to: CGPoint(x: 4, y: 5), control1: CGPoint(x: 9, y: 22), control2: CGPoint(x: 2, y: 14))
        ctx.addPath(string)
        ctx.setStrokeColor(UIColor(hex: 0x8C7350).cgColor)
        ctx.setLineWidth(1.3)
        ctx.strokePath()
    }

    private func bubble(in ctx: CGContext) {
        let body = CGPath(roundedRect: CGRect(x: 5, y: 5, width: 90, height: 54), cornerWidth: 18, cornerHeight: 18, transform: nil)
        let tail = CGMutablePath()
        tail.addLines(between: [CGPoint(x: 24, y: 55), CGPoint(x: 18, y: 73), CGPoint(x: 42, y: 55)])
        tail.closeSubpath()
        let path = body.union(tail)
        shadow(path, in: ctx)
        ctx.addPath(path)
        ctx.setFillColor(UIColor(hex: 0xFFFDF8).cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(Self.ink.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1.8)
        ctx.strokePath()
    }

    private func banner(in ctx: CGContext) {
        let fold = UIColor(hex: 0xE58FA3)
        for mirror in [false, true] {
            func x(_ value: CGFloat) -> CGFloat { mirror ? 100 - value : value }
            let tail = CGMutablePath()
            tail.addLines(between: [CGPoint(x: x(3), y: 11), CGPoint(x: x(20), y: 11), CGPoint(x: x(20), y: 30), CGPoint(x: x(3), y: 30), CGPoint(x: x(9), y: 20.5)])
            tail.closeSubpath()
            shadow(tail, in: ctx)
            ctx.addPath(tail)
            ctx.setFillColor(fold.cgColor)
            ctx.fillPath()
            ctx.addLines(between: [CGPoint(x: x(12), y: 25), CGPoint(x: x(20), y: 25), CGPoint(x: x(20), y: 30)])
            ctx.closePath()
            ctx.setFillColor(Self.rose.deep.cgColor)
            ctx.fillPath()
        }
        cutout(CGPath(roundedRect: CGRect(x: 12, y: 4, width: 76, height: 21), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil), Self.rose, gloss: false, in: ctx)
    }

    /// Washi tape with pinked ends: the colour, then whatever is printed on it.
    private func tape(_ color: UIColor, in ctx: CGContext, pattern: () -> Void) {
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
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 28))
        pattern()
        ctx.restoreGState()
    }

    private func stripes(in ctx: CGContext) {
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.38).cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.butt)
        for x in stride(from: -20 as CGFloat, to: 110, by: 10) {
            ctx.move(to: CGPoint(x: x, y: 26))
            ctx.addLine(to: CGPoint(x: x + 24, y: 2))
        }
        ctx.strokePath()
    }

    private func sprig(in ctx: CGContext) {
        let p0 = CGPoint(x: 10, y: 62), p1 = CGPoint(x: 36, y: 58), p2 = CGPoint(x: 64, y: 40), p3 = CGPoint(x: 90, y: 12)
        func point(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
                           y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y)
        }
        func heading(_ t: CGFloat) -> CGFloat {
            let a = point(max(t - 0.02, 0)), b = point(min(t + 0.02, 1))
            return atan2(b.y - a.y, b.x - a.x)
        }
        func leaf(at t: CGFloat, turn: CGFloat, length: CGFloat) -> CGPath {
            let shape = CGMutablePath()
            shape.move(to: .zero)
            shape.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.45, y: -length * 0.42))
            shape.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.45, y: length * 0.42))
            let origin = point(t)
            var place = CGAffineTransform(translationX: origin.x, y: origin.y).rotated(by: heading(t) + turn)
            return shape.copy(using: &place) ?? shape
        }
        let stem = CGMutablePath()
        stem.move(to: p0)
        stem.addCurve(to: p3, control1: p1, control2: p2)
        for (index, t) in [0.16, 0.32, 0.48, 0.64, 0.8].enumerated() {
            cutout(leaf(at: t, turn: index % 2 == 0 ? -0.9 : 0.9, length: 25 - CGFloat(index) * 2), Tone(0xA9D9B6, 0x3E8A5C), gloss: false, in: ctx)
        }
        cutout(leaf(at: 0.93, turn: 0, length: 14), Tone(0xA9D9B6, 0x3E8A5C), gloss: false, in: ctx)
        ctx.addPath(stem)
        ctx.setStrokeColor(Self.mint.deep.cgColor)
        ctx.setLineWidth(2.6)
        ctx.strokePath()
    }

    private func paperclip(in ctx: CGContext) {
        let wire = CGMutablePath()
        wire.move(to: CGPoint(x: 34, y: 10))
        wire.addLine(to: CGPoint(x: 80, y: 10))
        wire.addArc(center: CGPoint(x: 80, y: 21), radius: 11, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        wire.addLine(to: CGPoint(x: 20, y: 32))
        wire.addArc(center: CGPoint(x: 20, y: 24), radius: 8, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
        wire.addLine(to: CGPoint(x: 72, y: 16))
        wire.addArc(center: CGPoint(x: 72, y: 21), radius: 5, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        wire.addLine(to: CGPoint(x: 36, y: 26))
        brush(wire, width: 3.6, color: UIColor(hex: 0x66758C), in: ctx)
        ctx.addPath(wire)
        ctx.setStrokeColor(UIColor(hex: 0xC3CEDC).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
    }

    /// A pastel pill with a dot and tracked capitals, like a planner tag.
    private func tag(_ text: String, _ tone: Tone, height: CGFloat, in ctx: CGContext) {
        cutout(CGPath(roundedRect: CGRect(x: 3, y: 4, width: 94, height: height - 9), cornerWidth: 13, cornerHeight: 13, transform: nil), tone, gloss: false, in: ctx)
        let middle = 4 + (height - 9) / 2
        ctx.setFillColor(tone.deep.cgColor)
        ctx.fillEllipse(in: CGRect(x: 11.5, y: middle - 3, width: 6, height: 6))
        glyph(text, size: 12.5, color: tone.deep, centre: CGPoint(x: 57, y: middle), fitting: 68, kern: 1.2, in: ctx)
    }

    private func glyph(_ text: String, size: CGFloat, color: UIColor, centre: CGPoint, fitting width: CGFloat? = nil, kern: CGFloat = 0, in ctx: CGContext) {
        func line(_ size: CGFloat) -> CTLine {
            let system = UIFont.systemFont(ofSize: size, weight: .heavy)
            let font = system.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? system
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font as CTFont,
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

    /// A four-pointed star with pinched sides.
    private static func sparkle(at centre: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func point(_ angle: CGFloat, _ distance: CGFloat) -> CGPoint { CGPoint(x: centre.x + cos(angle) * distance, y: centre.y + sin(angle) * distance) }
        path.move(to: point(-.pi / 2, radius))
        for index in 0..<4 {
            let angle = CGFloat(index) * .pi / 2 - .pi / 2
            path.addQuadCurve(to: point(angle + .pi / 2, radius), control: point(angle + .pi / 4, radius * 0.18))
        }
        path.closeSubpath()
        return path
    }

    private static func starPath() -> CGPath {
        let path = CGMutablePath()
        let centre = CGPoint(x: 50, y: 53)
        for index in 0..<10 {
            let radius: CGFloat = index % 2 == 0 ? 37 : 17
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

private extension CGMutablePath {
    static func line(from start: CGPoint, to end: CGPoint) -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
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
                let title = links?.title(for: link) ?? (link.target == nil ? LinkTitles().title(for: link) : link.label.isEmpty ? String(localized: "Page") : link.label)
                PageLinkArt.draw(title: title, kind: link.kind, resolved: links?.resolves(link) ?? true, in: ctx, rect: rect)
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
