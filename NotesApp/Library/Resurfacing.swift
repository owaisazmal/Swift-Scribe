import Foundation

struct Resurfaced: Hashable, Sendable {
    enum Reason: Hashable, Sendable {
        case yearAgo, sixMonthsAgo, monthAgo
        case started(years: Int)
    }

    let notebookID: UUID
    let pageID: UUID?
    let reason: Reason
    let date: Date

    /// A date counts when adding the interval lands on today, so 29 February comes back on 28 February.
    static func candidate(today: Date, calendar: Calendar, journal: (id: UUID, pages: [NotebookPage])?,
                          notebooks: [(id: UUID, createdAt: Date, isTrashed: Bool)]) -> Resurfaced? {
        let gregorian = DailyJournal.gregorian(calendar)
        let todayKey = DailyJournal.dayKey(for: today, calendar: calendar)
        func lands(_ date: Date, after component: Calendar.Component, _ value: Int) -> Bool {
            gregorian.date(byAdding: component, value: value, to: date).map { DailyJournal.dayKey(for: $0, calendar: calendar) } == todayKey
        }

        if let journal, !(notebooks.first { $0.id == journal.id }?.isTrashed ?? false) {
            let written = journal.pages.compactMap { page -> (page: NotebookPage, date: Date)? in
                guard page.inkHash != nil, let date = page.day.flatMap({ DailyJournal.date(fromKey: $0, calendar: calendar) }) else { return nil }
                return (page, date)
            }
            let intervals: [(Reason, Calendar.Component, Int)] = [(.yearAgo, .year, 1), (.sixMonthsAgo, .month, 6), (.monthAgo, .month, 1)]
            for (reason, component, value) in intervals {
                if let match = written.filter({ lands($0.date, after: component, value) }).max(by: { $0.date < $1.date }) {
                    return Resurfaced(notebookID: journal.id, pageID: match.page.id, reason: reason, date: match.date)
                }
            }
        }

        let todayYear = gregorian.component(.year, from: today)
        let started = notebooks.filter { !$0.isTrashed }.compactMap { notebook -> (id: UUID, years: Int, date: Date)? in
            let years = todayYear - gregorian.component(.year, from: notebook.createdAt)
            guard years >= 1, lands(notebook.createdAt, after: .year, years) else { return nil }
            return (notebook.id, years, notebook.createdAt)
        }
        guard let oldest = started.min(by: { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }) else { return nil }
        return Resurfaced(notebookID: oldest.id, pageID: nil, reason: .started(years: oldest.years), date: oldest.date)
    }

    var headline: String {
        switch reason {
        case .yearAgo, .started(years: 1): String(localized: "One year ago today")
        case .sixMonthsAgo: String(localized: "Six months ago")
        case .monthAgo: String(localized: "A month ago")
        case .started(let years): String(localized: "\(years) years ago today")
        }
    }
}
