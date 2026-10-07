import UIKit
import PDFKit
import PencilKit

/// What is selected of a PDF page's own text: the words, and a rectangle for each line of them, in page points.
struct TextSelection: Sendable, Equatable {
    let text: String
    let lines: [CGRect]
}

/// A PDF page's own text: what lies between two points, the word at a point, and the stretch of a line that a
/// highlighter was drawn along. Points and rectangles are in the page's points as it is shown.
enum PDFText {
    static var snapsHighlighter: Bool { UserDefaults.standard.object(forKey: SettingsKey.snapsHighlighter) as? Bool ?? true }

    /// The lines of text on a page, each as a rectangle.
    static func lines(on page: PDFPage, pageSize: CGSize) -> [CGRect] {
        page.selection(for: page.bounds(for: .cropBox)).map { rects(of: $0, on: page, pageSize: pageSize) } ?? []
    }

    /// Where a touch is taken to be in the text: on the line it is on or nearest to, and never past that line's ends.
    /// Given a point off the text, PDFKit picks a letter that can be lines away, or none.
    static func settled(_ point: CGPoint, among lines: [CGRect]) -> (point: CGPoint, line: CGRect)? {
        let sideways = lines.count(where: { $0.width >= $0.height }) * 2 >= lines.count
        func away(_ line: CGRect) -> (CGFloat, CGFloat) {
            let across = max(line.minY - point.y, 0, point.y - line.maxY), along = max(line.minX - point.x, 0, point.x - line.maxX)
            return sideways ? (across, along) : (along, across)
        }
        guard let line = lines.min(by: { away($0) < away($1) }) else { return nil }
        let inside = inner(line)
        let held = CGPoint(x: min(max(point.x, inside.minX), inside.maxX), y: min(max(point.y, inside.minY), inside.maxY))
        return (line.width >= line.height ? CGPoint(x: held.x, y: line.midY) : CGPoint(x: line.midX, y: held.y), line)
    }

    private static func inner(_ line: CGRect) -> CGRect {
        line.insetBy(dx: min(0.5, line.width / 4), dy: min(0.5, line.height / 4))
    }

    /// The text from the letter under one point to the letter under the other, the way text is selected anywhere.
    static func selection(on page: PDFPage, from start: CGPoint, to end: CGPoint, pageSize: CGSize, lines: [CGRect]? = nil) -> TextSelection? {
        let lines = lines ?? Self.lines(on: page, pageSize: pageSize)
        guard let start = settled(start, among: lines)?.point, let end = settled(end, among: lines)?.point else { return nil }
        let toPDF = NotebookFind.transform(of: page, to: pageSize).inverted()
        return page.selection(from: start.applying(toPDF), to: end.applying(toPDF)).flatMap { made(of: $0, on: page, pageSize: pageSize) }
    }

    /// The word under a point, or nil when the point isn't on the text. PDFKit's own `selectionForWord(at:)` needs
    /// a PDFView behind the page and ends the app without one. Here the line is read from its start to the point and
    /// from the point to its end: the letter under the point is where the two meet.
    static func word(on page: PDFPage, at point: CGPoint, pageSize: CGSize, lines: [CGRect]? = nil) -> TextSelection? {
        let lines = lines ?? Self.lines(on: page, pageSize: pageSize)
        guard lines.contains(where: { $0.insetBy(dx: -4, dy: -4).contains(point) }), let (held, line) = settled(point, among: lines),
              let text = page.string as NSString? else { return nil }
        let toPDF = NotebookFind.transform(of: page, to: pageSize).inverted(), inside = inner(line), sideways = line.width >= line.height
        func range(from start: CGPoint, to end: CGPoint) -> NSRange? {
            guard let run = page.selection(from: start.applying(toPDF), to: end.applying(toPDF)), run.numberOfTextRanges(on: page) > 0 else { return nil }
            let range = run.range(at: 0, on: page)
            return range.length > 0 ? range : nil
        }
        let before = range(from: sideways ? CGPoint(x: inside.minX, y: line.midY) : CGPoint(x: line.midX, y: inside.minY), to: held)
        let after = range(from: held, to: sideways ? CGPoint(x: inside.maxX, y: line.midY) : CGPoint(x: line.midX, y: inside.maxY))
        let place: Int
        switch (before, after) {
        case let (before?, after?): place = max(before.location, after.location)
        case let (nil, after?): place = after.location
        case let (before?, nil): place = before.upperBound - 1
        case (nil, nil): return nil
        }
        guard place < text.length else { return nil }
        // A touch on the last half of a word's last letter meets the space after it.
        var word: NSRange?
        text.enumerateSubstrings(in: text.paragraphRange(for: NSRange(location: place, length: 0)), options: [.byWords, .substringNotRequired]) { _, found, _, stop in
            guard NSLocationInRange(place, found) || found.upperBound == place else { return }
            word = found
            stop.pointee = true
        }
        return word.flatMap { page.selection(for: $0) }.flatMap { made(of: $0, on: page, pageSize: pageSize) }
    }

    static func everything(on page: PDFPage, pageSize: CGSize) -> TextSelection? {
        page.selection(for: page.bounds(for: .cropBox)).flatMap { made(of: $0, on: page, pageSize: pageSize) }
    }

    private static func made(of selection: PDFSelection, on page: PDFPage, pageSize: CGSize) -> TextSelection? {
        let lines = rects(of: selection, on: page, pageSize: pageSize)
        let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return lines.isEmpty || text.isEmpty ? nil : TextSelection(text: text, lines: lines)
    }

    private static func rects(of selection: PDFSelection, on page: PDFPage, pageSize: CGSize) -> [CGRect] {
        let toPage = NotebookFind.transform(of: page, to: pageSize)
        return selection.selectionsByLine().map { $0.bounds(for: page).applying(toPage).standardized }.filter { $0.width > 0.5 && $0.height > 0.5 }
    }

    /// Whether a stroke runs the way a highlighter is drawn along a line of text: sideways, without much wander.
    static func runsAlongALine(_ points: [CGPoint]) -> Bool {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return false }
        let span = hypot(last.x - first.x, last.y - first.y)
        guard abs(last.x - first.x) >= 12, abs(last.y - first.y) <= 0.3 * abs(last.x - first.x) else { return false }
        return points.allSatisfy { ShapeRecognizer.distance($0, toSegment: first, last) <= max(0.12 * span, 9) }
    }

    /// The characters of one line of text that a stroke drawn along it passes over, as one rectangle the height of
    /// the line. Nil when the stroke isn't drawn along a line, or there is no text under it.
    static func line(on page: PDFPage, under points: [CGPoint], pageSize: CGSize) -> CGRect? {
        guard runsAlongALine(points) else { return nil }
        let box = ShapeRecognizer.bounds(of: points)
        let middle = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        let reach = max(box.height / 4, 2)
        let band = CGRect(x: box.minX, y: middle - reach, width: box.width, height: reach * 2)
        let toPDF = NotebookFind.transform(of: page, to: pageSize).inverted()
        guard let touched = page.selection(for: band.applying(toPDF).standardized) else { return nil }
        let lines = rects(of: touched, on: page, pageSize: pageSize).filter { $0.width >= 3 && $0.width > $0.height / 2 }
        // Of the lines the band touches, the one the stroke's middle runs through.
        return lines.filter { $0.minY - 1 <= middle && middle <= $0.maxY + 1 }.min { abs($0.midY - middle) < abs($1.midY - middle) }
    }
}

/// Reads PDF text off the main thread, keeping the documents it has opened. PDFKit's objects never leave it.
actor PDFTextReader {
    enum Request: Sendable {
        case range(from: CGPoint, to: CGPoint)
        case word(at: CGPoint)
        case everything
    }

    private var documents: [String: PDFDocument] = [:]
    private var opened: [String] = []
    /// The lines of the page last selected in, so a drag reads them once.
    private var lines: (key: String, rects: [CGRect])?

    private func lines(of page: PDFPage, file: URL, index: Int, pageSize: CGSize) -> [CGRect] {
        let key = "\(file.lastPathComponent)#\(index)|\(pageSize)"
        if lines?.key != key { lines = (key, PDFText.lines(on: page, pageSize: pageSize)) }
        return lines?.rects ?? []
    }

    private func page(_ file: URL, _ index: Int) -> PDFPage? {
        let key = file.path(percentEncoded: false)
        if documents[key] == nil {
            documents[key] = PDFDocument(url: file)
            opened.append(key)
            if opened.count > 3 { documents[opened.removeFirst()] = nil }
        }
        return documents[key]?.page(at: index)
    }

    func select(_ request: Request, file: URL, index: Int, pageSize: CGSize) -> TextSelection? {
        guard let page = page(file, index) else { return nil }
        switch request {
        case .range(let start, let end):
            return PDFText.selection(on: page, from: start, to: end, pageSize: pageSize, lines: lines(of: page, file: file, index: index, pageSize: pageSize))
        case .word(let point):
            return PDFText.word(on: page, at: point, pageSize: pageSize, lines: lines(of: page, file: file, index: index, pageSize: pageSize))
        case .everything: return PDFText.everything(on: page, pageSize: pageSize)
        }
    }

    func line(under points: [CGPoint], file: URL, index: Int, pageSize: CGSize) -> CGRect? {
        page(file, index).flatMap { PDFText.line(on: $0, under: points, pageSize: pageSize) }
    }
}

/// The colours text is highlighted in from the selection bar.
enum HighlightColor: String, CaseIterable, Identifiable {
    case yellow, green, pink, blue
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .pink: String(localized: "Pink")
        case .blue: String(localized: "Blue")
        }
    }

    var uiColor: UIColor {
        switch self {
        case .yellow: UIColor(hex: 0xFFD426)
        case .green: UIColor(hex: 0x7ED98B)
        case .pink: UIColor(hex: 0xFF8FB8)
        case .blue: UIColor(hex: 0x7CC4FF)
        }
    }

    static var last: HighlightColor {
        get { UserDefaults.standard.string(forKey: SettingsKey.highlightColor).flatMap(HighlightColor.init(rawValue:)) ?? .yellow }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: SettingsKey.highlightColor) }
    }
}

/// A highlighter stroke laid over a line of text: straight, and as tall as the line.
enum TextHighlight {
    /// How much taller than its points' size a marker stroke is drawn, with the chisel held across the stroke.
    static let spread: CGFloat = 1.43

    /// The stroke that covers `rect`. It takes the pressure and opacity of the stroke it stands in for, if there is one.
    static func stroke(over rect: CGRect, ink: PKInk, replacing drawn: PKStroke? = nil, date: Date = .now) -> PKStroke {
        let upright = rect.height > rect.width
        let length = upright ? rect.height : rect.width, thickness = upright ? rect.width : rect.height
        let unit = min(max(thickness / spread, 3), 60)
        // The chisel's ends reach a little past the path's.
        let lead = min(unit * 0.25, length / 2 - 0.5), trail = min(unit * 0.18, length / 2 - 0.5)
        let run = max(length - lead - trail, 1), steps = max(Int(run / 16), 3)
        let sample = drawn.flatMap { stroke in stroke.path.isEmpty ? nil : stroke.path[stroke.path.count / 2] }
        let points = (0...steps).map { step -> PKStrokePoint in
            let along = lead + run * CGFloat(step) / CGFloat(steps)
            let location = upright ? CGPoint(x: rect.midX, y: rect.minY + along) : CGPoint(x: rect.minX + along, y: rect.midY)
            return PKStrokePoint(location: location, timeOffset: 0.2 * Double(step) / Double(steps), size: CGSize(width: unit, height: unit),
                                 opacity: sample?.opacity ?? 1, force: sample?.force ?? 1, azimuth: upright ? 0 : .pi / 2, altitude: .pi / 2)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: drawn?.path.creationDate ?? date))
    }
}

/// Laid over the pages while PDF text is being selected: it takes the touches, and washes what is selected.
/// Rectangles are in stack points, like the ink lasso's.
final class TextSelectOverlay: UIView {
    var scale: CGFloat = 1 {
        didSet { if scale != oldValue { redraw() } }
    }

    private let wash = CAShapeLayer()
    private var rects: [CGRect] = []
    /// Where the touch that is now dragging came down: a pan only begins some way on from there.
    private(set) var touchDown: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        wash.lineWidth = 1
        layer.addSublayer(wash)
        colour()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        colour()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        touchDown = touches.first?.location(in: self)
    }

    private func colour() {
        wash.fillColor = tintColor.withAlphaComponent(0.26).cgColor
        wash.strokeColor = tintColor.withAlphaComponent(0.7).cgColor
    }

    func show(_ rects: [CGRect]) {
        self.rects = rects
        redraw()
    }

    private func redraw() {
        let path = CGMutablePath()
        for rect in rects {
            let box = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).insetBy(dx: -1, dy: 0)
            let corner = min(2, box.width / 2, box.height / 2)
            path.addRoundedRect(in: box, cornerWidth: corner, cornerHeight: corner)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.path = rects.isEmpty ? nil : path
        CATransaction.commit()
    }
}
