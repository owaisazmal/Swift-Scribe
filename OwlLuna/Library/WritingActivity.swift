import UIKit
import Observation
import os

/// This week at a glance: the pages written on each of its seven days.
struct WeekSummary: Hashable {
    struct Day: Hashable {
        let date: Date
        let pages: Int
    }

    private(set) var days: [Day] = []
    private(set) var today = Date.distantPast
    var pageCount: Int { days.reduce(0) { $0 + $1.pages } }
    var dayCount: Int { days.count(where: { $0.pages > 0 }) }

    init() {}

    init(log: ActivityLog, now: Date, calendar: Calendar) {
        today = calendar.startOfDay(for: now)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return }
        days = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: week.start).map { date in
                Day(date: date, pages: log.days[ActivityFile.dayKey(for: date, calendar: calendar)]?.pageCount ?? 0)
            }
        }
    }
}

/// The private writing log. Pages are recorded after their ink is saved, and the file is written off the main thread.
@MainActor
@Observable
final class WritingActivity {
    let root: StorageRoot
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: SettingsKey.keepsWritingHistory) }
    }
    private(set) var log = ActivityLog()
    private(set) var week = WeekSummary()
    private(set) var hasHistory = false

    @ObservationIgnored var writeDelay: Duration = .seconds(3)
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private var lastWrite: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.owais.OwlLuna", category: "activity")

    init(root: StorageRoot, defaults: UserDefaults = .standard) {
        self.root = root
        self.defaults = defaults
        isEnabled = defaults.object(forKey: SettingsKey.keepsWritingHistory) as? Bool ?? true
    }

    func load() async {
        let root = root
        var loaded = await Task.detached(priority: .userInitiated) { () -> ActivityLog in
            var log = ActivityFile.read(root)
            log.compact(before: ActivityFile.compactionCutoff(now: .now, calendar: .current))
            return log
        }.value
        loaded.merge(log)
        log = loaded
        hasHistory = log.hasPages
        refresh()
    }

    /// Recomputes this week, for when the day changes.
    func refresh(now: Date = .now) {
        let summary = WeekSummary(log: log, now: now, calendar: .current)
        if summary != week { week = summary }
    }

    func record(notebook: UUID, pages: [UUID], at date: Date) {
        guard isEnabled, !log.isNewerThanSupported, !pages.isEmpty else { return }
        let key = ActivityFile.dayKey(for: date, calendar: .current)
        var day = log.days[key] ?? DayActivity()
        let known = day.notebooks[notebook] ?? []
        guard log.days[key] == nil || !known.isSuperset(of: pages) else { return }
        day.notebooks[notebook] = known.union(pages)
        log.days[key] = day
        log.opaqueDays[key] = nil
        if !hasHistory { hasHistory = true }
        refresh()
        scheduleWrite()
    }

    /// Permanently deleted notebooks keep only their page counts.
    func forget(notebooks ids: [UUID]) {
        guard !log.isNewerThanSupported else { return }
        let gone = Set(ids)
        var changed = false
        for (key, day) in log.days where day.notebooks.keys.contains(where: gone.contains) {
            var kept = day
            for id in gone { kept.otherPages += kept.notebooks.removeValue(forKey: id)?.count ?? 0 }
            log.days[key] = kept
            changed = true
        }
        if changed { scheduleWrite() }
    }

    func clear() async {
        pendingWrite?.cancel()
        pendingWrite = nil
        log = ActivityLog()
        hasHistory = false
        refresh()
        isDirty = true
        await write().value
    }

    /// Writes any pending change now, with background time in case the app is leaving the foreground.
    @discardableResult
    func flush() -> Task<Void, Never> {
        pendingWrite?.cancel()
        pendingWrite = nil
        guard isDirty else { return lastWrite ?? Task {} }
        var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask(withName: "Save writing history") {
            UIApplication.shared.endBackgroundTask(background)
            background = .invalid
        }
        let written = write()
        return Task {
            await written.value
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
    }

    func days(in interval: DateInterval) -> [String: DayActivity] {
        let calendar = Calendar.current
        let start = ActivityFile.dayKey(for: interval.start, calendar: calendar)
        let end = ActivityFile.dayKey(for: interval.end, calendar: calendar)
        return log.days.filter { $0.key >= start && $0.key < end }
    }

    private func scheduleWrite() {
        isDirty = true
        pendingWrite?.cancel()
        let delay = writeDelay
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            pendingWrite = nil
            write()
        }
    }

    /// Writes are chained so they land in order; a failed one leaves the log dirty for the next.
    @discardableResult
    private func write() -> Task<Void, Never> {
        let snapshot = log, root = root, previous = lastWrite
        isDirty = false
        let task = Task { [weak self] in
            await previous?.value
            guard !snapshot.isNewerThanSupported else { return }
            let failure = await Task.detached(priority: .utility) { () -> String? in
                do { try ActivityFile.write(snapshot, to: root) } catch { return error.localizedDescription }
                return nil
            }.value
            guard let failure, let self else { return }
            isDirty = true
            logger.error("writing history couldn't be saved: \(failure)")
        }
        lastWrite = task
        return task
    }
}
