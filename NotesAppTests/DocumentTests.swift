import XCTest
import PencilKit
@testable import NotesApp

@MainActor
private final class RecordingObserver: InkObserver {
    var replaced: [UUID] = []
    func document(_ document: NotebookDocument, didReplaceInkOf pageID: UUID) { replaced.append(pageID) }
}

@MainActor
final class DocumentTests: XCTestCase {
    func testUndoLevelsShrinkAsPagesGetHeavier() {
        XCTAssertEqual(UndoBudget.levels(forPageBytes: 0), 200)
        XCTAssertEqual(UndoBudget.levels(forPageBytes: 100_000), 200)
        XCTAssertEqual(UndoBudget.levels(forPageBytes: 1 << 20), 48)
        XCTAssertEqual(UndoBudget.levels(forPageBytes: 8 << 20), 20, "never fewer than twenty steps")
    }

    private func makeDocument(pages: Int = 4, root: StorageRoot? = nil) async throws -> (NotebookDocument, StorageRoot) {
        let root = root ?? temporaryRoot(self)
        let manifest = NotebookManifest(title: "Doc", defaults: PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter),
                                        pages: (0..<pages).map { _ in .template(.narrowRuled, color: .white, size: .letter) })
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        document.saveDelay = .milliseconds(20)
        document.retryBase = .milliseconds(50)
        return (document, root)
    }

    private func ink(_ count: Int, y: CGFloat = 80) -> PKDrawing {
        PKDrawing(strokes: (0..<count).map { dot(at: CGPoint(x: 60 + CGFloat($0) * 25, y: y)) })
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func testStrokeUndoAndRedoWorkAcrossPages() async throws {
        let (document, _) = try await makeDocument()
        let observer = RecordingObserver()
        document.inkObserver = observer
        let a = document.pages[0].id, b = document.pages[3].id
        _ = await document.ink(a)
        _ = await document.ink(b)
        document.undoManager.groupsByEvent = false
        for (page, count) in [(a, 1), (a, 2), (b, 5)] {
            document.undoManager.beginUndoGrouping()
            document.canvasDidChangeInk(page, to: ink(count))
            document.undoManager.endUndoGrouping()
        }

        document.undoManager.undo()
        XCTAssertEqual(document.loadedInk(b)?.strokes.count, 0)
        document.undoManager.undo()
        XCTAssertEqual(document.loadedInk(a)?.strokes.count, 1)
        document.undoManager.undo()
        XCTAssertEqual(document.loadedInk(a)?.strokes.count, 0)
        XCTAssertEqual(observer.replaced, [b, a, a])
        document.undoManager.redo()
        document.undoManager.redo()
        document.undoManager.redo()
        XCTAssertEqual(document.loadedInk(a)?.strokes.count, 2)
        XCTAssertEqual(document.loadedInk(b)?.strokes.count, 5)
    }

    func testEveryPageOperationIsUndoable() async throws {
        let (document, _) = try await makeDocument()
        document.undoManager.groupsByEvent = false
        let original = document.pages
        func step(_ action: () -> Void) {
            document.undoManager.beginUndoGrouping()
            action()
            document.undoManager.endUndoGrouping()
        }
        step { document.insertPages([.template(.grid, color: .ivory, size: .a4)], at: 1) }
        step { document.removePages([original[3].id]) }
        step { document.movePage(from: 0, to: 2) }
        step { document.setPaper(template: .dotted, color: original[1].paperColor, forPage: original[1].id) }
        step { document.setPaper(template: original[2].template ?? .blank, color: .yellow, forPage: original[2].id) }
        document.undoManager.beginUndoGrouping()
        await document.duplicatePage(at: 0)
        document.undoManager.endUndoGrouping()
        XCTAssertEqual(document.pages.count, 5)
        XCTAssertNotEqual(document.pages, original)

        while document.undoManager.canUndo { document.undoManager.undo() }
        XCTAssertEqual(document.pages, original)
        while document.undoManager.canRedo { document.undoManager.redo() }
        XCTAssertEqual(document.pages.count, 5)
        XCTAssertEqual(document.pages.first { $0.id == original[1].id }?.template, .dotted)
        XCTAssertEqual(document.pages.first { $0.id == original[2].id }?.paperColor, .yellow)
    }

    func testDeletingTheLastPageLeavesABlankOneAndUndoRestoresIt() async throws {
        let (document, _) = try await makeDocument(pages: 1)
        document.undoManager.groupsByEvent = false
        let only = document.pages[0]
        document.undoManager.beginUndoGrouping()
        document.removePages([only.id])
        document.undoManager.endUndoGrouping()
        XCTAssertEqual(document.pages.count, 1)
        XCTAssertNotEqual(document.pages[0].id, only.id)
        document.undoManager.undo()
        XCTAssertEqual(document.pages, [only])
    }

    /// Ink-only saves no longer report to the library while editing (closing indexes everything), so the
    /// report is checked on the next library-visible save, where it must carry the saved ink hash.
    func testAutosaveWritesDirtyPagesAndReportsTheManifest() async throws {
        let (document, root) = try await makeDocument()
        var saved: [NotebookManifest] = []
        document.onSaved = { saved.append($0) }
        let page = document.pages[1].id
        _ = await document.ink(page)
        document.canvasDidChangeInk(page, to: ink(3))
        XCTAssertTrue(document.hasUnsavedChanges)
        await waitUntil { !document.hasUnsavedChanges }
        XCTAssertEqual(document.saveState, .saved)
        XCTAssertNotNil(document.pages[1].inkHash)
        let onDisk = try await NotebookPackage(root: root, id: document.id).readManifest().manifest
        XCTAssertEqual(onDisk.pages[1].inkHash, document.pages[1].inkHash)
        XCTAssertTrue(saved.isEmpty)
        document.rename("Reported")
        await waitUntil { !saved.isEmpty }
        XCTAssertEqual(saved.last?.pages[1].inkHash, document.pages[1].inkHash)
        XCTAssertEqual(saved.last?.title, "Reported")

        let reopened = try await NotebookDocument.open(document.id, root: root)
        let reloaded = await reopened.ink(page)
        XCTAssertEqual(reloaded.strokes.count, 3)
    }

    func testAFailedWriteKeepsChangesDirtyAndIsRetried() async throws {
        let (document, root) = try await makeDocument()
        let fileManager = FileManager.default
        try fileManager.removeItem(at: document.package.inkDirectory)
        try Data("blocker".utf8).write(to: document.package.inkDirectory)
        let page = document.pages[0].id
        _ = await document.ink(page)
        document.canvasDidChangeInk(page, to: ink(4))
        await waitUntil {
            if case .failed = document.saveState { return true }
            return false
        }
        guard case .failed = document.saveState else { return XCTFail("the save should fail while ink/ is blocked") }
        XCTAssertTrue(document.hasUnsavedChanges)
        XCTAssertTrue(document.notices.contains { $0.kind == .saveFailed })

        try fileManager.removeItem(at: document.package.inkDirectory)
        await waitUntil { document.saveState == .saved }
        XCTAssertEqual(document.saveState, .saved)
        XCTAssertFalse(document.hasUnsavedChanges)
        XCTAssertFalse(document.notices.contains { $0.kind == .saveFailed })
        let reopened = try await NotebookDocument.open(document.id, root: root)
        let reloaded = await reopened.ink(page)
        XCTAssertEqual(reloaded.strokes.count, 4)
    }

    func testDamagedInkIsReportedAndKept() async throws {
        let (document, _) = try await makeDocument()
        let page = document.pages[2].id
        let garbage = Data("not a drawing at all".utf8)
        try FileManager.default.createDirectory(at: document.package.inkDirectory, withIntermediateDirectories: true)
        try garbage.write(to: document.package.inkURL(page))
        let loaded = await document.ink(page)
        XCTAssertTrue(loaded.strokes.isEmpty)
        XCTAssertTrue(document.damagedPages.contains(page))
        XCTAssertTrue(document.notices.contains { $0.kind == .quarantined })
        document.canvasDidChangeInk(page, to: ink(2))
        let saved = await document.flush()
        XCTAssertTrue(saved)
        XCTAssertEqual(try Data(contentsOf: document.package.inkURL(page).appendingPathExtension("corrupt")), garbage)
    }

    func testCleanPagesAreEvictedButDirtyPagesStay() async throws {
        let (document, _) = try await makeDocument(pages: 10)
        document.inkCacheLimit = 3
        let dirty = document.pages[0].id
        _ = await document.ink(dirty)
        document.saveDelay = .seconds(60)
        document.canvasDidChangeInk(dirty, to: ink(2))
        for page in document.pages.dropFirst() { _ = await document.ink(page.id) }
        XCTAssertNotNil(document.loadedInk(dirty), "unsaved ink must never be evicted")
        XCTAssertNil(document.loadedInk(document.pages[1].id))
        XCTAssertNotNil(document.loadedInk(document.pages[9].id))
    }

    func testNewerSchemaDocumentNeverWrites() async throws {
        let root = temporaryRoot(self)
        var manifest = NotebookManifest(title: "Future", defaults: PageDefaults(template: .blank, paperColor: .white, pageSize: .letter),
                                        pages: [.template(.blank, color: .white, size: .letter)])
        manifest.schemaVersion = 99
        let package = NotebookPackage(root: root, id: manifest.id)
        try FileManager.default.createDirectory(at: package.url, withIntermediateDirectories: true)
        let bytes = try ManifestCodec.encode(manifest)
        try bytes.write(to: package.manifestURL)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        XCTAssertTrue(document.isReadOnly)
        document.canvasDidChangeInk(document.pages[0].id, to: ink(1))
        document.insertPages([.template(.grid, color: .white, size: .letter)], at: 0)
        _ = await document.flush()
        XCTAssertEqual(try Data(contentsOf: package.manifestURL), bytes)
        XCTAssertTrue(document.notices.contains { $0.kind == .readOnly })
    }

    /// Replaces v1's PageRemapper tests: ink belongs to its page through delete, insert, move and duplicate.
    func testInkFollowsItsPageThroughPageOperations() async throws {
        let (document, _) = try await makeDocument(pages: 3)
        let ids = document.pages.map(\.id)
        for (index, id) in ids.enumerated() {
            _ = await document.ink(id)
            document.canvasDidChangeInk(id, to: ink(index + 1))
        }
        document.removePages([ids[0]])
        XCTAssertEqual(document.pages.map(\.id), [ids[1], ids[2]])
        document.insertPages([.template(.blank, color: .white, size: .letter)], at: 0)
        document.movePage(from: 2, to: 1)
        await document.duplicatePage(at: 1)
        XCTAssertEqual(document.pages.count, 4)
        for page in document.pages {
            let expected = page.id == ids[1] ? 2 : page.id == ids[2] ? 3 : page.id == document.pages[0].id ? 0 : 3
            let drawing = await document.ink(page.id)
            XCTAssertEqual(drawing.strokes.count, expected)
        }
        XCTAssertEqual(document.pages[1].id, ids[2], "the move kept the page's identity")
        let saved = await document.flush()
        XCTAssertTrue(saved)
    }

    func testForeignUndoRegistrationsAreDropped() {
        let manager = DocumentUndoManager()
        manager.groupsByEvent = false
        let canvas = PKCanvasView()
        manager.registerUndo(withTarget: canvas, selector: #selector(UIView.layoutIfNeeded), object: nil)
        manager.registerUndo(withTarget: canvas) { _ in }
        (manager.prepare(withInvocationTarget: canvas) as? UIView)?.setNeedsLayout()
        XCTAssertFalse(manager.canUndo, "PencilKit's own registrations must not reach the document stack")
        XCTAssertEqual(manager.droppedRegistrations, 3)
    }
}
