import Foundation

/// What the app hands its widgets, written to the shared container when the library changes.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Notebook: Codable, Equatable, Sendable {
        var id: UUID
        var title: String
        var page: Int
        var pageCount: Int
        var clothHex: UInt32
    }

    /// The notebook last written in.
    var notebook: Notebook?
    /// Pages written on each recent day, keyed "yyyy-MM-dd".
    var pagesByDay: [String: Int] = [:]
    var hasJournal = false

    static let appGroup = "group.com.owais.NotesApp"
    static let coverFile = "widget-cover.png"

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func read(from directory: URL? = WidgetSnapshot.directory) -> WidgetSnapshot? {
        guard let directory, let data = try? Data(contentsOf: directory.appending(path: "widget.json")) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: directory.appending(path: "widget.json"), options: .atomic)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    struct Day: Equatable, Sendable {
        let date: Date
        let pages: Int
        let isToday: Bool
    }

    /// The seven days of the week containing `now`, starting on the calendar's first weekday.
    func week(containing now: Date, calendar: Calendar = .current) -> [Day] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: week.start).map { date in
                Day(date: date, pages: pagesByDay[Self.dayKey(for: date, calendar: calendar)] ?? 0, isToday: calendar.isDate(date, inSameDayAs: now))
            }
        }
    }

    /// Days in a row with writing, ending today, or yesterday when today is still blank.
    func run(endingAt now: Date, calendar: Calendar = .current) -> Int {
        var length = 0
        var day = now
        if (pagesByDay[Self.dayKey(for: day, calendar: calendar)] ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        while (pagesByDay[Self.dayKey(for: day, calendar: calendar)] ?? 0) > 0, let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            length += 1
            day = previous
        }
        return length
    }
}
