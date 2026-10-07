import XCTest
import PencilKit
import PDFKit
@testable import OwlLuna

final class WhiteboardModelTests: XCTestCase {
    private let far = CGPoint(x: 31_000, y: 9_000)

    func testABoardIsAPageWithNoShapeOfItsOwn() {
        let board = NotebookPage.board(template: .cornell, color: .ivory)
        XCTAssertTrue(board.isBoard)
        XCTAssertEqual(board.template, .dotted, "paper with margins falls back to dots")
        XCTAssertEqual(board.size, Whiteboard.size)
        XCTAssertEqual(board.shownSize, Whiteboard.shownSize)
        XCTAssertEqual(board.sheetSize, PageSize.letter.points)
        XCTAssertFalse(NotebookPage.template(.grid, color: .white, size: .a4).isBoard)
        XCTAssertTrue(board.duplicated().isBoard)
    }

    func testTheFrameHoldsEverythingOnTheBoardAndAnEmptyBoardGivesItsMiddle() {
        var board = NotebookPage.board(template: .grid, color: .white)
        let empty = Whiteboard.frame(of: board, ink: PKDrawing())
        XCTAssertEqual(empty.size, Whiteboard.shownSize)
        XCTAssertEqual(empty.midX, Whiteboard.center.x, accuracy: 1)

        let ink = PKDrawing(strokes: [stroke(from: far, to: CGPoint(x: far.x + 3000, y: far.y + 200))])
        board.items = [PageItem(content: .sticker("star"), center: CGPoint(x: far.x - 400, y: far.y + 900), size: CGSize(width: 80, height: 80))]
        let frame = Whiteboard.frame(of: board, ink: ink)
        XCTAssertTrue(frame.contains(ink.bounds))
        XCTAssertTrue(frame.contains(board.items[0].boundingBox))
        XCTAssertEqual(frame.width / frame.height, Whiteboard.shownSize.width / Whiteboard.shownSize.height, accuracy: 0.01)
        XCTAssertTrue(CGRect(origin: .zero, size: Whiteboard.size).contains(frame))

        let corner = Whiteboard.frame(of: NotebookPage.board(template: .blank, color: .white), ink: PKDrawing(strokes: [dot(at: CGPoint(x: 30, y: 30))]))
        XCTAssertEqual(corner.origin, .zero, "a frame never leaves the board")
    }

    func testAPieceKeepsInkInPlaceAndMovesWhatIsPlaced() {
        var board = NotebookPage.board(template: .dotted, color: .white)
        board.items = [PageItem(content: .sticker("star"), center: CGPoint(x: far.x + 50, y: far.y + 60), size: CGSize(width: 40, height: 40))]
        let rect = CGRect(x: far.x, y: far.y, width: 400, height: 300)
        let piece = Whiteboard.piece(of: board, in: rect)
        XCTAssertEqual(piece.size, rect.size)
        XCTAssertEqual(piece.inkRect, rect)
        XCTAssertEqual(piece.items[0].center, CGPoint(x: 50, y: 60))
        XCTAssertEqual(piece.shownSize, rect.size)
        XCTAssertEqual(Whiteboard.whole(piece, ink: PKDrawing()).inkRect, rect, "a piece is not cut again")
        let page = NotebookPage.template(.blank, color: .white, size: .letter)
        XCTAssertEqual(Whiteboard.whole(page, ink: PKDrawing()), page)
    }

    func testABoardIsDrawnAsThePartWithSomethingOnIt() throws {
        let board = NotebookPage.board(template: .blank, color: .white)
        let ink = PKDrawing(strokes: [stroke(from: far, to: CGPoint(x: far.x + 300, y: far.y), width: 10)])
        let frame = Whiteboard.frame(of: board, ink: ink)
        let image = PageRenderer.image(of: board, ink: ink, assets: temporaryRoot(self).url, width: 512, scale: 1)
        XCTAssertEqual(image.size.width, 512)
        XCTAssertEqual(image.size.height, 384, accuracy: 1)
        let factor = 512 / frame.width
        let onInk = CGPoint(x: (far.x + 150 - frame.minX) * factor, y: (far.y - frame.minY) * factor)
        XCTAssertLessThan(try luminance(of: image, at: onInk), 0.5, "the ink is where the frame puts it")
        XCTAssertGreaterThan(try luminance(of: image, at: CGPoint(x: 20, y: 20)), 0.9)
    }

    func testRulesStayUnderTheInkWhereverAPieceIsCut() throws {
        let board = NotebookPage.board(template: .grid, color: .white)
        let assets = temporaryRoot(self).url
        let first = PageRenderer.image(of: Whiteboard.piece(of: board, in: CGRect(x: 20_000, y: 20_000, width: 200, height: 150)),
                                       ink: PKDrawing(), assets: assets, width: 200, scale: 1)
        let second = PageRenderer.image(of: Whiteboard.piece(of: board, in: CGRect(x: 20_060, y: 20_040, width: 200, height: 150)),
                                        ink: PKDrawing(), assets: assets, width: 200, scale: 1)
        var ruled = 0
        for y in stride(from: 2, to: 100, by: 3) {
            for x in stride(from: 2, to: 130, by: 3) {
                let a = try luminance(of: first, at: CGPoint(x: x + 60, y: y + 40)), b = try luminance(of: second, at: CGPoint(x: x, y: y))
                XCTAssertEqual(a, b, accuracy: 0.03, "(\(x), \(y))")
                if a < 0.97 { ruled += 1 }
            }
        }
        XCTAssertGreaterThan(ruled, 10, "the grid is drawn")
    }

    func testAFlashcardClippingIsCutFromTheBoardWithoutDrawingTheBoard() {
        var board = NotebookPage.board(template: .dotted, color: .white)
        let tape = PageItem(content: .tape(.mustard), center: CGPoint(x: far.x, y: far.y), size: CGSize(width: 160, height: 22))
        board.items = [tape]
        let region = CardClipping.region(around: tape, on: board)
        XCTAssertTrue(region.contains(tape.boundingBox))
        XCTAssertLessThan(region.width, 600)
        let sides = CardClipping.tapeSides(tape, on: board, ink: PKDrawing(), assets: temporaryRoot(self).url)
        XCTAssertEqual(sides.front.size, region.size)
        XCTAssertEqual(sides.back.size, region.size)
        XCTAssertNotEqual(sides.front.pngData(), sides.back.pngData(), "the back shows the page with the tape lifted")
    }

    func testCardsStandInTheStackAndAnOpenBoardIsLaidOutAlone() {
        let letter = NotebookPage.template(.blank, color: .white, size: .letter)
        let pages = [letter, NotebookPage.board(template: .dotted, color: .white), letter]
        let stack = PageStackLayout(pages: pages)
        XCTAssertNil(stack.solo)
        XCTAssertEqual(stack.size.width, 612 + PageStackLayout.margin * 2)
        XCTAssertEqual(stack.frames[1].width, 612)
        XCTAssertEqual(stack.frames[1].height, 459)
        XCTAssertEqual(stack.frames[2].minY, stack.frames[1].maxY + PageStackLayout.margin)
        XCTAssertTrue(stack.isLaidOut(0, in: pages))
        XCTAssertFalse(stack.isLaidOut(1, in: pages), "a card is not the board at its own size")

        let solo = PageStackLayout(pages: pages, solo: 1)
        XCTAssertEqual(solo.solo, 1)
        XCTAssertEqual(solo.size, Whiteboard.size)
        XCTAssertEqual(solo.frames[1], CGRect(origin: .zero, size: Whiteboard.size))
        XCTAssertEqual(solo.pageIndex(atY: 123), 1)
        XCTAssertEqual(solo.range(from: 0, to: 500), 1...1)
        XCTAssertTrue(solo.isLaidOut(1, in: pages))
        XCTAssertFalse(solo.isLaidOut(0, in: pages))
        XCTAssertNil(PageStackLayout(pages: pages, solo: 0).solo, "only a whiteboard is laid out alone")
        XCTAssertEqual(PageStackLayout(pages: [pages[1]]).size.width, 612 + PageStackLayout.margin * 2, "a board alone counts as a Letter page")
    }

    private func luminance(of image: UIImage, at point: CGPoint) throws -> CGFloat {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: -point.x.rounded(), y: -(CGFloat(cgImage.height) - 1 - point.y.rounded()),
                                         width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return (0.299 * CGFloat(pixel[0]) + 0.587 * CGFloat(pixel[1]) + 0.114 * CGFloat(pixel[2])) / 255
    }
}

@MainActor
final class WhiteboardEditorTests: XCTestCase {
    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private var root: StorageRoot?

    private func open(_ pages: [NotebookPage], ink: [UUID: PKDrawing] = [:]) async throws -> (EditorSession, PageStackController, UIWindow) {
        let root = temporaryRoot(self)
        self.root = root
        let paper = PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter)
        let manifest = NotebookManifest(title: "Boards", defaults: paper, pages: pages)
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        for (id, drawing) in ink {
            _ = await document.ink(id)
            document.replaceInk(id, with: drawing)
        }
        let session = EditorSession(document: document)
        let controller = PageStackController(session: session)
        session.canvas = controller
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in window.isHidden = true }
        controller.view.layoutIfNeeded()
        return (session, controller, window)
    }

    private func settle(_ controller: PageStackController) async {
        for _ in 0..<100 where !controller.isPaperDrawn { await pause(0.05) }
    }

    func testABoardSavedInANotebookComesBackAsABoard() async throws {
        let (session, _, _) = try await open([.board(template: .grid, color: .sage)])
        let saved = await session.document.save()
        XCTAssertTrue(saved)
        let reopened = try await NotebookDocument.open(session.document.id, root: try XCTUnwrap(root))
        XCTAssertTrue(reopened.pages[0].isBoard)
        XCTAssertEqual(reopened.pages[0].template, .grid)
        XCTAssertNil(reopened.pages[0].cut)
    }

    func testOpeningABoardLaysItOutAloneAndGoingToAPageBringsTheStackBack() async throws {
        let letter = NotebookPage.template(.narrowRuled, color: .white, size: .letter)
        let board = NotebookPage.board(template: .dotted, color: .white)
        let (session, controller, window) = try await open([letter, board, letter])
        XCTAssertNil(controller.openBoardID, "among the pages a board is a card")
        XCTAssertNil(controller.canvas(forPage: 1), "and nothing is written on the card")
        XCTAssertNotNil(controller.canvas(forPage: 0))

        session.go(to: 1)
        XCTAssertEqual(controller.openBoardID, board.id)
        XCTAssertEqual(controller.currentPage, 1)
        XCTAssertEqual(session.currentPage, 1)
        XCTAssertEqual(controller.liveCanvasCount, 1)
        let canvas = try XCTUnwrap(controller.canvas(forPage: 1))
        XCTAssertLessThanOrEqual(canvas.frame.width, 834, "the canvas is a window onto the board, never the board")
        XCTAssertLessThanOrEqual(canvas.frame.height, 1194)
        let middle = try XCTUnwrap(controller.visibleCenter(ofPage: 1))
        XCTAssertEqual(middle.x, Whiteboard.center.x, accuracy: 2, "an empty board opens on its middle")
        XCTAssertEqual(middle.y, Whiteboard.center.y, accuracy: 2)
        await settle(controller)
        let viewport = Int(834 * 1194 * window.screen.scale * window.screen.scale)
        XCTAssertTrue(controller.isPaperDrawn)
        XCTAssertLessThan(controller.paperPixelCount, viewport * 5, "only the paper near the viewport is held")

        // Moving about: far to one side, zoomed in and out. Nothing but the viewport is ever backed.
        controller.setZoom(5)
        await settle(controller)
        XCTAssertLessThan(controller.paperPixelCount, viewport * 5)
        controller.setZoom(Whiteboard.minimumZoom)
        XCTAssertEqual(controller.zoom, Whiteboard.minimumZoom, accuracy: 0.001, "a board zooms out far further than a page")
        controller.setZoom(1)
        for _ in 0..<6 { controller.scrollBy(viewportFraction: 0.9) }
        let moved = try XCTUnwrap(controller.visibleCenter(ofPage: 1))
        XCTAssertGreaterThan(moved.y, middle.y + 2000)
        XCTAssertNil(controller.visibleCenter(ofPage: 0), "the other pages are put away")

        session.go(to: 2)
        XCTAssertNil(controller.openBoardID)
        XCTAssertEqual(controller.currentPage, 2)
        XCTAssertNotNil(controller.canvas(forPage: 2))
        XCTAssertNil(controller.canvas(forPage: 1))

        session.go(to: 1)
        let back = try XCTUnwrap(controller.visibleCenter(ofPage: 1))
        XCTAssertEqual(back.y, moved.y, accuracy: 2, "the board is where it was left")
        XCTAssertEqual(back.x, moved.x, accuracy: 2)
    }

    func testANotebookThatIsOnlyABoardOpensOnItAndShowsWhatIsThere() async throws {
        let board = NotebookPage.board(template: .dotted, color: .white)
        let spot = CGPoint(x: 26_000, y: 14_000)
        let ink = PKDrawing(strokes: [stroke(from: spot, to: CGPoint(x: spot.x + 400, y: spot.y + 300))])
        let (session, controller, _) = try await open([board], ink: [board.id: ink])
        XCTAssertEqual(controller.openBoardID, board.id)
        for _ in 0..<40 where controller.canvas(forPage: 0)?.isLoaded != true { await pause(0.05) }
        await pause(0.2)
        let middle = try XCTUnwrap(controller.visibleCenter(ofPage: 0))
        XCTAssertEqual(middle.x, ink.bounds.midX, accuracy: 60, "it opens on what is written, not the empty middle")
        XCTAssertEqual(middle.y, ink.bounds.midY, accuracy: 60)
        XCTAssertEqual(controller.canvas(forPage: 0)?.drawing.strokes.count, 1)

        // New things land in view and are sized for a sheet of paper, not for the board.
        session.addText()
        let box = try XCTUnwrap(session.document.pages[0].items.first)
        XCTAssertLessThanOrEqual(box.size.width, 280)
        XCTAssertEqual(box.center.x, middle.x, accuracy: 60)

        // A page added after a board is an ordinary page.
        session.addPage(after: 0)
        XCTAssertEqual(session.document.pages[1].size, PageSize.letter.points)
        XCTAssertNil(controller.openBoardID)
        session.addBoard(after: 1)
        XCTAssertTrue(session.document.pages[2].isBoard)
        XCTAssertEqual(controller.openBoardID, session.document.pages[2].id)

        // Deleting the open board shows the page that takes its place.
        session.document.removePages([session.document.pages[2].id])
        XCTAssertNil(controller.openBoardID)
        XCTAssertEqual(session.currentPage, 1)
    }

    func testTheEditorsModesWorkOnABoard() async throws {
        let letter = NotebookPage.template(.narrowRuled, color: .white, size: .letter)
        let board = NotebookPage.board(template: .grid, color: .white)
        let spot = CGPoint(x: 21_000, y: 19_500)
        let ink = PKDrawing(strokes: [stroke(from: spot, to: CGPoint(x: spot.x + 300, y: spot.y)), dot(at: CGPoint(x: spot.x + 2600, y: spot.y + 1500))])
        let (session, controller, _) = try await open([letter, board], ink: [board.id: ink])
        XCTAssertNil(controller.openBoardID)

        // A match on the board opens it and brings the match into view.
        session.enter(.finding)
        let match = FindMatch(pageID: board.id, page: 1, rect: CGRect(x: spot.x + 2590, y: spot.y + 1490, width: 20, height: 20))
        controller.showFind([match], current: match)
        XCTAssertEqual(controller.openBoardID, board.id)
        XCTAssertEqual(session.currentPage, 1)
        session.enter(.writing)

        // Presenting shows everything on the board; leaving it goes back to where the board was.
        controller.setZoom(1)
        let before = try XCTUnwrap(controller.visibleCenter(ofPage: 1))
        session.enter(.presenting)
        let frame = Whiteboard.frame(of: board, ink: ink)
        let shown = try XCTUnwrap(controller.visibleCenter(ofPage: 1))
        XCTAssertEqual(shown.x, frame.midX, accuracy: 40)
        XCTAssertLessThan(controller.zoom, 1, "all of it fits")
        session.step(-1)
        XCTAssertNil(controller.openBoardID, "stepping back presents the page before")
        session.step(1)
        XCTAssertEqual(controller.openBoardID, board.id)
        session.enter(.writing)
        XCTAssertEqual(controller.zoom, 1, accuracy: 0.001)
        let after = try XCTUnwrap(controller.visibleCenter(ofPage: 1))
        XCTAssertEqual(after.x, before.x, accuracy: 2)
        XCTAssertEqual(after.y, before.y, accuracy: 2)

        // The lasso catches ink where it lies on the board.
        session.enter(.selecting)
        controller.catchInk(inside: [CGPoint(x: spot.x - 50, y: spot.y - 50), CGPoint(x: spot.x + 400, y: spot.y - 50),
                                     CGPoint(x: spot.x + 400, y: spot.y + 50), CGPoint(x: spot.x - 50, y: spot.y + 50)])
        XCTAssertEqual(session.inkSelectionCount, 1)
        controller.deleteInkSelection()
        XCTAssertEqual(session.document.loadedInk(board.id)?.strokes.count, 1)
        session.enter(.writing)

        // The zoom window is sized for a sheet of paper and stays on the board.
        session.setZoomWindow(true)
        XCTAssertTrue(session.isZoomWindowOpen)
        XCTAssertEqual(controller.openBoardID, board.id)
        session.go(to: 0)
        XCTAssertFalse(session.isZoomWindowOpen, "leaving the board closes its zoom window")
        XCTAssertNil(controller.openBoardID)
    }

    func testABoardExportsAsOneSheetTheSizeOfWhatIsOnIt() async throws {
        let board = NotebookPage.board(template: .grid, color: .white)
        let spot = CGPoint(x: 8_000, y: 30_000)
        let ink = PKDrawing(strokes: [stroke(from: spot, to: CGPoint(x: spot.x + 2400, y: spot.y + 500))])
        let (session, _, _) = try await open([board, .template(.blank, color: .white, size: .a5)], ink: [board.id: ink])
        let document = session.document
        let frame = Whiteboard.frame(of: board, ink: ink)
        let input = NotebookExporter.Input(title: "Boards", pages: document.pages, inMemoryInk: [board.id: ink], package: document.package)
        let url = try await NotebookExporter.export(input) { _ in }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 2)
        let sheet = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox).size
        XCTAssertEqual(sheet.width, frame.width, accuracy: 1)
        XCTAssertEqual(sheet.height, frame.height, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(pdf.page(at: 1)).bounds(for: .mediaBox).size.width, PageSize.a5.points.width, accuracy: 1)

        let images = try await NotebookExporter.exportImages(input) { _ in }
        let picture = try XCTUnwrap(UIImage(contentsOfFile: images[0].path(percentEncoded: false)))
        XCTAssertLessThanOrEqual(max(picture.size.width * picture.scale, picture.size.height * picture.scale), 6001)
        XCTAssertEqual(picture.size.width / picture.size.height, frame.width / frame.height, accuracy: 0.01)

        let thumbnail = PageThumbnailer.render(page: board, ink: ink, assets: document.package.assetsDirectory)
        XCTAssertEqual(thumbnail.size.width / thumbnail.size.height, 4.0 / 3, accuracy: 0.01)
    }
}
