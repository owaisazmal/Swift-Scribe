import Foundation

/// Where everything lives. The app uses `.live`; tests pass a temporary directory.
struct StorageRoot: Sendable, Hashable {
    let url: URL

    var library: URL { url.appending(path: "Library", directoryHint: .isDirectory) }
    var foldersFile: URL { library.appending(path: "folders.json") }
    var indexStore: URL { url.appending(path: "LibraryIndex.store") }
    var activityFile: URL { library.appending(path: "activity.json") }
    var deleting: URL { url.appending(path: "Deleting", directoryHint: .isDirectory) }
    var stickers: URL { url.appending(path: "Stickers", directoryHint: .isDirectory) }

    func package(_ id: UUID) -> URL {
        library.appending(path: "\(id.uuidString).\(Self.packageExtension)", directoryHint: .isDirectory)
    }

    static let packageExtension = "scribe"

    static let live: StorageRoot = {
        if let override = ProcessInfo.processInfo.environment["SCRIBE_STORAGE_ROOT"] {
            return StorageRoot(url: URL(filePath: override, directoryHint: .isDirectory))
        }
        return StorageRoot(url: URL.applicationSupportDirectory)
    }()

    func packageIDs() -> [UUID] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? []
        return contents.compactMap { url in
            url.pathExtension == Self.packageExtension ? UUID(uuidString: url.deletingPathExtension().lastPathComponent) : nil
        }
    }
}

enum Quarantine {
    /// Renames a damaged file to `<name>.corrupt` (or `.corrupt-2`, …) so it's kept and never overwritten.
    @discardableResult
    static func move(_ url: URL) throws -> URL {
        let fileManager = FileManager.default
        var target = url.appendingPathExtension("corrupt")
        var suffix = 2
        while fileManager.fileExists(atPath: target.path(percentEncoded: false)) {
            target = url.appendingPathExtension("corrupt-\(suffix)")
            suffix += 1
        }
        try fileManager.moveItem(at: url, to: target)
        return target
    }
}
