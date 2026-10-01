import UIKit
import CoreText

/// The date printed at the head of a journal page, drawn as part of the paper in units of width / 800. Thread-safe.
enum PageMasthead {
    private struct Lines: @unchecked Sendable {
        let weekday: CTLine
        let date: CTLine
        let count: CTLine
    }

    private static let cache = LRUCache<Lines>(capacity: 32)
    private static let left: CGFloat = 114
    private static let rightMargin: CGFloat = 96

    /// Nil where the paper's own layout fills the head of the page.
    static func baselines(for template: PaperTemplate, size: CGSize) -> (weekday: CGFloat, date: CGFloat)? {
        switch template {
        case .weekPlanner, .engineering: nil
        case .storyboard: size.height >= size.width ? (58, 92) : nil
        case .cornell, .music, .dayPlanner: (40, 74)
        default: (58, 92)
        }
    }

    static func draw(day: String, template: PaperTemplate, paper: PaperColor, in ctx: CGContext, size: CGSize) {
        let u = size.width / 800
        guard u > 0, ctx.boundingBoxOfClipPath.minY < 110 * u, let baselines = baselines(for: template, size: size),
              let lines = lines(for: day) else { return }
        let right = 800 - rightMargin
        let weekday = bounds(of: lines.weekday), date = bounds(of: lines.date), count = bounds(of: lines.count)
        let ink = paper.isDark ? UIColor(white: 1, alpha: 0.7) : UIColor(hex: 0x1B2230, alpha: 0.7)

        let textMatrix = ctx.textMatrix
        ctx.saveGState()
        defer {
            ctx.restoreGState()
            ctx.textMatrix = textMatrix
        }
        ctx.scaleBy(x: u, y: u)
        let top = baselines.weekday - weekday.ascent - 6, bottom = baselines.date + date.descent + 9
        var knockout = CGRect(x: left - 8, y: top, width: right - left + 16, height: bottom - top)
        if template == .dotted || template == .grid { knockout = snapped(knockout, step: 26) }
        ctx.setFillColor(PageRenderer.paperColor(paper).cgColor)
        ctx.fill(knockout)

        let ruleY = baselines.weekday - weekday.ascent * 0.32
        let ruleStart = left + weekday.width + 12, ruleEnd = right - count.width - 12
        if ruleEnd > ruleStart {
            ctx.setFillColor(ink.withAlphaComponent(paper.isDark ? 0.22 : 0.18).cgColor)
            ctx.fill(CGRect(x: ruleStart, y: ruleY - 0.5, width: ruleEnd - ruleStart, height: 1))
        }

        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.setFillColor(ink.cgColor)
        ctx.textPosition = CGPoint(x: left, y: baselines.weekday)
        CTLineDraw(lines.weekday, ctx)
        ctx.textPosition = CGPoint(x: left - 1, y: baselines.date)
        CTLineDraw(lines.date, ctx)
        ctx.setFillColor(ink.withAlphaComponent(paper.isDark ? 0.55 : 0.5).cgColor)
        ctx.textPosition = CGPoint(x: right - count.width, y: baselines.weekday)
        CTLineDraw(lines.count, ctx)
    }

    private static func bounds(of line: CTLine) -> (width: CGFloat, ascent: CGFloat, descent: CGFloat) {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        return (width, ascent, descent)
    }

    /// Out to the midpoints between dots, so none is cut in half.
    private static func snapped(_ rect: CGRect, step: CGFloat) -> CGRect {
        let half = step / 2
        let minX = ((rect.minX - half) / step).rounded(.down) * step + half
        let minY = ((rect.minY - half) / step).rounded(.down) * step + half
        let maxX = ((rect.maxX - half) / step).rounded(.up) * step + half
        let maxY = ((rect.maxY - half) / step).rounded(.up) * step + half
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func lines(for day: String) -> Lines? {
        cache.value("\(day)|\(Locale.current.identifier)") {
            var calendar = Calendar.current
            calendar.timeZone = .current
            guard let date = DailyJournal.date(fromKey: day, calendar: calendar) else { return nil }
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
            return Lines(weekday: line(date.formatted(.dateTime.weekday(.wide)), font: smallCaps(weight: .semibold), kern: 1.6),
                         date: line(date.formatted(.dateTime.day().month(.wide).year()), font: ScribeFonts.coverLabel(size: 26), kern: 0),
                         count: line(String(localized: "Day \(dayOfYear)"), font: smallCaps(weight: .medium), kern: 1.4))
        }
    }

    private static func smallCaps(weight: UIFont.Weight) -> CTFont {
        let features: [[UIFontDescriptor.FeatureKey: Int]] = [
            [.type: kLowerCaseType, .selector: kLowerCaseSmallCapsSelector],
            [.type: kUpperCaseType, .selector: kUpperCaseSmallCapsSelector],
            [.type: kNumberSpacingType, .selector: kMonospacedNumbersSelector]
        ]
        let descriptor = UIFont.systemFont(ofSize: 11, weight: weight).fontDescriptor.addingAttributes([.featureSettings: features])
        return UIFont(descriptor: descriptor, size: 11) as CTFont
    }

    private static func line(_ string: String, font: CTFont, kern: CGFloat) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            .kern: kern
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }
}
