import SwiftUI
import SwiftData
import os

/// Process-wide state shared by every window: storage and the library index.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Phase: Equatable { case starting, ready }

    let root: StorageRoot
    let container: ModelContainer
    let library: LibraryStore
    let activity: WritingActivity
    let sync: SyncCenter
    private(set) var phase: Phase = .starting
    /// Set by a shortcut; the front window's library takes it and carries it out.
    var pendingAction: AppAction?
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
        activity = WritingActivity(root: root)
        sync = SyncCenter(root: root)
        library.onPermanentlyDeleted = { [activity] in activity.forget(notebooks: $0) }
        sync.busy = { Set(DocumentRegistry.shared.openDocuments.map(\.id)) }
        sync.onLibraryChanged = { [library] _ in await library.reloadFromDisk() }
        library.onIndexSaved = { [sync] in sync.schedule() }
    }

    /// Safe to call from anywhere: later callers wait for the first one to finish.
    func start() async {
        guard !started else {
            while phase != .ready { try? await Task.sleep(for: .milliseconds(50)) }
            return
        }
        started = true
        let interval = signposter.beginInterval("Launch")
        #if DEBUG
        if root.packageIDs().isEmpty {
            if let count = LaunchOptions.value("-seedLibrary").flatMap(Int.init) { await LibrarySeed.write(count: count, root: root) }
            if LaunchOptions.arguments.contains("-seedLongPDF") { await LibrarySeed.writeLongPDF(root: root) }
            if LaunchOptions.arguments.contains("-seedReplay") { await ReplaySeed.write(root: root) }
            if LaunchOptions.arguments.contains("-seedHandwriting") { await HandwritingSeed.write(root: root) }
            await DailyJournal.seedForTests(root: root)
        }
        if LaunchOptions.arguments.contains("-seedActivity") { await WritingActivity.seedForTests(root: root) }
        if LaunchOptions.arguments.contains("-increaseContrast") {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes { scene.traitOverrides.accessibilityContrast = .high }
        }
        #endif
        let root = root
        Task.detached(priority: .utility) { LibraryStore.sweepDeleted(root: root) }
        // An index made by an older build reads every manifest once, for what that build didn't keep.
        let indexSchema = UserDefaults.standard.integer(forKey: SettingsKey.indexSchema)
        await LibraryIndex.refresh(root: root, context: container.mainContext, full: indexWasRecovered || indexSchema < LibraryIndex.schemaNumber)
        if indexSchema != LibraryIndex.schemaNumber { UserDefaults.standard.set(LibraryIndex.schemaNumber, forKey: SettingsKey.indexSchema) }
        await activity.load()
        library.purgeExpiredTrash()
        phase = .ready
        Task {
            await sync.resolve()
            await sync.syncNow()
        }
        Task.detached(priority: .background) { CoverCache.shared.sweepDisk() }
        signposter.endInterval("Launch", interval)
    }

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
            activity.flush()
            await sync.syncNow()
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
}
