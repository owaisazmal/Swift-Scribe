import XCTest
@testable import NotesApp

@MainActor
final class PaperDrawerTests: XCTestCase {
    private func makeDocument(_ pages: [NotebookPage]) async throws -> NotebookDocument {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Paper", defaults: PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter),
                                        pages: pages)
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        document.saveDelay = .milliseconds(20)
        document.undoManager.groupsByEvent = false
        return document
    }

    private func ruled(_ count: Int) -> [NotebookPage] {
        (0..<count).map { _ in .template(.narrowRuled, color: .white, size: .letter) }
    }

    private func step(_ document: NotebookDocument, _ action: () -> Void) {
        document.undoManager.beginUndoGrouping()
        action()
        document.undoManager.endUndoGrouping()
    }

    func testSetPaperIsOneUndoStep() async throws {
        let document = try await makeDocument(ruled(3))
        let id = document.pages[1].id
        step(document) { document.setPaper(template: .dayPlanner, color: .chalkboard, forPage: id) }
        XCTAssertEqual(document.pages[1].template, .dayPlanner)
        XCTAssertEqual(document.pages[1].paperColor, .chalkboard)
        XCTAssertEqual(document.undoManager.undoActionName, "Change Paper")

        document.undoManager.undo()
        XCTAssertEqual(document.pages[1].template, .narrowRuled)
        XCTAssertEqual(document.pages[1].paperColor, .white)
        XCTAssertFalse(document.undoManager.canUndo, "template and colour came back in one step")

        document.undoManager.redo()
        XCTAssertEqual(document.pages[1].template, .dayPlanner)
        XCTAssertEqual(document.pages[1].paperColor, .chalkboard)

        var changed = false
        document.onStructureChange = { changed = true }
        document.setPaper(template: .dayPlanner, color: .chalkboard, forPage: id)
        XCTAssertFalse(changed, "choosing the same paper again changes nothing and adds no step")
    }

    func testSetPaperIgnoresPDFAndPhotoPages() async throws {
        let pdf = NotebookPage(background: .pdf(file: "a.pdf", index: 0), paperColor: .white, size: PageSize.letter.points)
        let photo = NotebookPage(background: .image(file: "b.jpg"), paperColor: .white, size: PageSize.a5.points)
        let document = try await makeDocument([pdf, photo])
        document.setPaper(template: .grid, color: .kraft, forPage: pdf.id)
        document.setPaper(template: .grid, color: .kraft, forPage: photo.id)
        XCTAssertEqual(document.pages, [pdf, photo])
        XCTAssertFalse(document.undoManager.canUndo)
    }

    func testAddPageInsertsAfterTheIndexWithThatPaperAndMakesItCurrent() async throws {
        let document = try await makeDocument(ruled(4))
        let session = EditorSession(document: document)
        step(document) { session.addPage(after: 1, template: .storyboard, color: .kraft, size: .widescreen) }
        XCTAssertEqual(document.pages.count, 5)
        XCTAssertEqual(document.pages[2].template, .storyboard)
        XCTAssertEqual(document.pages[2].paperColor, .kraft)
        XCTAssertEqual(document.pages[2].size, PageSize.widescreen.points)
        XCTAssertEqual(session.currentPage, 2)

        step(document) { session.addPage(after: 4, template: .checklist, color: .sage, size: nil) }
        XCTAssertEqual(document.pages[5].template, .checklist)
        XCTAssertEqual(document.pages[5].size, PageSize.letter.points, "without a size it matches the page it follows")
        XCTAssertEqual(session.currentPage, 5)
    }

    func testPreviewsKeepThePageAspectAndAreCached() async throws {
        let wide = await PaperPreviewCache.image(template: .storyboard, color: .chalkboard, size: PageSize.widescreen.points, scale: 2)
        XCTAssertEqual(wide.size.width / wide.size.height, 16 / 9, accuracy: 0.02)
        XCTAssertEqual(wide.size.width, 120)
        let again = await PaperPreviewCache.image(template: .storyboard, color: .chalkboard, size: PageSize.widescreen.points, scale: 2)
        XCTAssertTrue(wide === again)
        let letter = await PaperPreviewCache.image(template: .storyboard, color: .chalkboard, size: PageSize.letter.points, scale: 2)
        XCTAssertEqual(letter.size.height / letter.size.width, 792 / 612, accuracy: 0.02)
    }
}
