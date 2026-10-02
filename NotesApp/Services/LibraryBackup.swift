import Foundation
import AppleArchive
import System
import UniformTypeIdentifiers

extension UTType {
    static let scribeBackup = UTType(exportedAs: "com.owais.swiftscribe.backup")
}

/// The whole library as one file: every notebook package, the folders, the writing history and your own stickers,
/// in an Apple Archive. Thumbnails are left out; they are made again when needed.
enum LibraryBackup {
    static let fileExtension = "scribebackup"
    static let infoFile = "backup.json"
    static let currentVersion = 1

    struct Summary: Sendable, Equatable {
        /// Notebooks the library didn't have.
        var added = 0
        /// Notebooks the library has in a different state, brought back beside it under a new name.
        var copies = 0
        /// Notebooks the library already has exactly as they are in the backup.
        var unchanged = 0
        var unreadable = 0
        var folders = 0
        var stickers = 0
        /// The notebook the backup's library used as its daily journal, if it was restored under its own ID.
        var journal: UUID?

        var isEmpty: Bool { added + copies + folders + stickers == 0 }
    }

    enum Failure: LocalizedError {
        case notABackup, newer, archive

        var errorDescription: String? {
            switch self {
            case .notABackup: String(localized: "This file isn't a Swift Scribe backup.")
            case .newer: String(localized: "This backup was made by a newer version of Swift Scribe. Update the app, then restore it.")
            case .archive: String(localized: "The backup couldn't be written.")
            }
        }
    }


    static func fileName(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "Swift Scribe Backup \(formatter.string(from: now)).\(fileExtension)"
    }

    /// Writes a backup to a temporary file and returns it. Open notebooks should be saved first.
    static func create(root: StorageRoot, journal: UUID? = nil, now: Date = .now) throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appending(path: "backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        let staging = directory.appending(path: "info", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        var info: [String: JSONValue] = ["version": .number(Double(currentVersion)), "createdAt": ManifestCodec.encodeDate(now),
                                         "notebooks": .number(Double(root.packageIDs().count))]
        if let journal { info["journal"] = .string(journal.uuidString) }
        try JSONValue.object(info).serialized().write(to: staging.appending(path: infoFile))

        let destination = directory.appending(path: fileName(now: now))
        guard let keys = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD,MTM"),
              let file = ArchiveByteStream.fileStream(path: FilePath(destination.path(percentEncoded: false)), mode: .writeOnly,
                                                      options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o644)) else { throw Failure.archive }
        defer { try? file.close() }
        guard let compress = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: file) else { throw Failure.archive }
        defer { try? compress.close() }
        guard let encode = ArchiveStream.encodeStream(writingTo: compress) else { throw Failure.archive }
        defer { try? encode.close() }

        // Thumbnails are a cache, and a half-deleted notebook isn't part of the library.
        let filter: ArchiveHeader.EntryFilter = { message, path, _ in
            guard message == .searchPruneDirectory || message == .searchExclude else { return .ok }
            return path.lastComponent?.string == "thumbs" ? .skip : .ok
        }
        try encode.writeDirectoryContents(archiveFrom: FilePath(staging.path(percentEncoded: false)), keySet: keys)
        for folder in [root.library, root.stickers] where fileManager.fileExists(atPath: folder.path(percentEncoded: false)) {
            try encode.writeDirectoryContents(archiveFrom: FilePath(folder.deletingLastPathComponent().path(percentEncoded: false)),
                                              path: FilePath(folder.lastPathComponent), keySet: keys, selectUsing: filter)
        }
        return destination
    }

    private static func extract(_ archive: URL, to directory: URL) throws {
        guard let file = ArchiveByteStream.fileStream(path: FilePath(archive.path(percentEncoded: false)), mode: .readOnly, options: [],
                                                      permissions: FilePermissions(rawValue: 0o644)) else { throw Failure.notABackup }
        defer { try? file.close() }
        guard let decompress = ArchiveByteStream.decompressionStream(readingFrom: file) else { throw Failure.notABackup }
        defer { try? decompress.close() }
        guard let decode = ArchiveStream.decodeStream(readingFrom: decompress) else { throw Failure.notABackup }
        defer { try? decode.close() }
        // Nothing is written outside the folder the backup is unpacked into.
        let inside: ArchiveHeader.EntryFilter = { _, path, _ in
            path.isAbsolute || path.components.contains { $0.string == ".." } ? .skip : .ok
        }
        guard let extract = ArchiveStream.extractStream(extractingTo: FilePath(directory.path(percentEncoded: false)), selectUsing: inside,
                                                        flags: [.ignoreOperationNotPermitted]) else { throw Failure.notABackup }
        defer { try? extract.close() }
        do { _ = try ArchiveStream.process(readingFrom: decode, writingTo: extract) } catch { throw Failure.notABackup }
        let links = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])?
            .compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true } ?? []
        for link in links { try? FileManager.default.removeItem(at: link) }
    }

    /// Adds what the backup holds to the library and never replaces anything: a notebook the library has in a different
    /// state comes back beside it as a copy. The caller refreshes the index afterwards.
    static func restore(from archive: URL, into root: StorageRoot, keepsHistory: Bool = true) async throws -> Summary {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appending(path: "restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try extract(archive, to: directory)

        let info = (try? Data(contentsOf: directory.appending(path: infoFile))).flatMap { try? JSONValue.parse($0) }
        guard let version = info?["version"]?.doubleValue else { throw Failure.notABackup }
        guard Int(version) <= currentVersion else { throw Failure.newer }
        let backup = StorageRoot(url: directory)
        var summary = Summary()
        try fileManager.createDirectory(at: root.library, withIntermediateDirectories: true)

        var renamed: [UUID: UUID] = [:]
        for id in backup.packageIDs().sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let incoming = try? await NotebookPackage(root: backup, id: id).readManifest().manifest else {
                summary.unreadable += 1
                continue
            }
            let exists = fileManager.fileExists(atPath: root.package(id).path(percentEncoded: false))
            if !exists {
                try fileManager.moveItem(at: backup.package(id), to: root.package(id))
                summary.added += 1
                continue
            }
            let current = try? await NotebookPackage(root: root, id: id).readManifest().manifest
            if let current, current.modifiedAt == incoming.modifiedAt, current.pages.map(\.id) == incoming.pages.map(\.id) {
                summary.unchanged += 1
                continue
            }
            let copy = UUID()
            try fileManager.moveItem(at: backup.package(id), to: root.package(copy))
            let title = String(localized: "\(incoming.title) (from backup)")
            _ = try await NotebookPackage(root: root, id: copy).updateManifest { manifest in
                manifest.id = copy
                manifest.title = title
                manifest.library.deletedAt = nil
            }
            renamed[id] = copy
            summary.copies += 1
        }

        var folders = FolderFile.read(root)
        let known = Set(folders.folders.map(\.id))
        let incoming = FolderFile.read(backup).folders.filter { !known.contains($0.id) }
        if !incoming.isEmpty {
            let offset = (folders.folders.map(\.sortIndex).max() ?? -1) + 1
            folders.folders += incoming.map { entry in
                var entry = entry
                entry.sortIndex += offset
                return entry
            }
            try folders.write(root)
            summary.folders = incoming.count
        }

        for file in (try? fileManager.contentsOfDirectory(at: backup.stickers, includingPropertiesForKeys: nil)) ?? [] {
            let target = root.stickers.appending(path: file.lastPathComponent)
            guard !fileManager.fileExists(atPath: target.path(percentEncoded: false)) else { continue }
            try fileManager.createDirectory(at: root.stickers, withIntermediateDirectories: true)
            try fileManager.moveItem(at: file, to: target)
            summary.stickers += 1
        }

        if keepsHistory {
            var log = ActivityFile.read(root)
            let old = ActivityFile.read(backup)
            if !log.isNewerThanSupported, !old.isNewerThanSupported, old.hasPages {
                log.merge(old)
                try? ActivityFile.write(log, to: root)
            }
        }

        if let journal = info?["journal"]?.stringValue.flatMap(UUID.init(uuidString:)), renamed[journal] == nil,
           fileManager.fileExists(atPath: root.package(journal).path(percentEncoded: false)) {
            summary.journal = journal
        }
        return summary
    }
}

extension LibraryBackup.Summary {
    /// "Restored 12 notebooks. 3 came back as copies because the library has newer versions."
    var message: String {
        var parts: [String] = []
        if added > 0 { parts.append(added == 1 ? String(localized: "Restored 1 notebook.") : String(localized: "Restored \(added) notebooks.")) }
        if copies > 0 {
            parts.append(copies == 1 ? String(localized: "1 notebook differs from the one in your library, so it came back beside it as a copy.")
                                     : String(localized: "\(copies) notebooks differ from the ones in your library, so they came back beside them as copies."))
        }
        if unchanged > 0 {
            parts.append(unchanged == 1 ? String(localized: "1 notebook was already here.") : String(localized: "\(unchanged) notebooks were already here."))
        }
        if folders > 0 { parts.append(folders == 1 ? String(localized: "1 folder was added.") : String(localized: "\(folders) folders were added.")) }
        if stickers > 0 { parts.append(stickers == 1 ? String(localized: "1 sticker was added.") : String(localized: "\(stickers) stickers were added.")) }
        if unreadable > 0 {
            parts.append(unreadable == 1 ? String(localized: "1 notebook in the backup couldn't be read and was left out.")
                                         : String(localized: "\(unreadable) notebooks in the backup couldn't be read and were left out."))
        }
        return parts.isEmpty ? String(localized: "The backup had nothing in it.") : parts.joined(separator: " ")
    }
}
