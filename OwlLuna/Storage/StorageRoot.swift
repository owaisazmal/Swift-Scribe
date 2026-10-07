import Foundation
import os

/// Where everything lives. The app uses `.live`; tests pass a temporary directory.
struct StorageRoot: Sendable, Hashable {
    private static let log = Logger(subsystem: "com.owais.OwlLuna", category: "storage")

    let url: URL

    var library: URL { url.appending(path: "Library", directoryHint: .isDirectory) }
    var foldersFile: URL { library.appending(path: "folders.json") }
    var indexStore: URL { url.appending(path: "LibraryIndex.store") }
    var activityFile: URL { library.appending(path: "activity.json") }
    var smartShelvesFile: URL { library.appending(path: "smart-shelves.json") }
    var deleting: URL { url.appending(path: "Deleting", directoryHint: .isDirectory) }
    var stickers: URL { url.appending(path: "Stickers", directoryHint: .isDirectory) }

    func package(_ id: UUID) -> URL {
        library.appending(path: "\(id.uuidString).\(Self.packageExtension)", directoryHint: .isDirectory)
    }

    static let packageExtension = "owlluna"
    static let legacyPackageExtension = "scribe"

    static let live: StorageRoot = {
        if let override = ProcessInfo.processInfo.environment["OWLLUNA_STORAGE_ROOT"] {
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

    /// Renames the `<uuid>.scribe` packages an older build wrote, and returns their IDs. One that already has a
    /// successor is left as it is; so is anything that isn't named by a UUID.
    @discardableResult
    func adoptLegacyPackages() -> [UUID] {
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? []
        return contents.compactMap { url in
            guard url.pathExtension == Self.legacyPackageExtension, let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  !fileManager.fileExists(atPath: package(id).path(percentEncoded: false)) else { return nil }
            do {
                try fileManager.moveItem(at: url, to: package(id))
                return id
            } catch {
                Self.log.error("could not adopt \(url.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
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
