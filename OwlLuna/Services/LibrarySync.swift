import Foundation
import os

/// The synced copy of the library: the app's iCloud container on a device, or any folder in tests.
/// The library the app works in always stays on the device; syncing copies whole notebooks to and from this folder.
struct CloudFolder: Sendable, Hashable {
    let url: URL
    /// True for a real iCloud container, whose files may still need downloading before they can be read.
    var isUbiquitous = false

    var library: URL { url.appending(path: "Library", directoryHint: .isDirectory) }
    var stickers: URL { url.appending(path: "Stickers", directoryHint: .isDirectory) }
    var tombstones: URL { url.appending(path: "Deleted", directoryHint: .isDirectory) }
    var foldersFile: URL { library.appending(path: "folders.json") }

    func package(_ id: UUID) -> URL {
        library.appending(path: "\(id.uuidString).\(StorageRoot.packageExtension)", directoryHint: .isDirectory)
    }

    func tombstone(_ id: UUID) -> URL { tombstones.appending(path: id.uuidString) }
}

/// What this device and the synced copy agreed on last time, kept on the device. It is what tells a notebook that was
/// deleted elsewhere from one that was never uploaded, and a change made here from one made there.
struct SyncState: Sendable, Equatable {
    /// Each notebook's modification date when it was last in step.
    var notebooks: [UUID: Date] = [:]
    var folders: Set<UUID> = []
    var stickers: Set<String> = []

    static func file(_ root: StorageRoot) -> URL { root.url.appending(path: "sync-state.json") }

    static func read(_ root: StorageRoot) -> SyncState {
        guard let data = try? Data(contentsOf: file(root)), let json = try? JSONValue.parse(data) else { return SyncState() }
        var state = SyncState()
        for (key, value) in json["notebooks"]?.objectValue ?? [:] {
            if let id = UUID(uuidString: key), let date = value.stringValue.flatMap(ManifestCodec.parseDate) { state.notebooks[id] = date }
        }
        state.folders = Set(json["folders"]?.arrayValue?.compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) } ?? [])
        state.stickers = Set(json["stickers"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        return state
    }

    func write(_ root: StorageRoot) throws {
        let json = JSONValue.object([
            "notebooks": .object(Dictionary(uniqueKeysWithValues: notebooks.map { ($0.key.uuidString, ManifestCodec.encodeDate($0.value)) })),
            "folders": .array(folders.map { .string($0.uuidString) }.sorted { ($0.stringValue ?? "") < ($1.stringValue ?? "") }),
            "stickers": .array(stickers.sorted().map(JSONValue.string)),
        ])
        try json.serialized().write(to: Self.file(root), options: .atomic)
    }
}

struct SyncReport: Sendable, Equatable {
    /// Notebooks sent to the synced copy, and notebooks brought in from it.
    var pushed: [UUID] = []
    var pulled: [UUID] = []
    /// Notebooks removed here because they were deleted on another device, and removed from the synced copy because they were deleted here.
    var removedHere: [UUID] = []
    var removedThere: [UUID] = []
    /// Notebooks changed on two devices since they last agreed: the older version was kept as a copy under this new ID.
    var conflictCopies: [UUID] = []
    /// Notebooks left for next time because they are open here or still arriving.
    var waiting: [UUID] = []
    var foldersChanged = false
    var stickersChanged = false

    var changedHere: Bool { !pulled.isEmpty || !removedHere.isEmpty || !conflictCopies.isEmpty || foldersChanged || stickersChanged }
}

/// Brings this device's library and the synced copy into step, one notebook at a time. Nothing is merged inside a
/// notebook: the newer version wins, and when both sides changed since they last agreed the older is kept as a copy,
/// so a sync never loses writing.
enum LibrarySync {
    private static let log = Logger(subsystem: "com.owais.OwlLuna", category: "sync")

    /// When a notebook was last changed, read straight from its manifest.
    static func stamp(ofPackage url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url.appending(path: "manifest.json")), let json = try? JSONValue.parse(data) else { return nil }
        return json["modifiedAt"]?.stringValue.flatMap(ManifestCodec.parseDate)
    }

    private static func same(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.timeIntervalSince(b)) < 0.002
    }

    private static func packageIDs(in directory: URL) -> Set<UUID> {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return Set(contents.compactMap { url -> UUID? in
            // A notebook that hasn't been downloaded yet is listed as ".<name>.icloud".
            var name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") { name = String(name.dropFirst().dropLast(7)) }
            guard name.hasSuffix(".\(StorageRoot.packageExtension)") else { return nil }
            return UUID(uuidString: String(name.dropLast(StorageRoot.packageExtension.count + 1)))
        })
    }

    /// `busy` names the notebooks open in an editor here; they are left alone until they close.
    static func run(root: StorageRoot, cloud: CloudFolder, busy: Set<UUID> = []) async throws -> SyncReport {
        let fileManager = FileManager.default
        for directory in [root.library, cloud.library, cloud.tombstones] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if cloud.isUbiquitous { await CloudFiles.download(cloud.url) }
        var state = SyncState.read(root)
        var report = SyncReport()
        let here = Set(root.packageIDs()), there = packageIDs(in: cloud.library)
        let deleted = Set(((try? fileManager.contentsOfDirectory(atPath: cloud.tombstones.path(percentEncoded: false))) ?? []).compactMap(UUID.init(uuidString:)))

        for id in here.union(there).union(state.notebooks.keys).sorted(by: { $0.uuidString < $1.uuidString }) {
            guard !busy.contains(id) else { report.waiting.append(id); continue }
            let local = here.contains(id) ? stamp(ofPackage: root.package(id)) : nil
            let remote = there.contains(id) ? stamp(ofPackage: cloud.package(id)) : nil
            let agreed = state.notebooks[id]
            let isHere = here.contains(id), isThere = there.contains(id)
            if (isHere && local == nil) || (isThere && remote == nil) {
                // A manifest that can't be read yet (still arriving, or damaged) is never copied over a good one.
                report.waiting.append(id)
                continue
            }
            do {
                switch (isHere, isThere) {
                case (true, true):
                    if same(local, remote) {
                        state.notebooks[id] = local
                    } else if agreed != nil, same(local, agreed) {
                        try pull(id, from: cloud, into: root)
                        state.notebooks[id] = remote
                        report.pulled.append(id)
                    } else if agreed != nil, same(remote, agreed) {
                        try push(id, from: root, to: cloud)
                        state.notebooks[id] = local
                        report.pushed.append(id)
                    } else {
                        let copy = try await resolveConflict(id, local: local!, remote: remote!, root: root, cloud: cloud)
                        state.notebooks[id] = max(local!, remote!)
                        report.conflictCopies.append(copy)
                        if remote! > local! { report.pulled.append(id) } else { report.pushed.append(id) }
                    }
                case (true, false):
                    if deleted.contains(id), agreed != nil, same(local, agreed) {
                        try remove(root.package(id), root: root)
                        state.notebooks[id] = nil
                        report.removedHere.append(id)
                    } else {
                        // New here, or changed here after it was deleted elsewhere: writing wins over a delete.
                        try? fileManager.removeItem(at: cloud.tombstone(id))
                        try push(id, from: root, to: cloud)
                        state.notebooks[id] = local
                        report.pushed.append(id)
                    }
                case (false, true):
                    if agreed != nil {
                        // It was here and in step, and now it's gone: it was deleted on this device.
                        try Data().write(to: cloud.tombstone(id))
                        try coordinated(writing: cloud.package(id)) { try fileManager.removeItem(at: $0) }
                        state.notebooks[id] = nil
                        report.removedThere.append(id)
                    } else if deleted.contains(id) {
                        try coordinated(writing: cloud.package(id)) { try fileManager.removeItem(at: $0) }
                    } else {
                        try pull(id, from: cloud, into: root)
                        state.notebooks[id] = remote
                        report.pulled.append(id)
                    }
                case (false, false):
                    state.notebooks[id] = nil
                }
            } catch {
                log.error("sync of \(id) failed: \(error.localizedDescription)")
                report.waiting.append(id)
            }
        }

        report.foldersChanged = try syncFolders(root: root, cloud: cloud, state: &state)
        report.stickersChanged = try syncStickers(root: root, cloud: cloud, state: &state)
        try state.write(root)
        return report
    }

    // MARK: Copying notebooks

    /// Thumbnails are made again where they're needed, and a file set aside as damaged stays on the device it was found on.
    private static func travels(_ relative: String) -> Bool {
        !relative.hasPrefix("thumbs/") && relative != "thumbs" && !relative.contains(".corrupt")
    }

    private static func files(in package: URL) -> [String: URL] {
        var result: [String: URL] = [:]
        let base = package.standardizedFileURL.path(percentEncoded: false)
        let enumerator = FileManager.default.enumerator(at: package, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let relative = String(url.standardizedFileURL.path(percentEncoded: false).dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if travels(relative) { result[relative] = url }
        }
        return result
    }

    /// A copy keeps its original's modification date, so a file of the same size written at the same instant is the
    /// same file. The manifests are small and decide everything, so they are always copied.
    private static func unchanged(_ relative: String, _ a: URL, _ b: URL) -> Bool {
        guard !relative.hasPrefix("manifest") else { return false }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let first = try? a.resourceValues(forKeys: keys), let second = try? b.resourceValues(forKeys: keys),
              let written = first.contentModificationDate, let copied = second.contentModificationDate else { return false }
        return first.fileSize == second.fileSize && abs(written.timeIntervalSince(copied)) < 0.000_002
    }

    /// Makes `destination` hold what `source` holds: files that differ are copied, files that are gone are removed,
    /// and the manifest goes last so a reader never sees it name ink that hasn't arrived.
    private static func mirror(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let wanted = files(in: source), present = files(in: destination)
        for (relative, url) in wanted.sorted(by: { ($0.key == "manifest.json" ? 1 : 0, $0.key) < ($1.key == "manifest.json" ? 1 : 0, $1.key) }) {
            let target = destination.appending(path: relative)
            if let existing = present[relative], unchanged(relative, url, existing) { continue }
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let staged = target.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).part")
            try fileManager.copyItem(at: url, to: staged)
            _ = try fileManager.replaceItemAt(target, withItemAt: staged)
        }
        for (relative, url) in present where wanted[relative] == nil { try? fileManager.removeItem(at: url) }
    }

    private static func coordinated(writing url: URL, _ work: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { granted in
            do { try work(granted) } catch { failure = error }
        }
        if let error = coordinationError ?? failure { throw error }
    }

    private static func coordinated(reading url: URL, _ work: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { granted in
            do { try work(granted) } catch { failure = error }
        }
        if let error = coordinationError ?? failure { throw error }
    }

    private static func push(_ id: UUID, from root: StorageRoot, to cloud: CloudFolder) throws {
        try coordinated(writing: cloud.package(id)) { try mirror(root.package(id), to: $0) }
    }

    /// The notebook is assembled beside the library and swapped in whole, so a pull that stops halfway changes nothing.
    private static func pull(_ id: UUID, from cloud: CloudFolder, into root: StorageRoot) throws {
        let fileManager = FileManager.default
        let staging = root.url.appending(path: "Arriving/\(id.uuidString)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let target = root.package(id)
        if fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
            // Starting from what is here means only the pages that changed are copied.
            try fileManager.copyItem(at: target, to: staging)
        }
        try coordinated(reading: cloud.package(id)) { try mirror($0, to: staging) }
        guard stamp(ofPackage: staging) != nil else { throw PackageError.unreadable }
        try? fileManager.removeItem(at: staging.appending(path: "thumbs"))
        try fileManager.setAttributes([.modificationDate: Date.now], ofItemAtPath: staging.appending(path: "manifest.json").path(percentEncoded: false))
        if fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(target, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: target)
        }
    }

    private static func remove(_ package: URL, root: StorageRoot) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root.deleting, withIntermediateDirectories: true)
        let tombstone = root.deleting.appending(path: "\(package.deletingPathExtension().lastPathComponent)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.moveItem(at: package, to: tombstone)
        try? fileManager.removeItem(at: tombstone)
    }

    /// Both sides changed. The newer keeps the notebook's identity everywhere; the older is kept here as a notebook of
    /// its own, which the next pass uploads like any new notebook. Returns the copy's ID.
    private static func resolveConflict(_ id: UUID, local: Date, remote: Date, root: StorageRoot, cloud: CloudFolder) async throws -> UUID {
        let fileManager = FileManager.default
        let copy = UUID()
        if remote > local {
            try fileManager.moveItem(at: root.package(id), to: root.package(copy))
            try pull(id, from: cloud, into: root)
        } else {
            try coordinated(reading: cloud.package(id)) { try mirror($0, to: root.package(copy)) }
            try push(id, from: root, to: cloud)
        }
        _ = try await NotebookPackage(root: root, id: copy).updateManifest { manifest in
            manifest.id = copy
            manifest.title = String(localized: "\(manifest.title) (conflicted copy)")
            manifest.library.isFavorite = false
        }
        return copy
    }

    // MARK: Folders and stickers

    /// A three-way merge on which folders exist: one added on either side is kept, one deleted on either side goes.
    /// For a folder both sides have, the copy from the more recently written file is used.
    private static func syncFolders(root: StorageRoot, cloud: CloudFolder, state: inout SyncState) throws -> Bool {
        let local = FolderFile.read(root)
        var remote = FolderFile()
        if let data = try? Data(contentsOf: cloud.foldersFile) {
            let scratch = StorageRoot(url: FileManager.default.temporaryDirectory.appending(path: "folders-\(UUID().uuidString)", directoryHint: .isDirectory))
            try FileManager.default.createDirectory(at: scratch.library, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch.url) }
            try data.write(to: scratch.foldersFile)
            remote = FolderFile.read(scratch)
        }
        func modified(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        let localIsNewer = modified(root.foldersFile) >= modified(cloud.foldersFile)
        let localByID = Dictionary(local.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteByID = Dictionary(remote.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged: [FolderEntry] = []
        for id in (localIsNewer ? local.folders + remote.folders : remote.folders + local.folders).map(\.id) where !merged.contains(where: { $0.id == id }) {
            let wasAgreed = state.folders.contains(id)
            switch (localByID[id], remoteByID[id]) {
            case (let here?, let there?): merged.append(localIsNewer ? here : there)
            case (let here?, nil): if !wasAgreed { merged.append(here) }
            case (nil, let there?): if !wasAgreed { merged.append(there) }
            case (nil, nil): break
            }
        }
        let ids = Set(merged.map(\.id))
        merged = merged.map { entry in
            var entry = entry
            if let parent = entry.parentID, !ids.contains(parent) { entry.parentID = nil }
            return entry
        }
        state.folders = ids
        var changedHere = false
        if merged != local.folders {
            var file = local
            file.folders = merged
            try file.write(root)
            changedHere = true
        }
        if merged != remote.folders {
            var file = remote
            file.folders = merged
            let scratch = StorageRoot(url: FileManager.default.temporaryDirectory.appending(path: "folders-\(UUID().uuidString)", directoryHint: .isDirectory))
            defer { try? FileManager.default.removeItem(at: scratch.url) }
            try file.write(scratch)
            let data = try Data(contentsOf: scratch.foldersFile)
            try coordinated(writing: cloud.foldersFile) { try data.write(to: $0, options: .atomic) }
        }
        return changedHere
    }

    private static func syncStickers(root: StorageRoot, cloud: CloudFolder, state: inout SyncState) throws -> Bool {
        let fileManager = FileManager.default
        func names(_ directory: URL) -> Set<String> {
            Set(((try? fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []).filter { $0.hasSuffix(".png") })
        }
        let here = names(root.stickers), there = names(cloud.stickers)
        var changedHere = false
        for name in here.union(there) {
            let agreed = state.stickers.contains(name)
            switch (here.contains(name), there.contains(name)) {
            case (true, false):
                if agreed {
                    try? fileManager.removeItem(at: root.stickers.appending(path: name))
                    changedHere = true
                } else {
                    try fileManager.createDirectory(at: cloud.stickers, withIntermediateDirectories: true)
                    try coordinated(writing: cloud.stickers.appending(path: name)) { try fileManager.copyItem(at: root.stickers.appending(path: name), to: $0) }
                }
            case (false, true):
                if agreed {
                    try coordinated(writing: cloud.stickers.appending(path: name)) { try fileManager.removeItem(at: $0) }
                } else {
                    try fileManager.createDirectory(at: root.stickers, withIntermediateDirectories: true)
                    try fileManager.copyItem(at: cloud.stickers.appending(path: name), to: root.stickers.appending(path: name))
                    changedHere = true
                }
            default:
                break
            }
        }
        state.stickers = names(root.stickers).intersection(names(cloud.stickers))
        return changedHere
    }
}

/// Getting files in an iCloud container onto the device before they are read. Not used for a plain folder.
enum CloudFiles {
    /// Asks for everything under `url` to be downloaded and waits, up to `timeout`, for it to arrive.
    static func download(_ url: URL, timeout: Duration = .seconds(60)) async {
        let fileManager = FileManager.default
        func pending() -> [URL] {
            var result: [URL] = []
            let keys: [URLResourceKey] = [.ubiquitousItemDownloadingStatusKey, .isDirectoryKey]
            let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: [])
            while let item = enumerator?.nextObject() as? URL {
                let name = item.lastPathComponent
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    result.append(item.deletingLastPathComponent().appending(path: String(name.dropFirst().dropLast(7))))
                } else if let status = (try? item.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus,
                          status == .notDownloaded {
                    result.append(item)
                }
            }
            return result
        }
        let deadline = ContinuousClock.now + timeout
        var waiting = pending()
        while !waiting.isEmpty, ContinuousClock.now < deadline {
            for item in waiting { try? fileManager.startDownloadingUbiquitousItem(at: item) }
            try? await Task.sleep(for: .milliseconds(500))
            waiting = pending()
        }
    }
}
