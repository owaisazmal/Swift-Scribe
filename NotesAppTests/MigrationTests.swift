import XCTest
import PencilKit
import SwiftData
@testable import NotesApp

/// A v1 library as the v1 app stored it. `Fixtures/v1-library.json` was written by the real v1 code before it was removed.
struct V1LibraryFixture {
    let root: StorageRoot
    let cellBiology = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000001")!
    let syllabus = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000002")!
    let damaged = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000003")!
    let lostPages = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000004")!
    let orphan = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000005")!
    let folderID = UUID(uuidString: "C0FFEE00-0000-4000-8000-0000000000F0")!
    /// Page-local (page point) centres of the strokes written on each Cell Biology page.
    let cellBiologyLocal: [[CGPoint]] = [
        [CGPoint(x: 76.5, y: 114.75), CGPoint(x: 300, y: 500)],
        [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200), CGPoint(x: 400, y: 700)],
        [CGPoint(x: 500, y: 60)],
    ]
    let pdfFile = "5B1D5B1D-0000-4000-8000-00000000A001.pdf"
    let imageFile = "5B1D5B1D-0000-4000-8000-00000000A002.jpg"
    let audioFile = "5B1D5B1D-0000-4000-8000-00000000A003.m4a"
    let corruptBytes = Data("this is not a PencilKit drawing".utf8)

    func v1Directory(_ id: UUID) -> URL { root.v1Notebooks.appending(path: id.uuidString, directoryHint: .isDirectory) }

    func write() throws {
        let url = try XCTUnwrap(Bundle(for: MigrationTests.self).url(forResource: "v1-library", withExtension: "json"))
        let files = try XCTUnwrap(JSONValue.parse(Data(contentsOf: url))["files"]?.objectValue)
        for (path, value) in files {
            let target = root.url.appending(path: path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(value.stringValue))).write(to: target)
        }
    }

    /// Every v1 file with its bytes, keyed by path relative to `base`.
    static func snapshot(_ base: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        let base = base.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return result }
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let relative = url.resolvingSymlinksInPath().pathComponents.dropFirst(base.pathComponents.count).joined(separator: "/")
            result[relative] = try? Data(contentsOf: url)
        }
        return result
    }
}

@MainActor
final class MigrationTests: XCTestCase {
    private func migrated() async throws -> (V1LibraryFixture, MigrationReport, v1Notebooks: [String: Data]) {
        let fixture = V1LibraryFixture(root: temporaryRoot(self))
        try fixture.write()
        let v1Notebooks = V1LibraryFixture.snapshot(fixture.root.v1Notebooks)
        let report = await V1Migrator(root: fixture.root).run()
        return (fixture, report, v1Notebooks)
    }

    private func load(_ root: StorageRoot, _ id: UUID) async throws -> (NotebookPackage, NotebookManifest) {
        let package = NotebookPackage(root: root, id: id)
        return (package, try await package.readManifest().manifest)
    }

    private func ink(_ package: NotebookPackage, _ page: NotebookPage) async -> PKDrawing {
        if case .ink(let drawing, _) = await package.readInk(page.id) { return drawing }
        return PKDrawing()
    }

    /// Frames v1's NotebookLayout produced for Letter, A4 and a 612 × 400 photo page, recorded before v1 was removed.
    func testLegacyLayoutMatchesV1() {
        let sizes = [PageSize.letter.points, PageSize.a4.points, CGSize(width: 612, height: 400)]
        XCTAssertEqual(LegacyV1Layout.frames(for: sizes), [CGRect(x: 24, y: 24, width: 800, height: 1035),
                                                           CGRect(x: 24, y: 1083, width: 800, height: 1131),
                                                           CGRect(x: 24, y: 2238, width: 800, height: 523)])
    }

    func testEveryNotebookMigrates() async throws {
        let (fixture, report, _) = try await migrated()
        XCTAssertTrue(report.isComplete, "\(report.failed)")
        XCTAssertEqual(Set(report.migrated), [fixture.cellBiology, fixture.syllabus, fixture.damaged, fixture.lostPages, fixture.orphan])
        XCTAssertEqual(Set(fixture.root.packageIDs()), Set(report.migrated))
    }

    func testInkIsSplitIntoPageLocalPages() async throws {
        let (fixture, _, _) = try await migrated()
        let (package, manifest) = try await load(fixture.root, fixture.cellBiology)
        XCTAssertEqual(manifest.title, "Cell Biology")
        XCTAssertEqual(manifest.pages.map(\.template), [.narrowRuled, .grid, .dotted])
        XCTAssertEqual(manifest.pages[1].paperColor, .ivory)
        XCTAssertEqual(manifest.pages[2].size, PageSize.a4.points)
        XCTAssertEqual(manifest.migratedFrom, "v1")
        for (index, page) in manifest.pages.enumerated() {
            let drawing = await ink(package, page)
            let expected = fixture.cellBiologyLocal[index]
            XCTAssertEqual(drawing.strokes.count, expected.count, "page \(index)")
            XCTAssertNotNil(page.inkHash)
            let centres = drawing.strokes.map { CGPoint(x: $0.renderBounds.midX, y: $0.renderBounds.midY) }.sorted { $0.y < $1.y }
            for (actual, wanted) in zip(centres, expected.sorted { $0.y < $1.y }) {
                XCTAssertEqual(actual.x, wanted.x, accuracy: 1.5, "page \(index)")
                XCTAssertEqual(actual.y, wanted.y, accuracy: 1.5, "page \(index)")
            }
            for stroke in drawing.strokes {
                XCTAssertTrue(CGRect(origin: .zero, size: page.size).contains(stroke.renderBounds), "page \(index) stroke stays on its page")
            }
        }
    }

    func testStrokeWidthScalesWithThePage() async throws {
        let (fixture, _, _) = try await migrated()
        let (package, manifest) = try await load(fixture.root, fixture.cellBiology)
        let firstPage = await ink(package, manifest.pages[0])
        let first = try XCTUnwrap(firstPage.strokes.first)
        // A 20-point-long, 3-point-wide v1 dot becomes 20 × 612/800 long in page points.
        XCTAssertEqual(first.renderBounds.width, (20 + 3) * 612 / 800, accuracy: 1.5)
    }

    func testLibraryStateFoldersAndSearchTextMigrate() async throws {
        let (fixture, _, _) = try await migrated()
        let (package, cell) = try await load(fixture.root, fixture.cellBiology)
        XCTAssertTrue(cell.library.isFavorite)
        XCTAssertEqual(cell.library.folderID, fixture.folderID)
        XCTAssertEqual(cell.cover.style, .firstPage, "migrated notebooks show their first page, as their v1 cards did")
        XCTAssertEqual(try String(contentsOf: package.textDirectory.appending(path: "legacy-v1.txt"), encoding: .utf8), "mitochondria ribosome")
        let folders = FolderFile.read(fixture.root)
        XCTAssertEqual(folders.folders.map(\.name), ["Biology"])
        XCTAssertEqual(folders.folders.first?.cloth, .moss)
    }

    func testPDFImageAndAudioAssetsMigrate() async throws {
        let (fixture, _, v1) = try await migrated()
        let (package, manifest) = try await load(fixture.root, fixture.syllabus)
        XCTAssertEqual(manifest.pages.map(\.background), [.pdf(file: fixture.pdfFile, index: 0), .pdf(file: fixture.pdfFile, index: 1), .image(file: fixture.imageFile)])
        XCTAssertEqual(manifest.cover.style, .firstPage, "notebooks that open on a PDF use the first page as their cover")
        XCTAssertNotNil(manifest.library.deletedAt)
        XCTAssertEqual(manifest.recordings.map(\.file), [fixture.audioFile])
        XCTAssertEqual(manifest.recordings.first?.duration, 42)
        for file in [fixture.pdfFile, fixture.imageFile, fixture.audioFile] {
            XCTAssertEqual(try Data(contentsOf: package.assetURL(file)), v1["\(fixture.syllabus.uuidString)/assets/\(file)"], file)
        }
        let landscape = await ink(package, manifest.pages[1])
        XCTAssertEqual(landscape.strokes.count, 1)
        XCTAssertEqual(landscape.strokes[0].renderBounds.midX, 200, accuracy: 1.5)
        XCTAssertEqual(landscape.strokes[0].renderBounds.midY, 100, accuracy: 1.5)
        let firstPageInk = await ink(package, manifest.pages[0])
        XCTAssertEqual(firstPageInk.strokes.count, 0)
    }

    func testUnreadableV1DataIsKeptNotDropped() async throws {
        let (fixture, report, _) = try await migrated()
        let (damagedPackage, damaged) = try await load(fixture.root, fixture.damaged)
        XCTAssertEqual(damaged.pages.count, 1)
        XCTAssertEqual(try Data(contentsOf: damagedPackage.url.appending(path: "legacy/drawing.pkdrawing.corrupt")), fixture.corruptBytes)

        let (lostPackage, lost) = try await load(fixture.root, fixture.lostPages)
        XCTAssertEqual(lost.pages.count, 2, "pages are rebuilt from the ink when the page list is unreadable")
        let perPage = await [ink(lostPackage, lost.pages[0]).strokes.count, ink(lostPackage, lost.pages[1]).strokes.count]
        XCTAssertEqual(perPage, [1, 1])
        XCTAssertEqual(try Data(contentsOf: lostPackage.url.appending(path: "legacy/pages.json")), Data("{not json".utf8))

        let (_, orphan) = try await load(fixture.root, fixture.orphan)
        XCTAssertEqual(orphan.title, "Recovered Notebook")
        XCTAssertGreaterThanOrEqual(report.warnings.count, 3)
    }

    func testLegacySearchTextGoesOnceEveryPageHasItsOwn() async throws {
        let (fixture, _, _) = try await migrated()
        let (package, manifest) = try await load(fixture.root, fixture.cellBiology)
        let legacy = package.textDirectory.appending(path: NotebookPackage.legacyTextName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path(percentEncoded: false)))
        for page in manifest.pages.dropLast() {
            try await package.writeText(HandwritingIndexer.header(for: page) + "cell", pageID: page.id)
        }
        let last = try XCTUnwrap(manifest.pages.last)
        let partial = await HandwritingIndexer.shared.index(HandwritingIndexer.Job(package: package, pages: Array(manifest.pages.dropLast())))
        XCTAssertTrue(partial.contains("mitochondria"), "kept while any page of the notebook might still need it")
        try await package.writeText(HandwritingIndexer.header(for: last) + "membrane", pageID: last.id)
        let text = await HandwritingIndexer.shared.index(HandwritingIndexer.Job(package: package, pages: manifest.pages))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path(percentEncoded: false)))
        XCTAssertFalse(text.contains("mitochondria"), "v1 text that no page has any more stops matching")
        XCTAssertTrue(text.contains("membrane"))
    }

    func testMigratedFoldersGoAfterExistingShelvesWithoutGaps() async throws {
        let fixture = V1LibraryFixture(root: temporaryRoot(self))
        try fixture.write()
        var file = FolderFile()
        file.folders = [FolderEntry(id: UUID(), name: "Existing", clothRaw: ClothColor.slate.rawValue, createdAt: .now, sortIndex: 0)]
        try file.write(fixture.root)
        _ = await V1Migrator(root: fixture.root).run()
        let folders = FolderFile.read(fixture.root).folders
        XCTAssertEqual(folders.map(\.name), ["Existing", "Biology"])
        XCTAssertEqual(folders.map(\.sortIndex), [0, 1])
    }

    func testFoldersKeepV1OrderAndDistinctColours() {
        let clothes = FolderColor.allCases.map(\.cloth)
        XCTAssertEqual(Set(clothes).count, FolderColor.allCases.count)
        XCTAssertEqual(FolderColor.purple.cloth, .plum)
    }

    func testV1FilesMoveToBackupUnchanged() async throws {
        let (fixture, report, v1) = try await migrated()
        let backup = try XCTUnwrap(report.backupURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.v1Notebooks.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.v1Store.path(percentEncoded: false)))
        XCTAssertEqual(V1LibraryFixture.snapshot(backup.appending(path: "Notebooks")), v1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appending(path: "SwiftScribe.store").path(percentEncoded: false)))
        XCTAssertFalse(V1Migrator(root: fixture.root).isNeeded)
        let log = try JSONValue.parse(Data(contentsOf: fixture.root.migrationLog))
        XCTAssertEqual(log["runs"]?.arrayValue?.last?["complete"], .bool(true))
    }

    func testMigrationIsIdempotent() async throws {
        let (fixture, first, _) = try await migrated()
        let manifests = Dictionary(uniqueKeysWithValues: try first.migrated.map { ($0, try Data(contentsOf: NotebookPackage(root: fixture.root, id: $0).manifestURL)) })
        // Put the v1 files back as if the move had been undone, then run again.
        let backup = try XCTUnwrap(first.backupURL)
        try FileManager.default.moveItem(at: backup.appending(path: "Notebooks"), to: fixture.root.v1Notebooks)
        try FileManager.default.moveItem(at: backup.appending(path: "SwiftScribe.store"), to: fixture.root.v1Store)

        let second = await V1Migrator(root: fixture.root).run()
        XCTAssertTrue(second.migrated.isEmpty)
        XCTAssertEqual(Set(second.alreadyMigrated), Set(first.migrated))
        for (id, data) in manifests {
            XCTAssertEqual(try Data(contentsOf: NotebookPackage(root: fixture.root, id: id).manifestURL), data, "a second run must not rewrite \(id)")
        }
        XCTAssertEqual(FolderFile.read(fixture.root).folders.count, 1)
    }

    func testMigrationResumesAfterAnInterruptedRun() async throws {
        let fixture = V1LibraryFixture(root: temporaryRoot(self))
        try fixture.write()
        let migrator = V1Migrator(root: fixture.root)
        let (notebooks, _, _) = try migrator.readV1()
        // First run died after finishing Syllabus and while Cell Biology was half-written.
        _ = try migrator.migrate(try XCTUnwrap(notebooks.first { $0.id == fixture.syllabus }))
        let staging = fixture.root.library.appending(path: "\(fixture.cellBiology.uuidString).migrating", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging.appending(path: "ink"), withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: staging.appending(path: "ink/half.pkdrawing"))

        let report = await migrator.run()
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.alreadyMigrated, [fixture.syllabus])
        XCTAssertTrue(report.migrated.contains(fixture.cellBiology))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path(percentEncoded: false)))
        let (package, manifest) = try await load(fixture.root, fixture.cellBiology)
        let count = await ink(package, manifest.pages[1]).strokes.count
        XCTAssertEqual(count, 3)
        XCTAssertNotNil(report.backupURL)
    }

    func testUnreadableV1StoreIsRetriedNotArchived() async throws {
        let fixture = V1LibraryFixture(root: temporaryRoot(self))
        try fixture.write()
        try Data("not a database".utf8).write(to: fixture.root.v1Store)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: fixture.root.url.appending(path: "SwiftScribe.store\(suffix)"))
        }
        let report = await V1Migrator(root: fixture.root).run()
        XCTAssertNotNil(report.storeError)
        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(fixture.root.packageIDs().isEmpty, "nothing is rebuilt from drawings alone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.root.v1Notebooks.path(percentEncoded: false)), "v1 files stay in place")
        XCTAssertTrue(V1Migrator(root: fixture.root).isNeeded, "the next launch tries again")
    }

    func testDeletedMigratedNotebookDoesNotComeBack() async throws {
        let fixture = V1LibraryFixture(root: temporaryRoot(self))
        try fixture.write()
        try FileManager.default.createDirectory(at: fixture.root.library.appending(path: "\(fixture.lostPages.uuidString).scribe"),
                                                withIntermediateDirectories: true)
        let first = await V1Migrator(root: fixture.root).run()
        XCTAssertNotNil(first.failed[fixture.lostPages], "a clash with an existing package fails that notebook")
        XCTAssertEqual(first.titles[fixture.lostPages], "Lost Pages")
        XCTAssertFalse(first.isComplete)

        try FileManager.default.removeItem(at: fixture.root.package(fixture.cellBiology))
        try FileManager.default.removeItem(at: fixture.root.package(fixture.lostPages))
        let second = await V1Migrator(root: fixture.root).run()
        XCTAssertTrue(second.alreadyMigrated.contains(fixture.cellBiology), "the log remembers it")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.package(fixture.cellBiology).path(percentEncoded: false)),
                       "a migrated notebook the user deleted stays deleted")
        XCTAssertTrue(second.migrated.contains(fixture.lostPages), "the one that failed is retried")
        XCTAssertTrue(second.isComplete)
    }

    func testIndexIsRebuiltFromManifests() async throws {
        let (fixture, _, _) = try await migrated()
        let schema = Schema(versionedSchema: LibraryIndexSchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        await LibraryIndex.refresh(root: fixture.root, context: context)
        let records = try context.fetch(FetchDescriptor<NotebookRecord>())
        XCTAssertEqual(records.count, 5)
        let cell = try XCTUnwrap(records.first { $0.id == fixture.cellBiology })
        XCTAssertEqual(cell.title, "Cell Biology")
        XCTAssertEqual(cell.pageCount, 3)
        XCTAssertTrue(cell.isFavorite)
        XCTAssertEqual(cell.folder?.name, "Biology")
        XCTAssertTrue(cell.searchText.contains("mitochondria"))
        XCTAssertTrue(try XCTUnwrap(records.first { $0.id == fixture.syllabus }).isTrashed)
        XCTAssertEqual(try XCTUnwrap(records.first { $0.id == fixture.syllabus }).coverStyle, .firstPage)

        // Deleting the whole index and refreshing gives the same answer.
        try context.delete(model: NotebookRecord.self)
        try context.delete(model: FolderRecord.self)
        try context.save()
        await LibraryIndex.refresh(root: fixture.root, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NotebookRecord>()), 5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FolderRecord>()), 1)
    }

    func testUnreadableIndexStoreIsSetAsideAndRebuilt() throws {
        let root = temporaryRoot(self)
        try Data("not a database".utf8).write(to: root.indexStore)
        let (container, recovered) = LibraryIndex.makeContainer(root: root)
        XCTAssertTrue(recovered)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<NotebookRecord>()), 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.url.path(percentEncoded: false))
        XCTAssertTrue(names.contains { $0.hasPrefix("LibraryIndex.store.unreadable-") }, "\(names)")
    }
}
