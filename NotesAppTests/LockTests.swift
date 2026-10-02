import XCTest
import SwiftData
@testable import NotesApp

/// Locked notebooks: the flag in the manifest and the index, who may open one, and what the widgets are told.
@MainActor
final class LockTests: XCTestCase {
    private var container: ModelContainer?
    private let paper = PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter)

    private func makeStore() throws -> LibraryStore {
        let schema = LibraryIndex.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        return LibraryStore(root: temporaryRoot(self), context: container.mainContext)
    }

    private func makeNotebook(_ title: String, in store: LibraryStore, opened: Date? = nil) async throws -> NotebookRecord {
        var manifest = NotebookManifest(title: title, defaults: paper, pages: [paper.newPage()])
        manifest.library.lastOpenedAt = opened
        try await NotebookPackage(root: store.root, id: manifest.id).create(manifest)
        store.index(manifest)
        return try XCTUnwrap(store.record(manifest.id))
    }

    func testTheLockIsKeptInTheManifest() throws {
        var manifest = NotebookManifest(title: "Diary", defaults: paper, pages: [paper.newPage()])
        XCTAssertFalse(manifest.library.isLocked)
        XCTAssertNil(manifest.library.extra["locked"], "an unlocked notebook's manifest says nothing about locks")
        manifest.library.isLocked = true
        let decoded = try ManifestCodec.decode(ManifestCodec.encode(manifest), fallbackID: manifest.id, fallbackDate: .now).manifest
        XCTAssertTrue(decoded.library.isLocked)
        manifest.library.isLocked = false
        XCTAssertEqual(try ManifestCodec.decode(ManifestCodec.encode(manifest), fallbackID: manifest.id, fallbackDate: .now).manifest.library.isLocked, false)
    }

    func testLockingReachesTheIndexAndTheFile() async throws {
        let store = try makeStore()
        let record = try await makeNotebook("Diary", in: store)
        XCTAssertFalse(record.isLocked)
        store.setLocked(true, for: [record])
        XCTAssertTrue(record.isLocked)
        let package = NotebookPackage(root: store.root, id: record.id)
        for _ in 0..<50 {
            if (try? await package.readManifest().manifest.library.isLocked) == true { break }
            try await Task.sleep(for: .milliseconds(40))
        }
        let saved = try await package.readManifest().manifest
        XCTAssertTrue(saved.library.isLocked)

        let fresh = try ModelContainer(for: LibraryIndex.schema, configurations: ModelConfiguration(schema: LibraryIndex.schema, isStoredInMemoryOnly: true))
        await LibraryIndex.refresh(root: store.root, context: fresh.mainContext)
        XCTAssertEqual(try fresh.mainContext.fetch(FetchDescriptor<NotebookRecord>()).map(\.isLocked), [true], "a rebuilt index reads the lock back")
    }

    func testAnIndexFromBeforeLocksIsMigrated() async throws {
        let root = temporaryRoot(self)
        try FileManager.default.createDirectory(at: root.url, withIntermediateDirectories: true)
        var manifest = NotebookManifest(title: "Diary", defaults: paper, pages: [paper.newPage()])
        manifest.library.isLocked = true
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)

        try autoreleasepool {
            let old = Schema(versionedSchema: LibraryIndexSchemaV3.self)
            let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: root.indexStore))
            let record = LibraryIndexSchemaV3.NotebookRecord(id: manifest.id)
            record.title = "Diary"
            record.indexedAt = .distantFuture
            container.mainContext.insert(record)
            try container.mainContext.save()
        }

        let (container, recovered) = LibraryIndex.makeContainer(root: root)
        XCTAssertFalse(recovered, "the old index is migrated, not set aside")
        let context = container.mainContext
        XCTAssertEqual(try context.fetch(FetchDescriptor<NotebookRecord>()).map(\.isLocked), [false], "the lock starts off")
        await LibraryIndex.refresh(root: root, context: context, full: true)
        XCTAssertEqual(try context.fetch(FetchDescriptor<NotebookRecord>()).map(\.isLocked), [true], "and the first refresh reads it from the manifest")
    }

    func testANotebookStaysOpenOnlyUntilItIsLockedAgain() async {
        let lock = NotebookLock()
        let id = UUID()
        lock.authenticator = ScriptedAuthenticator(passes: 0)
        let refused = await lock.unlock(id, title: "Diary")
        XCTAssertFalse(refused)
        XCTAssertFalse(lock.isUnlocked(id))

        lock.authenticator = ScriptedAuthenticator(passes: 1)
        let allowed = await lock.unlock(id, title: "Diary")
        XCTAssertTrue(allowed)
        XCTAssertTrue(lock.isUnlocked(id))
        let again = await lock.unlock(id, title: "Diary")
        XCTAssertTrue(again, "an open notebook isn't asked about twice")

        lock.lock(id)
        XCTAssertFalse(lock.isUnlocked(id))
        let afterwards = await lock.unlock(id, title: "Diary")
        XCTAssertFalse(afterwards, "closed, it asks again")
    }

    func testALockedNotebookNeverReachesTheWidgets() async throws {
        let store = try makeStore()
        let diary = try await makeNotebook("Diary", in: store, opened: .now)
        let biology = try await makeNotebook("Biology", in: store, opened: Date.now.addingTimeInterval(-3600))
        let activity = WritingActivity(root: store.root)
        XCTAssertEqual(WidgetBridge.snapshot(library: store, activity: activity).notebook?.title, "Diary")
        store.setLocked(true, for: [diary])
        XCTAssertEqual(WidgetBridge.snapshot(library: store, activity: activity).notebook?.title, "Biology", "the widget moves on to the last notebook that isn't locked")
        XCTAssertEqual(store.lastOpenedNotebook?.id, diary.id, "Continue Writing still goes to it, and asks first")
        store.setLocked(true, for: [biology])
        XCTAssertNil(WidgetBridge.snapshot(library: store, activity: activity).notebook)
        XCTAssertTrue(diary.accessibilityDescription.contains("locked"))
    }
}
