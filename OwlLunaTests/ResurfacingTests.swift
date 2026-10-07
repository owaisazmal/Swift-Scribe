import XCTest
@testable import OwlLuna

final class ResurfacingTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    private let journalID = UUID()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func page(_ key: String, written: Bool = true) -> NotebookPage {
        var page = NotebookPage.template(.dotted, color: .ivory, size: .letter)
        page.day = key
        page.inkHash = written ? "hash-\(key)" : nil
        return page
    }

    private func candidate(today: Date, pages: [NotebookPage] = [], notebooks: [(id: UUID, createdAt: Date, isTrashed: Bool)] = []) -> Resurfaced? {
        Resurfaced.candidate(today: today, calendar: calendar, journal: pages.isEmpty ? nil : (journalID, pages), notebooks: notebooks)
    }

    func testJournalPagesComeFirstYearThenSixMonthsThenAMonth() {
        let today = date(2026, 9, 29)
        let year = page("2025-09-29"), half = page("2026-03-29"), month = page("2026-08-29")
        let started = (id: UUID(), createdAt: date(2024, 9, 29), isTrashed: false)
        XCTAssertEqual(candidate(today: today, pages: [year, half, month], notebooks: [started])?.reason, .yearAgo)
        XCTAssertEqual(candidate(today: today, pages: [year, half, month])?.pageID, year.id)
        XCTAssertEqual(candidate(today: today, pages: [half, month])?.reason, .sixMonthsAgo)
        XCTAssertEqual(candidate(today: today, pages: [month])?.reason, .monthAgo)
        XCTAssertEqual(candidate(today: today, pages: [month])?.notebookID, journalID)
        let anniversary = candidate(today: today, pages: [page("2026-09-01")], notebooks: [started])
        XCTAssertEqual(anniversary?.reason, .started(years: 2))
        XCTAssertEqual(anniversary?.notebookID, started.id)
        XCTAssertNil(anniversary?.pageID, "an anniversary opens at the saved page")
    }

    func testOnlyTheExactDateMatchesAnd29FebruaryComesBackOn28February() {
        XCTAssertNil(candidate(today: date(2026, 9, 29), pages: [page("2025-09-28"), page("2025-09-30"), page("2026-08-28")]))
        XCTAssertNil(candidate(today: date(2026, 9, 29), pages: [page("2025-09-29", written: false)]), "a page never written on stays put")
        XCTAssertEqual(candidate(today: date(2025, 2, 28), pages: [page("2024-02-29")])?.reason, .yearAgo)
        XCTAssertNil(candidate(today: date(2025, 3, 1), pages: [page("2024-02-29")]))
        let leap = (id: UUID(), createdAt: date(2024, 2, 29, hour: 23), isTrashed: false)
        XCTAssertEqual(candidate(today: date(2025, 2, 28), notebooks: [leap])?.reason, .started(years: 1))
        XCTAssertEqual(candidate(today: date(2028, 2, 29), notebooks: [leap])?.reason, .started(years: 4))
        XCTAssertNil(candidate(today: date(2028, 2, 28), notebooks: [leap]), "leap years keep the real day")
    }

    func testTrashedNotebooksAreSkipped() {
        let today = date(2026, 9, 29)
        let trashed = (id: UUID(), createdAt: date(2025, 9, 29), isTrashed: true)
        XCTAssertNil(candidate(today: today, notebooks: [trashed]))
        XCTAssertNil(candidate(today: today, pages: [page("2025-09-29")], notebooks: [(journalID, date(2025, 1, 1), true)]))
    }

    func testNothingMatchesWithoutAnEarlierDay() {
        let today = date(2026, 9, 29)
        XCTAssertNil(candidate(today: today))
        XCTAssertNil(candidate(today: today, notebooks: [(UUID(), date(2026, 9, 29, hour: 7), false), (UUID(), date(2026, 8, 29), false)]),
                     "anniversaries start at one year")
        XCTAssertEqual(candidate(today: today, notebooks: [(UUID(), date(2025, 9, 29, hour: 22), false)])?.reason, .started(years: 1))
    }
}
