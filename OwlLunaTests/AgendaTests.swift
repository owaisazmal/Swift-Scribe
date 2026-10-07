import XCTest
@testable import OwlLuna

/// Today's events on a page: how they read, where they are printed, and which pages get them.
final class AgendaTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let paper = PageDefaults(template: .dotted, paperColor: .ivory, pageSize: .letter)
    private let day = Date(timeIntervalSince1970: 1_790_899_200)

    private var events: [AgendaEvent] {
        [AgendaEvent(title: "Lab group", start: day.addingTimeInterval(13.5 * 3600)),
         AgendaEvent(title: "Library books due", start: day, isAllDay: true),
         AgendaEvent(title: "  ", start: day.addingTimeInterval(3600)),
         AgendaEvent(title: "Lecture: Cell Biology ", start: day.addingTimeInterval(9 * 3600))]
    }

    private func time(_ hours: Double) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = utc
        return day.addingTimeInterval(hours * 3600).formatted(style)
    }

    func testEventsReadAllDayFirstThenByTheClock() {
        XCTAssertEqual(Agenda.ordered(events).map(\.title), ["Library books due", "Lecture: Cell Biology ", "Lab group"], "an event with no title is left out")
        XCTAssertEqual(Agenda.text(for: events, timeZone: utc),
                       "All day  Library books due\n\(time(9))  Lecture: Cell Biology\n\(time(13.5))  Lab group")
        XCTAssertEqual(Agenda.text(for: events, heading: "Friday", timeZone: utc).components(separatedBy: "\n").first, "Friday")

        let many = (0..<13).map { AgendaEvent(title: "Meeting \($0)", start: day.addingTimeInterval(Double($0) * 1800)) }
        let lines = Agenda.text(for: many, timeZone: utc).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 11)
        XCTAssertEqual(lines.last, "+ 3 more", "past ten, the rest are counted")
    }

    func testTheBoxSitsBelowTheDateAgainstTheMargin() throws {
        var page = paper.newPage()
        page.day = "2026-10-02"
        let item = try XCTUnwrap(Agenda.item(for: events, on: page))
        let frame = CGRect(x: item.center.x - item.size.width / 2, y: item.center.y - item.size.height / 2, width: item.size.width, height: item.size.height)
        XCTAssertTrue(CGRect(origin: .zero, size: page.size).contains(frame))
        XCTAssertGreaterThan(frame.minX, page.size.width / 2, "on the right-hand side")
        XCTAssertGreaterThan(frame.minY, 92 * page.size.width / 800, "clear of the printed date")
        XCTAssertLessThan(frame.minY, page.size.height / 4)
        XCTAssertEqual(item.text?.fontSize, 11)
        XCTAssertTrue(item.isPrintedAgenda)
        XCTAssertNil(Agenda.item(for: [], on: page), "a day with nothing in it prints nothing")
    }

    func testOnlyANewDaysPageIsPrinted() {
        var manifest = NotebookManifest(title: "Journal", defaults: paper, pages: [paper.newPage()])
        manifest.pages[0].day = "2026-10-01"
        manifest.pages[0].inkHash = "written"

        DailyJournal.dateToday("2026-10-02", newPageID: UUID(), agenda: events, in: &manifest)
        XCTAssertEqual(manifest.pages.count, 2)
        XCTAssertEqual(manifest.pages[1].items.count, 1)
        XCTAssertTrue(manifest.pages[1].items[0].text?.string.contains("Lecture: Cell Biology") == true)
        XCTAssertFalse(manifest.pages[0].hasItems, "yesterday's page is left alone")

        let printed = manifest.pages[1].items
        DailyJournal.dateToday("2026-10-02", newPageID: UUID(), agenda: [AgendaEvent(title: "Something new", start: day)], in: &manifest)
        XCTAssertEqual(manifest.pages[1].items, printed, "a page that is already today's isn't printed twice")

        // Nothing was written on the 2nd, so its page becomes the 3rd's: the 2nd's events come off it.
        DailyJournal.dateToday("2026-10-03", newPageID: UUID(), agenda: [AgendaEvent(title: "Seminar", start: day)], in: &manifest)
        XCTAssertEqual(manifest.pages.count, 2)
        XCTAssertEqual(manifest.pages[1].day, "2026-10-03")
        XCTAssertEqual(manifest.pages[1].items.count, 1)
        XCTAssertTrue(manifest.pages[1].items[0].text?.string.hasSuffix("Seminar") == true)

        DailyJournal.dateToday("2026-10-04", newPageID: UUID(), in: &manifest)
        XCTAssertFalse(manifest.pages[1].hasItems, "and with nothing on the next day, the page is blank again")

        manifest.pages[1].items = [PageItem(content: .sticker("star"), center: CGPoint(x: 100, y: 100), size: CGSize(width: 40, height: 40))]
        DailyJournal.dateToday("2026-10-05", newPageID: UUID(), agenda: events, in: &manifest)
        XCTAssertEqual(manifest.pages[1].items.count, 1, "a page with something placed on it by hand keeps just that")
        XCTAssertNil(manifest.pages[1].items[0].text)
    }
}
