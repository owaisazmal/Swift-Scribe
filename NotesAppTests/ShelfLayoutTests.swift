import XCTest
@testable import NotesApp

final class ShelfLayoutTests: XCTestCase {
    func testShelvesFillTheWidth() {
        let portraitWithSidebar = ShelfMetrics.fit(width: 450)
        XCTAssertEqual(portraitWithSidebar.columns, 2)
        XCTAssertGreaterThanOrEqual(portraitWithSidebar.coverWidth, 200)
        XCTAssertEqual(ShelfMetrics.fit(width: 770).columns, 4)
        XCTAssertEqual(ShelfMetrics.fit(width: 810).columns, 4)
        XCTAssertEqual(ShelfMetrics.fit(width: 250).columns, 1)
        XCTAssertLessThanOrEqual(ShelfMetrics.fit(width: 1400).coverWidth, 232)
        for width in stride(from: CGFloat(300), through: 2000, by: 1) {
            let metrics = ShelfMetrics.fit(width: width)
            XCTAssertGreaterThanOrEqual(metrics.coverWidth, 116, "width \(width)")
            XCTAssertLessThanOrEqual(metrics.coverWidth, 232, "width \(width)")
            let used = metrics.coverWidth * CGFloat(metrics.columns) + metrics.gap * CGFloat(metrics.columns - 1)
            XCTAssertLessThan(width - used, CGFloat(metrics.columns), "width \(width) leaves a gutter")
        }
    }

    func testRenderWidthBuckets() {
        XCTAssertEqual(ShelfMetrics.fit(width: 770).renderWidth, CoverWidth.shelf)
        XCTAssertEqual(ShelfMetrics.fit(width: 450).renderWidth, CoverWidth.spread)
    }

    func testChunking() {
        XCTAssertEqual([Int]().chunked(into: 3), [])
        XCTAssertEqual([1, 2, 3, 4, 5, 6].chunked(into: 3), [[1, 2, 3], [4, 5, 6]])
        XCTAssertEqual([1, 2, 3, 4, 5].chunked(into: 2), [[1, 2], [3, 4], [5]])
        XCTAssertEqual([1, 2].chunked(into: 0), [[1, 2]])
    }

    func testRecencyBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2
        func date(_ day: Int, _ month: Int = 9, hour: Int = 12) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
        }
        let now = try date(24)
        XCTAssertEqual(ShelfGrouping.bucket(for: try date(24, hour: 1), now: now, calendar: calendar), "today")
        XCTAssertEqual(ShelfGrouping.bucket(for: try date(23, hour: 23), now: now, calendar: calendar), "yesterday")
        XCTAssertEqual(ShelfGrouping.bucket(for: try date(21), now: now, calendar: calendar), "week")
        XCTAssertEqual(ShelfGrouping.bucket(for: try date(3), now: now, calendar: calendar), "month")
        XCTAssertEqual(ShelfGrouping.bucket(for: try date(15, 6), now: now, calendar: calendar), "2026-6")
        let monday = try date(21)
        XCTAssertEqual(ShelfGrouping.bucket(for: try date(20), now: monday, calendar: calendar), "yesterday", "yesterday even across a week boundary")
    }
}
