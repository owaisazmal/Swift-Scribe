import XCTest
import PDFKit
import PencilKit
@testable import OwlLuna

/// A PDF page's own text: selecting it, finding the line a highlighter was drawn along, and the stroke laid over it.
final class PDFTextTests: XCTestCase {
    private let size = PageSize.letter.points

    /// One page: a heading at 72 pt down, then six lines of body text from 130 pt down, 20 pt apart.
    private func makePage(rotated: Bool = false) throws -> PDFPage {
        let url = FileManager.default.temporaryDirectory.appending(path: "pdftext-\(UUID().uuidString).pdf")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).writePDF(to: url) { context in
            context.beginPage()
            ("Chapter One" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 28)])
            for line in 0..<6 {
                ("Body text line \(line + 1) of the page." as NSString)
                    .draw(at: CGPoint(x: 72, y: 130 + CGFloat(line) * 20), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
            }
        }
        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        if rotated { page.rotation = 90 }
        return page
    }

    func testADragSelectsFromTheLetterItBeganOnToTheLetterItReached() throws {
        let page = try makePage()
        let one = try XCTUnwrap(PDFText.selection(on: page, from: CGPoint(x: 74, y: 137), to: CGPoint(x: 300, y: 137), pageSize: size))
        XCTAssertEqual(one.text, "Body text line 1 of the page.")
        XCTAssertEqual(one.lines.count, 1)
        let line = try XCTUnwrap(one.lines.first)
        XCTAssertEqual(line.minX, 72, accuracy: 2)
        XCTAssertEqual(line.midY, 137, accuracy: 4, "the rectangle is where the line is shown, measured from the top of the page")
        XCTAssertLessThan(line.height, 20)

        let three = try XCTUnwrap(PDFText.selection(on: page, from: CGPoint(x: 100, y: 137), to: CGPoint(x: 120, y: 177), pageSize: size))
        XCTAssertEqual(three.lines.count, 3, "down the page it takes in the lines between")
        XCTAssertTrue(three.text.contains("line 2"))
        XCTAssertFalse(three.text.contains("line 4"))

        // Off the text, a touch counts as on the nearest line and no further than its ends.
        let lines = PDFText.lines(on: page, pageSize: size)
        XCTAssertEqual(lines.count, 7)
        XCTAssertEqual(PDFText.settled(CGPoint(x: 500, y: 139), among: lines)?.point.x ?? 0, line.maxX, accuracy: 1)
        XCTAssertEqual(PDFText.settled(CGPoint(x: 500, y: 139), among: lines)?.point.y ?? 0, line.midY, accuracy: 0.1)
        let below = try XCTUnwrap(PDFText.selection(on: page, from: CGPoint(x: 20, y: 228), to: CGPoint(x: 600, y: 700), pageSize: size))
        XCTAssertEqual(below.text, "Body text line 6 of the page.", "from the margin beside the last line to the foot of the page")
        let backwards = try XCTUnwrap(PDFText.selection(on: page, from: CGPoint(x: 300, y: 157), to: CGPoint(x: 74, y: 137), pageSize: size))
        XCTAssertEqual(backwards.lines.count, 2, "dragged back up the page, it selects the same text")
        XCTAssertNil(PDFText.settled(CGPoint(x: 10, y: 10), among: [])?.point, "a page without text")
    }

    func testATapSelectsAWordAndNothingOffTheText() throws {
        let page = try makePage()
        XCTAssertEqual(PDFText.word(on: page, at: CGPoint(x: 90, y: 90), pageSize: size)?.text, "Chapter")
        XCTAssertEqual(PDFText.word(on: page, at: CGPoint(x: 104, y: 137), pageSize: size)?.text, "text")
        XCTAssertEqual(PDFText.word(on: page, at: CGPoint(x: 215, y: 236), pageSize: size)?.text, "page", "the full stop after it isn't part of the word")
        XCTAssertNil(PDFText.word(on: page, at: CGPoint(x: 400, y: 500), pageSize: size), "PDFKit would offer the nearest word")
    }

    func testTheWholePageIsSevenLines() throws {
        let all = try XCTUnwrap(PDFText.everything(on: try makePage(), pageSize: size))
        XCTAssertEqual(all.lines.count, 7)
        XCTAssertTrue(all.text.hasPrefix("Chapter One"))
        XCTAssertTrue(all.text.hasSuffix("line 6 of the page."))
    }

    func testATurnedPageKeepsItsTextOnThePage() throws {
        let turned = CGSize(width: size.height, height: size.width)
        let all = try XCTUnwrap(PDFText.everything(on: try makePage(rotated: true), pageSize: turned))
        let page = CGRect(origin: .zero, size: turned)
        XCTAssertTrue(all.lines.allSatisfy { page.contains($0) })
        XCTAssertTrue(all.lines.allSatisfy { $0.height > $0.width }, "its lines now run down the page")
    }

    /// A stroke the way a hand draws a highlighter along a line: left to right, never quite level.
    private func wobble(from start: CGFloat, to end: CGFloat, y: CGFloat) -> [CGPoint] {
        stride(from: start, through: end, by: 6).map { CGPoint(x: $0, y: y + 2.5 * sin($0 / 15)) }
    }

    func testAHighlighterDrawnAlongALineIsGivenThatLine() throws {
        let page = try makePage()
        let whole = try XCTUnwrap(PDFText.selection(on: page, from: CGPoint(x: 74, y: 177), to: CGPoint(x: 300, y: 177), pageSize: size)?.lines.first)
        let line = try XCTUnwrap(PDFText.line(on: page, under: wobble(from: 60, to: 320, y: 178), pageSize: size))
        XCTAssertEqual(line.minY, whole.minY, accuracy: 0.5, "as tall as the line of text")
        XCTAssertEqual(line.height, whole.height, accuracy: 0.5)
        XCTAssertEqual(line.minX, whole.minX, accuracy: 1, "and no wider than its words, however far the stroke ran on")
        XCTAssertEqual(line.maxX, whole.maxX, accuracy: 1)

        let part = try XCTUnwrap(PDFText.line(on: page, under: wobble(from: 100, to: 150, y: 176), pageSize: size))
        XCTAssertGreaterThan(part.minX, whole.minX + 10, "a stroke over part of the line takes the letters it passed over")
        XCTAssertLessThan(part.maxX, whole.maxX - 10)
        XCTAssertEqual(part.height, whole.height, accuracy: 0.5)
    }

    func testOtherStrokesAreLeftAsTheyWereDrawn() throws {
        let page = try makePage()
        XCTAssertNil(PDFText.line(on: page, under: wobble(from: 60, to: 320, y: 500), pageSize: size), "nothing is written there")
        XCTAssertNil(PDFText.line(on: page, under: stride(from: CGFloat(120), through: 240, by: 6).map { CGPoint(x: 100, y: $0) }, pageSize: size), "down the page")
        XCTAssertNil(PDFText.line(on: page, under: stride(from: CGFloat(0), through: 120, by: 6).map { CGPoint(x: 80 + $0, y: 130 + $0 * 0.6) }, pageSize: size), "slanting")
        XCTAssertNil(PDFText.line(on: page, under: [CGPoint(x: 80, y: 137), CGPoint(x: 84, y: 137)], pageSize: size), "a dot")
        let zigzag = stride(from: CGFloat(60), through: 300, by: 6).map { CGPoint(x: $0, y: 150 + 30 * sin($0 / 8)) }
        XCTAssertFalse(PDFText.runsAlongALine(zigzag), "shading back and forth over a paragraph")
    }

    func testTheStrokeLaidOverALineCoversItAndNoMore() throws {
        for rect in [CGRect(x: 72, y: 170, width: 160, height: 13), CGRect(x: 100, y: 300, width: 320, height: 22), CGRect(x: 200, y: 100, width: 30, height: 34)] {
            let stroke = TextHighlight.stroke(over: rect, ink: PKInk(.marker, color: HighlightColor.yellow.uiColor))
            let frame = rect.insetBy(dx: -40, dy: -40)
            let inked = try XCTUnwrap(Self.inked(PKDrawing(strokes: [stroke]).image(from: frame, scale: 2), scale: 2)).offsetBy(dx: frame.minX, dy: frame.minY)
            XCTAssertEqual(inked.minY, rect.minY, accuracy: 2.5, "\(rect)")
            XCTAssertEqual(inked.maxY, rect.maxY, accuracy: 2.5, "\(rect)")
            XCTAssertEqual(inked.minX, rect.minX, accuracy: 3, "\(rect)")
            XCTAssertEqual(inked.maxX, rect.maxX, accuracy: 3, "\(rect)")
        }
        let upright = CGRect(x: 300, y: 100, width: 14, height: 200)
        let stroke = TextHighlight.stroke(over: upright, ink: PKInk(.marker, color: .yellow))
        XCTAssertEqual(stroke.renderBounds.midX, upright.midX, accuracy: 2)
        XCTAssertGreaterThan(stroke.renderBounds.height, 190, "text that runs down the page is covered down the page")
        XCTAssertLessThan(stroke.renderBounds.width, 26)
    }

    func testItStandsInForTheStrokeThatWasDrawn() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let points = (0...8).map { PKStrokePoint(location: CGPoint(x: 80 + CGFloat($0) * 10, y: 176), timeOffset: Double($0) * 0.02, size: CGSize(width: 20, height: 20),
                                                 opacity: 0.8, force: 1, azimuth: 0, altitude: .pi / 2) }
        let ink = PKInk(.marker, color: .systemPink)
        let drawn = PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: date))
        let laid = TextHighlight.stroke(over: CGRect(x: 72, y: 170, width: 160, height: 13), ink: drawn.ink, replacing: drawn)
        XCTAssertEqual(laid.path.creationDate, date, "written when the drawn stroke was, so a replay shows it at the same moment")
        XCTAssertEqual(laid.ink.inkType, .marker)
        XCTAssertEqual(laid.path.first?.opacity ?? 0, 0.8, accuracy: 0.01)
    }

    /// The part of an image that holds ink, in points.
    private static func inked(_ image: UIImage, scale: CGFloat) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 40 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        // The bitmap's first row is the image's last.
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(height - 1 - maxY) / scale, width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }
}
