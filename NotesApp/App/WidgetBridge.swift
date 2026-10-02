import SwiftUI
import WidgetKit

/// Keeps the widgets' snapshot current. Nothing leaves the device: the snapshot sits in the app's own shared container.
@MainActor
enum WidgetBridge {
    private static var lastWritten: WidgetSnapshot?
    private static var lastCoverKey: String?

    static func snapshot(library: LibraryStore, activity: WritingActivity, now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        var snapshot = WidgetSnapshot()
        if let record = library.lastOpenedNotebook {
            snapshot.notebook = .init(id: record.id, title: record.title.isEmpty ? String(localized: "Untitled") : record.title,
                                      page: min(record.currentPage + 1, max(record.pageCount, 1)), pageCount: record.pageCount, clothHex: record.cloth.hex)
        }
        if activity.isEnabled, let start = calendar.date(byAdding: .day, value: -60, to: now) {
            let first = WidgetSnapshot.dayKey(for: start, calendar: calendar)
            for (key, day) in activity.log.days where key >= first && day.pageCount > 0 { snapshot.pagesByDay[key] = day.pageCount }
        }
        snapshot.hasJournal = library.dailyJournal != nil
        return snapshot
    }

    /// UI-test libraries never reach the widgets.
    static func update(_ app: AppModel) async {
        guard app.phase == .ready, LaunchOptions.value("-storageRoot") == nil, let directory = WidgetSnapshot.directory else { return }
        let snapshot = snapshot(library: app.library, activity: app.activity)
        var coverChanged = false
        if let record = app.library.lastOpenedNotebook {
            let request = record.coverRequest(width: 176, scale: 2, colorScheme: .light, contrast: .standard, root: app.root)
            if request.key != lastCoverKey, let png = await CoverCache.shared.image(for: request)?.pngData() {
                try? png.write(to: directory.appending(path: WidgetSnapshot.coverFile), options: .atomic)
                lastCoverKey = request.key
                coverChanged = true
            }
        }
        guard snapshot != lastWritten || coverChanged else { return }
        do {
            try snapshot.write(to: directory)
            lastWritten = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            return
        }
    }
}
