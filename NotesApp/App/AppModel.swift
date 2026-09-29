import SwiftUI
import SwiftData
import os

/// Process-wide state shared by every window: storage, the library index, and launch-time migration.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Phase: Equatable { case starting, migrating, ready }

    let root: StorageRoot
    let container: ModelContainer
    let library: LibraryStore
    private(set) var phase: Phase = .starting
    private(set) var migrationReport: MigrationReport?
    var showsMigrationProblem = false
    @ObservationIgnored private let indexWasRecovered: Bool
    @ObservationIgnored private var started = false
    @ObservationIgnored private let signposter = OSSignposter(subsystem: "com.owais.NotesApp", category: "app")

    init(root: StorageRoot = LaunchOptions.storageRoot) {
        ScribeFonts.register()
        self.root = root
        let (container, recovered) = LibraryIndex.makeContainer(root: root)
        self.container = container
        indexWasRecovered = recovered
        library = LibraryStore(root: root, context: container.mainContext)
    }

    func start() async {
        guard !started else { return }
        started = true
        let interval = signposter.beginInterval("Launch")
        if LaunchOptions.seedV1Fixture { await LaunchOptions.seedV1(into: root) }
        #if DEBUG
        if let count = LaunchOptions.value("-seedLibrary").flatMap(Int.init) { await LibrarySeed.write(count: count, root: root) }
        if LaunchOptions.arguments.contains("-seedLongPDF") { await LibrarySeed.writeLongPDF(root: root) }
        #endif
        let root = root
        Task.detached(priority: .utility) { LibraryStore.sweepDeleted(root: root) }
        let migrator = V1Migrator(root: root)
        if migrator.isNeeded {
            phase = .migrating
            let report = await Task.detached(priority: .userInitiated) { await migrator.run() }.value
            migrationReport = report
            showsMigrationProblem = !report.isComplete
        }
        await LibraryIndex.refresh(root: root, context: container.mainContext,
                                   full: indexWasRecovered || !(migrationReport?.migrated.isEmpty ?? true))
        library.purgeExpiredTrash()
        phase = .ready
        Task.detached(priority: .background) { CoverCache.shared.sweepDisk() }
        signposter.endInterval("Launch", interval)
    }

    /// What went wrong moving v1 notebooks, in words for the alert and Settings. Nil when nothing did.
    var migrationProblem: String? {
        guard let report = migrationReport, !report.isComplete else { return nil }
        if let storeError = report.storeError {
            return String(localized: "Swift Scribe couldn't read your notebook library (\(storeError)), so nothing was moved yet.")
        }
        let titles = report.failed.keys.map { report.titles[$0] ?? String(localized: "Untitled") }.sorted()
        return titles.count == 1
            ? String(localized: "“\(titles[0])” couldn't be moved to the new format yet.")
            : String(localized: "\(titles.count) notebooks couldn't be moved to the new format yet: \(titles.formatted(.list(type: .and))).")
    }

    /// Finishes pending writes for every open notebook, with background time if the app is leaving the foreground.
    func flushOpenDocuments() {
        let documents = DocumentRegistry.shared.openDocuments.filter(\.hasUnsavedChanges)
        guard !documents.isEmpty else { return }
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Save notebooks") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        Task {
            for document in documents { await document.flush() }
            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        }
    }
}

enum LaunchOptions {
    static let arguments = ProcessInfo.processInfo.arguments

    static func value(_ key: String) -> String? {
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// `-storageRoot <name>` keeps UI tests in their own folder; `-resetStorage` empties it first.
    static let storageRoot: StorageRoot = {
        guard let name = value("-storageRoot") else { return .live }
        let url = URL.applicationSupportDirectory.appending(path: "UITesting/\(name)", directoryHint: .isDirectory)
        if arguments.contains("-resetStorage") { try? FileManager.default.removeItem(at: url) }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return StorageRoot(url: url)
    }()

    static var seedV1Fixture: Bool { arguments.contains("-seedV1Fixture") }

    /// Writes a small v1 library (store plus drawings) so the migration can be exercised end to end in UI tests.
    static func seedV1(into root: StorageRoot) async {
        guard !FileManager.default.fileExists(atPath: root.v1Store.path(percentEncoded: false)),
              root.packageIDs().isEmpty else { return }
        await V1Seed.write(root: root)
    }
}
