import XCTest
import PDFKit
import PencilKit
@testable import OwlLuna

/// Find in a notebook: where the words are in typed text, PDF text and handwriting, and the order matches are shown in.
@MainActor
final class FindTests: XCTestCase {
    private let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)

    private func textBox(_ string: String, at center: CGPoint) -> PageItem {
        PageItem(content: .text(TextBox(string: string)), center: center, size: CGSize(width: 200, height: 40))
    }

    private func makeDocument(_ pages: [NotebookPage], ink: [UUID: PKDrawing] = [:]) async throws -> NotebookDocument {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Find", defaults: paper, pages: pages)
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        if !ink.isEmpty { _ = try await package.write(SaveSnapshot(manifest: manifest, ink: ink)) }
        return try await NotebookDocument.open(manifest.id, root: root)
    }

    private func finish(_ finder: NotebookFinder) async {
        for _ in 0..<400 where finder.isSearching { try? await Task.sleep(for: .milliseconds(25)) }
    }

    func testATextBoxHoldingTheWordsIsMarkedWhole() {
        var page = paper.newPage()
        page.items = [textBox("Mitochondria make ATP", at: CGPoint(x: 200, y: 100)), textBox("Ribosomes", at: CGPoint(x: 200, y: 300))]
        XCTAssertEqual(NotebookFind.typed("atp", on: page), [CGRect(x: 100, y: 80, width: 200, height: 40)])
        XCTAssertEqual(NotebookFind.typed("RIBO", on: page).count, 1, "whatever the case")
        XCTAssertTrue(NotebookFind.typed("golgi", on: page).isEmpty)
        var turned = page
        turned.items[0].rotation = .pi / 2
        XCTAssertEqual(NotebookFind.typed("atp", on: turned)[0].integral, CGRect(x: 180, y: 0, width: 40, height: 200), "a turned box is marked by the room it takes")
    }

    func testWordsInAPDFAreFoundWhereTheyArePrinted() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "find-\(UUID().uuidString).pdf")
        let bounds = CGRect(origin: .zero, size: PageSize.letter.points)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: url) { context in
            context.beginPage()
            ("Chapter Seven" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 28)])
            ("The seven sisters and seven seas" as NSString).draw(at: CGPoint(x: 72, y: 400), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        let rects = NotebookFind.inReadingOrder(NotebookFind.pdfRects(for: "seven", on: page, pageSize: bounds.size))
        XCTAssertEqual(rects.count, 3)
        XCTAssertEqual(rects[0].midY, 89, accuracy: 12, "the heading, measured from the top of the page")
        XCTAssertGreaterThan(rects[0].minX, 150)
        XCTAssertEqual(rects[1].midY, 408, accuracy: 10)
        XCTAssertLessThan(rects[1].minX, rects[2].minX, "matches on a line run left to right")
        XCTAssertTrue(NotebookFind.pdfRects(for: "eight", on: page, pageSize: bounds.size).isEmpty)
    }

    func testHandwritingIsFoundWhereItWasWritten() async throws {
        let page = paper.newPage()
        let ink = PKDrawing(strokes: BlockLetters.strokes("HELLO", origin: CGPoint(x: 150, y: 160)))
        let reader = FindReader()
        let rects = await reader.inkRects(for: "hello", page: page, ink: ink, assets: FileManager.default.temporaryDirectory)
        try XCTSkipIf(rects.isEmpty, "text recognition isn't available on this simulator")
        XCTAssertEqual(rects.count, 1)
        XCTAssertTrue(rects[0].intersects(ink.bounds), "\(rects[0]) should lie over \(ink.bounds)")
        XCTAssertEqual(rects[0].midY, ink.bounds.midY, accuracy: 30)
        let none = await reader.inkRects(for: "goodbye", page: page, ink: ink, assets: FileManager.default.temporaryDirectory)
        XCTAssertTrue(none.isEmpty)
    }

    func testMatchesStartFromThePageBeingReadAndComeRound() async throws {
        var pages = [paper.newPage(), paper.newPage(), paper.newPage()]
        pages[0].items = [textBox("enzyme kinetics", at: CGPoint(x: 200, y: 100))]
        pages[2].items = [textBox("an enzyme", at: CGPoint(x: 200, y: 500)), textBox("Enzyme again", at: CGPoint(x: 200, y: 100))]
        let document = try await makeDocument(pages)
        let finder = NotebookFinder(document: document)
        finder.delay = .zero
        finder.startPage = { 1 }
        var changes = 0
        finder.onChange = { changes += 1 }

        finder.search("enzyme")
        await finish(finder)
        XCTAssertEqual(finder.matches.map(\.page), [0, 2, 2], "in page order")
        XCTAssertEqual(finder.matches.map(\.rect.midY), [100, 100, 500], "and down each page")
        XCTAssertEqual(finder.position, 1, "the first one shown is the nearest ahead of the page being read")
        XCTAssertGreaterThan(changes, 0)

        finder.step(1)
        XCTAssertEqual(finder.position, 2)
        finder.step(1)
        XCTAssertEqual(finder.position, 0, "past the last match it comes round to the first")
        finder.step(-1)
        XCTAssertEqual(finder.position, 2)

        finder.search("ribosome")
        await finish(finder)
        XCTAssertTrue(finder.matches.isEmpty)
        XCTAssertNil(finder.current)
        finder.search("  ")
        XCTAssertFalse(finder.isSearching, "nothing to look for")
        finder.clear()
        XCTAssertEqual(finder.query, "")
    }

    func testAPageReadAsNotHoldingTheWordsIsNotReadAgain() async throws {
        let page = paper.newPage()
        let ink = PKDrawing(strokes: BlockLetters.strokes("HELLO", origin: CGPoint(x: 150, y: 160)))
        let document = try await makeDocument([page], ink: [page.id: ink])
        let saved = try XCTUnwrap(document.pages.first)
        XCTAssertNotNil(saved.inkHash)
        // The search index says this page reads "goodbye": the finder trusts it while the ink hasn't changed.
        try await document.package.writeText(HandwritingIndexer.header(for: saved) + "goodbye", pageID: saved.id)
        let finder = NotebookFinder(document: document)
        finder.delay = .zero
        finder.search("hello")
        await finish(finder)
        XCTAssertTrue(finder.matches.isEmpty)

        try await document.package.writeText("#ink:stale\ngoodbye", pageID: saved.id)
        finder.search("hello ")
        await finish(finder)
        try XCTSkipIf(finder.matches.isEmpty, "text recognition isn't available on this simulator")
        XCTAssertEqual(finder.matches.count, 1, "an out-of-date reading is not trusted")
    }
}
