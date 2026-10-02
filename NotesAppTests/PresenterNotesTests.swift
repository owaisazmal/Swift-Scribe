import XCTest
import PencilKit
@testable import NotesApp

/// Notes for the presenter: kept with the page, undoable, searchable, and never drawn.
@MainActor
final class PresenterNotesTests: XCTestCase {
    private let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)

    private func makeDocument() async throws -> NotebookDocument {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Talk", defaults: paper, pages: (0..<2).map { _ in paper.newPage() })
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        return try await NotebookDocument.open(manifest.id, root: root)
    }

    func testNotesAreKeptWithThePageAndUndone() async throws {
        let document = try await makeDocument()
        let page = document.pages[0]
        document.setNotes("  Start with the question.\nThen the demo.  ", forPage: page.id)
        XCTAssertEqual(document.pages[0].notes, "Start with the question.\nThen the demo.")
        XCTAssertEqual(document.undoManager.undoActionName, "Presenter Notes")
        XCTAssertEqual(document.pages[0].thumbnailKey, page.thumbnailKey, "notes aren't part of how the page looks")

        let saved = await document.flush()
        XCTAssertTrue(saved)
        let reread = try await document.package.readManifest().manifest
        XCTAssertEqual(reread.pages[0].notes, "Start with the question.\nThen the demo.")
        XCTAssertEqual(reread.pages[1].notes, "")
        XCTAssertNil(reread.pages[1].extra["notes"], "a page without notes carries no key")

        document.undoManager.undo()
        XCTAssertEqual(document.pages[0].notes, "")
        document.undoManager.redo()
        XCTAssertEqual(document.pages[0].notes, "Start with the question.\nThen the demo.")
        let count = document.undoManager.canUndo
        document.setNotes("Start with the question.\nThen the demo.", forPage: page.id)
        XCTAssertEqual(document.undoManager.canUndo, count, "the same notes again are no change")
    }

    func testNotesAreSearchableAndNeverDrawn() async throws {
        let document = try await makeDocument()
        let page = document.pages[0]
        XCTAssertEqual(HandwritingIndexer.header(for: page), "#ink:none\n")
        document.setNotes("Mention the Hubble constant", forPage: page.id)
        _ = await document.flush()
        XCTAssertNotEqual(HandwritingIndexer.header(for: document.pages[0]), "#ink:none\n", "the page is read again once it has notes")
        let text = await HandwritingIndexer.shared.index(HandwritingIndexer.Job(package: document.package, pages: document.pages))
        XCTAssertTrue(text.contains("Hubble"))

        let plain = PageRenderer.image(of: page, ink: PKDrawing(), assets: document.package.assetsDirectory, width: 306)
        let noted = PageRenderer.image(of: document.pages[0], ink: PKDrawing(), assets: document.package.assetsDirectory, width: 306)
        XCTAssertEqual(plain.pngData(), noted.pngData(), "thumbnails, exports and the audience's screen show the page without them")
    }
}
