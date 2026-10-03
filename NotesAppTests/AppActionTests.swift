import XCTest
import SwiftData
@testable import NotesApp

/// Widget links and shortcuts, and the snapshot the widgets read.
@MainActor
final class AppActionTests: XCTestCase {
    private var container: ModelContainer?

    private func makeStore() throws -> LibraryStore {
        let schema = LibraryIndex.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        return LibraryStore(root: temporaryRoot(self), context: container.mainContext)
    }

    private func makeNotebook(_ title: String, in store: LibraryStore, opened: Date?, pages: Int = 3, currentPage: Int = 0) async throws -> UUID {
        let paper = PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter)
        var manifest = NotebookManifest(title: title, cover: CoverSpec(style: .cloth, cloth: .moss, inks: (.teal, .pink), seed: 1), defaults: paper,
                                        pages: (0..<pages).map { _ in paper.newPage() })
        manifest.library.lastOpenedAt = opened
        manifest.library.currentPage = currentPage
        try await NotebookPackage(root: store.root, id: manifest.id).create(manifest)
        store.index(manifest)
        return manifest.id
    }

    func testLinksBecomeActions() throws {
        let id = UUID()
        XCTAssertEqual(AppAction(url: URL(string: "swiftscribe://today")!), .today)
        XCTAssertEqual(AppAction(url: URL(string: "swiftscribe://quicknote")!), .quickNote)
        XCTAssertEqual(AppAction(url: URL(string: "swiftscribe://continue")!), .continueWriting)
        XCTAssertEqual(AppAction(url: URL(string: "swiftscribe://notebook/\(id.uuidString)")!), .open(id))
        let page = UUID()
        XCTAssertEqual(AppAction(url: try XCTUnwrap(AppAction.url(forNotebook: id, page: page))), .open(id, page: page), "a link in an exported PDF comes back to its page")
        XCTAssertEqual(AppAction(url: try XCTUnwrap(AppAction.url(forNotebook: id))), .open(id))
        XCTAssertNil(AppAction(url: URL(string: "swiftscribe://notebook/not-an-id")!))
        XCTAssertNil(AppAction(url: URL(string: "swiftscribe://delete-everything")!))
        XCTAssertNil(AppAction(url: URL(string: "https://today")!))
    }

    func testTheSnapshotNamesTheNotebookLastOpenedAndRecentDaysOnly() async throws {
        let store = try makeStore()
        let now = Date.now, calendar = Calendar.current
        _ = try await makeNotebook("Older", in: store, opened: now.addingTimeInterval(-86_400))
        let latest = try await makeNotebook("Cell Biology", in: store, opened: now, pages: 12, currentPage: 4)
        let binned = try await makeNotebook("Binned", in: store, opened: now.addingTimeInterval(60))
        store.moveToTrash([try XCTUnwrap(store.record(binned))])
        _ = try await makeNotebook("Never opened", in: store, opened: nil)

        let suite = "widget-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let activity = WritingActivity(root: store.root, defaults: defaults)
        activity.record(notebook: latest, pages: [UUID(), UUID()], at: now)
        activity.record(notebook: latest, pages: [UUID()], at: try XCTUnwrap(calendar.date(byAdding: .day, value: -100, to: now)))

        let snapshot = WidgetBridge.snapshot(library: store, activity: activity, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.notebook, .init(id: latest, title: "Cell Biology", page: 5, pageCount: 12, clothHex: ClothColor.moss.hex))
        XCTAssertEqual(snapshot.pagesByDay, [WidgetSnapshot.dayKey(for: now, calendar: calendar): 2], "a day from months ago isn't sent")
        XCTAssertFalse(snapshot.hasJournal)
        XCTAssertEqual(store.notebooks().count, 3)

        activity.isEnabled = false
        XCTAssertTrue(WidgetBridge.snapshot(library: store, activity: activity, now: now, calendar: calendar).pagesByDay.isEmpty,
                      "with writing history off, the widgets get no days")
    }

    func testTheSnapshotRoundTripsAndCountsTheWeekAndTheRun() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        calendar.firstWeekday = 1
        let thursday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9)))
        XCTAssertEqual(WidgetSnapshot.dayKey(for: thursday, calendar: calendar), "2026-10-01")
        XCTAssertEqual(WidgetSnapshot.dayKey(for: thursday, calendar: calendar), ActivityFile.dayKey(for: thursday, calendar: calendar))

        var snapshot = WidgetSnapshot()
        snapshot.pagesByDay = ["2026-09-28": 3, "2026-09-29": 1, "2026-09-30": 2]
        let week = snapshot.week(containing: thursday, calendar: calendar)
        XCTAssertEqual(week.map(\.pages), [0, 3, 1, 2, 0, 0, 0])
        XCTAssertEqual(week.map(\.isToday), [false, false, false, false, true, false, false])
        XCTAssertEqual(snapshot.run(endingAt: thursday, calendar: calendar), 3, "today is still blank, so the run ends yesterday")
        snapshot.pagesByDay["2026-10-01"] = 1
        XCTAssertEqual(snapshot.run(endingAt: thursday, calendar: calendar), 4)
        snapshot.pagesByDay["2026-09-29"] = nil
        XCTAssertEqual(snapshot.run(endingAt: thursday, calendar: calendar), 2)
        XCTAssertEqual(WidgetSnapshot().run(endingAt: thursday, calendar: calendar), 0)

        let directory = temporaryRoot(self).url
        try snapshot.write(to: directory)
        XCTAssertEqual(WidgetSnapshot.read(from: directory), snapshot)
        XCTAssertNil(WidgetSnapshot.read(from: directory.appending(path: "missing")))
    }

    func testAWindowRemembersWhatItHasOpenUntilItIsGone() {
        let scene = "test-\(UUID().uuidString)", other = "test-\(UUID().uuidString)"
        let notebook = UUID(), beside = UUID()
        XCTAssertNil(WindowMemory.remembered(in: scene), "a window never seen falls back to what iPadOS saved for it")
        WindowMemory.remember(notebook, beside: beside, in: scene)
        WindowMemory.remember(nil, beside: beside, in: other)
        XCTAssertEqual(WindowMemory.remembered(in: scene)?.notebook, notebook)
        XCTAssertEqual(WindowMemory.remembered(in: scene)?.beside, beside)
        let closed = WindowMemory.remembered(in: other)
        XCTAssertNotNil(closed, "a window whose notebook was closed says so, so an older saved state can't reopen one")
        XCTAssertNil(closed?.notebook)
        XCTAssertNil(closed?.beside)
        WindowMemory.keep(only: [other])
        XCTAssertNil(WindowMemory.remembered(in: scene))
        WindowMemory.keep(only: Set(UIApplication.shared.openSessions.map(\.persistentIdentifier)))
        XCTAssertNil(WindowMemory.remembered(in: other))
    }
}
