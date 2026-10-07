import Foundation
import SwiftData
import os

/// The first index schema, kept only so a store written by it can be migrated. Each record carried its notebook's
/// whole search text, so every library query loaded it.
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
        var firstPageThumbKey: String?
        var firstPageIsPDF: Bool = false
        var isReadOnly: Bool = false
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

/// The second index schema, kept so a store written by it can be migrated. Its folders were a flat list.
enum LibraryIndexSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [NotebookRecord.self, FolderRecord.self, NotebookSearchText.self] }

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
        var coverStyleRaw: String = CoverStyle.cloth.rawValue
        var clothRaw: String = ClothColor.slate.rawValue
        var inksRaw: String = "teal,blue"
        var coverSeed: Int = 0
        var firstPageID: UUID?
        var firstPageInkHash: String?
        var firstPageThumbKey: String?
        var firstPageIsPDF: Bool = false
        var isReadOnly: Bool = false
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
        @Relationship(deleteRule: .nullify, inverse: \LibraryIndexSchemaV2.NotebookRecord.folder)
        var notebooks: [NotebookRecord]? = []

        init(id: UUID) { self.id = id }
    }

    /// Everything recognised, typed or read from PDFs in one notebook. Deliberately not a relationship of the record.
    @Model
    final class NotebookSearchText {
        @Attribute(.unique) var notebookID: UUID = UUID()
        var text: String = ""

        init(notebookID: UUID, text: String) {
            self.notebookID = notebookID
            self.text = text
        }
    }
}

/// The third index schema, kept so a store written by it can be migrated. Its notebooks had no lock.
enum LibraryIndexSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [NotebookRecord.self, FolderRecord.self, NotebookSearchText.self] }

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
        var coverStyleRaw: String = CoverStyle.cloth.rawValue
        var clothRaw: String = ClothColor.slate.rawValue
        var inksRaw: String = "teal,blue"
        var coverSeed: Int = 0
        var firstPageID: UUID?
        var firstPageInkHash: String?
        var firstPageThumbKey: String?
        var firstPageIsPDF: Bool = false
        var isReadOnly: Bool = false
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
        var parentID: UUID?
        @Relationship(deleteRule: .nullify, inverse: \LibraryIndexSchemaV3.NotebookRecord.folder)
        var notebooks: [NotebookRecord]? = []

        init(id: UUID) { self.id = id }
    }

    /// Everything recognised, typed or read from PDFs in one notebook. Deliberately not a relationship of the record.
    @Model
    final class NotebookSearchText {
        @Attribute(.unique) var notebookID: UUID = UUID()
        var text: String = ""

        init(notebookID: UUID, text: String) {
            self.notebookID = notebookID
            self.text = text
        }
    }
}

/// The fourth index schema, kept so a store written by it can be migrated. Its notebooks had no tags.
enum LibraryIndexSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] { [NotebookRecord.self, FolderRecord.self, NotebookSearchText.self] }

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
        var coverStyleRaw: String = CoverStyle.cloth.rawValue
        var clothRaw: String = ClothColor.slate.rawValue
        var inksRaw: String = "teal,blue"
        var coverSeed: Int = 0
        var firstPageID: UUID?
        var firstPageInkHash: String?
        var firstPageThumbKey: String?
        var firstPageIsPDF: Bool = false
        var isReadOnly: Bool = false
        var issueCount: Int = 0
        var indexedAt: Date = Date.distantPast
        var isLocked: Bool = false

        init(id: UUID) { self.id = id }
    }

    @Model
    final class FolderRecord {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var clothRaw: String = ClothColor.slate.rawValue
        var createdAt: Date = Date()
        var sortIndex: Int = 0
        var parentID: UUID?
        @Relationship(deleteRule: .nullify, inverse: \LibraryIndexSchemaV4.NotebookRecord.folder)
        var notebooks: [NotebookRecord]? = []

        init(id: UUID) { self.id = id }
    }

    /// Everything recognised, typed or read from PDFs in one notebook. Deliberately not a relationship of the record.
    @Model
    final class NotebookSearchText {
        @Attribute(.unique) var notebookID: UUID = UUID()
        var text: String = ""

        init(notebookID: UUID, text: String) {
            self.notebookID = notebookID
            self.text = text
        }
    }
}

/// The library index: a SwiftData cache of what's in the notebook manifests and `folders.json`,
/// for fast sorting, filtering and search. It can always be rebuilt from those files.
/// Search text has its own table, so the shelf's queries never read it. Folders name the folder they sit inside,
/// and a notebook says whether it is locked and which tags it and its pages carry.
enum LibraryIndexSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] { [NotebookRecord.self, FolderRecord.self, NotebookSearchText.self] }

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
        var coverStyleRaw: String = CoverStyle.cloth.rawValue
        var clothRaw: String = ClothColor.slate.rawValue
        var inksRaw: String = "teal,blue"
        var coverSeed: Int = 0
        var firstPageID: UUID?
        var firstPageInkHash: String?
        var firstPageThumbKey: String?
        var firstPageIsPDF: Bool = false
        var isReadOnly: Bool = false
        var issueCount: Int = 0
        var indexedAt: Date = Date.distantPast
        var isLocked: Bool = false
        /// The notebook's tags, one to a line.
        var tagsRaw: String = ""
        /// Every tag on any of its pages, one to a line.
        var pageTagsRaw: String = ""

        init(id: UUID) { self.id = id }
    }

    @Model
    final class FolderRecord {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var clothRaw: String = ClothColor.slate.rawValue
        var createdAt: Date = Date()
        var sortIndex: Int = 0
        var parentID: UUID?
        @Relationship(deleteRule: .nullify, inverse: \LibraryIndexSchemaV5.NotebookRecord.folder)
        var notebooks: [NotebookRecord]? = []

        init(id: UUID) { self.id = id }
    }

    /// Everything recognised, typed or read from PDFs in one notebook. Deliberately not a relationship of the record.
    @Model
    final class NotebookSearchText {
        @Attribute(.unique) var notebookID: UUID = UUID()
        var text: String = ""

        init(notebookID: UUID, text: String) {
            self.notebookID = notebookID
            self.text = text
        }
    }
}

typealias NotebookRecord = LibraryIndexSchemaV5.NotebookRecord
typealias FolderRecord = LibraryIndexSchemaV5.FolderRecord
typealias NotebookSearchText = LibraryIndexSchemaV5.NotebookSearchText

/// V1 to V2 drops the record's search text and adds the empty table; the next refresh reads the text back from the packages.
/// V2 to V3 gives folders a parent, which the same refresh fills in from `folders.json`.
/// V3 to V4 adds the lock, which starts off: the first refresh afterwards reads every manifest for it.
/// V4 to V5 adds the tags, which start empty and are read by that same first refresh.
enum LibraryIndexMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibraryIndexSchemaV1.self, LibraryIndexSchemaV2.self, LibraryIndexSchemaV3.self, LibraryIndexSchemaV4.self,
         LibraryIndexSchemaV5.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LibraryIndexSchemaV1.self, toVersion: LibraryIndexSchemaV2.self),
         .lightweight(fromVersion: LibraryIndexSchemaV2.self, toVersion: LibraryIndexSchemaV3.self),
         .lightweight(fromVersion: LibraryIndexSchemaV3.self, toVersion: LibraryIndexSchemaV4.self),
         .lightweight(fromVersion: LibraryIndexSchemaV4.self, toVersion: LibraryIndexSchemaV5.self)]
    }
}

extension NotebookRecord {
    var isTrashed: Bool { deletedAt != nil }
    var coverStyle: CoverStyle { CoverStyle(rawValue: coverStyleRaw) ?? .cloth }
    var cloth: ClothColor { ClothColor(rawValue: clothRaw) ?? .slate }
    var tags: [String] { Tags.split(tagsRaw) }
    var pageTags: [String] { Tags.split(pageTagsRaw) }

    var cover: CoverSpec {
        CoverSpec(styleRaw: coverStyleRaw, clothRaw: clothRaw, inksRaw: inksRaw.split(separator: ",").map(String.init),
                  seed: UInt32(clamping: coverSeed))
    }

    /// Copies the indexed fields, assigning only those that differ so unchanged records don't invalidate
    /// the library's queries. Returns whether anything changed.
    @discardableResult
    func apply(_ manifest: NotebookManifest, issues: Int) -> Bool {
        let first = manifest.pages.first
        var changed = false
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<NotebookRecord, T>, _ value: T) {
            guard self[keyPath: keyPath] != value else { return }
            self[keyPath: keyPath] = value
            changed = true
        }
        set(\.title, manifest.title)
        set(\.createdAt, manifest.createdAt)
        set(\.modifiedAt, manifest.modifiedAt)
        set(\.lastOpenedAt, manifest.library.lastOpenedAt)
        set(\.pageCount, manifest.pages.count)
        set(\.currentPage, min(manifest.library.currentPage, max(manifest.pages.count - 1, 0)))
        set(\.isFavorite, manifest.library.isFavorite)
        set(\.deletedAt, manifest.library.deletedAt)
        set(\.isLocked, manifest.library.isLocked)
        set(\.tagsRaw, Tags.joined(manifest.library.tags))
        set(\.pageTagsRaw, Tags.joined(manifest.pageTags))
        set(\.coverStyleRaw, manifest.cover.styleRaw)
        set(\.clothRaw, manifest.cover.clothRaw)
        set(\.inksRaw, manifest.cover.inksRaw.joined(separator: ","))
        set(\.coverSeed, Int(manifest.cover.seed))
        set(\.firstPageID, first?.id)
        set(\.firstPageInkHash, first?.inkHash)
        set(\.firstPageThumbKey, first?.thumbnailKey)
        let firstIsPDF: Bool = if case .pdf = first?.background { true } else { false }
        set(\.firstPageIsPDF, firstIsPDF)
        set(\.isReadOnly, manifest.isNewerThanSupported)
        set(\.issueCount, issues)
        if changed { indexedAt = .now }
        return changed
    }
}

extension FolderRecord {
    var cloth: ClothColor { ClothColor(rawValue: clothRaw) ?? .slate }

    func apply(_ entry: FolderEntry) {
        name = entry.name
        clothRaw = entry.clothRaw
        createdAt = entry.createdAt
        sortIndex = entry.sortIndex
        parentID = entry.parentID
    }

    var node: FolderTree.Node { FolderTree.Node(id: id, parent: parentID, name: name, sortIndex: sortIndex) }
}

extension FolderTree {
    @MainActor
    init(folders: [FolderRecord]) { self.init(folders.map(\.node)) }
}

@MainActor
enum LibraryIndex {
    private static let log = Logger(subsystem: "com.owais.OwlLuna", category: "index")
    static let schemaNumber = 5

    /// Opens the index. A store that can't be opened is set aside (never deleted) and a fresh one is rebuilt
    /// from the manifests; if even that fails, the app runs on an in-memory index for this launch.
    static var schema: Schema { Schema(versionedSchema: LibraryIndexSchemaV5.self) }

    static func makeContainer(root: StorageRoot) -> (container: ModelContainer, recovered: Bool) {
        let schema = schema
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
            setSearchText(item.searchText, for: id, in: context)
            record.folder = item.load.manifest.library.folderID.flatMap { folders[$0] }
        }
        for (id, record) in byID where stamps[id] == nil {
            context.delete(record)
        }

        // Notebooks with no search row yet (a migrated or rebuilt index) get theirs from the text already on disk.
        var listing = FetchDescriptor<NotebookSearchText>()
        listing.propertiesToFetch = [\.notebookID]
        let rows = (try? context.fetch(listing)) ?? []
        let have = Set(rows.map(\.notebookID))
        for row in rows where stamps[row.notebookID] == nil { context.delete(row) }
        let missing = stamps.keys.filter { !have.contains($0) && scanned[$0] == nil }
        if !missing.isEmpty {
            let texts = await Task.detached(priority: .userInitiated) { () -> [UUID: String] in
                var result: [UUID: String] = [:]
                for id in missing { result[id] = searchText(in: NotebookPackage(root: root, id: id).textDirectory) }
                return result
            }.value
            for (id, text) in texts { setSearchText(text, for: id, in: context) }
        }
        do { try context.save() } catch { log.error("index save failed: \(error.localizedDescription)") }
    }

    static func searchRow(for id: UUID, in context: ModelContext) -> NotebookSearchText? {
        try? context.fetch(FetchDescriptor<NotebookSearchText>(predicate: #Predicate { $0.notebookID == id })).first
    }

    /// Returns whether anything changed.
    @discardableResult
    static func setSearchText(_ text: String, for id: UUID, in context: ModelContext) -> Bool {
        if let row = searchRow(for: id, in: context) {
            guard row.text != text else { return false }
            row.text = text
        } else {
            context.insert(NotebookSearchText(notebookID: id, text: text))
        }
        return true
    }

    /// The notebooks whose title, tags or text contains `query`. Only IDs are read, so a library full of PDF text stays on disk.
    nonisolated static func notebookIDs(matching query: String, in context: ModelContext) -> Set<UUID> {
        let tag = Tags.normalized(query) ?? query
        var titles = FetchDescriptor<NotebookRecord>(predicate: #Predicate {
            $0.title.localizedStandardContains(query) || $0.tagsRaw.localizedStandardContains(tag) || $0.pageTagsRaw.localizedStandardContains(tag)
        })
        titles.propertiesToFetch = [\.id]
        var texts = FetchDescriptor<NotebookSearchText>(predicate: #Predicate { $0.text.localizedStandardContains(query) })
        texts.propertiesToFetch = [\.notebookID]
        let byTitle = ((try? context.fetch(titles)) ?? []).map(\.id)
        let byText = ((try? context.fetch(texts)) ?? []).map(\.notebookID)
        return Set(byTitle).union(byText)
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
