import Foundation
import SwiftData
import os

/// The library index: a SwiftData cache of what's in the notebook manifests and `folders.json`,
/// for fast sorting, filtering and search. It can always be rebuilt from those files.
enum LibraryIndexSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [NotebookRecord.self, FolderRecord.self] }

    @Model
    final class NotebookRecord {
        @Attribute(.unique) var id: UUID = UUID()
        var title: String = ""
        var createdAt: Date = Date()
        var modifiedAt: Date = Date()
        var lastOpenedAt: Date?
        var pageCount: Int = 0
        var currentPage: Int = 0
        var isFavorite: Bool = false
        var deletedAt: Date?
        var folder: FolderRecord?
        var searchText: String = ""
        var coverStyleRaw: String = CoverStyle.cloth.rawValue
        var clothRaw: String = ClothColor.slate.rawValue
        var inksRaw: String = "teal,blue"
        var coverSeed: Int = 0
        var firstPageID: UUID?
        var firstPageInkHash: String?
        var firstPageIsPDF: Bool = false
        var issueCount: Int = 0
        var indexedAt: Date = Date.distantPast

        init(id: UUID) { self.id = id }
    }

    @Model
    final class FolderRecord {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var clothRaw: String = ClothColor.slate.rawValue
        var createdAt: Date = Date()
        var sortIndex: Int = 0
        @Relationship(deleteRule: .nullify, inverse: \LibraryIndexSchemaV1.NotebookRecord.folder)
        var notebooks: [NotebookRecord]? = []

        init(id: UUID) { self.id = id }
    }
}

typealias NotebookRecord = LibraryIndexSchemaV1.NotebookRecord
typealias FolderRecord = LibraryIndexSchemaV1.FolderRecord

enum LibraryIndexMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibraryIndexSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

extension NotebookRecord {
    var isTrashed: Bool { deletedAt != nil }
    var coverStyle: CoverStyle { CoverStyle(rawValue: coverStyleRaw) ?? .cloth }
    var cloth: ClothColor { ClothColor(rawValue: clothRaw) ?? .slate }

    var cover: CoverSpec {
        CoverSpec(styleRaw: coverStyleRaw, clothRaw: clothRaw, inksRaw: inksRaw.split(separator: ",").map(String.init),
                  seed: UInt32(clamping: coverSeed))
    }

    func apply(_ manifest: NotebookManifest, issues: Int) {
        title = manifest.title
        createdAt = manifest.createdAt
        modifiedAt = manifest.modifiedAt
        lastOpenedAt = manifest.library.lastOpenedAt
        pageCount = manifest.pages.count
        currentPage = min(manifest.library.currentPage, max(manifest.pages.count - 1, 0))
        isFavorite = manifest.library.isFavorite
        deletedAt = manifest.library.deletedAt
        coverStyleRaw = manifest.cover.styleRaw
        clothRaw = manifest.cover.clothRaw
        inksRaw = manifest.cover.inksRaw.joined(separator: ",")
        coverSeed = Int(manifest.cover.seed)
        firstPageID = manifest.pages.first?.id
        firstPageInkHash = manifest.pages.first?.inkHash
        firstPageIsPDF = if case .pdf = manifest.pages.first?.background { true } else { false }
        issueCount = issues
        indexedAt = .now
    }
}

extension FolderRecord {
    var cloth: ClothColor { ClothColor(rawValue: clothRaw) ?? .slate }

    func apply(_ entry: FolderEntry) {
        name = entry.name
        clothRaw = entry.clothRaw
        createdAt = entry.createdAt
        sortIndex = entry.sortIndex
    }
}

@MainActor
enum LibraryIndex {
    private static let log = Logger(subsystem: "com.owais.NotesApp", category: "index")

    /// Opens the index. A store that can't be opened is set aside (never deleted) and a fresh one is rebuilt
    /// from the manifests; if even that fails, the app runs on an in-memory index for this launch.
    static func makeContainer(root: StorageRoot) -> (container: ModelContainer, recovered: Bool) {
        let schema = Schema(versionedSchema: LibraryIndexSchemaV1.self)
        try? FileManager.default.createDirectory(at: root.url, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: schema, url: root.indexStore)
        do {
            return (try ModelContainer(for: schema, migrationPlan: LibraryIndexMigrationPlan.self, configurations: configuration), false)
        } catch {
            log.error("index store unreadable, setting it aside: \(error.localizedDescription)")
            setAside(root.indexStore)
            if let container = try? ModelContainer(for: schema, migrationPlan: LibraryIndexMigrationPlan.self, configurations: configuration) {
                return (container, true)
            }
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // An in-memory container with a known-good schema cannot fail.
            return (try! ModelContainer(for: schema, configurations: memory), true)
        }
    }

    private static func setAside(_ store: URL) {
        let fileManager = FileManager.default
        let stamp = Int(Date.now.timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let file = store.deletingLastPathComponent().appending(path: store.lastPathComponent + suffix)
            guard fileManager.fileExists(atPath: file.path(percentEncoded: false)) else { continue }
            try? fileManager.moveItem(at: file, to: file.deletingLastPathComponent().appending(path: "\(store.lastPathComponent).unreadable-\(stamp)\(suffix)"))
        }
    }

    struct Scanned: Sendable {
        var load: ManifestLoad
        var searchText: String
        var issues: Int
    }

    /// Brings the index up to date with the packages on disk. Reads only manifests newer than their record,
    /// unless `full` is set.
    static func refresh(root: StorageRoot, context: ModelContext, full: Bool = false) async {
        let stamps = await Task.detached(priority: .userInitiated) { manifestStamps(root: root) }.value
        let records = (try? context.fetch(FetchDescriptor<NotebookRecord>())) ?? []
        var byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stale = stamps.filter { id, stamp in full || (byID[id]?.indexedAt ?? .distantPast) < stamp }.map(\.key)
        let scanned = await Task.detached(priority: .userInitiated) { await scan(root: root, ids: stale) }.value

        let folderFile = await Task.detached(priority: .userInitiated) { FolderFile.read(root) }.value
        var folders = Dictionary(((try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []).map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        for entry in folderFile.folders {
            let record = folders[entry.id] ?? FolderRecord(id: entry.id)
            if folders[entry.id] == nil { context.insert(record); folders[entry.id] = record }
            record.apply(entry)
        }
        for (id, record) in folders where !folderFile.folders.contains(where: { $0.id == id }) {
            context.delete(record)
            folders[id] = nil
        }

        for (id, item) in scanned {
            let record = byID[id] ?? NotebookRecord(id: id)
            if byID[id] == nil { context.insert(record); byID[id] = record }
            record.apply(item.load.manifest, issues: item.issues)
            record.searchText = item.searchText
            record.folder = item.load.manifest.library.folderID.flatMap { folders[$0] }
        }
        for (id, record) in byID where stamps[id] == nil {
            context.delete(record)
        }
        do { try context.save() } catch { log.error("index save failed: \(error.localizedDescription)") }
    }

    nonisolated static func manifestStamps(root: StorageRoot) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for id in root.packageIDs() {
            let package = root.package(id)
            let manifest = package.appending(path: "manifest.json")
            let date = (try? manifest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            result[id] = date ?? .distantFuture
        }
        return result
    }

    nonisolated static func scan(root: StorageRoot, ids: [UUID]) async -> [UUID: Scanned] {
        var result: [UUID: Scanned] = [:]
        for id in ids {
            let package = NotebookPackage(root: root, id: id)
            guard let load = try? await package.readManifest() else { continue }
            if load.needsSave, !load.isReadOnly {
                try? await package.writeManifest(load.manifest)
            }
            let issues = await package.quarantinedFiles().count + load.manifest.opaquePages.count
            result[id] = Scanned(load: load, searchText: searchText(in: package.textDirectory), issues: issues)
        }
        return result
    }

    nonisolated static func searchText(in directory: URL) -> String {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map { $0.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix("#ink:") }.joined(separator: "\n") }
            .joined(separator: "\n")
    }
}
