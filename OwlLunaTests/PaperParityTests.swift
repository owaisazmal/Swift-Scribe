import XCTest
import PencilKit
@testable import OwlLuna

/// `PageRenderer.drawTemplate` as it was before the Paper Pack, kept verbatim as the golden for the original papers.
private enum LegacyTemplates {
    static func draw(_ template: PaperTemplate, color: PaperColor, in ctx: CGContext, size: CGSize) {
        let unit = size.width / 800
        let line = color.isDark ? UIColor(white: 1, alpha: 0.16) : UIColor(red: 0.55, green: 0.68, blue: 0.84, alpha: 0.55)
        let accent = color.isDark ? UIColor(red: 1, green: 0.45, blue: 0.45, alpha: 0.35) : UIColor(red: 0.9, green: 0.35, blue: 0.35, alpha: 0.45)
        ctx.saveGState()
        ctx.setLineWidth(max(0.5, unit))

        func hLines(spacing: CGFloat, from top: CGFloat) {
            var y = top
            while y < size.height - 20 * unit {
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            ctx.setStrokeColor(line.cgColor)
            ctx.strokePath()
        }

        func marginLine(x: CGFloat) {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: size.height))
            ctx.setStrokeColor(accent.cgColor)
            ctx.strokePath()
        }

        switch template {
        case .blank:
            break
        case .narrowRuled:
            hLines(spacing: 28 * unit, from: 120 * unit)
            marginLine(x: 104 * unit)
        case .wideRuled:
            hLines(spacing: 38 * unit, from: 120 * unit)
            marginLine(x: 104 * unit)
        case .grid:
            let spacing = 26 * unit
            var x = spacing
            while x < size.width { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
            var y = spacing
            while y < size.height { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
            ctx.setStrokeColor(line.withAlphaComponent(color.isDark ? 0.12 : 0.35).cgColor)
            ctx.strokePath()
        case .dotted:
            let spacing = 26 * unit
            let r = max(0.8, 1.6 * unit)
            ctx.setFillColor(line.withAlphaComponent(color.isDark ? 0.35 : 0.9).cgColor)
            var y = spacing
            while y < size.height {
                var x = spacing
                while x < size.width {
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += spacing
                }
                y += spacing
            }
        case .cornell:
            let summaryTop = size.height * 0.8
            let cueRight = 240 * unit
            var y = 120 * unit
            while y < summaryTop { ctx.move(to: CGPoint(x: cueRight, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y)); y += 30 * unit }
            ctx.setStrokeColor(line.cgColor)
            ctx.strokePath()
            ctx.setLineWidth(max(1, 2 * unit))
            ctx.move(to: CGPoint(x: 0, y: 90 * unit)); ctx.addLine(to: CGPoint(x: size.width, y: 90 * unit))
            ctx.move(to: CGPoint(x: cueRight, y: 90 * unit)); ctx.addLine(to: CGPoint(x: cueRight, y: summaryTop))
            ctx.move(to: CGPoint(x: 0, y: summaryTop)); ctx.addLine(to: CGPoint(x: size.width, y: summaryTop))
            ctx.setStrokeColor(accent.cgColor)
            ctx.strokePath()
        case .music:
            let staffGap = 10 * unit
            let staffHeight = staffGap * 4
            var top = 100 * unit
            while top + staffHeight < size.height - 60 * unit {
                for i in 0..<5 {
                    let y = top + CGFloat(i) * staffGap
                    ctx.move(to: CGPoint(x: 60 * unit, y: y)); ctx.addLine(to: CGPoint(x: size.width - 60 * unit, y: y))
                }
                top += staffHeight + 60 * unit
            }
            ctx.setStrokeColor((color.isDark ? UIColor(white: 1, alpha: 0.3) : UIColor(white: 0.35, alpha: 0.7)).cgColor)
            ctx.strokePath()
        default:
            break
        }
        ctx.restoreGState()
    }
}

/// RGBA pixels drawn into a top-left-origin context, the way UIKit and the tiled layers hand contexts to the renderer.
private struct Bitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(size: CGSize, scale: CGFloat = 1, draw: (CGContext) -> Void) {
        width = Int((size.width * scale).rounded())
        height = Int((size.height * scale).rounded())
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        let (w, h) = (width, height)
        pixels.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: scale, y: -scale)
            draw(ctx)
        }
    }

    func maxDifference(to other: Bitmap) -> Int {
        let same = pixels.withUnsafeBytes { a in other.pixels.withUnsafeBytes { b in a.count == b.count && memcmp(a.baseAddress, b.baseAddress, a.count) == 0 } }
        if same { return 0 }
        return pixels.withUnsafeBufferPointer { a in
            other.pixels.withUnsafeBufferPointer { b in
                var worst: Int32 = 0
                for i in 0..<min(a.count, b.count) { worst = max(worst, abs(Int32(a[i]) - Int32(b[i]))) }
                return Int(worst)
            }
        }
    }

    /// Mean luminance (0–255) of each `cell`-pixel square.
    func cellLuminance(_ cell: Int) -> [Double] {
        var means: [Double] = []
        for top in stride(from: 0, to: height, by: cell) {
            for left in stride(from: 0, to: width, by: cell) {
                var sum = 0.0, count = 0.0
                for y in top..<min(top + cell, height) {
                    for x in left..<min(left + cell, width) {
                        let i = (y * width + x) * 4
                        sum += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
                        count += 1
                    }
                }
                means.append(sum / count)
            }
        }
        return means
    }

    func luminance(at point: CGPoint) -> CGFloat {
        let i = (Int(point.y) * width + Int(point.x)) * 4
        return (0.2126 * CGFloat(pixels[i]) + 0.7152 * CGFloat(pixels[i + 1]) + 0.0722 * CGFloat(pixels[i + 2])) / 255
    }

    init(image: UIImage) {
        self.init(size: image.size, scale: image.scale) { ctx in
            UIGraphicsPushContext(ctx)
            image.draw(at: .zero)
            UIGraphicsPopContext()
        }
    }
}

final class PaperParityTests: XCTestCase {
    private let originals: [PaperTemplate] = [.blank, .narrowRuled, .wideRuled, .grid, .dotted, .cornell, .music]
    private let assets = FileManager.default.temporaryDirectory

    private func paper(_ color: PaperColor, _ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(PageRenderer.paperColor(color).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
    }

    func testExistingTemplatesArePixelIdentical() {
        let size = CGSize(width: 200, height: 259)
        for template in originals {
            for color in [PaperColor.white, .charcoal] {
                for scale in [1.0, 3.0] {
                    let before = Bitmap(size: size, scale: scale) { paper(color, $0, size); LegacyTemplates.draw(template, color: color, in: $0, size: size) }
                    let after = Bitmap(size: size, scale: scale) { paper(color, $0, size); PageRenderer.drawTemplate(template, color: color, in: $0, size: size) }
                    XCTAssertEqual(before.pixels, after.pixels, "\(template) on \(color) at \(scale)×")
                }
            }
        }
    }

    func testChunkedDrawingMatchesWholePage() {
        for template in PaperTemplate.allCases {
            for color in [PaperColor.white, .chalkboard] {
                for size in [PageSize.letter, .widescreen] {
                    let page = NotebookPage.template(template, color: color, size: size)
                    let whole = Bitmap(size: page.size, scale: 2) { PageRenderer.drawBackground(page, assets: assets, in: $0, size: page.size) }
                    for chunk in [256, 97] as [CGFloat] {
                        let tiled = Bitmap(size: page.size, scale: 2) { ctx in
                            for y in stride(from: 0, to: page.size.height, by: chunk) {
                                for x in stride(from: 0, to: page.size.width, by: chunk) {
                                    let region = CGRect(x: x, y: y, width: min(chunk, page.size.width - x), height: min(chunk, page.size.height - y))
                                    ctx.saveGState()
                                    ctx.translateBy(x: region.minX, y: region.minY)
                                    ctx.clip(to: CGRect(origin: .zero, size: region.size))
                                    ctx.translateBy(x: -region.minX, y: -region.minY)
                                    PageRenderer.drawBackground(page, assets: assets, in: ctx, size: page.size)
                                    ctx.restoreGState()
                                }
                            }
                        }
                        XCTAssertLessThanOrEqual(whole.maxDifference(to: tiled), 2, "\(template) on \(color), \(size), \(chunk)-point chunks")
                    }
                }
            }
        }
    }

    func testExportMatchesScreen() async throws {
        let root = temporaryRoot(self)
        let id = UUID()
        let package = NotebookPackage(root: root, id: id)
        let pages = [PaperColor.white, .chalkboard].flatMap { color in
            PaperTemplate.allCases.map { NotebookPage.template($0, color: color, size: $0 == .storyboard ? .widescreen : .letter) }
        }
        try await package.create(NotebookManifest(id: id, title: "Paper", defaults: PageDefaults(template: .blank, paperColor: .white, pageSize: .letter),
                                                  pages: pages))
        let url = try await NotebookExporter.export(.init(title: "Paper", pages: pages, inMemoryInk: [:], package: package)) { _ in }
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, pages.count)
        for (index, page) in pages.enumerated() {
            let pdfPage = try XCTUnwrap(pdf.page(at: index + 1))
            let exported = Bitmap(size: page.size) { ctx in
                paper(.white, ctx, page.size)
                PageRenderer.drawPDFPage(pdfPage, in: ctx, size: page.size)
            }
            let screen = Bitmap(image: PageRenderer.image(of: page, ink: PKDrawing(), assets: package.assetsDirectory, width: page.size.width))
            let worst = zip(exported.cellLuminance(16), screen.cellLuminance(16)).map { abs($0 - $1) }.max() ?? 0
            XCTAssertLessThanOrEqual(worst, 6, "\(page.template?.rawValue ?? "") on \(page.paperColor)")
        }
    }

    func testChalkboardInkRendersLight() throws {
        let drawing = PKDrawing(strokes: [stroke(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 400, y: 300), width: 10)])
        let chalk = NotebookPage.template(.narrowRuled, color: .chalkboard, size: .letter)
        let onChalk = Bitmap(image: PageRenderer.image(of: chalk, ink: drawing, assets: assets, width: chalk.size.width))
        XCTAssertGreaterThan(onChalk.luminance(at: CGPoint(x: 250, y: 300)), 0.7, "black ink writes chalk-white on Chalkboard")
        XCTAssertLessThan(onChalk.luminance(at: CGPoint(x: 250, y: 600)), 0.3)

        let forOCR = Bitmap(image: PageRenderer.image(of: chalk, ink: drawing, assets: assets, width: chalk.size.width, includeBackground: false))
        XCTAssertLessThan(forOCR.luminance(at: CGPoint(x: 250, y: 300)), 0.3, "handwriting search reads dark ink on white")
        XCTAssertGreaterThan(forOCR.luminance(at: CGPoint(x: 250, y: 600)), 0.9)

        let charcoal = NotebookPage.template(.narrowRuled, color: .charcoal, size: .letter)
        let rendered = Bitmap(image: PageRenderer.image(of: charcoal, ink: drawing, assets: assets, width: charcoal.size.width))
        var ink: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent { ink = drawing.image(from: CGRect(origin: .zero, size: charcoal.size), scale: 1) }
        let golden = Bitmap(size: charcoal.size) { ctx in
            paper(.charcoal, ctx, charcoal.size)
            LegacyTemplates.draw(.narrowRuled, color: .charcoal, in: ctx, size: charcoal.size)
            UIGraphicsPushContext(ctx)
            ink?.draw(in: CGRect(origin: .zero, size: charcoal.size))
            UIGraphicsPopContext()
        }
        XCTAssertLessThanOrEqual(rendered.maxDifference(to: golden), 1, "Charcoal pages and their ink render as before")
        XCTAssertLessThan(rendered.luminance(at: CGPoint(x: 250, y: 300)), 0.3)
    }

    func testLightPaperIsDarkAtNightAndKeepsItsColourWhenExported() async throws {
        let drawing = PKDrawing(strokes: [stroke(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 400, y: 300), width: 10)])
        let ink = CGPoint(x: 250, y: 300), bare = CGPoint(x: 250, y: 610)
        for color in PaperColor.allCases where !color.isDark {
            let page = NotebookPage.template(.blank, color: color, size: .letter)
            let night = Bitmap(image: PageRenderer.image(of: page, ink: drawing, assets: assets, width: page.size.width, night: true))
            XCTAssertLessThan(night.luminance(at: bare), 0.2, "\(color) is shown dark")
            XCTAssertGreaterThan(night.luminance(at: ink), 0.7, "black ink is light on it")
            let day = Bitmap(image: PageRenderer.image(of: page, ink: drawing, assets: assets, width: page.size.width))
            XCTAssertGreaterThan(day.luminance(at: bare), 0.6, "\(color) keeps its colour by day")
            XCTAssertLessThan(day.luminance(at: ink), 0.3)
        }

        let chalk = NotebookPage.template(.blank, color: .chalkboard, size: .letter)
        XCTAssertEqual(PageRenderer.image(of: chalk, ink: drawing, assets: assets, width: chalk.size.width, night: true).pngData(),
                       PageRenderer.image(of: chalk, ink: drawing, assets: assets, width: chalk.size.width).pngData(), "dark paper is as it was")
        let scan = NotebookPage(background: .image(file: "missing.png"), paperColor: .white, size: PageSize.letter.points)
        XCTAssertFalse(scan.turnsDark(true), "a photo or a PDF keeps its own colours")
        XCTAssertEqual(scan.inkAppearance(night: true), .light)

        let root = temporaryRoot(self), id = UUID()
        let package = NotebookPackage(root: root, id: id)
        let page = NotebookPage.template(.blank, color: .white, size: .letter)
        try await package.create(NotebookManifest(id: id, title: "Night", defaults: PageDefaults(template: .blank, paperColor: .white, pageSize: .letter),
                                                  pages: [page]))
        let input = NotebookExporter.Input(title: "Night", pages: [page], inMemoryInk: [page.id: drawing], package: package)
        let urls = try await NotebookExporter.exportImages(input) { _ in }
        let image = try XCTUnwrap(UIImage(contentsOfFile: try XCTUnwrap(urls.first).path(percentEncoded: false)))
        let bitmap = Bitmap(image: image), k = image.size.width / page.size.width
        XCTAssertGreaterThan(bitmap.luminance(at: CGPoint(x: bare.x * k, y: bare.y * k)), 0.9, "white paper is exported white")
        XCTAssertLessThan(bitmap.luminance(at: CGPoint(x: ink.x * k, y: ink.y * k)), 0.3, "and its ink dark")

        XCTAssertNotEqual(PageThumbnailer.key(for: page, night: true), PageThumbnailer.key(for: page, night: false))
        XCTAssertEqual(PageThumbnailer.key(for: chalk, night: true), chalk.thumbnailKey)
    }

    func testTileTimeAtFiveX() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OWLLUNA_PERF"] == "1", "Set OWLLUNA_PERF=1 to run")
        let scale: CGFloat = 10, tile: CGFloat = 512 / 10
        var report: [String] = []
        for template in PaperTemplate.allCases {
            let page = NotebookPage.template(template, color: .white, size: .letter)
            var worst = 0.0
            for y in stride(from: 0, to: page.size.height - tile, by: tile * 2.5) {
                for x in stride(from: 0, to: page.size.width - tile, by: tile * 2.5) {
                    var times: [Double] = []
                    for _ in 0..<7 {
                        _ = Bitmap(size: CGSize(width: tile, height: tile), scale: scale) { ctx in
                            ctx.clip(to: CGRect(x: 0, y: 0, width: tile, height: tile))
                            ctx.translateBy(x: -x, y: -y)
                            let start = CACurrentMediaTime()
                            PageRenderer.drawBackground(page, assets: assets, in: ctx, size: page.size)
                            times.append((CACurrentMediaTime() - start) * 1000)
                        }
                    }
                    worst = max(worst, times.sorted()[times.count / 2])
                }
            }
            report.append("\(template.rawValue) \(String(format: "%.2f", worst)) ms")
            XCTAssertLessThan(worst, 2, "\(template): densest 512 px tile at 5×")
        }
        print("TILE AT 5x (median, densest tile): \(report.joined(separator: ", "))")
    }

    func testPaperFamiliesCoverEveryTemplateOnce() {
        let listed = PaperFamily.allCases.flatMap(\.templates)
        XCTAssertEqual(listed.count, PaperTemplate.allCases.count)
        XCTAssertEqual(Set(listed), Set(PaperTemplate.allCases))
        for family in PaperFamily.allCases {
            for template in family.templates { XCTAssertEqual(template.family, family) }
        }
    }

    func testNewPaperRoundTripsAndOlderBuildsKeepTheRawValues() throws {
        var page = NotebookPage.template(.weekPlanner, color: .chalkboard, size: .a5)
        XCTAssertEqual(page.template, .weekPlanner)
        XCTAssertEqual(page.paperColor, .chalkboard)
        page.background = .template("fromTheFuture")
        page.paperColorRaw = "neon"
        XCTAssertEqual(page.template, .blank, "an unknown template draws as blank")
        XCTAssertEqual(page.paperColor, .white)
        XCTAssertEqual(page.background, .template("fromTheFuture"), "and its raw value is kept")
        XCTAssertEqual(page.paperColorRaw, "neon")
    }

    func testTemplateContactSheet() {
        let width: CGFloat = 150, gap: CGFloat = 12
        let colors: [PaperColor] = [.white, .kraft, .charcoal, .chalkboard]
        let templates = PaperFamily.allCases.flatMap(\.templates)
        let height = width * PageSize.letter.points.height / PageSize.letter.points.width
        let size = CGSize(width: gap + CGFloat(templates.count) * (width + gap), height: gap + CGFloat(colors.count) * (height + gap))
        let sheet = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hex: 0xE7E2D7).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (row, color) in colors.enumerated() {
                for (column, template) in templates.enumerated() {
                    let page = NotebookPage.template(template, color: color, size: .letter)
                    PageRenderer.image(of: page, ink: PKDrawing(), assets: assets, width: width, scale: 2)
                        .draw(at: CGPoint(x: gap + CGFloat(column) * (width + gap), y: gap + CGFloat(row) * (height + gap)))
                }
            }
        }
        let attachment = XCTAttachment(image: sheet)
        attachment.name = "paper-contact-sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
