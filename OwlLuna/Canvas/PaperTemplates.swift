import SwiftUI
import CoreText

/// The colours a template draws with on a given paper; grids and dots use the line colour at their own alpha.
struct TemplateInk {
    let line: UIColor
    let accent: UIColor
    let strong: UIColor
    var grid: CGFloat = 0.35
    var dots: CGFloat = 0.9

    /// At `night` light paper is shown dark, and is ruled as Charcoal is.
    static func `for`(_ color: PaperColor, night: Bool = false) -> TemplateInk {
        switch night && !color.isDark ? .charcoal : color {
        case .white, .ivory, .yellow, .gray:
            TemplateInk(line: UIColor(red: 0.55, green: 0.68, blue: 0.84, alpha: 0.55),
                        accent: UIColor(red: 0.9, green: 0.35, blue: 0.35, alpha: 0.45), strong: UIColor(white: 0.35, alpha: 0.7))
        case .charcoal:
            TemplateInk(line: UIColor(white: 1, alpha: 0.16), accent: UIColor(red: 1, green: 0.45, blue: 0.45, alpha: 0.35),
                        strong: UIColor(white: 1, alpha: 0.3), grid: 0.12, dots: 0.35)
        case .kraft:
            TemplateInk(line: UIColor(red: 0.42, green: 0.31, blue: 0.19, alpha: 0.45), accent: UIColor(red: 0.72, green: 0.24, blue: 0.18, alpha: 0.45),
                        strong: UIColor(red: 0.3, green: 0.21, blue: 0.12, alpha: 0.72), grid: 0.3, dots: 0.6)
        case .sage:
            TemplateInk(line: UIColor(red: 0.3, green: 0.45, blue: 0.35, alpha: 0.45), accent: UIColor(red: 0.75, green: 0.3, blue: 0.3, alpha: 0.4),
                        strong: UIColor(red: 0.2, green: 0.3, blue: 0.23, alpha: 0.72), grid: 0.3, dots: 0.7)
        case .blush:
            TemplateInk(line: UIColor(red: 0.7, green: 0.42, blue: 0.44, alpha: 0.4), accent: UIColor(red: 0.78, green: 0.28, blue: 0.3, alpha: 0.45),
                        strong: UIColor(red: 0.42, green: 0.22, blue: 0.24, alpha: 0.72), grid: 0.32, dots: 0.7)
        case .chalkboard:
            TemplateInk(line: UIColor(white: 1, alpha: 0.2), accent: UIColor(red: 0.91, green: 0.69, blue: 0.14, alpha: 0.45),
                        strong: UIColor(white: 1, alpha: 0.5), grid: 0.12, dots: 0.35)
        }
    }
}

extension PaperColor {
    /// How PencilKit shows ink on this paper. Only Chalkboard writes light; Charcoal keeps the ink its pages already have.
    var inkAppearance: UIUserInterfaceStyle { self == .chalkboard ? .dark : .light }

    /// Light paper as it is shown in Dark Mode: a dark sheet with a little of its own colour left in it.
    var nightRGB: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .white: (0.133, 0.129, 0.125)
        case .ivory: (0.141, 0.129, 0.106)
        case .yellow: (0.145, 0.133, 0.086)
        case .gray: (0.137, 0.145, 0.157)
        case .kraft: (0.165, 0.129, 0.094)
        case .sage: (0.11, 0.141, 0.118)
        case .blush: (0.161, 0.118, 0.114)
        case .charcoal, .chalkboard: rgb
        }
    }
}

extension NotebookPage {
    /// Whether the page is shown dark at `night`: light paper is. A PDF or a photo keeps its own colours.
    func turnsDark(_ night: Bool) -> Bool { night && template != nil && !paperColor.isDark }

    /// Whether what lies on the page is drawn for dark paper.
    func isDark(night: Bool) -> Bool { effectivePaperColor.isDark || turnsDark(night) }

    func inkAppearance(night: Bool) -> UIUserInterfaceStyle { turnsDark(night) ? .dark : effectivePaperColor.inkAppearance }

    /// The colour of the page's paper as it is shown.
    func paperShown(night: Bool) -> UIColor { PageRenderer.paperColor(effectivePaperColor, night: turnsDark(night)) }
}

/// Whether light paper is shown dark: in Dark Mode, unless that is turned off in Settings. What is exported never is.
@propertyWrapper
struct PaperNight: DynamicProperty {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(SettingsKey.darkPaper) private var isAllowed = true

    var wrappedValue: Bool { isAllowed && scheme == .dark }

    static func isOn(_ traits: UITraitCollection) -> Bool {
        traits.userInterfaceStyle == .dark && UserDefaults.standard.object(forKey: SettingsKey.darkPaper) as? Bool ?? true
    }
}

private extension UIColor {
    func faded(_ factor: CGFloat) -> UIColor { withAlphaComponent(min(1, cgColor.alpha * factor)) }
}

extension PageRenderer {
    /// A whiteboard's rules have no margins and never end: the same gaps as a Letter page, drawn only inside the clip.
    /// `origin` is where the piece being drawn sits on its board, so the rules stay under the ink they were under.
    /// Zoomed far out, every second or fourth rule is left out rather than run together.
    static func drawBoardPaper(_ template: PaperTemplate, color: PaperColor, origin: CGPoint, scale: CGFloat, in ctx: CGContext, night: Bool = false) {
        let gap: CGFloat = switch template {
        case .grid, .dotted: 26
        case .narrowRuled: 28
        case .wideRuled: 38
        default: 0
        }
        let unit = Whiteboard.unit * scale, clip = ctx.boundingBoxOfClipPath
        guard gap > 0, unit > 0, !clip.isNull, !clip.isInfinite else { return }
        let pixels = abs(ctx.ctm.a) + abs(ctx.ctm.b)
        var step = gap * unit
        while step * pixels < 14 { step *= 2 }
        let visible = clip.insetBy(dx: -2 * unit - 2, dy: -2 * unit - 2)
        func marks(from low: CGFloat, to high: CGFloat, offset: CGFloat) -> [CGFloat] {
            let first = Int(((low + offset) / step).rounded(.down)), last = Int(((high + offset) / step).rounded(.up))
            return last - first > 4000 ? [] : (first...last).map { CGFloat($0) * step - offset }
        }
        let xs = marks(from: visible.minX, to: visible.maxX, offset: origin.x * scale)
        let ys = marks(from: visible.minY, to: visible.maxY, offset: origin.y * scale)
        let ink = TemplateInk.for(color, night: night)
        ctx.saveGState()
        ctx.setLineWidth(max(0.5, unit))
        switch template {
        case .dotted:
            let r = max(0.8, 1.6 * unit)
            ctx.setFillColor(ink.line.withAlphaComponent(ink.dots).cgColor)
            for y in ys { for x in xs { ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) } }
        case .grid:
            for x in xs {
                ctx.move(to: CGPoint(x: x, y: visible.minY))
                ctx.addLine(to: CGPoint(x: x, y: visible.maxY))
            }
            fallthrough
        default:
            for y in ys {
                ctx.move(to: CGPoint(x: visible.minX, y: y))
                ctx.addLine(to: CGPoint(x: visible.maxX, y: y))
            }
            ctx.setStrokeColor((template == .grid ? ink.line.withAlphaComponent(ink.grid) : ink.line).cgColor)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Rules scale with the page width (v1's 800-unit grid); only rules inside the clip are drawn.
    static func drawTemplate(_ template: PaperTemplate, color: PaperColor, in ctx: CGContext, size: CGSize, night: Bool = false) {
        let unit = size.width / 800
        let ink = TemplateInk.for(color, night: night)
        let rules = TemplateRules(ctx: ctx, size: size)
        let width = size.width, height = size.height
        ctx.saveGState()
        ctx.setLineWidth(max(0.5, unit))

        switch template {
        case .blank:
            break
        case .narrowRuled:
            rules.hLines(rules.steps(from: 120 * unit, by: 28 * unit) { $0 < height - 20 * unit }, from: 0, to: width)
            rules.stroke(ink.line)
            rules.vLines([104 * unit], from: 0, to: height)
            rules.stroke(ink.accent)
        case .wideRuled:
            rules.hLines(rules.steps(from: 120 * unit, by: 38 * unit) { $0 < height - 20 * unit }, from: 0, to: width)
            rules.stroke(ink.line)
            rules.vLines([104 * unit], from: 0, to: height)
            rules.stroke(ink.accent)
        case .grid:
            let spacing = 26 * unit
            rules.vLines(rules.steps(from: spacing, by: spacing) { $0 < width }, from: 0, to: height)
            rules.hLines(rules.steps(from: spacing, by: spacing) { $0 < height }, from: 0, to: width)
            rules.stroke(ink.line.withAlphaComponent(ink.grid))
        case .dotted:
            let spacing = 26 * unit
            ctx.setFillColor(ink.line.withAlphaComponent(ink.dots).cgColor)
            rules.dotGrid(xs: rules.steps(from: spacing, by: spacing) { $0 < width },
                          ys: rules.steps(from: spacing, by: spacing) { $0 < height }, radius: max(0.8, 1.6 * unit))
        case .cornell:
            let summaryTop = height * 0.8
            let cueRight = 240 * unit
            rules.hLines(rules.steps(from: 120 * unit, by: 30 * unit) { $0 < summaryTop }, from: cueRight, to: width)
            rules.stroke(ink.line)
            ctx.setLineWidth(max(1, 2 * unit))
            rules.hLines([90 * unit], from: 0, to: width)
            rules.vLines([cueRight], from: 90 * unit, to: summaryTop)
            rules.hLines([summaryTop], from: 0, to: width)
            rules.stroke(ink.accent)
        case .music:
            let staffGap = 10 * unit
            let staffHeight = staffGap * 4
            let tops = rules.steps(from: 100 * unit, by: staffHeight + 60 * unit) { $0 + staffHeight < height - 60 * unit }
            rules.hLines(tops.flatMap { top in (0..<5).map { top + CGFloat($0) * staffGap } }, from: 60 * unit, to: width - 60 * unit)
            rules.stroke(ink.strong)
        case .engineering:
            drawEngineering(rules, ink: ink, unit: unit)
        case .isometric:
            let spacing = 24.25 * unit
            rules.vLines(rules.multiples(of: spacing, below: width), from: 0, to: height)
            rules.diagonalFamily(angle: .pi / 6, spacing: spacing)
            rules.diagonalFamily(angle: -.pi / 6, spacing: spacing)
            rules.stroke(ink.line.withAlphaComponent(ink.grid))
        case .checklist:
            let ys = rules.steps(from: 120 * unit, by: 38 * unit) { $0 < height - 20 * unit }
            rules.hLines(ys, from: 0, to: width)
            rules.stroke(ink.line)
            rules.boxes(ys.map { CGRect(x: 36 * unit, y: $0 - 20 * unit, width: 14 * unit, height: 14 * unit) }, corner: 2.5 * unit)
            ctx.setLineWidth(max(0.75, 1.25 * unit))
            rules.stroke(ink.strong)
            ctx.setLineWidth(max(0.5, unit))
            rules.vLines([72 * unit], from: 0, to: height)
            rules.stroke(ink.accent)
        case .penmanship:
            drawPenmanship(rules, ink: ink, unit: unit)
        case .dayPlanner:
            drawDayPlanner(rules, ink: ink, unit: unit)
        case .weekPlanner:
            drawWeekPlanner(rules, ink: ink, unit: unit)
        case .storyboard:
            drawStoryboard(rules, ink: ink, unit: unit)
        }
        ctx.restoreGState()
    }

    private static func drawEngineering(_ rules: TemplateRules, ink: TemplateInk, unit: CGFloat) {
        let step = 18 * unit, left = 40 * unit, top = 80 * unit
        let rows = max(1, Int((rules.size.height - 40 * unit - top) / step))
        let xs = (0...40).map { left + CGFloat($0) * step }, ys = (0...rows).map { top + CGFloat($0) * step }
        let right = xs[xs.count - 1], bottom = ys[ys.count - 1]
        func isMajor(_ index: Int, of count: Int) -> Bool { index % 5 == 0 || index == count - 1 }
        rules.vLines(xs.indices.filter { !isMajor($0, of: xs.count) }.map { xs[$0] }, from: top, to: bottom)
        rules.hLines(ys.indices.filter { !isMajor($0, of: ys.count) }.map { ys[$0] }, from: left, to: right)
        rules.stroke(ink.line.faded(0.5))
        rules.vLines(xs.indices.filter { isMajor($0, of: xs.count) }.map { xs[$0] }, from: top, to: bottom)
        rules.hLines(ys.indices.filter { isMajor($0, of: ys.count) }.map { ys[$0] }, from: left, to: right)
        rules.stroke(ink.line)
        rules.ctx.setLineWidth(max(0.75, 1.5 * unit))
        rules.hLines([60 * unit], from: left, to: right)
        rules.stroke(ink.accent)
    }

    private static func drawPenmanship(_ rules: TemplateRules, ink: TemplateInk, unit: CGFloat) {
        let ctx = rules.ctx, width = rules.size.width
        let band = 20 * unit
        let groups = rules.steps(from: 110 * unit, by: band * 3 + 24 * unit) { $0 + band * 3 < rules.size.height - 20 * unit }
        rules.hLines(groups, from: 0, to: width)
        rules.stroke(ink.line.faded(0.9))
        rules.hLines(groups.map { $0 + band * 3 }, from: 0, to: width)
        rules.stroke(ink.line.faded(0.64))
        ctx.setLineWidth(max(0.75, 1.5 * unit))
        rules.hLines(groups.map { $0 + band * 2 }, from: 0, to: width)
        rules.stroke(ink.line)
        ctx.saveGState()
        ctx.setLineWidth(max(0.5, unit))
        ctx.setLineDash(phase: 0, lengths: [6 * unit, 4 * unit])
        rules.hLines(groups.map { $0 + band }, from: 0, to: width)
        rules.stroke(ink.line)
        ctx.restoreGState()
        rules.vLines([72 * unit], from: 0, to: rules.size.height)
        rules.stroke(ink.accent)
    }

    private static func drawDayPlanner(_ rules: TemplateRules, ink: TemplateInk, unit: CGFloat) {
        let ctx = rules.ctx, width = rules.size.width
        let top = 130 * unit, bottom = rules.size.height - 40 * unit
        let hour = (bottom - top) / 15
        let hourRules = (0...15).map { top + CGFloat($0) * hour }
        rules.hLines(hourRules, from: 104 * unit, to: 540 * unit)
        rules.vLines([560 * unit], from: 100 * unit, to: bottom)
        let boxRules = (0..<6).map { 150 * unit + CGFloat($0) * 38 * unit }
        let notesTop = boxRules[boxRules.count - 1] + 68 * unit
        rules.hLines(boxRules + rules.steps(from: notesTop, by: 30 * unit) { $0 <= bottom }, from: 576 * unit, to: 776 * unit)
        rules.stroke(ink.line)

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineWidth(max(0.75, 1.25 * unit))
        ctx.setLineDash(phase: 0, lengths: [0, 5 * unit])
        rules.hLines((0..<15).map { top + (CGFloat($0) + 0.5) * hour }, from: 104 * unit, to: 540 * unit)
        rules.stroke(ink.line)
        ctx.restoreGState()

        ctx.setLineWidth(max(0.75, 1.25 * unit))
        rules.boxes(boxRules.map { CGRect(x: 576 * unit, y: $0 - 20 * unit, width: 14 * unit, height: 14 * unit) }, corner: 2.5 * unit)
        rules.stroke(ink.strong)
        ctx.setLineWidth(max(1, 2 * unit))
        rules.hLines([100 * unit], from: 0, to: width)
        rules.stroke(ink.accent)

        let labels = TemplateText.labels()
        for (index, y) in hourRules.dropLast().enumerated() {
            TemplateText.draw(labels.hours[index], size: 13 * unit, color: ink.strong, at: CGPoint(x: 88 * unit, y: y + 14 * unit),
                              alignment: .right, in: rules)
        }
    }

    private static func drawWeekPlanner(_ rules: TemplateRules, ink: TemplateInk, unit: CGFloat) {
        let ctx = rules.ctx, size = rules.size
        let (columns, rows) = size.height >= size.width ? (2, 4) : (4, 2)
        let margin = 32 * unit, gap = 16 * unit, header = 30 * unit
        let boxWidth = (size.width - margin * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let boxHeight = (size.height - margin * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let boxes = (0..<8).map { index in
            CGRect(x: margin + CGFloat(index % columns) * (boxWidth + gap), y: margin + CGFloat(index / columns) * (boxHeight + gap),
                   width: boxWidth, height: boxHeight)
        }
        let visible = boxes.indices.filter { boxes[$0].intersects(rules.visible) }
        ctx.setFillColor(ink.line.faded(0.18).cgColor)
        for index in visible { ctx.fill(CGRect(x: boxes[index].minX, y: boxes[index].minY, width: boxWidth, height: header)) }
        for index in visible {
            let box = boxes[index]
            rules.hLines(rules.steps(from: box.minY + header * 2, by: 30 * unit) { $0 < box.maxY - 8 * unit }, from: box.minX + 8 * unit, to: box.maxX - 8 * unit)
        }
        rules.stroke(ink.line)
        for index in visible {
            rules.boxes([boxes[index]], corner: 0)
            rules.hLines([boxes[index].minY + header], from: boxes[index].minX, to: boxes[index].maxX)
        }
        rules.stroke(ink.line.faded(0.8 / 0.55))
        let labels = TemplateText.labels().days
        for index in visible {
            TemplateText.draw(labels[index], size: 12 * unit, color: ink.strong,
                              at: CGPoint(x: boxes[index].minX + 10 * unit, y: boxes[index].minY + 19.5 * unit), alignment: .left, in: rules)
        }
    }

    private static func drawStoryboard(_ rules: TemplateRules, ink: TemplateInk, unit: CGFloat) {
        let ctx = rules.ctx, size = rules.size
        let (columns, rows) = size.height >= size.width ? (2, 3) : (3, 2)
        let margin = 40 * unit, gap = 28 * unit, captions = 44 * unit
        var frameWidth = (size.width - margin * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let tallest = (size.height - margin * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows) - captions
        frameWidth = min(frameWidth, tallest * 16 / 9)
        let frameHeight = frameWidth * 9 / 16
        let gridWidth = frameWidth * CGFloat(columns) + gap * CGFloat(columns - 1)
        let gridHeight = (frameHeight + captions) * CGFloat(rows) + gap * CGFloat(rows - 1)
        let origin = CGPoint(x: (size.width - gridWidth) / 2, y: (size.height - gridHeight) / 2)
        let frames = (0..<(columns * rows)).map { index in
            CGRect(x: origin.x + CGFloat(index % columns) * (frameWidth + gap),
                   y: origin.y + CGFloat(index / columns) * (frameHeight + captions + gap), width: frameWidth, height: frameHeight)
        }
        for frame in frames { rules.hLines([frame.maxY + 22 * unit, frame.maxY + captions], from: frame.minX, to: frame.maxX) }
        rules.stroke(ink.line)
        ctx.setLineWidth(max(0.75, 1.5 * unit))
        rules.boxes(frames, corner: 0)
        rules.stroke(ink.strong)
    }
}

/// Adds only the rules that reach the context's clip, padded so antialiased edges and dots still meet at tile seams.
struct TemplateRules {
    let ctx: CGContext
    let size: CGSize
    let visible: CGRect

    init(ctx: CGContext, size: CGSize) {
        self.ctx = ctx
        self.size = size
        let pad = max(2 * size.width / 800, 2)
        visible = ctx.boundingBoxOfClipPath.insetBy(dx: -pad, dy: -pad)
    }

    /// Positions summed step by step, as the original loops did, so existing paper stays pixel-identical.
    func steps(from start: CGFloat, by step: CGFloat, while condition: (CGFloat) -> Bool) -> [CGFloat] {
        var values: [CGFloat] = []
        var value = start
        while condition(value) {
            values.append(value)
            value += step
        }
        return values
    }

    func multiples(of step: CGFloat, below end: CGFloat) -> [CGFloat] {
        (1..<max(1, Int((end / step).rounded(.up)))).map { CGFloat($0) * step }
    }

    func hLines(_ ys: [CGFloat], from x0: CGFloat, to x1: CGFloat) {
        guard x1 >= visible.minX, x0 <= visible.maxX else { return }
        for y in ys where y >= visible.minY && y <= visible.maxY {
            ctx.move(to: CGPoint(x: x0, y: y))
            ctx.addLine(to: CGPoint(x: x1, y: y))
        }
    }

    func vLines(_ xs: [CGFloat], from y0: CGFloat, to y1: CGFloat) {
        guard y1 >= visible.minY, y0 <= visible.maxY else { return }
        for x in xs where x >= visible.minX && x <= visible.maxX {
            ctx.move(to: CGPoint(x: x, y: y0))
            ctx.addLine(to: CGPoint(x: x, y: y1))
        }
    }

    func dotGrid(xs: [CGFloat], ys: [CGFloat], radius r: CGFloat) {
        let columns = xs.filter { $0 + r >= visible.minX && $0 - r <= visible.maxX }
        for y in ys where y + r >= visible.minY && y - r <= visible.maxY {
            for x in columns { ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
        }
    }

    func boxes(_ rects: [CGRect], corner: CGFloat) {
        for rect in rects where rect.intersects(visible) {
            if corner > 0 {
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
            } else {
                ctx.addRect(rect)
            }
        }
    }

    /// Diagonals laid in short pieces on a fixed grid so they rasterise identically across tile seams.
    func diagonalFamily(angle: CGFloat, spacing: CGFloat) {
        let slope = tan(angle), step = spacing / cos(angle), piece = 32 * size.width / 800
        let area = visible.intersection(CGRect(origin: .zero, size: size))
        guard !area.isNull, step > 0, slope != 0 else { return }
        let low = area.minY - max(area.minX * slope, area.maxX * slope)
        let high = area.maxY - min(area.minX * slope, area.maxX * slope)
        let first = Int((low / step).rounded(.up)), last = Int((high / step).rounded(.down))
        guard first <= last else { return }
        for index in first...last {
            let c = CGFloat(index) * step
            let top = (0 - c) / slope, bottom = (size.height - c) / slope
            let x0 = max(0, min(top, bottom)), x1 = min(size.width, max(top, bottom))
            let enters = (area.minY - c) / slope, leaves = (area.maxY - c) / slope
            let from = max(area.minX, min(enters, leaves)), to = min(x1, area.maxX, max(enters, leaves))
            var cell = Int((from / piece).rounded(.down))
            while CGFloat(cell) * piece < to {
                let start = max(x0, CGFloat(cell) * piece), end = min(x1, CGFloat(cell + 1) * piece)
                if start < end {
                    ctx.move(to: CGPoint(x: start, y: start * slope + c))
                    ctx.addLine(to: CGPoint(x: end, y: end * slope + c))
                }
                cell += 1
            }
        }
    }

    func stroke(_ color: UIColor) {
        ctx.setStrokeColor(color.cgColor)
        ctx.strokePath()
    }
}

/// Planner labels drawn with Core Text into the flipped page context, with cached lines.
enum TemplateText {
    struct SharedLine: @unchecked Sendable { let line: CTLine }

    struct Labels: Sendable {
        let hours: [String]
        let days: [String]
    }

    enum Alignment { case left, right }

    private static let lines = LRUCache<SharedLine>(capacity: 128)
    private static let cachedLabels = LRUCache<Labels>(capacity: 4)

    /// Hours 7 to 21 and the week from the calendar's first weekday, plus Notes, in the current locale.
    static func labels() -> Labels {
        let calendar = Calendar.current, locale = Locale.current
        let key = "\(locale.identifier)|\(locale.hourCycle)|\(calendar.identifier)|\(calendar.firstWeekday)"
        return cachedLabels.value(key) {
            let day = Date(timeIntervalSinceReferenceDate: 0)
            let hours = (7...21).map { hour in
                calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)?
                    .formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .narrow))) ?? "\(hour)"
            }
            let symbols = calendar.shortWeekdaySymbols
            let days = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % symbols.count] } + [String(localized: "Notes")]
            return Labels(hours: hours, days: days)
        } ?? Labels(hours: [], days: [])
    }

    static func draw(_ string: String, size: CGFloat, color: UIColor, at point: CGPoint, alignment: Alignment, in rules: TemplateRules) {
        guard let line = line(string, size: size, color: color)?.line else { return }
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x = alignment == .right ? point.x - width : point.x
        guard CGRect(x: x, y: point.y - size, width: width, height: size * 1.3).intersects(rules.visible) else { return }
        let ctx = rules.ctx
        ctx.saveGState()
        let matrix = ctx.textMatrix
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: point.y)
        CTLineDraw(line, ctx)
        ctx.textMatrix = matrix
        ctx.restoreGState()
    }

    private static func line(_ string: String, size: CGFloat, color: UIColor) -> SharedLine? {
        let components = color.cgColor.components?.map { String(format: "%.3f", $0) }.joined(separator: ",") ?? ""
        return lines.value("\(string)|\(size)|\(components)") {
            guard let base = CTFontCreateUIFontForLanguage(.system, size, nil) else { return nil }
            let descriptor = CTFontDescriptorCreateCopyWithFeature(CTFontCopyFontDescriptor(base), NSNumber(value: kNumberSpacingType),
                                                                   NSNumber(value: kMonospacedNumbersSelector))
            let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                             NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor]
            return SharedLine(line: CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes)))
        }
    }
}
