import Foundation
import PencilKit

enum DailyJournal {
    /// "yyyy-MM-dd" on the Gregorian calendar, in the calendar's time zone.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        ActivityFile.dayKey(for: date, calendar: calendar)
    }

    /// Noon on the key's day, so the date survives daylight-saving changes.
    static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        let gregorian = gregorian(calendar)
        guard let date = gregorian.date(from: components), gregorian.component(.day, from: date) == parts[2] else { return nil }
        return date
    }

    static func gregorian(_ calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    static func spokenDay(_ key: String) -> String? {
        date(fromKey: key)?.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func canvasLabel(page number: Int, day: String?) -> String {
        guard let spoken = day.flatMap(spokenDay) else { return String(localized: "Page \(number), handwriting") }
        return String(localized: "Page \(number), \(spoken), handwriting")
    }

    /// Matches the paper of the last template page.
    static func makeTodayPage(after pages: [NotebookPage], defaults: PageDefaults, key: String, id: UUID = UUID()) -> NotebookPage {
        var page = defaults.newPage()
        page.id = id
        if let anchor = pages.last(where: { $0.template != nil }) {
            page.size = anchor.size
            page.paperColor = anchor.paperColor
            page.background = anchor.background
        }
        page.day = key
        return page
    }

    /// Idempotent. An empty last page from an earlier day is re-dated rather than adding another.
    /// The page that becomes today's is printed with `agenda`, the day's events, if there are any.
    static func dateToday(_ key: String, newPageID: UUID, agenda: [AgendaEvent] = [], in manifest: inout NotebookManifest) {
        guard !manifest.pages.contains(where: { $0.day == key }) else { return }
        if let last = manifest.pages.last, last.template != nil, last.inkHash == nil,
           last.day.map({ $0 < key }) ?? (manifest.pages.count == 1) {
            manifest.pages[manifest.pages.count - 1].day = key
        } else {
            manifest.pages.append(makeTodayPage(after: manifest.pages, defaults: manifest.defaults, key: key, id: newPageID))
        }
        print(agenda, on: &manifest.pages[manifest.pages.count - 1])
        manifest.modifiedAt = .now
    }

    /// Events printed for an earlier day are taken off a page that is re-dated. A page holding anything else is left as it is.
    static func print(_ agenda: [AgendaEvent], on page: inout NotebookPage) {
        let items = page.hasItems ? page.items : []
        guard items.allSatisfy(\.isPrintedAgenda) else { return }
        let printed = Agenda.item(for: agenda, on: page).map { [$0] } ?? []
        if !items.isEmpty || !printed.isEmpty { page.items = printed }
    }

    @MainActor
    static func ensureTodayPage(in document: NotebookDocument, now: Date = .now, calendar: Calendar = .current, agenda: [AgendaEvent] = []) -> UUID? {
        let key = dayKey(for: now, calendar: calendar)
        if let page = document.pages.last(where: { $0.day == key }) { return page.id }
        guard !document.isReadOnly else { return nil }
        var page = makeTodayPage(after: document.pages, defaults: document.manifest.defaults, key: key)
        print(agenda, on: &page)
        document.insertPages([page], at: document.pages.count, actionName: String(localized: "Add Today's Page"))
        return page.id
    }

    #if DEBUG
    /// `-seedJournal`: written pages from a year ago, a month ago and yesterday.
    static func seedForTests(root: StorageRoot) async {
        let defaults = UserDefaults.standard
        if LaunchOptions.arguments.contains("-resetStorage") {
            for key in [SettingsKey.dailyJournalID, SettingsKey.dailyJournalPromptHidden, SettingsKey.showsOnThisDay, SettingsKey.onThisDayHiddenDay] {
                defaults.removeObject(forKey: key)
            }
        }
        guard LaunchOptions.arguments.contains("-seedJournal") else { return }
        let calendar = Calendar.current, now = Date.now
        let days = [(Calendar.Component.year, -1), (.month, -1), (.day, -1)].compactMap { calendar.date(byAdding: $0.0, value: $0.1, to: now) }
        let id = UUID()
        let paper = PageDefaults(template: .dotted, paperColor: .ivory, pageSize: .letter)
        let pages = days.map { day -> NotebookPage in
            var page = paper.newPage()
            page.day = dayKey(for: day, calendar: calendar)
            return page
        }
        var manifest = NotebookManifest(id: id, title: String(localized: "Journal"), createdAt: days[0],
                                        cover: NotebookStarter.journal.spec(for: id), defaults: paper, pages: pages)
        manifest.modifiedAt = days[days.count - 1]
        manifest.library.currentPage = pages.count - 1
        let package = NotebookPackage(root: root, id: id)
        do {
            try await package.create(manifest)
            let ink = Dictionary(uniqueKeysWithValues: pages.enumerated().map { ($1.id, handwriting(seed: $0 + 1, lines: 5 - $0)) })
            _ = try await package.write(SaveSnapshot(manifest: manifest, ink: ink))
            defaults.set(id.uuidString, forKey: SettingsKey.dailyJournalID)
        } catch {
            return
        }
    }

    private static func handwriting(seed: Int, lines: Int) -> PKDrawing {
        var state = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15
        func random() -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(state >> 40) / CGFloat(1 << 24)
        }
        let ink = PKInk(.pen, color: UIColor(red: 0.12, green: 0.16, blue: 0.3, alpha: 1))
        var strokes: [PKStroke] = []
        for line in 0..<lines {
            let baseline = 128 + CGFloat(line) * 40
            var x: CGFloat = 92
            let end = 520 - random() * (line == lines - 1 ? 260 : 60)
            while x < end {
                let length = 30 + random() * 70
                var points: [PKStrokePoint] = []
                let steps = Int(length / 2.2)
                for step in 0...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let loop = sin(t * length / 3.2) * (5 + random() * 2)
                    let point = CGPoint(x: x + t * length + cos(t * length / 3.2) * 2.5, y: baseline - 6 + loop - (random() < 0.08 ? 7 : 0))
                    points.append(PKStrokePoint(location: point, timeOffset: TimeInterval(step) * 0.01, size: CGSize(width: 2.2, height: 2.2),
                                                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
                }
                strokes.append(PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: .now)))
                x += length + 10 + random() * 8
            }
        }
        return PKDrawing(strokes: strokes)
    }
    #endif
}
