import UIKit
import SwiftData
import CoreSpotlight
import UniformTypeIdentifiers
import os

/// What Spotlight is told about a notebook: its title, how long it is, and the words written, typed or printed in it.
struct SpotlightEntry: Equatable, Sendable {
    let id: UUID
    let title: String
    let pageCount: Int
    let modifiedAt: Date
    var coverKey = ""

    /// Changes when the title, the pages or the cover do. The words are stamped separately, by how many there are.
    var stamp: String { "\(title)|\(pageCount)|\(Int(modifiedAt.timeIntervalSince1970))|\(coverKey)" }

    func signature(textBytes: Int) -> String { "\(stamp)|\(textBytes)" }
}

/// Keeps the system's search index in step with the library, so a notebook can be found from the Home Screen by its
/// title or by what is in it. The index stays on the iPad. Locked and deleted notebooks are never in it.
@MainActor
final class SpotlightIndexer: NSObject, CSSearchableIndexDelegate {
    nonisolated static let domain = "notebooks"
    nonisolated static let textLimit = 30_000

    private let container: ModelContainer
    private let isLive: Bool
    private let file = URL.cachesDirectory.appending(path: "spotlight.json")
    private var known: [String: String] = [:]
    private var isLoaded = false
    private var checksEverything = true
    private var changed: Set<UUID> = []
    private var pending: Task<Void, Never>?
    private let log = Logger(subsystem: "com.owais.NotesApp", category: "spotlight")

    /// UI-test libraries never reach Spotlight.
    init(container: ModelContainer, isLive: Bool = LaunchOptions.value("-storageRoot") == nil) {
        self.container = container
        self.isLive = isLive && CSSearchableIndex.isIndexingAvailable()
        super.init()
        if self.isLive { CSSearchableIndex.default().indexDelegate = self }
    }

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: SettingsKey.spotlight) as? Bool ?? true }

    /// The words in a notebook were read again.
    func noteTextChanged(_ id: UUID) {
        changed.insert(id)
    }

    func schedule(_ library: LibraryStore, after delay: Duration = .seconds(3)) {
        guard isLive else { return }
        pending?.cancel()
        pending = Task { [weak self, weak library] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let library else { return }
            await self.update(library)
        }
    }

    // MARK: What to index

    static func entries(_ records: [NotebookRecord]) -> [SpotlightEntry] {
        records.filter { !$0.isTrashed && !$0.isLocked }.map {
            SpotlightEntry(id: $0.id, title: $0.title.isEmpty ? String(localized: "Untitled") : $0.title, pageCount: $0.pageCount,
                           modifiedAt: $0.modifiedAt, coverKey: "\($0.coverStyleRaw)-\($0.clothRaw)-\($0.inksRaw)-\($0.coverSeed)-\($0.firstPageThumbKey ?? "")")
        }
    }

    /// The notebooks whose words are worth reading again: new ones, ones whose stamp moved, and ones just re-read.
    static func candidates(_ entries: [SpotlightEntry], known: [String: String], changed: Set<UUID>, everything: Bool) -> [SpotlightEntry] {
        entries.filter { entry in
            everything || changed.contains(entry.id) || known[entry.id.uuidString].map { !$0.hasPrefix(entry.stamp + "|") } ?? true
        }
    }

    /// What Spotlight still holds that the library no longer offers it.
    static func removals(_ entries: [SpotlightEntry], known: [String: String]) -> [String] {
        let offered = Set(entries.map(\.id.uuidString))
        return known.keys.filter { !offered.contains($0) }.sorted()
    }

    static func attributes(for entry: SpotlightEntry, text: String, thumbnail: Data?) -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = entry.title
        attributes.contentDescription = entry.pageCount == 1 ? String(localized: "Notebook, 1 page") : String(localized: "Notebook, \(entry.pageCount) pages")
        attributes.textContent = String(text.prefix(textLimit))
        attributes.contentModificationDate = entry.modifiedAt
        attributes.thumbnailData = thumbnail
        return attributes
    }

    // MARK: Keeping in step

    func update(_ library: LibraryStore) async {
        guard isLive else { return }
        load()
        guard Self.isEnabled else { return await removeAll() }
        let records = library.notebooks()
        let entries = Self.entries(records)
        let index = CSSearchableIndex.default()

        let gone = Self.removals(entries, known: known)
        if !gone.isEmpty {
            do {
                try await index.deleteSearchableItems(withIdentifiers: gone)
                for id in gone { known[id] = nil }
            } catch {
                log.error("removing from Spotlight failed: \(error.localizedDescription)")
            }
        }

        let candidates = Self.candidates(entries, known: known, changed: changed, everything: checksEverything)
        checksEverything = false
        changed = []
        let texts = await Self.texts(for: candidates.map(\.id), in: container)
        var items: [CSSearchableItem] = []
        var signatures: [String: String] = [:]
        for entry in candidates {
            let text = texts[entry.id] ?? ""
            let signature = entry.signature(textBytes: text.utf8.count)
            guard known[entry.id.uuidString] != signature else { continue }
            var thumbnail: Data?
            if let record = records.first(where: { $0.id == entry.id }) {
                let request = record.coverRequest(width: 120, scale: 2, colorScheme: .light, contrast: .standard, root: library.root)
                thumbnail = await CoverCache.shared.image(for: request)?.jpegData(compressionQuality: 0.8)
            }
            let item = CSSearchableItem(uniqueIdentifier: entry.id.uuidString, domainIdentifier: Self.domain,
                                        attributeSet: Self.attributes(for: entry, text: text, thumbnail: thumbnail))
            item.expirationDate = .distantFuture
            items.append(item)
            signatures[entry.id.uuidString] = signature
        }
        if !items.isEmpty {
            do {
                try await index.indexSearchableItems(items)
                known.merge(signatures) { _, new in new }
            } catch {
                log.error("indexing for Spotlight failed: \(error.localizedDescription)")
            }
        }
        if !gone.isEmpty || !items.isEmpty { save() }
    }

    func removeAll() async {
        guard isLive else { return }
        load()
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domain])
        known = [:]
        checksEverything = true
        save()
    }

    /// Read on a background context, so a library full of PDF text stays off the main thread.
    private nonisolated static func texts(for ids: [UUID], in container: ModelContainer) async -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        return await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            var result: [UUID: String] = [:]
            for id in ids {
                let rows = try? context.fetch(FetchDescriptor<NotebookSearchText>(predicate: #Predicate { $0.notebookID == id }))
                if let text = rows?.first?.text { result[id] = String(text.prefix(textLimit)) }
            }
            return result
        }.value
    }

    private func load() {
        guard !isLoaded else { return }
        isLoaded = true
        known = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    private func save() {
        try? JSONEncoder().encode(known).write(to: file, options: .atomic)
    }

    // MARK: CSSearchableIndexDelegate

    /// The system lost its index and asks for everything again.
    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
        Task { @MainActor in
            self.forget()
            self.schedule(AppModel.shared.library, after: .zero)
        }
        acknowledgementHandler()
    }

    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String],
                                     acknowledgementHandler: @escaping () -> Void) {
        Task { @MainActor in
            self.forget(identifiers)
            self.schedule(AppModel.shared.library, after: .zero)
        }
        acknowledgementHandler()
    }

    private func forget(_ identifiers: [String]? = nil) {
        load()
        if let identifiers { for id in identifiers { known[id] = nil } } else { known = [:] }
        checksEverything = true
    }
}

extension AppAction {
    /// A notebook picked from Spotlight's results.
    init?(spotlight activity: NSUserActivity) {
        guard activity.activityType == CSSearchableItemActionType,
              let id = (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
        self = .open(id)
    }
}
