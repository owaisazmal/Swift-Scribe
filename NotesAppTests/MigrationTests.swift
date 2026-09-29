import XCTest
import PencilKit
import SwiftData
@testable import NotesApp

/// Builds a v1 library exactly as the v1 app stored it: one SwiftData store and one drawing per notebook
/// in the shared 800-point layout.
@MainActor
struct V1LibraryFixture {
    let root: StorageRoot
    let cellBiology = UUID(), syllabus = UUID(), damaged = UUID(), lostPages = UUID(), orphan = UUID()
    let folderID = UUID()
    /// Page-local (page point) centres of the strokes written on each Cell Biology page.
    let cellBiologyLocal: [[CGPoint]] = [
        [CGPoint(x: 76.5, y: 114.75), CGPoint(x: 300, y: 500)],
        [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200), CGPoint(x: 400, y: 700)],
        [CGPoint(x: 500, y: 60)],
    ]
    let pdfFile = "\(UUID().uuidString).pdf"
    let imageFile = "\(UUID().uuidString).jpg"
    let audioFile = "\(UUID().uuidString).m4a"
    let corruptBytes = Data("this is not a PencilKit drawing".utf8)

    func v1Directory(_ id: UUID) -> URL { root.v1Notebooks.appending(path: id.uuidString, directoryHint: .isDirectory) }

    private func canvasPoint(_ local: CGPoint, frame: CGRect, pageSize: CGSize) -> CGPoint {
        let scale = frame.width / pageSize.width
        return CGPoint(x: frame.minX + local.x * scale, y: frame.minY + local.y * scale)
    }

    func write() throws {
        let fileManager = FileManager.default
        let schema = Schema([Notebook.self, Folder.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: root.v1Store))
        let context = ModelContext(container)

        let folder = Folder(name: "Biology", color: .green)
        folder.id = folderID
        context.insert(folder)

        let cell = Notebook(title: "Cell Biology", template: .narrowRuled, color: .white, size: .letter, folder: folder)
        cell.id = cellBiology
        cell.isFavorite = true
        cell.pages = [.template(.narrowRuled, color: .white, size: .letter), .template(.grid, color: .ivory, size: .letter),
                      .template(.dotted, color: .white, size: .a4)]
        cell.searchText = "mitochondria ribosome"
        context.insert(cell)
        let layout = NotebookLayout(pages: cell.pages)
        var strokes: [PKStroke] = []
        for (index, points) in cellBiologyLocal.enumerated() {
            for point in points {
                strokes.append(dot(at: canvasPoint(point, frame: layout.frames[index], pageSize: cell.pages[index].size)))
            }
        }
        try fileManager.createDirectory(at: v1Directory(cellBiology), withIntermediateDirectories: true)
        try PKDrawing(strokes: strokes).dataRepresentation().write(to: v1Directory(cellBiology).appending(path: "drawing.pkdrawing"))

        let syllabus = Notebook(title: "Syllabus", template: .blank, color: .white, size: .letter)
        syllabus.id = self.syllabus
        syllabus.deletedAt = Date(timeIntervalSince1970: 1_790_000_000)
        syllabus.pages = [PageSpec(background: .pdf(file: pdfFile, pageIndex: 0), paperColor: .white, size: CGSize(width: 612, height: 792)),
                          PageSpec(background: .pdf(file: pdfFile, pageIndex: 1), paperColor: .white, size: CGSize(width: 792, height: 612)),
                          PageSpec(background: .image(file: imageFile), paperColor: .white, size: CGSize(width: 612, height: 400))]
        syllabus.recordings = [Recording(fileName: audioFile, createdAt: Date(timeIntervalSince1970: 1_790_000_500), duration: 42)]
        context.insert(syllabus)
        let syllabusLayout = NotebookLayout(pages: syllabus.pages)
        let assets = v1Directory(self.syllabus).appending(path: "assets", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
        try PKDrawing(strokes: [dot(at: canvasPoint(CGPoint(x: 200, y: 100), frame: syllabusLayout.frames[1], pageSize: syllabus.pages[1].size))])
            .dataRepresentation().write(to: v1Directory(self.syllabus).appending(path: "drawing.pkdrawing"))
        try Self.pdfData(sizes: [CGSize(width: 612, height: 792), CGSize(width: 792, height: 612)]).write(to: assets.appending(path: pdfFile))
        try Data(repeating: 0xAB, count: 2048).write(to: assets.appending(path: imageFile))
        try Data(repeating: 0xCD, count: 4096).write(to: assets.appending(path: audioFile))

        let damagedNotebook = Notebook(title: "Damaged", template: .grid, color: .white, size: .letter)
        damagedNotebook.id = damaged
        context.insert(damagedNotebook)
        try fileManager.createDirectory(at: v1Directory(damaged), withIntermediateDirectories: true)
        try corruptBytes.write(to: v1Directory(damaged).appending(path: "drawing.pkdrawing"))

        let lost = Notebook(title: "Lost Pages", template: .narrowRuled, color: .white, size: .letter)
        lost.id = lostPages
        lost.pagesData = Data("{not json".utf8)
        context.insert(lost)
        let twoPages = NotebookLayout(pages: [.template(.blank, color: .white, size: .letter), .template(.blank, color: .white, size: .letter)])
        try fileManager.createDirectory(at: v1Directory(lostPages), withIntermediateDirectories: true)
        try PKDrawing(strokes: [dot(at: CGPoint(x: 200, y: twoPages.frames[0].midY)), dot(at: CGPoint(x: 200, y: twoPages.frames[1].midY))])
            .dataRepresentation().write(to: v1Directory(lostPages).appending(path: "drawing.pkdrawing"))

        try fileManager.createDirectory(at: v1Directory(orphan), withIntermediateDirectories: true)
        try PKDrawing(strokes: [dot(at: CGPoint(x: 300, y: 300))]).dataRepresentation()
            .write(to: v1Directory(orphan).appending(path: "drawing.pkdrawing"))

        try context.save()
    }

    static func pdfData(sizes: [CGSize]) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: sizes[0])).pdfData { context in
            for size in sizes { context.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:]) }
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

    func testLegacyLayoutMatchesV1() {
        let pages: [PageSpec] = [.template(.blank, color: .white, size: .letter), .template(.blank, color: .white, size: .a4),
                                 PageSpec(background: .image(file: "x"), paperColor: .white, size: CGSize(width: 612, height: 400))]
        XCTAssertEqual(LegacyV1Layout.frames(for: pages.map(\.size)), NotebookLayout(pages: pages).frames)
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
        XCTAssertEqual(cell.cover.style, .cloth)
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
        let (notebooks, _, _) = migrator.readV1()
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
