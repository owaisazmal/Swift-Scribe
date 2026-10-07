import XCTest
import PencilKit
@testable import OwlLuna

private func calendar(_ zone: String = "UTC", firstWeekday: Int = 1, identifier: Calendar.Identifier = .gregorian) -> Calendar {
    var calendar = Calendar(identifier: identifier)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.firstWeekday = firstWeekday
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, in calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

final class ActivityFileTests: XCTestCase {
    func testRoundTripKeepsUnknownKeysAndUnreadableDays() throws {
        let notebook = UUID(), page = UUID()
        let raw = """
        {"version": 1, "future": {"a": 1},
         "days": {"2026-09-29": {"notebooks": {"\(notebook.uuidString)": ["\(page.uuidString)"]}, "otherPages": 2, "mood": "calm"},
                  "2026-09-30": {"notebooks": "garbage"},
                  "someday": {"otherPages": 1}}}
        """
        let log = try XCTUnwrap(ActivityFile.decode(Data(raw.utf8)))
        XCTAssertEqual(log.days["2026-09-29"]?.notebooks, [notebook: [page]])
        XCTAssertEqual(log.days["2026-09-29"]?.pageCount, 3)
        XCTAssertEqual(log.days["2026-09-29"]?.extra["mood"], .string("calm"))
        XCTAssertEqual(Set(log.opaqueDays.keys), ["2026-09-30", "someday"])
        XCTAssertNotNil(log.extra["future"])

        let encoded = try ActivityFile.encode(log)
        XCTAssertEqual(ActivityFile.decode(encoded), log)
        let object = try XCTUnwrap(JSONValue.parse(encoded).objectValue)
        XCTAssertEqual(object["days"]?.objectValue?["2026-09-30"], .object(["notebooks": .string("garbage")]))
        XCTAssertEqual(object["future"], .object(["a": .number(1)]))
    }

    func testOldDaysAreCompactedToCounts() throws {
        let root = temporaryRoot(self)
        let calendar = calendar()
        let now = date(2026, 9, 30, in: calendar)
        let old = ActivityFile.dayKey(for: calendar.date(byAdding: .day, value: -401, to: now)!, calendar: calendar)
        let recent = ActivityFile.dayKey(for: calendar.date(byAdding: .day, value: -399, to: now)!, calendar: calendar)
        var log = ActivityLog()
        log.days[old] = DayActivity(notebooks: [UUID(): [UUID(), UUID()]], otherPages: 1)
        log.days[recent] = DayActivity(notebooks: [UUID(): [UUID()]])
        try ActivityFile.write(log, to: root, now: now, calendar: calendar)

        let read = ActivityFile.read(root)
        XCTAssertEqual(read.days[old], DayActivity(otherPages: 3))
        XCTAssertEqual(read.days[recent]?.notebooks.count, 1)
    }

    func testAnUnreadableFileIsQuarantined() throws {
        let root = temporaryRoot(self)
        try FileManager.default.createDirectory(at: root.library, withIntermediateDirectories: true)
        try Data("[1, 2]".utf8).write(to: root.activityFile)

        XCTAssertEqual(ActivityFile.read(root), ActivityLog())
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.activityFile.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.activityFile.appendingPathExtension("corrupt").path(percentEncoded: false)))
    }

    func testDayKeysFollowTheCalendarsTimeZoneButStayGregorian() {
        let utc = calendar()
        let late = date(2026, 9, 29, hour: 23, in: utc)
        XCTAssertEqual(ActivityFile.dayKey(for: late, calendar: utc), "2026-09-29")
        XCTAssertEqual(ActivityFile.dayKey(for: late, calendar: calendar("Asia/Tokyo")), "2026-09-30")
        XCTAssertEqual(ActivityFile.dayKey(for: late, calendar: calendar(identifier: .buddhist)), "2026-09-29")
        XCTAssertEqual(ActivityFile.date(forKey: "2026-09-29", calendar: utc), date(2026, 9, 29, hour: 0, in: utc))
        XCTAssertNil(ActivityFile.date(forKey: "2026-02-30", calendar: utc))
        XCTAssertNil(ActivityFile.date(forKey: "someday", calendar: utc))
    }
}

final class WeekSummaryTests: XCTestCase {
    private func log(_ keys: [String: Int]) -> ActivityLog {
        var log = ActivityLog()
        for (key, pages) in keys { log.days[key] = DayActivity(notebooks: [UUID(): Set((0..<pages).map { _ in UUID() })]) }
        return log
    }

    func testTheWeekStartsOnTheCalendarsFirstWeekday() {
        let written = log(["2026-09-27": 2, "2026-09-28": 1, "2026-10-03": 4, "2026-10-04": 5])
        let sunday = calendar(firstWeekday: 1)
        let fromSunday = WeekSummary(log: written, now: date(2026, 9, 30, in: sunday), calendar: sunday)
        XCTAssertEqual(fromSunday.days.map { ActivityFile.dayKey(for: $0.date, calendar: sunday) }.first, "2026-09-27")
        XCTAssertEqual(fromSunday.days.map(\.pages), [2, 1, 0, 0, 0, 0, 4])
        XCTAssertEqual(fromSunday.pageCount, 7)
        XCTAssertEqual(fromSunday.dayCount, 3)

        let monday = calendar(firstWeekday: 2)
        let fromMonday = WeekSummary(log: written, now: date(2026, 9, 30, in: monday), calendar: monday)
        XCTAssertEqual(fromMonday.days.map(\.pages), [1, 0, 0, 0, 0, 4, 5])
        XCTAssertEqual(fromMonday.pageCount, 10)
        XCTAssertEqual(fromMonday.today, monday.startOfDay(for: date(2026, 9, 30, in: monday)))
    }

    func testTheWeekTheClocksGoBackStillHasSevenDays() {
        let newYork = calendar("America/New_York", firstWeekday: 1)
        let summary = WeekSummary(log: log(["2026-11-01": 1, "2026-11-07": 2]), now: date(2026, 11, 3, in: newYork), calendar: newYork)
        XCTAssertEqual(summary.days.map { ActivityFile.dayKey(for: $0.date, calendar: newYork) },
                       ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07"])
        XCTAssertEqual(summary.days.map(\.pages), [1, 0, 0, 0, 0, 0, 2])
    }
}

@MainActor
final class WritingActivityTests: XCTestCase {
    private func makeActivity(_ root: StorageRoot) -> WritingActivity {
        let suite = "WritingActivityTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let activity = WritingActivity(root: root, defaults: defaults)
        activity.writeDelay = .milliseconds(10)
        return activity
    }

    func testRecordForgetAndClear() async throws {
        let root = temporaryRoot(self)
        let activity = makeActivity(root)
        await activity.load()
        XCTAssertFalse(activity.hasHistory)
        let kept = UUID(), deleted = UUID()
        let pages = [UUID(), UUID()]
        let today = ActivityFile.dayKey(for: .now, calendar: .current)
        activity.record(notebook: kept, pages: [pages[0]], at: .now)
        activity.record(notebook: kept, pages: pages, at: .now)
        activity.record(notebook: deleted, pages: [UUID()], at: .now)
        XCTAssertTrue(activity.hasHistory)
        XCTAssertEqual(activity.log.days[today]?.pageCount, 3)
        XCTAssertEqual(activity.week.pageCount, 3)
        XCTAssertEqual(activity.week.dayCount, 1)
        await activity.flush().value
        XCTAssertEqual(ActivityFile.read(root).days[today]?.notebooks[kept], Set(pages))

        activity.forget(notebooks: [deleted])
        await activity.flush().value
        let forgotten = ActivityFile.read(root).days[today]
        XCTAssertNil(forgotten?.notebooks[deleted])
        XCTAssertEqual(forgotten?.otherPages, 1)
        XCTAssertEqual(forgotten?.pageCount, 3)

        let reloaded = makeActivity(root)
        await reloaded.load()
        XCTAssertEqual(reloaded.week.pageCount, 3)

        await activity.clear()
        XCTAssertFalse(activity.hasHistory)
        XCTAssertEqual(activity.week.pageCount, 0)
        XCTAssertTrue(ActivityFile.read(root).days.isEmpty)
    }

    func testNothingIsRecordedWhileHistoryIsOff() async {
        let activity = makeActivity(temporaryRoot(self))
        await activity.load()
        activity.isEnabled = false
        activity.record(notebook: UUID(), pages: [UUID()], at: .now)
        XCTAssertFalse(activity.hasHistory)
        XCTAssertTrue(activity.log.days.isEmpty)
    }

    func testSavingInkReportsOnlyThePagesLeftHoldingInk() async throws {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Doc", defaults: PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter),
                                        pages: (0..<3).map { _ in .template(.narrowRuled, color: .white, size: .letter) })
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        document.saveDelay = .seconds(30)
        let a = document.pages[0].id, b = document.pages[1].id
        _ = await document.ink(a)
        _ = await document.ink(b)
        document.canvasDidChangeInk(b, to: PKDrawing(strokes: [dot(at: CGPoint(x: 80, y: 80))]))
        _ = await document.save()

        var reports: [([UUID], Date)] = []
        document.onInkSaved = { reports.append(($0, $1)) }
        let before = Date.now
        document.canvasDidChangeInk(a, to: PKDrawing(strokes: [dot(at: CGPoint(x: 80, y: 80))]))
        document.canvasDidChangeInk(b, to: PKDrawing())
        let after = Date.now
        _ = await document.save()
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.0, [a])
        XCTAssertTrue((before...after).contains(try XCTUnwrap(reports.first?.1)))

        reports.removeAll()
        document.rename("Renamed")
        _ = await document.save()
        XCTAssertTrue(reports.isEmpty)
    }
}
