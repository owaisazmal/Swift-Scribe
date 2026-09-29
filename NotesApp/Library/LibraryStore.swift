import Foundation
import CoreGraphics
import SwiftData
import Observation
import os

enum ImportError: LocalizedError {
    case unreadable, locked, empty

    var errorDescription: String? {
        switch self {
        case .unreadable: "The file couldn't be read."
        case .locked: "This PDF is password protected. Unlock it in Files or Preview, then import it again."
        case .empty: "The file doesn't contain any pages."
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
    @ObservationIgnored private let log = Logger(subsystem: "com.owais.NotesApp", category: "library")

    init(root: StorageRoot, context: ModelContext) {
        self.root = root
        self.context = context
    }

    func record(_ id: UUID) -> NotebookRecord? {
        try? context.fetch(FetchDescriptor<NotebookRecord>(predicate: #Predicate { $0.id == id })).first
    }

    func saveIndex() {
        do { try context.save() } catch { log.error("index save failed: \(error.localizedDescription)") }
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

    @discardableResult
    func importPDF(from url: URL, folder: FolderRecord?) async throws -> UUID {
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
            manifest.library.folderID = folder?.id
            try await package.create(manifest)
            index(manifest)
            Task { [weak self] in
                let text = await HandwritingIndexer.shared.index(HandwritingIndexer.Job(package: package, pages: pages))
                self?.updateSearchText(text, for: id)
            }
            return id
        } catch {
            try? FileManager.default.removeItem(at: package.url)
            throw error
        }
    }

    @discardableResult
    func duplicate(_ record: NotebookRecord) async throws -> UUID {
        if let open = DocumentRegistry.shared.document(for: record.id) { await open.flush() }
        let newID = UUID()
        let source = root.package(record.id), destination = root.package(newID)
        try FileManager.default.copyItem(at: source, to: destination)
        let package = NotebookPackage(root: root, id: newID)
        do {
            let copy = try await package.updateManifest { manifest in
                manifest.id = newID
                manifest.title = "\(manifest.title) Copy"
                manifest.createdAt = .now
                manifest.modifiedAt = .now
                manifest.library.isFavorite = false
                manifest.library.lastOpenedAt = nil
                manifest.migratedFrom = nil
            }
            index(copy)
            return newID
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    // MARK: Changing

    func rename(_ record: NotebookRecord, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != record.title else { return }
        record.title = trimmed
        saveIndex()
        if let document = DocumentRegistry.shared.document(for: record.id) {
            document.rename(trimmed)
        } else {
            update(record.id) { $0.title = trimmed; $0.modifiedAt = .now }
        }
    }

    func setCover(_ cover: CoverSpec, for record: NotebookRecord) {
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

    func noteOpened(_ record: NotebookRecord) {
        record.lastOpenedAt = .now
        saveIndex()
    }

    /// Permanently removes notebooks from the library. Only offered for notebooks already in Recently Deleted.
    func deletePermanently(_ records: [NotebookRecord]) {
        for record in records where record.isTrashed && DocumentRegistry.shared.document(for: record.id) == nil {
            do {
                try FileManager.default.removeItem(at: root.package(record.id))
                context.delete(record)
            } catch {
                lastError = "“\(record.title)” couldn't be deleted: \(error.localizedDescription)"
            }
        }
        saveIndex()
    }

    func purgeExpiredTrash(olderThan days: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let expired = ((try? context.fetch(FetchDescriptor<NotebookRecord>(predicate: #Predicate { $0.deletedAt != nil }))) ?? [])
            .filter { ($0.deletedAt ?? .now) < cutoff }
        if !expired.isEmpty { deletePermanently(expired) }
    }

    private func changeLibraryState(_ records: [NotebookRecord], index: (NotebookRecord) -> Void,
                                    manifest change: @escaping @Sendable (inout LibraryState) -> Void) {
        for record in records {
            index(record)
            if let document = DocumentRegistry.shared.document(for: record.id) {
                document.updateLibraryState(change)
            } else {
                update(record.id) { change(&$0.library) }
            }
        }
        saveIndex()
    }

    private func update(_ id: UUID, _ change: @escaping @Sendable (inout NotebookManifest) -> Void) {
        let package = NotebookPackage(root: root, id: id)
        Task {
            do {
                _ = try await package.updateManifest(change)
            } catch {
                lastError = "A change couldn't be saved: \(error.localizedDescription)"
                log.error("manifest update failed for \(id): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Folders

    @discardableResult
    func createFolder(name: String, cloth: ClothColor) -> FolderRecord? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let count = (try? context.fetchCount(FetchDescriptor<FolderRecord>())) ?? 0
        let entry = FolderEntry(id: UUID(), name: trimmed, clothRaw: cloth.rawValue, createdAt: .now, sortIndex: count)
        let record = FolderRecord(id: entry.id)
        record.apply(entry)
        context.insert(record)
        saveIndex()
        writeFolders()
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

    /// Deleting a folder keeps its notebooks; they move back to the whole library.
    func deleteFolder(_ folder: FolderRecord) {
        move(folder.notebooks ?? [], to: nil)
        context.delete(folder)
        saveIndex()
        writeFolders()
    }

    private func writeFolders() {
        let folders = ((try? context.fetch(FetchDescriptor<FolderRecord>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []).map {
            FolderEntry(id: $0.id, name: $0.name, clothRaw: $0.clothRaw, createdAt: $0.createdAt, sortIndex: $0.sortIndex)
        }
        let root = root
        Task.detached(priority: .utility) {
            var file = FolderFile.read(root)
            file.folders = folders
            try? file.write(root)
        }
    }

    // MARK: Index

    func index(_ manifest: NotebookManifest) {
        let record = self.record(manifest.id) ?? {
            let new = NotebookRecord(id: manifest.id)
            context.insert(new)
            return new
        }()
        record.apply(manifest, issues: record.issueCount)
        if let folderID = manifest.library.folderID {
            record.folder = try? context.fetch(FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.id == folderID })).first
        } else {
            record.folder = nil
        }
        saveIndex()
    }

    func updateSearchText(_ text: String, for id: UUID) {
        guard let record = record(id), record.searchText != text else { return }
        record.searchText = text
        saveIndex()
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
