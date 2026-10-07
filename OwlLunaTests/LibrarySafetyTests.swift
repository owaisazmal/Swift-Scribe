import XCTest
import SwiftData
@testable import OwlLuna

/// The library's undo slip and ⌘Z, and the confirmation before a permanent delete.
@MainActor
final class LibrarySafetyTests: XCTestCase {
    private var container: ModelContainer?

    private func makeStore() throws -> LibraryStore {
        let schema = LibraryIndex.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        return LibraryStore(root: temporaryRoot(self), context: container.mainContext)
    }

    private func makeNotebook(_ title: String, in store: LibraryStore, folder: FolderRecord? = nil, favorite: Bool = false) async throws -> NotebookRecord {
        var manifest = NotebookManifest(title: title, defaults: PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter),
                                        pages: [NotebookPage(background: .template(.narrowRuled), paperColor: .white, size: PageSize.letter.points)])
        manifest.library.folderID = folder?.id
        manifest.library.isFavorite = favorite
        try await NotebookPackage(root: store.root, id: manifest.id).create(manifest)
        store.index(manifest)
        return try XCTUnwrap(store.record(manifest.id))
    }

    private func makeUndoManager() -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return undoManager
    }

    private func grouped(_ undoManager: UndoManager, _ change: () -> Void) {
        undoManager.beginUndoGrouping()
        change()
        undoManager.endUndoGrouping()
    }

    private func manifest(_ id: UUID, in store: LibraryStore, until condition: (NotebookManifest) -> Bool) async throws -> NotebookManifest {
        let package = NotebookPackage(root: store.root, id: id)
        let deadline = Date().addingTimeInterval(5)
        var manifest = try await package.readManifest().manifest
        while !condition(manifest), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
            manifest = try await package.readManifest().manifest
        }
        return manifest
    }

    func testUndoingATrashRestoresTheNotebookAndRedoTrashesItAgain() async throws {
        let store = try makeStore()
        let changes = LibraryChangeCenter()
        let undoManager = makeUndoManager()
        let record = try await makeNotebook("Physics", in: store)

        grouped(undoManager) { changes.moveToTrash([record], in: store, undoManager: undoManager) }
        XCTAssertTrue(record.isTrashed)
        XCTAssertEqual(changes.current?.message, "Moved “Physics” to Recently Deleted")
        XCTAssertEqual(changes.trashBumps, 1, "the bin bounces")
        var onDisk = try await manifest(record.id, in: store) { $0.library.deletedAt != nil }
        XCTAssertNotNil(onDisk.library.deletedAt)

        changes.current?.undo()
        XCTAssertFalse(record.isTrashed)
        XCTAssertNil(changes.current, "undoing takes the slip away")
        onDisk = try await manifest(record.id, in: store) { $0.library.deletedAt == nil }
        XCTAssertNil(onDisk.library.deletedAt)

        XCTAssertTrue(undoManager.canRedo)
        undoManager.redo()
        XCTAssertTrue(record.isTrashed)
        onDisk = try await manifest(record.id, in: store) { $0.library.deletedAt != nil }
        XCTAssertNotNil(onDisk.library.deletedAt)
        undoManager.undo()
        XCTAssertFalse(record.isTrashed, "undo and redo keep alternating")
    }

    func testTheSlipUndoesOnlyItsOwnChangeOnceSomethingElseIsUndoable() async throws {
        let store = try makeStore()
        let changes = LibraryChangeCenter()
        let undoManager = makeUndoManager()
        let record = try await makeNotebook("Physics", in: store)
        let other = UndoProbe()

        grouped(undoManager) { changes.moveToTrash([record], in: store, undoManager: undoManager) }
        grouped(undoManager) { undoManager.registerUndo(withTarget: other) { $0.undone = true } }

        changes.current?.undo()
        XCTAssertFalse(record.isTrashed)
        XCTAssertNil(changes.current)
        XCTAssertFalse(other.undone, "the later change is left alone")
        undoManager.undo()
        XCTAssertTrue(other.undone)
        XCTAssertFalse(undoManager.canUndo, "the trash isn't undone twice")
        XCTAssertFalse(record.isTrashed)
    }

    func testUndoingAMoveReturnsEachNotebookToItsOwnShelf() async throws {
        let store = try makeStore()
        let changes = LibraryChangeCenter()
        let undoManager = makeUndoManager()
        let biology = try XCTUnwrap(store.createFolder(name: "Biology", cloth: .moss))
        let physics = try XCTUnwrap(store.createFolder(name: "Physics", cloth: .cobalt))
        let archive = try XCTUnwrap(store.createFolder(name: "Archive", cloth: .oxblood))
        let cells = try await makeNotebook("Cells", in: store, folder: biology)
        let optics = try await makeNotebook("Optics", in: store, folder: physics)
        let loose = try await makeNotebook("Loose", in: store)

        grouped(undoManager) { changes.move([cells, optics, loose], to: archive, in: store, undoManager: undoManager) }
        XCTAssertEqual([cells, optics, loose].map(\.folder?.id), [archive.id, archive.id, archive.id])
        XCTAssertEqual(changes.current?.message, "Moved 3 notebooks to Archive")

        undoManager.undo()
        XCTAssertEqual(cells.folder?.id, biology.id)
        XCTAssertEqual(optics.folder?.id, physics.id)
        XCTAssertNil(loose.folder)
        let onDisk = try await manifest(optics.id, in: store) { $0.library.folderID == physics.id }
        XCTAssertEqual(onDisk.library.folderID, physics.id)

        undoManager.redo()
        store.deleteFolder(biology)
        undoManager.undo()
        XCTAssertNil(cells.folder, "a shelf deleted since goes back to no shelf")
        XCTAssertEqual(optics.folder?.id, physics.id)
    }

    func testUndoingAFavouriteRestoresEachPreviousValue() async throws {
        let store = try makeStore()
        let changes = LibraryChangeCenter()
        let undoManager = makeUndoManager()
        let starred = try await makeNotebook("Starred", in: store, favorite: true)
        let plain = try await makeNotebook("Plain", in: store)

        grouped(undoManager) { changes.setFavorite(true, for: [starred, plain], in: store, undoManager: undoManager) }
        XCTAssertTrue(starred.isFavorite)
        XCTAssertTrue(plain.isFavorite)
        XCTAssertEqual(changes.current?.message, "Added 2 notebooks to Favourites")

        undoManager.undo()
        XCTAssertTrue(starred.isFavorite, "it was a favourite before")
        XCTAssertFalse(plain.isFavorite)
    }

    func testAPermanentDeleteWaitsForConfirmation() async throws {
        let store = try makeStore()
        let changes = LibraryChangeCenter()
        let record = try await makeNotebook("Physics", in: store)
        let id = record.id
        store.moveToTrash([record])

        changes.requestPermanentDelete([id])
        XCTAssertEqual(changes.pendingPermanentDelete, [id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.root.package(id).path(percentEncoded: false)), "nothing is deleted yet")
        XCTAssertNotNil(store.record(id))

        changes.confirmPermanentDelete(in: store)
        XCTAssertTrue(changes.pendingPermanentDelete.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.package(id).path(percentEncoded: false)))
        XCTAssertNil(store.record(id))
    }

    func testUndoAfterAPermanentDeleteDoesNothing() async throws {
        let store = try makeStore()
        let changes = LibraryChangeCenter()
        let undoManager = makeUndoManager()
        let record = try await makeNotebook("Physics", in: store)
        let id = record.id

        grouped(undoManager) { changes.moveToTrash([record], in: store, undoManager: undoManager) }
        changes.requestPermanentDelete([id])
        changes.confirmPermanentDelete(in: store)
        XCTAssertNil(store.record(id))

        undoManager.undo()
        XCTAssertNil(store.record(id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.root.package(id).path(percentEncoded: false)))
    }
}

private final class UndoProbe {
    var undone = false
}
