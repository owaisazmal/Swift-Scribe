import XCTest
import PencilKit
import PDFKit
@testable import NotesApp

final class NotebookLayoutTests: XCTestCase {
    private func page(_ size: PageSize = .letter) -> PageSpec {
        .template(.blank, color: .white, size: size)
    }

    func testPagesStackVerticallyAtFixedWidth() {
        let layout = NotebookLayout(pages: [page(), page(.a4)])
        XCTAssertEqual(layout.frames.count, 2)
        XCTAssertEqual(layout.frames[0].width, NotebookLayout.pageWidth)
        XCTAssertEqual(layout.frames[0].height, (800 * 792 / 612).rounded())
        XCTAssertEqual(layout.frames[1].minY, layout.frames[0].maxY + NotebookLayout.pageGap)
    }

    func testPageIndexAtY() {
        let layout = NotebookLayout(pages: [page(), page(), page()])
        XCTAssertEqual(layout.pageIndex(atY: 0), 0)
        XCTAssertEqual(layout.pageIndex(atY: layout.frames[1].midY), 1)
        XCTAssertEqual(layout.pageIndex(atY: layout.frames[2].maxY + 500), 2)
    }
}

final class PageRemapperTests: XCTestCase {
    private func stroke(atY y: CGFloat) -> PKStroke {
        let points = [
            PKStrokePoint(location: CGPoint(x: 100, y: y), timeOffset: 0, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: 200, y: y), timeOffset: 0.1, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
        ]
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))
    }

    private let pages = (0..<3).map { _ in PageSpec.template(.blank, color: .white, size: .letter) }

    private func drawingWithOneStrokePerPage() -> PKDrawing {
        let layout = NotebookLayout(pages: pages)
        return PKDrawing(strokes: layout.frames.map { stroke(atY: $0.minY + 50) })
    }

    private func pageIndices(of drawing: PKDrawing, pages: [PageSpec]) -> [Int] {
        let layout = NotebookLayout(pages: pages)
        return drawing.strokes.map { layout.pageIndex(atY: $0.renderBounds.midY) }.sorted()
    }

    func testDeletingPageRemovesItsInkAndShiftsLaterPages() {
        let entries = [pages[0], pages[2]].map { (page: $0, source: Optional($0.id)) }
        let result = PageRemapper.remap(drawing: drawingWithOneStrokePerPage(), oldPages: pages, newPages: entries)
        XCTAssertEqual(result.strokes.count, 2)
        XCTAssertEqual(pageIndices(of: result, pages: entries.map(\.page)), [0, 1])
    }

    func testInsertingBlankPageKeepsInkWithOriginalPages() {
        let inserted = PageSpec.template(.grid, color: .white, size: .letter)
        let entries = [(page: pages[0], source: Optional(pages[0].id)), (page: inserted, source: nil),
                       (page: pages[1], source: Optional(pages[1].id)), (page: pages[2], source: Optional(pages[2].id))]
        let result = PageRemapper.remap(drawing: drawingWithOneStrokePerPage(), oldPages: pages, newPages: entries)
        XCTAssertEqual(pageIndices(of: result, pages: entries.map(\.page)), [0, 2, 3])
    }

    func testMovingPageMovesItsInk() {
        let original = drawingWithOneStrokePerPage()
        let entries = [pages[2], pages[0], pages[1]].map { (page: $0, source: Optional($0.id)) }
        let result = PageRemapper.remap(drawing: original, oldPages: pages, newPages: entries)
        let layout = NotebookLayout(pages: entries.map(\.page))
        let firstPageStroke = result.strokes.first { layout.pageIndex(atY: $0.renderBounds.midY) == 0 }
        XCTAssertEqual(firstPageStroke?.renderBounds.midY ?? 0, layout.frames[0].minY + 50, accuracy: 3)
        XCTAssertEqual(result.strokes.count, 3)
    }

    func testDuplicatingPageCopiesInk() {
        var copy = pages[0]
        copy.id = UUID()
        let entries = [(page: pages[0], source: Optional(pages[0].id)), (page: copy, source: Optional(pages[0].id)),
                       (page: pages[1], source: Optional(pages[1].id)), (page: pages[2], source: Optional(pages[2].id))]
        let result = PageRemapper.remap(drawing: drawingWithOneStrokePerPage(), oldPages: pages, newPages: entries)
        XCTAssertEqual(pageIndices(of: result, pages: entries.map(\.page)), [0, 1, 2, 3])
    }
}

final class PDFRoundTripTests: XCTestCase {
    private var notebookID = UUID()

    override func tearDown() {
        NotebookStore.deleteFiles(for: notebookID)
        super.tearDown()
    }

    private func makePDF(pageSizes: [CGSize]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSizes[0]))
        try renderer.writePDF(to: url) { context in
            for size in pageSizes {
                context.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                ("Mitochondria" as NSString).draw(at: CGPoint(x: 40, y: 40),
                                                  withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
        return url
    }

    func testImportCreatesOnePagePerPDFPage() throws {
        let source = try makePDF(pageSizes: [CGSize(width: 612, height: 792), CGSize(width: 792, height: 612)])
        let pages = try NotebookImporter.pdfPages(from: source, notebookID: notebookID)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[1].size, CGSize(width: 792, height: 612))
        guard case .pdf(_, let index) = pages[1].background else { return XCTFail("Expected PDF background") }
        XCTAssertEqual(index, 1)
    }

    func testExportKeepsPageCountSizesAndText() throws {
        let source = try makePDF(pageSizes: [CGSize(width: 612, height: 792)])
        var pages = try NotebookImporter.pdfPages(from: source, notebookID: notebookID)
        pages.append(.template(.dotted, color: .ivory, size: .a4))
        let url = try PDFExporter.export(title: "Bio: Cells", pages: pages, drawing: PKDrawing(), notebookID: notebookID)
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(url.lastPathComponent, "Bio- Cells.pdf")
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.page(at: 1)?.bounds(for: .mediaBox).size.width ?? 0, 595.28, accuracy: 0.1)
        XCTAssertTrue(document.page(at: 0)?.string?.contains("Mitochondria") ?? false)
    }

    func testPageSpecRoundTripsThroughNotebookStorage() {
        let notebook = Notebook(title: "Test", template: .cornell, color: .yellow, size: .a5)
        var pages = notebook.pages
        pages.append(PageSpec(background: .image(file: "x.jpg"), paperColor: .white, size: CGSize(width: 612, height: 400)))
        notebook.pages = pages
        XCTAssertEqual(notebook.pages, pages)
        XCTAssertEqual(notebook.pageCount, 2)
        XCTAssertEqual(notebook.pages.first?.template, .cornell)
    }
}
