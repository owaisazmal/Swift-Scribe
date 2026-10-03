import Foundation
import Observation
import os

/// Runs the library's sync with iCloud: finds the container, decides when to sync, and tells the library what changed.
/// Off unless turned on in Settings, and unavailable in a build without the iCloud capability.
@MainActor
@Observable
final class SyncCenter {
    enum Availability: Equatable {
        case checking
        case unavailable(String)
        case available
    }

    private(set) var availability = Availability.checking
    private(set) var isSyncing = false
    private(set) var lastSynced: Date?
    private(set) var lastError: String?
    private(set) var lastReport: SyncReport?
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: SettingsKey.syncsWithICloud)
            if isEnabled { schedule(after: .zero) } else { stopWatching() }
        }
    }

    @ObservationIgnored private let root: StorageRoot
    @ObservationIgnored private var cloud: CloudFolder?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var wantsAnotherPass = false
    @ObservationIgnored private let log = Logger(subsystem: "com.owais.NotesApp", category: "sync")
    /// Called after a sync that changed the library on this device, so the index can be brought up to date.
    @ObservationIgnored var onLibraryChanged: (@MainActor (SyncReport) async -> Void)?
    /// The notebooks open in an editor, which a sync leaves alone.
    @ObservationIgnored var busy: @MainActor () -> Set<UUID> = { [] }

    init(root: StorageRoot) {
        self.root = root
        isEnabled = UserDefaults.standard.bool(forKey: SettingsKey.syncsWithICloud)
    }

    /// Finds where the synced copy lives. A test can stand a plain folder in for iCloud with `-cloudFolder <name>`.
    func resolve() async {
        #if DEBUG
        if let name = LaunchOptions.value("-cloudFolder") {
            let url = URL.applicationSupportDirectory.appending(path: "UITesting/cloud-\(name)", directoryHint: .isDirectory)
            if LaunchOptions.arguments.contains("-resetCloud") { try? FileManager.default.removeItem(at: url) }
            cloud = CloudFolder(url: url)
            availability = .available
            return
        }
        #endif
        guard FileManager.default.ubiquityIdentityToken != nil else {
            availability = .unavailable(String(localized: "iCloud isn't available. Sign in to iCloud and turn on iCloud Drive in Settings; this copy of Swift Scribe also has to be built with the iCloud capability."))
            return
        }
        let container = await Task.detached(priority: .utility) { FileManager.default.url(forUbiquityContainerIdentifier: nil) }.value
        guard let container else {
            availability = .unavailable(String(localized: "This copy of Swift Scribe was built without the iCloud capability, so it can't sync."))
            return
        }
        cloud = CloudFolder(url: container.appending(path: "Sync", directoryHint: .isDirectory), isUbiquitous: true)
        availability = .available
        if isEnabled { startWatching() }
    }

    /// Syncs a little later, so a burst of changes becomes one sync.
    func schedule(after delay: Duration = .seconds(4)) {
        guard isEnabled, availability == .available else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard isEnabled, let cloud else { return }
        guard !isSyncing else { wantsAnotherPass = true; return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            wantsAnotherPass = false
            let root = root, busy = busy()
            do {
                // A second pass uploads the copies a conflict left behind.
                var report = try await Task.detached(priority: .utility) { try await LibrarySync.run(root: root, cloud: cloud, busy: busy) }.value
                if !report.conflictCopies.isEmpty {
                    let again = try await Task.detached(priority: .utility) { try await LibrarySync.run(root: root, cloud: cloud, busy: busy) }.value
                    report.pushed += again.pushed
                }
                lastReport = report
                lastSynced = .now
                lastError = nil
                if report.changedHere { await onLibraryChanged?(report) }
            } catch {
                lastError = error.localizedDescription
                log.error("sync failed: \(error.localizedDescription)")
            }
        } while wantsAnotherPass
        if query == nil, cloud.isUbiquitous { startWatching() }
    }

    /// Notebooks arriving from another device show up as changes to the container's files.
    private func startWatching() {
        guard query == nil, cloud?.isUbiquitous == true else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, "manifest.json")
        for name in [Notification.Name.NSMetadataQueryDidUpdate, .NSMetadataQueryDidFinishGathering] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
        query.start()
        self.query = query
    }

    private func stopWatching() {
        pending?.cancel()
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}

extension SyncReport {
    /// "3 notebooks sent, 1 received." for the Settings row.
    var summary: String {
        var parts: [String] = []
        let deletions = removedHere.count + removedThere.count
        if pushed.count > 0 { parts.append(String(localized: "\(pushed.count) notebooks sent")) }
        if pulled.count > 0 { parts.append(String(localized: "\(pulled.count) notebooks received")) }
        if deletions > 0 { parts.append(String(localized: "\(deletions) deletions carried over")) }
        if conflictCopies.count > 0 { parts.append(String(localized: "\(conflictCopies.count) conflicted copies kept")) }
        if waiting.count > 0 { parts.append(String(localized: "\(waiting.count) notebooks waiting until they're closed")) }
        return parts.isEmpty ? String(localized: "Everything is up to date") : parts.joined(separator: ", ")
    }
}
