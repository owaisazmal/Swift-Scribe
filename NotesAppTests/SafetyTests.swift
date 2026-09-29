import XCTest
import PencilKit
import SwiftData
@testable import NotesApp

/// Regression tests for the data-safety findings from the Phase 2 review.
@MainActor
final class DocumentSafetyTests: XCTestCase {
    private func makeDocument(pages: Int = 3, root: StorageRoot? = nil) async throws -> (NotebookDocument, StorageRoot) {
        let root = root ?? temporaryRoot(self)
        var manifest = NotebookManifest(title: "Safety", defaults: PageDefaults(template: .grid, paperColor: .white, pageSize: .letter),
                                        pages: (0..<pages).map { _ in .template(.grid, color: .white, size: .letter) })
        manifest.modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        document.saveDelay = .milliseconds(20)
        document.retryBase = .milliseconds(50)
        return (document, root)
    }

    private func ink(_ count: Int) -> PKDrawing {
        PKDrawing(strokes: (0..<count).map { dot(at: CGPoint(x: 60 + CGFloat($0) * 25, y: 90)) })
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func blockWrites(_ document: NotebookDocument) throws {
        try FileManager.default.removeItem(at: document.package.inkDirectory)
        try Data("blocker".utf8).write(to: document.package.inkDirectory)
    }

    private func unblockWrites(_ document: NotebookDocument) throws {
        try FileManager.default.removeItem(at: document.package.inkDirectory)
    }

    private func savedManifest(_ root: StorageRoot, _ id: UUID) async throws -> NotebookManifest {
        try await NotebookPackage(root: root, id: id).readManifest().manifest
    }

    func testClosingWhileSavesFailKeepsTheDocumentUntilItSaves() async throws {
        var (document, root): (NotebookDocument?, StorageRoot) = try await makeDocument()
        let id = try XCTUnwrap(document?.id)
        let page = try XCTUnwrap(document?.pages[0].id)
        _ = await document?.ink(page)
        try blockWrites(try XCTUnwrap(document))
        document?.canvasDidChangeInk(page, to: ink(4))
        let flushed = await document?.flush()
        XCTAssertEqual(flushed, false, "closing must be able to tell that the save failed")

        var released = false
        DocumentRegistry.shared.keepUntilSaved(try XCTUnwrap(document), retryEvery: .milliseconds(50)) { released = true }
        let blocked = try XCTUnwrap(document)
        document = nil
        XCTAssertTrue(DocumentRegistry.shared.document(for: id) === blocked, "the registry keeps it alive and findable")

        try unblockWrites(blocked)
        await waitUntil { released }
        XCTAssertTrue(released)
        XCTAssertNil(DocumentRegistry.shared.document(for: id))
        let reopened = try await NotebookDocument.open(id, root: root)
        let reloaded = await reopened.ink(page)
        XCTAssertEqual(reloaded.strokes.count, 4)
    }

    func testReopeningANotebookStillSavingReusesItsDocument() async throws {
        let (document, root) = try await makeDocument()
        try blockWrites(document)
        document.rename("Unsaved title")
        _ = await document.flush(attempts: 1)
        DocumentRegistry.shared.keepUntilSaved(document, retryEvery: .milliseconds(50)) {}
        let reopened = try await DocumentRegistry.shared.open(document.id, root: root, scene: nil) { _ in }
        XCTAssertTrue(reopened === document, "a second document would race the first one's retries")
        XCTAssertEqual(reopened.title, "Unsaved title")
        try unblockWrites(document)
        let saved = await document.flush()
        XCTAssertTrue(saved)
        DocumentRegistry.shared.unregister(document.id, document: document)
    }

    func testAPendingSaveKeepsAnUnreferencedDocumentAlive() async throws {
        var (document, root): (NotebookDocument?, StorageRoot) = try await makeDocument()
        let id = try XCTUnwrap(document?.id)
        document?.saveDelay = .milliseconds(80)
        document?.addRecording(RecordingEntry(id: UUID(), file: "lecture.m4a", createdAt: .now, duration: 12))
        document = nil
        try await Task.sleep(for: .milliseconds(400))
        let manifest = try await savedManifest(root, id)
        XCTAssertEqual(manifest.recordings.map(\.file), ["lecture.m4a"], "a recording added as the editor closes must still be saved")
    }

    func testInkOfARemovedPageDoesNotKeepTheDocumentDirty() async throws {
        let (document, _) = try await makeDocument()
        document.saveDelay = .seconds(60)
        document.undoManager.groupsByEvent = false
        let page = NotebookPage.template(.dotted, color: .white, size: .letter)
        document.undoManager.beginUndoGrouping()
        document.insertPages([page], at: 1, ink: [page.id: ink(2)])
        document.undoManager.endUndoGrouping()
        document.undoManager.undo()
        let first = await document.flush()
        XCTAssertTrue(first, "ink left behind by the undone insert must not block saving forever")
        XCTAssertFalse(document.hasUnsavedChanges)

        document.undoManager.redo()
        XCTAssertTrue(document.hasUnsavedChanges, "the page came back, so its ink needs saving again")
        let second = await document.flush()
        XCTAssertTrue(second)
        let saved = try NotebookPackage.decodeInk(Data(contentsOf: document.package.inkURL(page.id)))
        XCTAssertEqual(saved.strokes.count, 2)
    }

    func testPagesWithALiveCanvasAreNeverEvicted() async throws {
        let (document, _) = try await makeDocument(pages: 8)
        document.inkCacheLimit = 2
        let visible = document.pages[0].id
        document.pinInk([visible])
        for page in document.pages { _ = await document.ink(page.id) }
        XCTAssertNotNil(document.loadedInk(visible))
        XCTAssertNil(document.loadedInk(document.pages[1].id))
    }

    func testAStrokeOnAPageWhoseInkIsNotLoadedNeverUndoesToBlank() async throws {
        let (document, _) = try await makeDocument()
        let page = document.pages[0].id
        _ = try await document.package.write(SaveSnapshot(manifest: document.manifest, ink: [page: ink(3)]))
        document.undoManager.groupsByEvent = false
        document.undoManager.beginUndoGrouping()
        document.canvasDidChangeInk(page, to: ink(4))
        document.undoManager.endUndoGrouping()
        if document.undoManager.canUndo { document.undoManager.undo() }
        XCTAssertEqual(document.loadedInk(page)?.strokes.count, 4, "without the previous drawing, undo must not blank the page")
        let saved = await document.flush()
        XCTAssertTrue(saved)
        XCTAssertEqual(try NotebookPackage.decodeInk(Data(contentsOf: document.package.inkURL(page))).strokes.count, 4)
    }

    func testRedoAfterDeletingTheOnlyPageKeepsLaterSteps() async throws {
        let (document, _) = try await makeDocument(pages: 1)
        document.undoManager.groupsByEvent = false
        func step(_ action: () -> Void) {
            document.undoManager.beginUndoGrouping()
            action()
            document.undoManager.endUndoGrouping()
        }
        let original = document.pages[0]
        step { document.removePages([original.id]) }
        let placeholder = document.pages[0]
        _ = await document.ink(placeholder.id)
        step { document.canvasDidChangeInk(placeholder.id, to: ink(2)) }
        step { document.setTemplate(.dotted, forPage: placeholder.id) }

        document.undoManager.undo()
        document.undoManager.undo()
        document.undoManager.undo()
        XCTAssertEqual(document.pages.map(\.id), [original.id])

        document.undoManager.redo()
        XCTAssertEqual(document.pages.map(\.id), [placeholder.id], "redo brings back the same blank page")
        document.undoManager.redo()
        XCTAssertEqual(document.loadedInk(placeholder.id)?.strokes.count, 2)
        document.undoManager.redo()
        XCTAssertEqual(document.pages.first?.template, .dotted)
    }

    func testInkEditsDateTheNotebook() async throws {
        let (document, root) = try await makeDocument()
        let before = document.manifest.modifiedAt
        let page = document.pages[1].id
        _ = await document.ink(page)
        document.canvasDidChangeInk(page, to: ink(1))
        let saved = await document.flush()
        XCTAssertTrue(saved)
        XCTAssertGreaterThan(document.manifest.modifiedAt, before)
        let onDisk = try await savedManifest(root, document.id)
        XCTAssertGreaterThan(onDisk.modifiedAt, before)
    }

    func testOpeningIsRecordedInTheManifest() async throws {
        let (document, root) = try await makeDocument()
        XCTAssertNil(document.manifest.library.lastOpenedAt)
        document.noteOpened()
        let saved = await document.flush()
        XCTAssertTrue(saved)
        let onDisk = try await savedManifest(root, document.id)
        XCTAssertNotNil(onDisk.library.lastOpenedAt)
    }

    func testTurningPagesDoesNotPostponeAnInkSave() async throws {
        let (document, _) = try await makeDocument(pages: 6)
        document.saveDelay = .milliseconds(150)
        let page = document.pages[0].id
        _ = await document.ink(page)
        document.canvasDidChangeInk(page, to: ink(2))
        for index in 1..<6 {
            try await Task.sleep(for: .milliseconds(60))
            document.noteCurrentPage(index)
        }
        XCTAssertFalse(document.hasUnsavedInk(page), "the ink save was due before the page turns were")
    }

    func testContinuousWritingStillSavesWithinTheLatencyCap() async throws {
        let (document, _) = try await makeDocument()
        document.saveDelay = .milliseconds(200)
        document.maxSaveLatency = .milliseconds(300)
        let page = document.pages[0].id
        _ = await document.ink(page)
        var savedWhileWriting = false
        for count in 1...16 {
            document.canvasDidChangeInk(page, to: ink(count))
            try await Task.sleep(for: .milliseconds(50))
            if FileManager.default.fileExists(atPath: document.package.inkURL(page).path(percentEncoded: false)) { savedWhileWriting = true }
        }
        XCTAssertTrue(savedWhileWriting, "a stroke every 50 ms must not hold the save back indefinitely")
    }

    func testOnlyLibraryVisibleChangesReindexWhileEditing() async throws {
        let (document, _) = try await makeDocument()
        var indexed = 0
        document.onSaved = { _ in indexed += 1 }
        let page = document.pages[2].id
        _ = await document.ink(page)
        document.canvasDidChangeInk(page, to: ink(3))
        document.noteCurrentPage(2)
        _ = await document.flush()
        XCTAssertEqual(indexed, 0, "ink and page turns don't change what the library shows until close")
        document.rename("Renamed")
        _ = await document.flush()
        XCTAssertEqual(indexed, 1)
    }

    func testImportsInFlightFinishBeforeClosing() async throws {
        let (document, _) = try await makeDocument()
        document.perform {
            try? await Task.sleep(for: .milliseconds(150))
            document.insertPages([.template(.blank, color: .white, size: .letter)], at: 3)
        }
        await document.finishPendingWork()
        XCTAssertEqual(document.pages.count, 4)
    }
}

@MainActor
private final class Counter {
    var value = 0
}

@MainActor
final class RegistrySafetyTests: XCTestCase {
    func testConcurrentOpensShareOneDocument() async throws {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Twice", defaults: PageDefaults(template: .blank, paperColor: .white, pageSize: .letter),
                                        pages: [.template(.blank, color: .white, size: .letter)])
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let configured = Counter()
        let first = Task { try await DocumentRegistry.shared.open(manifest.id, root: root, scene: "a") { _ in configured.value += 1 } }
        let second = Task { try await DocumentRegistry.shared.open(manifest.id, root: root, scene: "b") { _ in configured.value += 1 } }
        let (a, b) = try await (first.value, second.value)
        XCTAssertTrue(a === b)
        XCTAssertEqual(configured.value, 1)
        DocumentRegistry.shared.unregister(manifest.id, document: a)
    }
}

final class StorageSafetyTests: XCTestCase {
    private func makePackage() async throws -> (NotebookPackage, NotebookManifest) {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Assets", defaults: PageDefaults(template: .grid, paperColor: .white, pageSize: .letter),
                                        pages: [.template(.grid, color: .white, size: .letter)])
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        return (package, manifest)
    }

    private func makeAsset(_ package: NotebookPackage, _ name: String) throws {
        try Data(repeating: 0xAB, count: 64).write(to: package.assetURL(name))
    }

    func testGarbageCollectionKeepsAssetsNamedAnywhereInTheManifest() async throws {
        let (package, base) = try await makePackage()
        for name in ["scan.heic", "sticker.png", "orphan.pdf"] { try makeAsset(package, name) }
        var manifest = base
        manifest.pages.append(NotebookPage(background: .unknown(.object(["kind": .string("scan"), "file": .string("scan.heic")])),
                                           paperColor: .white, size: PageSize.letter.points))
        manifest.pages[0].extra["stickers"] = .array([.string("assets/sticker.png")])
        try await Task.sleep(for: .milliseconds(20))
        try await package.writeManifest(manifest)
        await package.collectGarbage(keeping: manifest)
        let names = try FileManager.default.contentsOfDirectory(atPath: package.assetsDirectory.path(percentEncoded: false))
        XCTAssertEqual(Set(names), ["scan.heic", "sticker.png"])
    }

    func testNothingIsCollectedWhileAManifestIsQuarantined() async throws {
        let (package, manifest) = try await makePackage()
        try makeAsset(package, "recording.m4a")
        try Data("{ damaged".utf8).write(to: package.url.appending(path: "manifest.json.corrupt"))
        let unlisted = UUID()
        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: [unlisted: PKDrawing(strokes: [dot(at: CGPoint(x: 50, y: 50))])]))
        try await Task.sleep(for: .milliseconds(20))
        try await package.writeManifest(manifest)
        await package.collectGarbage(keeping: manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.assetURL("recording.m4a").path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.inkURL(unlisted).path(percentEncoded: false)))
    }

    func testARebuiltManifestNeverCollectsAssets() async throws {
        let (package, manifest) = try await makePackage()
        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: PKDrawing(strokes: [dot(at: CGPoint(x: 50, y: 50))])]))
        try makeAsset(package, "lecture.pdf")
        for file in [package.manifestURL, package.previousManifestURL] { try? FileManager.default.removeItem(at: file) }
        let load = try await package.readManifest()
        XCTAssertTrue(load.needsSave)
        try await Task.sleep(for: .milliseconds(20))
        try await package.writeManifest(load.manifest)
        let reread = try await package.readManifest().manifest
        await package.collectGarbage(keeping: reread)
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.assetURL("lecture.pdf").path(percentEncoded: false)))
    }

    func testAFolderWithOnlyAssetsIsNotRebuiltIntoANotebook() async throws {
        let root = temporaryRoot(self)
        let package = NotebookPackage(root: root, id: UUID())
        _ = try await package.writeAsset(Data("pdf".utf8), ext: "pdf")
        do {
            _ = try await package.readManifest()
            XCTFail("an interrupted import must not appear as a Recovered Notebook")
        } catch {
            XCTAssertEqual(error as? PackageError, .missing)
        }
    }

    func testBackgroundWritesNeverRecreateADeletedPackage() async throws {
        let (package, manifest) = try await makePackage()
        try FileManager.default.removeItem(at: package.url)
        do {
            try await package.writeText("#ink:none\nhello", pageID: manifest.pages[0].id)
            XCTFail("OCR for a deleted notebook must fail")
        } catch {}
        do {
            try await package.writeThumbnail(Data([1, 2, 3]), pageID: manifest.pages[0].id, key: "k")
            XCTFail("a thumbnail for a deleted notebook must fail")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.url.path(percentEncoded: false)))
    }

    func testBackgroundWritesWorkOnALivePackage() async throws {
        let (package, manifest) = try await makePackage()
        let page = manifest.pages[0].id
        try await package.writeText("#ink:none\nfirst", pageID: page)
        try await package.writeText("#ink:none\nsecond", pageID: page)
        let text = await package.readText(page)
        XCTAssertEqual(text, "#ink:none\nsecond")
        try FileManager.default.removeItem(at: package.thumbsDirectory)
        try await package.writeThumbnail(Data([1, 2, 3]), pageID: page, key: "k")
        try await package.writeThumbnail(Data([4, 5, 6]), pageID: page, key: "k")
        XCTAssertEqual(try Data(contentsOf: package.thumbURL(page, key: "k")), Data([4, 5, 6]))
    }

    func testThumbnailKeysFollowAppearanceAndInk() {
        var page = NotebookPage.template(.narrowRuled, color: .white, size: .letter)
        let plain = page.thumbnailKey
        XCTAssertEqual(page.thumbnailKey, plain, "stable")
        page.background = .template(.grid)
        XCTAssertNotEqual(page.thumbnailKey, plain)
        let grid = page.thumbnailKey
        page.paperColor = .charcoal
        XCTAssertNotEqual(page.thumbnailKey, grid)
        let charcoal = page.thumbnailKey
        page.inkHash = "0123456789abcdef"
        XCTAssertNotEqual(page.thumbnailKey, charcoal)
    }
}

final class ManifestSafetyTests: XCTestCase {
    func testNewerSchemaWithRestructuredPagesOpensReadOnly() throws {
        let raw = #"{"schemaVersion": 3, "title": "From the future", "pages": {"order": ["a", "b"]}}"#
        let (manifest, _) = try ManifestCodec.decode(Data(raw.utf8), fallbackID: UUID())
        XCTAssertTrue(manifest.isNewerThanSupported)
        XCTAssertTrue(manifest.pages.isEmpty)
        XCTAssertEqual(manifest.title, "From the future")
        let rewritten = try JSONValue.parse(ManifestCodec.encode(manifest))
        XCTAssertEqual(rewritten["pages"], .object(["order": .array([.string("a"), .string("b")])]))
    }

    func testUnreadableNestedFieldsAreWrittenBackUnchanged() throws {
        let id = UUID()
        let raw = """
        {"schemaVersion": 2, "id": "\(id.uuidString)", "title": "Nested", "pages": [],
         "cover": {"style": "cloth", "cloth": "oxblood", "seed": "lucky", "inks": ["teal", 7]},
         "library": {"favorite": "yes", "deletedAt": 1727600000, "folderID": ["A", "B"], "currentPage": -2},
         "recordings": [{"id": "\(UUID().uuidString)", "file": "a.m4a", "duration": "long"}]}
        """
        var (manifest, _) = try ManifestCodec.decode(Data(raw.utf8), fallbackID: id)
        manifest.library.lastOpenedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let rewritten = try JSONValue.parse(ManifestCodec.encode(manifest))
        XCTAssertEqual(rewritten["library"]?["deletedAt"], .number(1_727_600_000), "a trashed notebook must stay trashed")
        XCTAssertEqual(rewritten["library"]?["folderID"], .array([.string("A"), .string("B")]))
        XCTAssertEqual(rewritten["library"]?["favorite"], .string("yes"))
        XCTAssertEqual(rewritten["library"]?["currentPage"], .number(-2))
        XCTAssertNotEqual(rewritten["library"]?["lastOpenedAt"], .null, "fields the app changed are still written")
        XCTAssertEqual(rewritten["cover"]?["seed"], .string("lucky"))
        XCTAssertEqual(rewritten["cover"]?["inks"], .array([.string("teal"), .number(7)]))
        XCTAssertEqual(rewritten["recordings"]?.arrayValue?.first?["duration"], .string("long"))

        manifest.library.isFavorite = true
        let changed = try JSONValue.parse(ManifestCodec.encode(manifest))
        XCTAssertEqual(changed["library"]?["favorite"], .bool(true), "a value the user changed replaces the unreadable one")
        XCTAssertEqual(changed["library"]?["deletedAt"], .number(1_727_600_000))
    }
}

@MainActor
final class LibraryStoreSafetyTests: XCTestCase {
    private var container: ModelContainer?

    private func makeStore() throws -> (LibraryStore, StorageRoot, ModelContext) {
        let root = temporaryRoot(self)
        let schema = Schema(versionedSchema: LibraryIndexSchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        return (LibraryStore(root: root, context: container.mainContext), root, container.mainContext)
    }

    private func makeNotebook(_ store: LibraryStore, title: String = "Physics", schemaVersion: Int = 2) async throws -> NotebookManifest {
        var manifest = NotebookManifest(title: title, defaults: PageDefaults(template: .grid, paperColor: .white, pageSize: .letter),
                                        pages: [.template(.grid, color: .white, size: .letter)])
        manifest.schemaVersion = schemaVersion
        let package = NotebookPackage(root: store.root, id: manifest.id)
        try FileManager.default.createDirectory(at: package.url, withIntermediateDirectories: true)
        try ManifestCodec.encode(manifest).write(to: package.manifestURL)
        store.index(manifest)
        return manifest
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func testIndexingAnUnchangedManifestLeavesTheRecordAlone() async throws {
        let (store, _, _) = try makeStore()
        let manifest = try await makeNotebook(store)
        let record = try XCTUnwrap(store.record(manifest.id))
        let stamp = record.indexedAt
        try await Task.sleep(for: .milliseconds(20))
        store.index(manifest)
        XCTAssertEqual(record.indexedAt, stamp)
        var renamed = manifest
        renamed.title = "Physics II"
        store.index(renamed)
        XCTAssertGreaterThan(record.indexedAt, stamp)
        XCTAssertEqual(record.title, "Physics II")
    }

    func testDuplicateKeepsHandwritingSearchable() async throws {
        let (store, _, _) = try makeStore()
        let manifest = try await makeNotebook(store)
        store.updateSearchText("momentum and inertia", for: manifest.id)
        let copyID = try await store.duplicate(try XCTUnwrap(store.record(manifest.id)))
        XCTAssertEqual(store.record(copyID)?.searchText, "momentum and inertia")
    }

    func testReadOnlyNotebooksIgnoreLibraryChanges() async throws {
        let (store, root, _) = try makeStore()
        let manifest = try await makeNotebook(store, schemaVersion: 9)
        let record = try XCTUnwrap(store.record(manifest.id))
        XCTAssertTrue(record.isReadOnly)
        let bytes = try Data(contentsOf: NotebookPackage(root: root, id: manifest.id).manifestURL)
        store.setFavorite(true, for: [record])
        store.rename(record, to: "Changed")
        store.moveToTrash([record])
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(record.isFavorite)
        XCTAssertFalse(record.isTrashed)
        XCTAssertEqual(record.title, "Physics")
        XCTAssertEqual(try Data(contentsOf: NotebookPackage(root: root, id: manifest.id).manifestURL), bytes)
        XCTAssertNil(store.lastError)
    }

    func testALibraryChangeSurvivesADocumentOpeningAtTheSameTime() async throws {
        let (store, root, _) = try makeStore()
        let manifest = try await makeNotebook(store)
        store.setFavorite(true, for: [try XCTUnwrap(store.record(manifest.id))])
        let document = try await DocumentRegistry.shared.open(manifest.id, root: root, scene: nil) { store.reapplyChangesInFlight(to: $0) }
        XCTAssertTrue(document.manifest.library.isFavorite)
        document.rename("Opened")
        let saved = await document.flush()
        XCTAssertTrue(saved)
        let onDisk = try await NotebookPackage(root: root, id: manifest.id).readManifest().manifest
        XCTAssertTrue(onDisk.library.isFavorite, "the document's save must not revert the favourite")
        DocumentRegistry.shared.unregister(manifest.id, document: document)
    }

    func testDeletingPermanentlyMovesThePackageAsideAtOnce() async throws {
        let (store, root, _) = try makeStore()
        let manifest = try await makeNotebook(store)
        let record = try XCTUnwrap(store.record(manifest.id))
        store.moveToTrash([record])
        store.deletePermanently([record])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.package(manifest.id).path(percentEncoded: false)))
        XCTAssertNil(store.record(manifest.id))
        LibraryStore.sweepDeleted(root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deleting.path(percentEncoded: false)))
    }

    func testFolderWritesKeepKeysThisVersionDoesNotKnow() async throws {
        let (store, root, context) = try makeStore()
        let id = UUID()
        let raw = """
        {"folders": [{"id": "\(id.uuidString)", "name": "Bio", "cloth": "moss", "createdAt": "2026-01-01T00:00:00.000Z", "sortIndex": 0, "icon": "leaf"}]}
        """
        try FileManager.default.createDirectory(at: root.library, withIntermediateDirectories: true)
        try Data(raw.utf8).write(to: root.foldersFile)
        await LibraryIndex.refresh(root: root, context: context)
        let folder = try XCTUnwrap(try context.fetch(FetchDescriptor<FolderRecord>()).first)
        store.renameFolder(folder, to: "Biology")
        store.setCloth(.jade, for: folder)
        await waitUntil { FolderFile.read(root).folders.first?.clothRaw == ClothColor.jade.rawValue }
        let file = FolderFile.read(root)
        XCTAssertEqual(file.folders.first?.name, "Biology")
        XCTAssertEqual(file.folders.first?.extra["icon"], .string("leaf"))
    }
}

@MainActor
final class ExportSafetyTests: XCTestCase {
    func testCancellingAnExportStaysCancelled() async throws {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Long", defaults: PageDefaults(template: .grid, paperColor: .white, pageSize: .letter),
                                        pages: (0..<80).map { _ in .template(.grid, color: .white, size: .letter) })
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        let job = ExportJob(document: document)
        try await Task.sleep(for: .milliseconds(30))
        job.cancel()
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(job.state, .cancelled)
    }
}
