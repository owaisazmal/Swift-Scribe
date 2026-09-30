import Foundation
import SwiftData
import PencilKit
import os

struct MigrationReport: Sendable, Equatable {
    var migrated: [UUID] = []
    var alreadyMigrated: [UUID] = []
    var failed: [UUID: String] = [:]
    var titles: [UUID: String] = [:]
    /// Set when the v1 database exists but couldn't be read. Nothing is migrated or archived then,
    /// and the next launch tries again.
    var storeError: String?
    var warnings: [String] = []
    var backupURL: URL?

    var isComplete: Bool { failed.isEmpty && storeError == nil }
}

/// Moves v1 notebooks (one SwiftData store plus `Notebooks/<id>/drawing.pkdrawing`) into v2 packages.
/// Each notebook is built in a staging folder and renamed into place, so a crash leaves nothing half-written;
/// finished notebooks, including ones deleted since, are skipped on the next run. The v1 files are moved to
/// `Backups/` only after every notebook has migrated, and are never modified.
struct V1Migrator: Sendable {
    let root: StorageRoot
    private let log = Logger(subsystem: "com.owais.NotesApp", category: "migration")

    init(root: StorageRoot) { self.root = root }

    var isNeeded: Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: root.v1Store.path(percentEncoded: false))
            || fileManager.fileExists(atPath: root.v1Notebooks.path(percentEncoded: false))
    }

    struct V1Notebook: Sendable {
        var id: UUID
        var title: String
        var createdAt: Date
        var modifiedAt: Date
        var isFavorite: Bool
        var deletedAt: Date?
        var folderID: UUID?
        var pagesData: Data
        var recordingsData: Data
        var searchText: String
        var defaults: PageDefaults
    }

    struct V1Folder: Sendable {
        var id: UUID
        var name: String
        var colorRaw: String
        var createdAt: Date
    }

    func run() async -> MigrationReport {
        var report = MigrationReport()
        guard isNeeded else { return report }
        let v1: (notebooks: [V1Notebook], folders: [V1Folder], warnings: [String])
        do {
            v1 = try readV1()
        } catch {
            report.storeError = error.localizedDescription
            log.error("v1 store unreadable: \(error.localizedDescription)")
            writeLog(report)
            return report
        }
        let (notebooks, folders, readWarnings) = v1
        report.warnings += readWarnings
        let finishedEarlier = loggedAsMigrated()

        var folderFile = FolderFile.read(root)
        let byName = folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for folder in byName where !folderFile.folders.contains(where: { $0.id == folder.id }) {
            folderFile.upsert(FolderEntry(id: folder.id, name: folder.name,
                                          clothRaw: (FolderColor(rawValue: folder.colorRaw) ?? .blue).cloth.rawValue,
                                          createdAt: folder.createdAt, sortIndex: (folderFile.folders.map(\.sortIndex).max() ?? -1) + 1))
        }
        do { try folderFile.write(root) } catch { report.warnings.append("folders couldn't be written: \(error.localizedDescription)") }

        for notebook in notebooks {
            if isMigrated(notebook.id) || finishedEarlier.contains(notebook.id) {
                report.alreadyMigrated.append(notebook.id)
                continue
            }
            do {
                let warnings = try migrate(notebook)
                report.migrated.append(notebook.id)
                report.warnings += warnings.map { "\(notebook.title): \($0)" }
            } catch {
                report.failed[notebook.id] = error.localizedDescription
                report.titles[notebook.id] = notebook.title
                log.error("migration failed for \(notebook.id): \(error.localizedDescription)")
            }
        }

        if report.isComplete {
            do { report.backupURL = try moveV1ToBackup() } catch {
                report.warnings.append("v1 files couldn't be moved to Backups: \(error.localizedDescription)")
            }
        }
        writeLog(report)
        return report
    }

    func isMigrated(_ id: UUID) -> Bool {
        guard let data = try? Data(contentsOf: root.package(id).appending(path: "manifest.json")),
              let manifest = try? ManifestCodec.decode(data, fallbackID: id).manifest else { return false }
        return manifest.migratedFrom == "v1"
    }

    /// Notebooks an earlier run finished. They stay finished even after the user deletes them.
    func loggedAsMigrated() -> Set<UUID> {
        let log = (try? Data(contentsOf: root.migrationLog)).flatMap { try? JSONValue.parse($0) }
        var ids = Set<UUID>()
        for run in log?["runs"]?.arrayValue ?? [] {
            for (key, status) in run["notebooks"]?.objectValue ?? [:] where status == .string("migrated") {
                if let id = UUID(uuidString: key) { ids.insert(id) }
            }
        }
        return ids
    }

    // MARK: Reading v1

    /// Throws when the v1 database exists but can't be read: without it, titles, page lists and library state
    /// are unknown, so nothing is migrated from the drawings alone.
    func readV1() throws -> ([V1Notebook], [V1Folder], [String]) {
        var warnings: [String] = []
        var notebooks: [V1Notebook] = []
        var folders: [V1Folder] = []
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: root.v1Store.path(percentEncoded: false)) {
            let copy = try copyStore()
            defer { try? fileManager.removeItem(at: copy.deletingLastPathComponent()) }
            let schema = Schema(versionedSchema: LegacyV1Schema.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: copy))
            let context = ModelContext(container)
            for folder in try context.fetch(FetchDescriptor<LegacyV1Schema.Folder>()) {
                folders.append(V1Folder(id: folder.id, name: folder.name, colorRaw: folder.colorRaw, createdAt: folder.createdAt))
            }
            for notebook in try context.fetch(FetchDescriptor<LegacyV1Schema.Notebook>()) {
                notebooks.append(V1Notebook(
                    id: notebook.id, title: notebook.title, createdAt: notebook.createdAt, modifiedAt: notebook.modifiedAt,
                    isFavorite: notebook.isFavorite, deletedAt: notebook.deletedAt, folderID: notebook.folder?.id,
                    pagesData: notebook.pagesData, recordingsData: notebook.recordingsData, searchText: notebook.searchText,
                    defaults: PageDefaults(templateRaw: notebook.defaultTemplateRaw, paperColorRaw: notebook.defaultColorRaw,
                                           pageSizeRaw: notebook.defaultSizeRaw, extra: [:])))
            }
        }

        let known = Set(notebooks.map(\.id))
        let directories = (try? fileManager.contentsOfDirectory(at: root.v1Notebooks, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for directory in directories {
            guard let id = UUID(uuidString: directory.lastPathComponent), !known.contains(id) else { continue }
            let created = (try? directory.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .now
            notebooks.append(V1Notebook(id: id, title: "Recovered Notebook", createdAt: created, modifiedAt: created,
                                        isFavorite: false, deletedAt: nil, folderID: nil, pagesData: Data(),
                                        recordingsData: Data(), searchText: "",
                                        defaults: PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter)))
            warnings.append("a notebook folder without a library entry was recovered as “Recovered Notebook”")
        }
        return (notebooks, folders, warnings)
    }

    /// SwiftData may touch a store it opens, so migration reads a copy and the original stays byte-for-byte intact.
    private func copyStore() throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appending(path: "v1-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = root.v1Store.lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            let source = root.v1Store.deletingLastPathComponent().appending(path: name + suffix)
            if fileManager.fileExists(atPath: source.path(percentEncoded: false)) {
                try fileManager.copyItem(at: source, to: directory.appending(path: name + suffix))
            }
        }
        return directory.appending(path: name)
    }

    // MARK: One notebook

    func migrate(_ notebook: V1Notebook) throws -> [String] {
        let fileManager = FileManager.default
        var warnings: [String] = []
        let source = root.v1Notebooks.appending(path: notebook.id.uuidString, directoryHint: .isDirectory)
        let destination = root.package(notebook.id)
        let staging = root.library.appending(path: "\(notebook.id.uuidString).migrating", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root.library, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: staging.path(percentEncoded: false)) { try fileManager.removeItem(at: staging) }
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: "a v2 notebook with this ID already exists"])
        }
        for sub in ["ink", "assets", "thumbs", "text"] {
            try fileManager.createDirectory(at: staging.appending(path: sub, directoryHint: .isDirectory), withIntermediateDirectories: true)
        }

        var drawing = PKDrawing()
        let drawingFile = source.appending(path: "drawing.pkdrawing")
        if let data = try? Data(contentsOf: drawingFile) {
            do {
                drawing = try NotebookPackage.decodeInk(data)
            } catch {
                try fileManager.createDirectory(at: staging.appending(path: "legacy", directoryHint: .isDirectory), withIntermediateDirectories: true)
                try data.write(to: staging.appending(path: "legacy/drawing.pkdrawing.corrupt"))
                warnings.append("the ink couldn't be read; the original file was kept in the notebook as legacy/drawing.pkdrawing.corrupt")
            }
        }

        var pages = LegacyV1Layout.decodePages(notebook.pagesData) ?? []
        if pages.isEmpty {
            let pitch = (LegacyV1Layout.pageWidth * PageSize.letter.points.height / PageSize.letter.points.width).rounded() + LegacyV1Layout.pageGap
            let count = drawing.strokes.isEmpty ? 1 : max(1, Int(ceil((drawing.bounds.maxY - LegacyV1Layout.topMargin) / pitch)))
            pages = (0..<count).map { _ in notebook.defaults.newPage() }
            if !notebook.pagesData.isEmpty { warnings.append("the page list couldn't be read; \(count) page(s) were rebuilt from the ink") }
            if !notebook.pagesData.isEmpty {
                try fileManager.createDirectory(at: staging.appending(path: "legacy", directoryHint: .isDirectory), withIntermediateDirectories: true)
                try notebook.pagesData.write(to: staging.appending(path: "legacy/pages.json"))
            }
        }

        let frames = LegacyV1Layout.frames(for: pages.map(\.size))
        var strokesByPage = Array(repeating: [PKStroke](), count: pages.count)
        for stroke in drawing.strokes {
            let index = LegacyV1Layout.pageIndex(atY: stroke.renderBounds.midY, frames: frames)
            var local = stroke
            local.transform = stroke.transform.concatenating(LegacyV1Layout.pageLocalTransform(frame: frames[index], size: pages[index].size))
            strokesByPage[index].append(local)
        }
        for index in pages.indices where !strokesByPage[index].isEmpty {
            let data = PKDrawing(strokes: strokesByPage[index]).dataRepresentation()
            try data.write(to: staging.appending(path: pages[index].inkFile), options: .atomic)
            pages[index].inkHash = NotebookPackage.hash(data)
        }

        let assets = source.appending(path: "assets", directoryHint: .isDirectory)
        for file in (try? fileManager.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)) ?? [] {
            try fileManager.copyItem(at: file, to: staging.appending(path: "assets/\(file.lastPathComponent)"))
        }
        let assetNames = Set(((try? fileManager.contentsOfDirectory(atPath: staging.appending(path: "assets").path(percentEncoded: false))) ?? []))
        for page in pages {
            if let file = page.background.assetFile, !assetNames.contains(file) {
                warnings.append("a page's background file (\(file)) was missing in v1")
            }
        }
        if !notebook.searchText.isEmpty {
            try Data(notebook.searchText.utf8).write(to: staging.appending(path: "text/\(NotebookPackage.legacyTextName)"), options: .atomic)
        }

        var cover = CoverSpec.defaultCloth(for: notebook.id)
        cover.style = .firstPage
        var manifest = NotebookManifest(id: notebook.id, title: notebook.title.isEmpty ? "Untitled Notebook" : notebook.title,
                                        createdAt: notebook.createdAt, cover: cover, defaults: notebook.defaults, pages: pages)
        manifest.modifiedAt = notebook.modifiedAt
        manifest.recordings = LegacyV1Layout.decodeRecordings(notebook.recordingsData)
        manifest.library = LibraryState(isFavorite: notebook.isFavorite, deletedAt: notebook.deletedAt, folderID: notebook.folderID)
        manifest.migratedFrom = "v1"
        try ManifestCodec.encode(manifest).write(to: staging.appending(path: "manifest.json"), options: .atomic)
        try fileManager.moveItem(at: staging, to: destination)
        return warnings
    }

    // MARK: Backup and log

    private func moveV1ToBackup() throws -> URL? {
        let fileManager = FileManager.default
        let backup = root.backups.appending(path: "v1", directoryHint: .isDirectory)
        var moved = false
        let storeName = root.v1Store.lastPathComponent
        let items = [root.v1Notebooks] + ["", "-wal", "-shm"].map { root.v1Store.deletingLastPathComponent().appending(path: storeName + $0) }
        for item in items where fileManager.fileExists(atPath: item.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
            var target = backup.appending(path: item.lastPathComponent)
            var suffix = 2
            while fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
                target = backup.appending(path: "\(item.lastPathComponent)-\(suffix)")
                suffix += 1
            }
            try fileManager.moveItem(at: item, to: target)
            moved = true
        }
        return moved ? backup : nil
    }

    private func writeLog(_ report: MigrationReport) {
        var notebooks: [String: JSONValue] = [:]
        for id in report.migrated { notebooks[id.uuidString] = .string("migrated") }
        for id in report.alreadyMigrated { notebooks[id.uuidString] = .string("already migrated") }
        for (id, error) in report.failed { notebooks[id.uuidString] = .string("failed: \(error)") }
        if let storeError = report.storeError { notebooks["store"] = .string("unreadable: \(storeError)") }
        var previous = (try? Data(contentsOf: root.migrationLog)).flatMap { try? JSONValue.parse($0) }?.objectValue ?? [:]
        var runs = previous["runs"]?.arrayValue ?? []
        runs.append(.object([
            "date": ManifestCodec.encodeDate(.now),
            "complete": .bool(report.isComplete),
            "notebooks": .object(notebooks),
            "warnings": .array(report.warnings.map(JSONValue.string)),
            "backup": report.backupURL.map { .string($0.path(percentEncoded: false)) } ?? .null,
        ]))
        previous["runs"] = .array(runs)
        try? FileManager.default.createDirectory(at: root.library, withIntermediateDirectories: true)
        try? JSONValue.object(previous).serialized().write(to: root.migrationLog, options: .atomic)
    }
}
