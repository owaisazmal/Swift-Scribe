import XCTest
import SwiftData
@testable import OwlLuna

/// Search text in its own table: finding notebooks without loading it, and coming over from the first index schema.
@MainActor
final class SearchIndexTests: XCTestCase {
    private var container: ModelContainer?
    private let paper = PageDefaults(template: .grid, paperColor: .white, pageSize: .letter)

    private func makeStore() throws -> LibraryStore {
        let schema = LibraryIndex.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        return LibraryStore(root: temporaryRoot(self), context: container.mainContext)
    }

    private func makeNotebook(_ title: String, in store: LibraryStore) async throws -> NotebookManifest {
        let manifest = NotebookManifest(title: title, defaults: paper, pages: [paper.newPage()])
        try await NotebookPackage(root: store.root, id: manifest.id).create(manifest)
        store.index(manifest)
        return manifest
    }

    func testNotebooksAreFoundByTitleOrByTheirText() async throws {
        let store = try makeStore()
        let physics = try await makeNotebook("Physics", in: store), cooking = try await makeNotebook("Recipes", in: store)
        store.updateSearchText("momentum and inertia", for: physics.id)
        store.updateSearchText("Sourdough starter, day three", for: cooking.id)
        let context = ModelContext(try XCTUnwrap(container))
        XCTAssertEqual(LibraryIndex.notebookIDs(matching: "inertia", in: context), [physics.id])
        XCTAssertEqual(LibraryIndex.notebookIDs(matching: "SOURDOUGH", in: context), [cooking.id], "case doesn't matter")
        XCTAssertEqual(LibraryIndex.notebookIDs(matching: "recipes", in: context), [cooking.id], "titles still match")
        XCTAssertEqual(LibraryIndex.notebookIDs(matching: "s", in: context), [physics.id, cooking.id])
        XCTAssertTrue(LibraryIndex.notebookIDs(matching: "zebra", in: context).isEmpty)
    }

    func testSearchTextIsOneRowPerNotebook() async throws {
        let store = try makeStore()
        let manifest = try await makeNotebook("Physics", in: store)
        let context = try XCTUnwrap(container).mainContext
        store.updateSearchText("momentum", for: manifest.id)
        let version = store.searchVersion
        store.updateSearchText("momentum", for: manifest.id)
        XCTAssertEqual(store.searchVersion, version, "the same text again changes nothing, so a search isn't redone")
        store.updateSearchText("momentum and inertia", for: manifest.id)
        XCTAssertEqual(store.searchVersion, version + 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotebookSearchText>()), 1)
        XCTAssertEqual(store.searchText(for: manifest.id), "momentum and inertia")

        store.updateSearchText("orphan", for: UUID())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotebookSearchText>()), 1, "no row for a notebook the library doesn't have")

        let record = try XCTUnwrap(store.record(manifest.id))
        store.moveToTrash([record])
        store.deletePermanently([record])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotebookSearchText>()), 0, "deleting the notebook deletes its text")
    }

    func testAnIndexFromTheFirstSchemaMigratesAndFindsItsTextAgain() async throws {
        let root = temporaryRoot(self)
        try FileManager.default.createDirectory(at: root.url, withIntermediateDirectories: true)
        let manifest = NotebookManifest(title: "Physics", defaults: paper, pages: [paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        try await package.writeText("#ink:none\nmomentum and inertia", pageID: manifest.pages[0].id)

        try autoreleasepool {
            let old = Schema(versionedSchema: LibraryIndexSchemaV1.self)
            let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: root.indexStore))
            let record = LibraryIndexSchemaV1.NotebookRecord(id: manifest.id)
            record.title = "Physics"
            record.searchText = "momentum and inertia"
            record.isFavorite = true
            record.indexedAt = .distantFuture
            container.mainContext.insert(record)
            try container.mainContext.save()
        }

        let (container, recovered) = LibraryIndex.makeContainer(root: root)
        XCTAssertFalse(recovered, "the old index is migrated, not set aside")
        let context = container.mainContext
        let records = try context.fetch(FetchDescriptor<NotebookRecord>())
        XCTAssertEqual(records.map(\.title), ["Physics"])
        XCTAssertEqual(records.first?.isFavorite, true, "what the record knew comes across")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotebookSearchText>()), 0)

        await LibraryIndex.refresh(root: root, context: context)
        XCTAssertEqual(LibraryIndex.notebookIDs(matching: "inertia", in: ModelContext(container)), [manifest.id],
                       "the text is read back from the notebook, though its manifest hasn't changed")
        await LibraryIndex.refresh(root: root, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotebookSearchText>()), 1)

        try FileManager.default.removeItem(at: root.package(manifest.id))
        await LibraryIndex.refresh(root: root, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotebookSearchText>()), 0, "a notebook removed from disk takes its text with it")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotebookRecord>()), 0)
    }
}
