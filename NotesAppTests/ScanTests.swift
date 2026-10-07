import XCTest
import SwiftData
@testable import NotesApp

/// Scanned sheets become pages, and what is printed on them is read for search.
@MainActor
final class ScanTests: XCTestCase {
    private var container: ModelContainer?

    private func makeStore() throws -> LibraryStore {
        let schema = LibraryIndex.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        return LibraryStore(root: temporaryRoot(self), context: container.mainContext)
    }

    func testAScanIsShrunkAndFillsItsPage() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 4000), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 4000))
        }
        let picture = try DocumentScan.picture(sheet)
        XCTAssertEqual(picture.size, CGSize(width: 1800, height: 2400), "no more than 2,400 px on the long side")
        XCTAssertNotNil(UIImage(data: picture.data))
        let page = DocumentScan.page(file: "sheet.jpg", pictureSize: picture.size)
        XCTAssertEqual(page.background, .image(file: "sheet.jpg"))
        XCTAssertEqual(page.size, CGSize(width: 612, height: 816), "as wide as a letter page, as tall as the paper was")
        XCTAssertThrowsError(try DocumentScan.picture(UIImage()))
    }

    func testScannedSheetsBecomeANotebook() async throws {
        let store = try makeStore()
        let id = try await store.importScan(DocumentScan.samples(), folder: nil)
        let record = try XCTUnwrap(store.record(id))
        XCTAssertEqual(record.pageCount, 2)
        XCTAssertEqual(record.coverStyle, .firstPage, "its first sheet is its cover")
        XCTAssertTrue(record.title.hasPrefix("Scan "))
        let package = NotebookPackage(root: store.root, id: id)
        let manifest = try await package.readManifest().manifest
        for page in manifest.pages {
            let file = try XCTUnwrap(page.background.assetFile)
            XCTAssertTrue(FileManager.default.fileExists(atPath: package.assetURL(file).path(percentEncoded: false)))
        }
        do {
            _ = try await store.importScan([], folder: nil)
            XCTFail("a scan with no sheets makes no notebook")
        } catch {
            XCTAssertEqual(store.notebooks().count, 1)
        }
    }

    func testWhatIsPrintedOnAScanIsSearchable() async throws {
        let root = temporaryRoot(self)
        let package = NotebookPackage(root: root, id: UUID())
        let pages = try await DocumentScan.pages(from: DocumentScan.samples(), in: package)
        let manifest = NotebookManifest(id: package.id, title: "Scan", defaults: PageDefaults(template: .blank, paperColor: .white, pageSize: .letter), pages: pages)
        try await package.create(manifest)
        XCTAssertEqual(HandwritingIndexer.header(for: pages[0]), "#ink:none+img\n")

        // A page stamped before pictures were read is read again.
        try await package.writeText("#ink:none\n", pageID: pages[0].id)
        // Recognition runs at utility priority. Asked for from a test, which runs above that, it is a priority
        // inversion; awaiting the task's value would only raise it to the test's priority, so it answers a continuation.
        let job = HandwritingIndexer.Job(package: package, pages: pages)
        let text = await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) { continuation.resume(returning: await HandwritingIndexer.shared.index(job)) }
        }
        try XCTSkipIf(text.isEmpty, "text recognition isn't available on this simulator")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("quarterly report"), "read as \(text)")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("agenda"))
        let first = await package.readText(pages[0].id)
        XCTAssertEqual(first?.hasPrefix("#ink:none+img\n"), true)
    }
}
