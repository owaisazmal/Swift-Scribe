import XCTest
import PencilKit
import SwiftData
@testable import NotesApp

@MainActor
final class DailyJournalTests: XCTestCase {
    private var container: ModelContainer?
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func makeStore() throws -> LibraryStore {
        let schema = LibraryIndex.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        let saved = UserDefaults.standard.object(forKey: SettingsKey.dailyJournalID)
        addTeardownBlock { UserDefaults.standard.set(saved, forKey: SettingsKey.dailyJournalID) }
        return LibraryStore(root: temporaryRoot(self), context: container.mainContext)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    private func manifest(_ store: LibraryStore, _ id: UUID) async throws -> NotebookManifest {
        try await NotebookPackage(root: store.root, id: id).readManifest().manifest
    }

    private func write(ink pageID: UUID, in store: LibraryStore, notebook id: UUID) async throws {
        let package = NotebookPackage(root: store.root, id: id)
        let current = try await package.readManifest().manifest
        let receipt = try await package.write(SaveSnapshot(manifest: current, ink: [pageID: PKDrawing(strokes: [stroke(from: CGPoint(x: 80, y: 200), to: CGPoint(x: 300, y: 210))])]))
        store.index(receipt.manifest)
    }

    func testDayKeyFollowsTheCalendarsTimeZone() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-29T20:00:00Z"))
        var auckland = Calendar(identifier: .gregorian)
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        var losAngeles = Calendar(identifier: .buddhist)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(DailyJournal.dayKey(for: instant, calendar: auckland), "2026-09-30")
        XCTAssertEqual(DailyJournal.dayKey(for: instant, calendar: losAngeles), "2026-09-29", "always Gregorian")
        let parsed = try XCTUnwrap(DailyJournal.date(fromKey: "2026-09-30", calendar: auckland))
        XCTAssertEqual(DailyJournal.dayKey(for: parsed, calendar: auckland), "2026-09-30")
        XCTAssertNil(DailyJournal.date(fromKey: "2026-02-30"))
        XCTAssertNil(DailyJournal.date(fromKey: "someday"))
    }

    func testAClosedJournalGetsOneDatedPagePerDay() async throws {
        let store = try makeStore()
        let id = try await store.createDailyJournal(now: day(2026, 9, 28), calendar: calendar)
        XCTAssertEqual(store.dailyJournal?.id, id)
        let first = try await manifest(store, id)
        XCTAssertEqual(first.pages.map(\.day), ["2026-09-28"])
        XCTAssertEqual(first.defaults.template, .dotted)
        XCTAssertEqual(first.cover.cloth, .moss)

        let sameDay = await store.prepareTodayPage(id, now: day(2026, 9, 28), calendar: calendar)
        XCTAssertEqual(sameDay, first.pages[0].id)
        try await write(ink: first.pages[0].id, in: store, notebook: id)

        let next = await store.prepareTodayPage(id, now: day(2026, 9, 29), calendar: calendar)
        let again = await store.prepareTodayPage(id, now: day(2026, 9, 29), calendar: calendar)
        var pages = try await manifest(store, id).pages
        XCTAssertEqual(pages.map(\.day), ["2026-09-28", "2026-09-29"], "a page with ink is never re-dated")
        XCTAssertEqual(next, pages[1].id)
        XCTAssertEqual(again, next)
        XCTAssertEqual(pages[1].template, .dotted)
        XCTAssertEqual(pages[1].paperColor, .ivory)
        XCTAssertEqual(store.record(id)?.pageCount, 2)

        let later = await store.prepareTodayPage(id, now: day(2026, 10, 2), calendar: calendar)
        pages = try await manifest(store, id).pages
        XCTAssertEqual(pages.map(\.day), ["2026-09-28", "2026-10-02"], "the empty page from an earlier day is re-dated")
        XCTAssertEqual(later, next)
    }

    func testTheOpenDocumentPathIsUndoable() async throws {
        let store = try makeStore()
        let id = try await store.createDailyJournal(now: day(2026, 9, 28), calendar: calendar)
        let document = try await DocumentRegistry.shared.open(id, root: store.root, scene: nil) { _ in }
        addTeardownBlock { @MainActor in DocumentRegistry.shared.unregister(id, document: document) }

        document.undoManager.groupsByEvent = false
        document.undoManager.beginUndoGrouping()
        let page = await store.prepareTodayPage(id, now: day(2026, 9, 29), calendar: calendar)
        document.undoManager.endUndoGrouping()
        XCTAssertEqual(document.pages.count, 2)
        XCTAssertEqual(document.pages.last?.id, page)
        XCTAssertEqual(document.pages.last?.day, "2026-09-29")
        XCTAssertEqual(document.undoManager.undoActionName, "Add Today's Page")
        let again = await store.prepareTodayPage(id, now: day(2026, 9, 29), calendar: calendar)
        XCTAssertEqual(again, page)
        XCTAssertEqual(document.pages.count, 2)

        document.undoManager.undo()
        XCTAssertEqual(document.pages.count, 1)
        XCTAssertEqual(document.pages[0].day, "2026-09-28")
    }

    func testTheDateIsKeptByTheCodecDroppedByDuplicatesAndPartOfTheAppearance() throws {
        let plain = NotebookPage.template(.dotted, color: .ivory, size: .letter)
        var dated = plain
        let undatedKey = plain.appearanceKey
        dated.day = "2026-09-29"
        XCTAssertEqual(plain.appearanceKey, undatedKey)
        XCTAssertNotEqual(dated.appearanceKey, undatedKey)
        XCTAssertNil(dated.duplicated().day)
        XCTAssertEqual(dated.duplicated().appearanceKey, undatedKey)

        let manifest = NotebookManifest(title: "Journal", defaults: PageDefaults(template: .dotted, paperColor: .ivory, pageSize: .letter), pages: [dated, plain])
        let decoded = try ManifestCodec.decode(ManifestCodec.encode(manifest), fallbackID: UUID()).manifest
        XCTAssertEqual(decoded.pages.map(\.day), ["2026-09-29", nil])
        XCTAssertEqual(decoded.pages[0].appearanceKey, dated.appearanceKey)
    }

    func testTheMastheadIsPrintedOnThePaperButNotRecognised() throws {
        let assets = FileManager.default.temporaryDirectory
        var dated = NotebookPage.template(.blank, color: .white, size: .letter)
        dated.day = "2026-09-29"
        let undated = NotebookPage.template(.blank, color: .white, size: .letter)
        func inkedPixels(_ image: UIImage) -> Int { Self.darkPixels(in: image, rows: 40..<100) }
        XCTAssertGreaterThan(inkedPixels(PageRenderer.image(of: dated, ink: PKDrawing(), assets: assets, width: 800)), 200)
        XCTAssertEqual(inkedPixels(PageRenderer.image(of: undated, ink: PKDrawing(), assets: assets, width: 800)), 0)
        XCTAssertEqual(inkedPixels(PageRenderer.image(of: dated, ink: PKDrawing(), assets: assets, width: 800, includeBackground: false)), 0)

        var weekly = dated
        weekly.background = .template(.weekPlanner)
        var weeklyUndated = weekly
        weeklyUndated.day = nil
        XCTAssertEqual(PageRenderer.image(of: weekly, ink: PKDrawing(), assets: assets, width: 800).pngData(),
                       PageRenderer.image(of: weeklyUndated, ink: PKDrawing(), assets: assets, width: 800).pngData(),
                       "no masthead where the paper fills the head of the page")
    }

    private static func darkPixels(in image: UIImage, rows: Range<Int>) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for y in rows where y < height {
            for x in 0..<width where pixels[(y * width + x) * 4] < 200 { count += 1 }
        }
        return count
    }
}
