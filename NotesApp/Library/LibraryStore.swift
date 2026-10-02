import Foundation
import CoreGraphics
import SwiftData
import Observation
import os

enum ImportError: LocalizedError {
    case unreadable, locked, empty

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "The file couldn't be read.")
        case .locked: String(localized: "This PDF is password protected. Unlock it in Files or Preview, then import it again.")
        case .empty: String(localized: "The file doesn't contain any pages.")
        }
    }
}

/// Library-level changes. Every change is written to the notebook's manifest (through its open document
/// if it's being edited, so the two never race) and mirrored in the SwiftData index, which is saved explicitly.
@MainActor
@Observable
final class LibraryStore {
    let root: StorageRoot
    @ObservationIgnored let context: ModelContext
    private(set) var lastError: String?
    /// Bumped on every index save, so views holding derived results (search) know to refresh them.
    private(set) var indexVersion = 0
    /// Bumped only when something search matches on changes (titles, recognised text, notebooks added), so an
    /// active search isn't redone on every autosave.
    private(set) var searchVersion = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.owais.NotesApp", category: "library")
    @ObservationIgnored private var changesInFlight: [UUID: [UUID: @Sendable (inout NotebookManifest) -> Void]] = [:]
    @ObservationIgnored private var folderWrite: Task<Void, Never>?
    /// Called with the notebooks a permanent delete actually removed.
    @ObservationIgnored var onPermanentlyDeleted: (([UUID]) -> Void)?
    /// Called after every change to the index made on this device, so a sync can follow it.
    @ObservationIgnored var onIndexSaved: (() -> Void)?

    init(root: StorageRoot, context: ModelContext) {
        self.root = root
        self.context = context
    }

    func record(_ id: UUID) -> NotebookRecord? {
        try? context.fetch(FetchDescriptor<NotebookRecord>(predicate: #Predicate { $0.id == id })).first
    }

    func saveIndex() {
        do { try context.save() } catch { log.error("index save failed: \(error.localizedDescription)") }
        indexVersion &+= 1
        onIndexSaved?()
    }

    func clearError() { lastError = nil }

    // MARK: Creating

    @discardableResult
    func createNotebook(id: UUID = UUID(), title: String, cover: CoverSpec, defaults: PageDefaults, folder: FolderRecord?) async throws -> UUID {
        var manifest = NotebookManifest(id: id, title: title, cover: cover, defaults: defaults, pages: [defaults.newPage()])
        manifest.library.folderID = folder?.id
        manifest.library.lastOpenedAt = .now
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        index(manifest)
        return manifest.id
    }

    /// A notebook with the default paper from Settings, dated rather than named, created without the sheet.
    func createQuickNote(folder: FolderRecord?) async throws -> UUID {
        let defaults = UserDefaults.standard
        let template = defaults.string(forKey: SettingsKey.defaultTemplate).flatMap(PaperTemplate.init(rawValue:)) ?? .narrowRuled
        let color = defaults.string(forKey: SettingsKey.defaultPaperColor).flatMap(PaperColor.init(rawValue:)) ?? .white
        let size = defaults.string(forKey: SettingsKey.defaultPageSize).flatMap(PageSize.init(rawValue:)) ?? .letter
        let id = UUID()
        return try await createNotebook(id: id, title: String(localized: "Note \(Date.now.formatted(date: .abbreviated, time: .shortened))"),
                                        cover: .defaultCloth(for: id), defaults: PageDefaults(template: template, paperColor: color, pageSize: size),
                                        folder: folder)
    }

    @discardableResult
    func importPDF(from url: URL, folder: FolderRecord?) async throws -> UUID {
        let folderID = folder?.id
        let id = UUID()
        let package = NotebookPackage(root: root, id: id)
        do {
            let file = try await package.importAsset(from: url, ext: "pdf")
            let assetURL = package.assetURL(file)
            let pages = try await Task.detached(priority: .userInitiated) { try PDFImport.pages(at: assetURL, file: file) }.value
            var cover = CoverSpec.defaultCloth(for: id)
            cover.style = .firstPage
            var manifest = NotebookManifest(id: id, title: url.deletingPathExtension().lastPathComponent, cover: cover,
                                            defaults: PageDefaults(template: .blank, paperColor: .white, pageSize: .letter), pages: pages)
            manifest.library.folderID = folderID
            try await package.create(manifest)
            index(manifest)
            indexHandwriting(package: package, pages: pages)
            return id
        } catch {
            try? FileManager.default.removeItem(at: package.url)
            throw error
        }
    }

    @discardableResult
    func duplicate(_ record: NotebookRecord) async throws -> UUID {
        let sourceID = record.id, searchText = searchText(for: record.id)
        if let open = DocumentRegistry.shared.document(for: sourceID) { await open.flush() }
        let newID = UUID()
        let source = root.package(sourceID), destination = root.package(newID)
        try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: source, to: destination) }.value
        let package = NotebookPackage(root: root, id: newID)
        do {
            let copy = try await package.updateManifest { manifest in
                manifest.id = newID
                manifest.title = String(localized: "\(manifest.title) Copy")
                manifest.createdAt = .now
                manifest.modifiedAt = .now
                manifest.library.isFavorite = false
                manifest.library.lastOpenedAt = nil
            }
            index(copy)
            updateSearchText(searchText, for: newID)
            return newID
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    // MARK: Changing

    func rename(_ record: NotebookRecord, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !record.isReadOnly, !trimmed.isEmpty, trimmed != record.title else { return }
        record.title = trimmed
        searchVersion &+= 1
        saveIndex()
        if let document = DocumentRegistry.shared.document(for: record.id) {
            document.rename(trimmed)
        } else {
            update(record.id) { $0.title = trimmed; $0.modifiedAt = .now }
        }
    }

    func setCover(_ cover: CoverSpec, for record: NotebookRecord) {
        guard !record.isReadOnly else { return }
        record.coverStyleRaw = cover.styleRaw
        record.clothRaw = cover.clothRaw
        record.inksRaw = cover.inksRaw.joined(separator: ",")
        record.coverSeed = Int(cover.seed)
        saveIndex()
        if let document = DocumentRegistry.shared.document(for: record.id) {
            document.updateCover(cover)
        } else {
            update(record.id) { $0.cover = cover }
        }
    }

    func setFavorite(_ favorite: Bool, for records: [NotebookRecord]) {
        changeLibraryState(records, index: { $0.isFavorite = favorite }) { $0.isFavorite = favorite }
    }

    func moveToTrash(_ records: [NotebookRecord]) {
        let now = Date.now
        changeLibraryState(records, index: { $0.deletedAt = now }) { $0.deletedAt = now }
    }

    func restore(_ records: [NotebookRecord]) {
        changeLibraryState(records, index: { $0.deletedAt = nil }) { $0.deletedAt = nil }
    }

    func move(_ records: [NotebookRecord], to folder: FolderRecord?) {
        let folderID = folder?.id
        changeLibraryState(records, index: { $0.folder = folder }) { $0.folderID = folderID }
    }

    /// Permanently removes notebooks from the library. Only offered for notebooks already in Recently Deleted.
    /// Each package is renamed into `Deleting/` (one cheap move on the main thread) and removed in the background;
    /// anything left there is swept at the next launch.
    func deletePermanently(_ records: [NotebookRecord]) {
        let registry = DocumentRegistry.shared
        var moved: [URL] = []
        var deleted: [UUID] = []
        for record in records where record.isTrashed && registry.document(for: record.id) == nil && !registry.isOpening(record.id) {
            let tombstone = root.deleting.appending(path: "\(record.id.uuidString)-\(UUID().uuidString)", directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: root.deleting, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: root.package(record.id), to: tombstone)
                moved.append(tombstone)
                deleted.append(record.id)
                if let row = LibraryIndex.searchRow(for: record.id, in: context) { context.delete(row) }
                context.delete(record)
            } catch {
                lastError = String(localized: "“\(record.title)” couldn't be deleted: \(error.localizedDescription)")
            }
        }
        saveIndex()
        guard !moved.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in moved { try? FileManager.default.removeItem(at: url) }
        }
        onPermanentlyDeleted?(deleted)
    }

    /// Finishes deletes interrupted by the app quitting.
    nonisolated static func sweepDeleted(root: StorageRoot) {
        try? FileManager.default.removeItem(at: root.deleting)
    }

    func purgeExpiredTrash(olderThan days: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let expired = ((try? context.fetch(FetchDescriptor<NotebookRecord>(predicate: #Predicate { $0.deletedAt != nil }))) ?? [])
            .filter { ($0.deletedAt ?? .now) < cutoff }
        if !expired.isEmpty { deletePermanently(expired) }
    }

    private func changeLibraryState(_ records: [NotebookRecord], index: (NotebookRecord) -> Void,
                                    manifest change: @escaping @Sendable (inout LibraryState) -> Void) {
        for record in records where !record.isReadOnly {
            index(record)
            if let document = DocumentRegistry.shared.document(for: record.id) {
                document.updateLibraryState(change)
            } else {
                update(record.id) { change(&$0.library) }
            }
        }
        saveIndex()
    }

    /// Read-modify-write of a closed notebook's manifest. A document that starts opening meanwhile gets the
    /// change applied again (see `reapplyChangesInFlight`); if the write fails, the index is re-read from the file.
    private func update(_ id: UUID, _ change: @escaping @Sendable (inout NotebookManifest) -> Void) {
        let package = NotebookPackage(root: root, id: id)
        let token = UUID()
        changesInFlight[id, default: [:]][token] = change
        Task {
            do {
                _ = try await package.updateManifest(change)
            } catch {
                lastError = String(localized: "A change couldn't be saved: \(error.localizedDescription)")
                log.error("manifest update failed for \(id): \(error.localizedDescription)")
                if let manifest = try? await package.readManifest().manifest { index(manifest) }
            }
            changesInFlight[id]?[token] = nil
            if changesInFlight[id]?.isEmpty == true { changesInFlight[id] = nil }
        }
    }

    func reapplyChangesInFlight(to document: NotebookDocument) {
        guard let changes = changesInFlight[document.id] else { return }
        for change in changes.values { document.applyLibraryChange(change) }
    }

    // MARK: Folders

    private func allFolders() -> [FolderRecord] {
        (try? context.fetch(FetchDescriptor<FolderRecord>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    }

    func folderTree() -> FolderTree { FolderTree(folders: allFolders()) }

    /// Numbers every folder in sidebar order, parents before their children, so a plain sort by index gives that order.
    private func renumberFolders(_ folders: [FolderRecord], tree: FolderTree) {
        let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (index, id) in tree.ordered.enumerated() where byID[id]?.sortIndex != index { byID[id]?.sortIndex = index }
    }

    private func saveFolders() {
        let folders = allFolders()
        renumberFolders(folders, tree: FolderTree(folders: folders))
        saveIndex()
        writeFolders()
    }

    @discardableResult
    func createFolder(name: String, cloth: ClothColor, parent: FolderRecord? = nil) -> FolderRecord? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folders = allFolders()
        guard !trimmed.isEmpty, FolderTree(folders: folders).canAddFolder(inside: parent?.id) else { return nil }
        let entry = FolderEntry(id: UUID(), name: trimmed, clothRaw: cloth.rawValue, createdAt: .now,
                                sortIndex: (folders.map(\.sortIndex).max() ?? -1) + 1, parentID: parent?.id)
        let record = FolderRecord(id: entry.id)
        record.apply(entry)
        context.insert(record)
        saveFolders()
        return record
    }

    func renameFolder(_ folder: FolderRecord, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        saveIndex()
        writeFolders()
    }

    func setCloth(_ cloth: ClothColor, for folder: FolderRecord) {
        folder.clothRaw = cloth.rawValue
        saveIndex()
        writeFolders()
    }

    /// Puts a folder inside another, or back at the top level, after the folders already there.
    @discardableResult
    func moveFolder(_ folder: FolderRecord, into parent: FolderRecord?) -> Bool {
        let folders = allFolders()
        guard folder.parentID != parent?.id, FolderTree(folders: folders).canMove(folder.id, into: parent?.id) else { return false }
        folder.parentID = parent?.id
        folder.sortIndex = (folders.map(\.sortIndex).max() ?? -1) + 1
        saveFolders()
        return true
    }

    /// Reorders the sidebar's rows. A folder keeps its parent: it takes the place among its own siblings that the drop gives it.
    func moveFolders(_ rows: [FolderRecord], from source: IndexSet, to destination: Int) {
        var ordered = rows
        ordered.move(fromOffsets: source, toOffset: destination)
        let moved = Set(source.map { rows[$0].id })
        var tree = FolderTree(folders: allFolders())
        for group in Set(rows.filter { moved.contains($0.id) }.map { tree.parent(of: $0.id) }) {
            let siblings = ordered.filter { tree.parent(of: $0.id) == group }
            for (index, sibling) in siblings.enumerated() { sibling.sortIndex = index }
            tree = FolderTree(folders: allFolders())
        }
        saveFolders()
    }

    /// Sorts every level by name.
    func sortFoldersByName(_ folders: [FolderRecord]) {
        let tree = FolderTree(folders: folders)
        for group in Set(folders.map { tree.parent(of: $0.id) }) {
            let siblings = folders.filter { tree.parent(of: $0.id) == group }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            for (index, sibling) in siblings.enumerated() { sibling.sortIndex = index }
        }
        saveFolders()
    }

    /// Deleting a folder keeps what was in it: its notebooks and its folders move up to the folder it sat in.
    func deleteFolder(_ folder: FolderRecord) {
        let folders = allFolders()
        let parent = folders.first { $0.id == folder.parentID }
        move(folder.notebooks ?? [], to: parent)
        for child in folders where child.parentID == folder.id { child.parentID = parent?.id }
        context.delete(folder)
        saveFolders()
    }

    /// Writes are chained so they land in order, and each merges into the file so keys this version
    /// doesn't know about survive.
    private func writeFolders() {
        let folders = ((try? context.fetch(FetchDescriptor<FolderRecord>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []).map {
            FolderEntry(id: $0.id, name: $0.name, clothRaw: $0.clothRaw, createdAt: $0.createdAt, sortIndex: $0.sortIndex, parentID: $0.parentID)
        }
        let root = root, previous = folderWrite
        folderWrite = Task { [weak self] in
            await previous?.value
            let failure = await Task.detached(priority: .utility) { () -> String? in
                var file = FolderFile.read(root)
                file.merge(folders)
                do { try file.write(root) } catch { return error.localizedDescription }
                return nil
            }.value
            if let failure { self?.lastError = String(localized: "Folders couldn't be saved: \(failure)") }
        }
    }

    // MARK: Index

    /// Mirrors a manifest into the index, saving only when something the library shows changed.
    func index(_ manifest: NotebookManifest) {
        let existing = self.record(manifest.id)
        let record = existing ?? {
            let new = NotebookRecord(id: manifest.id)
            context.insert(new)
            return new
        }()
        let oldTitle = record.title
        var changed = record.apply(manifest, issues: record.issueCount) || existing == nil
        if existing == nil || record.title != oldTitle { searchVersion &+= 1 }
        let folderID = manifest.library.folderID
        if record.folder?.id != folderID {
            record.folder = folderID.flatMap { id in try? context.fetch(FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.id == id })).first }
            changed = true
        }
        if changed { saveIndex() }
    }

    /// Recognises handwriting and PDF text for pages whose text is out of date, in the background.
    func indexHandwriting(package: NotebookPackage, pages: [NotebookPage]) {
        let id = package.id
        Task(priority: .utility) { [weak self] in
            let text = await HandwritingIndexer.shared.index(HandwritingIndexer.Job(package: package, pages: pages))
            self?.updateSearchText(text, for: id)
        }
    }

    func updateSearchText(_ text: String, for id: UUID) {
        guard record(id) != nil, LibraryIndex.setSearchText(text, for: id, in: context) else { return }
        searchVersion &+= 1
        saveIndex()
    }

    func searchText(for id: UUID) -> String {
        LibraryIndex.searchRow(for: id, in: context)?.text ?? ""
    }

    // MARK: Daily journal

    /// Nil once the journal has been deleted or moved to the bin.
    var dailyJournal: NotebookRecord? {
        guard let id = UserDefaults.standard.string(forKey: SettingsKey.dailyJournalID).flatMap(UUID.init(uuidString:)),
              let journal = record(id), !journal.isTrashed else { return nil }
        return journal
    }

    @discardableResult
    func createDailyJournal(id: UUID = UUID(), now: Date = .now, calendar: Calendar = .current) async throws -> UUID {
        let size = UserDefaults.standard.string(forKey: SettingsKey.defaultPageSize).flatMap(PageSize.init(rawValue:)) ?? .letter
        let defaults = PageDefaults(template: NotebookStarter.journal.template, paperColor: NotebookStarter.journal.paperColor, pageSize: size)
        var page = defaults.newPage()
        page.day = DailyJournal.dayKey(for: now, calendar: calendar)
        var manifest = NotebookManifest(id: id, title: NotebookStarter.journal.title, createdAt: now,
                                        cover: NotebookStarter.journal.spec(for: id), defaults: defaults, pages: [page])
        manifest.library.lastOpenedAt = now
        try await NotebookPackage(root: root, id: id).create(manifest)
        index(manifest)
        UserDefaults.standard.set(id.uuidString, forKey: SettingsKey.dailyJournalID)
        return id
    }

    /// Nil for read-only notebooks and ones still opening, which then open at their saved page.
    func prepareTodayPage(_ id: UUID, now: Date = .now, calendar: Calendar = .current) async -> UUID? {
        guard let journal = record(id), !journal.isReadOnly else { return nil }
        if let document = DocumentRegistry.shared.document(for: id) {
            return DailyJournal.ensureTodayPage(in: document, now: now, calendar: calendar)
        }
        guard !DocumentRegistry.shared.isOpening(id) else { return nil }
        let key = DailyJournal.dayKey(for: now, calendar: calendar)
        let package = NotebookPackage(root: root, id: id)
        let pageID = UUID()
        let change: @Sendable (inout NotebookManifest) -> Void = { DailyJournal.dateToday(key, newPageID: pageID, in: &$0) }
        let token = UUID()
        defer {
            changesInFlight[id]?[token] = nil
            if changesInFlight[id]?.isEmpty == true { changesInFlight[id] = nil }
        }
        do {
            if let page = try await package.readManifest().manifest.pages.last(where: { $0.day == key }) { return page.id }
            changesInFlight[id, default: [:]][token] = change
            let manifest = try await package.updateManifest(change)
            index(manifest)
            return manifest.pages.last { $0.day == key }?.id
        } catch {
            log.error("today's page failed for \(id): \(error.localizedDescription)")
            return nil
        }
    }
}

extension LibraryStore {
    /// Saves what is open, then writes the whole library into one file.
    func makeBackup() async throws -> URL {
        for document in DocumentRegistry.shared.openDocuments { await document.flush() }
        await folderWrite?.value
        let root = root, journal = dailyJournal?.id
        return try await Task.detached(priority: .userInitiated) { try LibraryBackup.create(root: root, journal: journal) }.value
    }

    /// Notebooks, folders or stickers were changed on disk by something other than this store (a sync): read them again.
    func reloadFromDisk() async {
        await folderWrite?.value
        await LibraryIndex.refresh(root: root, context: context, full: true)
        searchVersion &+= 1
        indexVersion &+= 1
    }

    /// Adds a backup's notebooks, folders and stickers to the library, then brings the index up to date.
    func restoreBackup(from url: URL) async throws -> LibraryBackup.Summary {
        await folderWrite?.value
        let root = root, keepsHistory = UserDefaults.standard.object(forKey: SettingsKey.keepsWritingHistory) as? Bool ?? true
        let summary = try await Task.detached(priority: .userInitiated) {
            try await LibraryBackup.restore(from: url, into: root, keepsHistory: keepsHistory)
        }.value
        await LibraryIndex.refresh(root: root, context: context)
        searchVersion &+= 1
        indexVersion &+= 1
        if dailyJournal == nil, let journal = summary.journal, record(journal) != nil {
            UserDefaults.standard.set(journal.uuidString, forKey: SettingsKey.dailyJournalID)
        }
        return summary
    }
}

enum PDFImport {
    /// One page per PDF page, sized to its displayed crop box. Refuses locked and empty PDFs.
    static func pages(at url: URL, file: String) throws -> [NotebookPage] {
        guard let document = CGPDFDocument(url as CFURL) else { throw ImportError.unreadable }
        if document.isEncrypted && !document.isUnlocked && !document.unlockWithPassword("") { throw ImportError.locked }
        let pages = (0..<document.numberOfPages).compactMap { index -> NotebookPage? in
            guard let page = document.page(at: index + 1) else { return nil }
            return NotebookPage(background: .pdf(file: file, index: index), paperColor: .white, size: PageRenderer.displaySize(of: page))
        }
        guard !pages.isEmpty else { throw ImportError.empty }
        return pages
    }
}
