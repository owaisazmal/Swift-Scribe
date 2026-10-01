import XCTest
@testable import NotesApp

final class ActivityStatsTests: XCTestCase {
    private func calendar(_ zone: String = "UTC", firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func log(_ days: [String]) -> ActivityLog {
        var log = ActivityLog()
        for key in days { log.days[key] = DayActivity(notebooks: [UUID(): [UUID()]]) }
        return log
    }

    func testSeptember2026StartsAfterTheRightNumberOfBlanks() {
        for (firstWeekday, leading) in [(1, 2), (2, 1)] {
            let calendar = calendar(firstWeekday: firstWeekday)
            let cells = ActivityStats.monthGrid(containing: day(2026, 9, 15, in: calendar), calendar: calendar)
            XCTAssertEqual(cells.count, 35)
            XCTAssertEqual(cells.prefix { $0 == nil }.count, leading)
            XCTAssertEqual(cells.compactMap { $0 }.count, 30)
            XCTAssertEqual(cells[leading].map { calendar.component(.day, from: $0) }, 1)
        }
    }

    func testAMonthWithAClockChangeHasOneCellPerDay() {
        let newYork = calendar("America/New_York")
        for month in [day(2026, 11, 10, in: newYork), day(2027, 3, 10, in: newYork)] {
            let dates = ActivityStats.monthGrid(containing: month, calendar: newYork).compactMap { $0 }
            let length = newYork.range(of: .day, in: .month, for: month)!.count
            XCTAssertEqual(dates.map { newYork.component(.day, from: $0) }, Array(1...length))
            XCTAssertEqual(Set(dates.map { ActivityFile.dayKey(for: $0, calendar: newYork) }).count, length)
        }
    }

    func testLongestRunCrossesMonthBoundaries() {
        let utc = calendar()
        let written = log(["2026-09-10", "2026-09-11", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-05"])
        XCTAssertEqual(ActivityStats.longestRun(in: written, calendar: utc), 4)
        let september = utc.dateInterval(of: .month, for: day(2026, 9, 1, in: utc))
        XCTAssertEqual(ActivityStats.longestRun(in: written, calendar: utc, within: september), 2)
        XCTAssertEqual(ActivityStats.longestRun(in: ActivityLog(), calendar: utc), 0)
    }

    func testTotalsCountPagesFromForgottenNotebooks() {
        let utc = calendar()
        var written = log(["2026-09-29"])
        written.days["2026-09-29"]?.otherPages = 3
        written.days["2026-09-30"] = DayActivity(otherPages: 2)
        written.days["2025-12-31"] = DayActivity(otherPages: 4)
        XCTAssertTrue(ActivityStats.totals(for: "2026-09-29", in: written) == (pages: 4, notebooks: 1))
        XCTAssertTrue(ActivityStats.totals(for: "2026-09-30", in: written) == (pages: 2, notebooks: 0))
        XCTAssertTrue(ActivityStats.totals(for: "2026-10-01", in: written) == (pages: 0, notebooks: 0))
        XCTAssertTrue(ActivityStats.yearTotals(year: 2026, in: written, calendar: utc) == (pages: 6, days: 2))
        XCTAssertTrue(ActivityStats.yearTotals(year: 2025, in: written, calendar: utc) == (pages: 4, days: 1))
    }
}
