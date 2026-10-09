import Foundation
import PencilKit
import CryptoKit

enum PackageError: LocalizedError, Equatable {
    case missing
    case unreadable
    case readOnly

    var errorDescription: String? {
        switch self {
        case .missing: String(localized: "The notebook's files couldn't be found.")
        case .unreadable: String(localized: "The notebook's files couldn't be read.")
        case .readOnly: String(localized: "This notebook was saved by a newer version of OwlLuna and can't be changed here.")
        }
    }
}

enum InkLoad: Sendable {
    case empty
    case ink(PKDrawing, hash: String)
    case quarantined(file: String)
    case cancelled
}

struct ManifestLoad: Sendable {
    var manifest: NotebookManifest
    var warnings: [String] = []
    var quarantined: [String] = []
    var recoveredPageIDs: [UUID] = []
    /// True when the loaded manifest differs from what's on disk and should be saved.
    var needsSave = false
    var isReadOnly: Bool { manifest.isNewerThanSupported }
}

struct SaveSnapshot: Sendable {
    var manifest: NotebookManifest
    var ink: [UUID: PKDrawing]
}

struct SaveReceipt: Sendable {
    var manifest: NotebookManifest
    var inkHashes: [UUID: String?]
    var inkBytes: [UUID: Int] = [:]
}

/// All file IO for one `<uuid>.owlluna` package. Ink files are written before the manifest,
/// every write is atomic, and nothing that fails to decode is ever overwritten.
actor NotebookPackage {
    nonisolated let id: UUID
    nonisolated let url: URL

    init(root: StorageRoot, id: UUID) {
        self.id = id
        self.url = root.package(id)
    }

    nonisolated var manifestURL: URL { url.appending(path: "manifest.json") }
    nonisolated var previousManifestURL: URL { url.appending(path: "manifest.prev.json") }
    nonisolated var inkDirectory: URL { url.appending(path: "ink", directoryHint: .isDirectory) }
    nonisolated var assetsDirectory: URL { url.appending(path: "assets", directoryHint: .isDirectory) }
    nonisolated var thumbsDirectory: URL { url.appending(path: "thumbs", directoryHint: .isDirectory) }
    nonisolated var textDirectory: URL { url.appending(path: "text", directoryHint: .isDirectory) }

    nonisolated func inkURL(_ pageID: UUID) -> URL { inkDirectory.appending(path: "\(pageID.uuidString).pkdrawing") }
    nonisolated func assetURL(_ file: String) -> URL { assetsDirectory.appending(path: file) }
    nonisolated func textURL(_ pageID: UUID) -> URL { textDirectory.appending(path: "\(pageID.uuidString).txt") }
    nonisolated func thumbURL(_ pageID: UUID, key: String) -> URL {
        thumbsDirectory.appending(path: "\(pageID.uuidString)-\(key).png")
    }

    // MARK: Create

    func create(_ manifest: NotebookManifest) throws {
        try makeDirectories()
        guard !FileManager.default.fileExists(atPath: manifestURL.path(percentEncoded: false)) else { return }
        try ManifestCodec.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    private func makeDirectories() throws {
        for directory in [url, inkDirectory, assetsDirectory, thumbsDirectory, textDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: Read

    func readManifest() throws -> ManifestLoad {
        var quarantined: [String] = []
        var loaded: (manifest: NotebookManifest, warnings: [String])?
        var source: URL?

        for candidate in [manifestURL, previousManifestURL] {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            do {
                loaded = try ManifestCodec.decode(data, fallbackID: id, fallbackDate: creationDate(of: candidate))
                source = candidate
                break
            } catch {
                let moved = try Quarantine.move(candidate)
                quarantined.append(moved.lastPathComponent)
            }
        }

        var load: ManifestLoad
        if let loaded, let source {
            load = ManifestLoad(manifest: loaded.manifest, warnings: loaded.warnings)
            if source == previousManifestURL {
                load.warnings.append("the latest manifest was unreadable; opened the previous version")
                load.needsSave = true
            }
            load.quarantined = quarantined
            recoverOrphans(into: &load, manifestDate: modificationDate(of: source) ?? .distantPast)
        } else if !quarantined.isEmpty || !inkFiles().isEmpty {
            load = ManifestLoad(manifest: rebuiltManifest(), warnings: ["the manifest was missing or unreadable; rebuilt from ink files"])
            load.quarantined = quarantined
            load.needsSave = true
        } else {
            throw quarantined.isEmpty ? PackageError.missing : PackageError.unreadable
        }
        return load
    }

    /// Ink files the manifest doesn't list but that are newer than it were written just before a crash.
    private func recoverOrphans(into load: inout ManifestLoad, manifestDate: Date) {
        var known = Set(load.manifest.pages.map(\.id))
        for opaque in load.manifest.opaquePages {
            if let id = opaque.raw["id"]?.stringValue.flatMap(UUID.init(uuidString:)) { known.insert(id) }
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: inkDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let orphans = files.compactMap { file -> (UUID, Date)? in
            guard file.pathExtension == "pkdrawing",
                  let pageID = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  !known.contains(pageID),
                  let date = modificationDate(of: file), date > manifestDate else { return nil }
            return (pageID, date)
        }.sorted { $0.1 < $1.1 }
        guard !orphans.isEmpty else { return }
        for (pageID, _) in orphans {
            var page = load.manifest.defaults.newPage()
            page.id = pageID
            page.inkHash = (try? Data(contentsOf: inkURL(pageID))).map(Self.hash)
            load.manifest.pages.append(page)
            load.recoveredPageIDs.append(pageID)
        }
        load.warnings.append("recovered \(orphans.count) page(s) written just before the app last quit")
        load.needsSave = true
    }

    private func inkFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: inkDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "pkdrawing" }
    }

    private func rebuiltManifest() -> NotebookManifest {
        let pages = inkFiles()
            .compactMap { file -> (UUID, Date)? in
                UUID(uuidString: file.deletingPathExtension().lastPathComponent).map { ($0, modificationDate(of: file) ?? .distantPast) }
            }
            .sorted { $0.1 < $1.1 }
            .map { pageID, _ -> NotebookPage in
                var page = NotebookPage.template(.blank, color: .white, size: .letter)
                page.id = pageID
                page.inkHash = (try? Data(contentsOf: inkURL(pageID))).map(Self.hash)
                return page
            }
        var manifest = NotebookManifest(id: id, title: "Recovered Notebook",
                                        defaults: PageDefaults(template: .blank, paperColor: .white, pageSize: .letter),
                                        pages: pages.isEmpty ? [.template(.blank, color: .white, size: .letter)] : pages)
        manifest.createdAt = creationDate(of: url)
        manifest.extra[Self.rebuiltKey] = .bool(true)
        return manifest
    }

    /// Marks a manifest rebuilt from ink alone, whose assets may still be listed only in a quarantined copy.
    static let rebuiltKey = "rebuiltFromInk"

    /// Reads and decodes off the actor, so page loads run in parallel at their task's priority instead of
    /// queueing behind each other and behind saves. Only setting a damaged file aside goes through the actor.
    nonisolated func readInk(_ pageID: UUID) async -> InkLoad {
        if Task.isCancelled { return .cancelled }
        guard let data = try? Data(contentsOf: inkURL(pageID)) else { return .empty }
        if let drawing = try? Self.decodeInk(data) { return .ink(drawing, hash: Self.hash(data)) }
        return await quarantineInk(pageID)
    }

    private func quarantineInk(_ pageID: UUID) -> InkLoad {
        let file = inkURL(pageID)
        guard let data = try? Data(contentsOf: file) else { return .empty }
        if let drawing = try? Self.decodeInk(data) { return .ink(drawing, hash: Self.hash(data)) }
        guard let moved = try? Quarantine.move(file) else { return .quarantined(file: file.lastPathComponent) }
        return .quarantined(file: "ink/\(moved.lastPathComponent)")
    }

    func readText(_ pageID: UUID) -> String? {
        try? String(contentsOf: textURL(pageID), encoding: .utf8)
    }

    // MARK: Write

    /// Writes the given pages' ink, each atomically, then the manifest last. Throws on the first failure;
    /// callers keep those pages dirty and retry.
    func write(_ snapshot: SaveSnapshot) throws -> SaveReceipt {
        guard !snapshot.manifest.isNewerThanSupported else { throw PackageError.readOnly }
        try makeDirectories()
        var manifest = snapshot.manifest
        var hashes: [UUID: String?] = [:]
        var bytes: [UUID: Int] = [:]
        for (pageID, drawing) in snapshot.ink {
            let file = inkURL(pageID)
            if drawing.strokes.isEmpty {
                if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: file)
                }
                hashes[pageID] = .some(nil)
            } else {
                let data = drawing.dataRepresentation()
                try data.write(to: file, options: .atomic)
                hashes[pageID] = Self.hash(data)
                bytes[pageID] = data.count
            }
        }
        for index in manifest.pages.indices {
            if let hash = hashes[manifest.pages[index].id] { manifest.pages[index].inkHash = hash }
        }
        try writeManifest(manifest)
        return SaveReceipt(manifest: manifest, inkHashes: hashes, inkBytes: bytes)
    }

    func writeManifest(_ manifest: NotebookManifest) throws {
        guard !manifest.isNewerThanSupported else { throw PackageError.readOnly }
        try makeDirectories()
        let data = try ManifestCodec.encode(manifest)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) {
            try? fileManager.removeItem(at: previousManifestURL)
            try? fileManager.copyItem(at: manifestURL, to: previousManifestURL)
        }
        try data.write(to: manifestURL, options: .atomic)
    }

    /// Read-modify-write of the manifest for library changes to a notebook that isn't open.
    func updateManifest(_ change: @Sendable (inout NotebookManifest) -> Void) throws -> NotebookManifest {
        var manifest = try readManifest().manifest
        change(&manifest)
        try writeManifest(manifest)
        return manifest
    }

    func writeText(_ text: String, pageID: UUID) throws {
        try makeDirectoryInExistingPackage(textDirectory)
        try Data(text.utf8).write(to: textURL(pageID), options: .atomic)
    }

    func writeThumbnail(_ png: Data, pageID: UUID, key: String) throws {
        try makeDirectoryInExistingPackage(thumbsDirectory)
        try png.write(to: thumbURL(pageID, key: key), options: .atomic)
    }

    /// Background jobs (OCR, thumbnails) must never bring back a package that was deleted while they ran.
    private func makeDirectoryInExistingPackage(_ directory: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) else { throw PackageError.missing }
        guard !fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    // MARK: Assets

    func importAsset(from source: URL, ext: String) throws -> String {
        try makeDirectories()
        let name = "\(UUID().uuidString).\(ext)"
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: assetURL(name))
        return name
    }

    func writeAsset(_ data: Data, ext: String) throws -> String {
        try makeDirectories()
        let name = "\(UUID().uuidString).\(ext)"
        try data.write(to: assetURL(name), options: .atomic)
        return name
    }

    // MARK: Transcripts

    nonisolated func transcriptTextURL(_ recordingID: UUID) -> URL { textDirectory.appending(path: "\(recordingID.uuidString).txt") }

    /// A transcript is kept with the assets under a name the recording's entry holds; its words are also kept as
    /// plain text beside the pages' recognised text, so search finds them.
    func writeTranscript(_ transcript: Transcript, recordingID: UUID) throws -> String {
        let file = try writeAsset(JSONEncoder().encode(transcript), ext: "json")
        try makeDirectoryInExistingPackage(textDirectory)
        try Data(transcript.text.utf8).write(to: transcriptTextURL(recordingID), options: .atomic)
        return file
    }

    nonisolated func readTranscript(_ file: String) -> Transcript? {
        (try? Data(contentsOf: assetURL(file))).flatMap { try? JSONDecoder().decode(Transcript.self, from: $0) }
    }

    func removeTranscriptText(_ recordingID: UUID) {
        try? FileManager.default.removeItem(at: transcriptTextURL(recordingID))
    }

    func removeAsset(_ file: String) {
        try? FileManager.default.removeItem(at: assetURL(file))
    }

    // MARK: Maintenance

    /// Removes ink, text, thumbnails and assets that the saved manifest no longer references.
    /// Only call once the manifest is on disk and no undo history can bring those pages back.
    /// Nothing but stale thumbnails is removed while a damaged manifest is set aside or the manifest was
    /// rebuilt, since the files may be all that's left of what the damaged copy listed.
    func collectGarbage(keeping manifest: NotebookManifest) {
        let fileManager = FileManager.default
        let currentThumbs = Set(manifest.pages.flatMap { page in
            [page.thumbnailKey, page.thumbnailKey + PageThumbnailer.nightSuffix].map { thumbURL(page.id, key: $0).lastPathComponent }
        })
        for file in (try? fileManager.contentsOfDirectory(at: thumbsDirectory, includingPropertiesForKeys: nil)) ?? []
        where !currentThumbs.contains(file.lastPathComponent) {
            try? fileManager.removeItem(at: file)
        }
        guard manifest.extra[Self.rebuiltKey] == nil, !hasQuarantinedManifest() else { return }

        let manifestDate = modificationDate(of: manifestURL) ?? .distantPast
        var keep = Set(manifest.pages.map(\.id.uuidString))
        for opaque in manifest.opaquePages { if let id = opaque.raw["id"]?.stringValue { keep.insert(id.uppercased()) } }
        for recording in manifest.recordings where recording.transcriptFile != nil { keep.insert(recording.id.uuidString) }
        for directory in [inkDirectory, textDirectory] {
            for file in (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                guard !file.lastPathComponent.contains(".corrupt") else { continue }
                let pageID = String(file.deletingPathExtension().lastPathComponent.prefix(36)).uppercased()
                guard UUID(uuidString: pageID) != nil, !keep.contains(pageID),
                      (modificationDate(of: file) ?? .distantFuture) <= manifestDate else { continue }
                try? fileManager.removeItem(at: file)
            }
        }
        let referenced = Self.strings(in: ManifestCodec.encodeValue(manifest))
        for file in (try? fileManager.contentsOfDirectory(at: assetsDirectory, includingPropertiesForKeys: nil)) ?? [] {
            let name = file.lastPathComponent
            guard !referenced.contains(name), !referenced.contains("assets/\(name)"),
                  (modificationDate(of: file) ?? .distantFuture) <= manifestDate else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    private func hasQuarantinedManifest() -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []
        return files.contains { $0.hasPrefix("manifest") && $0.contains(".corrupt") }
    }

    /// Every string anywhere in the manifest, so an asset named by a field this version can't read is still kept.
    private static func strings(in value: JSONValue) -> Set<String> {
        switch value {
        case .string(let string): [string]
        case .array(let values): values.reduce(into: []) { $0.formUnion(strings(in: $1)) }
        case .object(let object): object.values.reduce(into: []) { $0.formUnion(strings(in: $1)) }
        case .null, .bool, .number: []
        }
    }

    func quarantinedFiles() -> [String] {
        let fileManager = FileManager.default
        return [url, inkDirectory].flatMap { directory in
            ((try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.contains(".corrupt") }
                .map { $0.path(percentEncoded: false).replacingOccurrences(of: url.path(percentEncoded: false), with: "") }
        }
    }

    // MARK: Helpers

    /// PencilKit decodes data without its format header as an empty drawing instead of failing, so an
    /// empty result only counts when the header is there and the file is small enough to be an empty drawing.
    static func decodeInk(_ data: Data) throws -> PKDrawing {
        let drawing = try PKDrawing(data: data)
        if drawing.strokes.isEmpty, !data.starts(with: [0x77, 0x72, 0x64]) || data.count > 1024 {
            throw CocoaError(.fileReadCorruptFile)
        }
        return drawing
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated func modificationDate(of file: URL) -> Date? {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private nonisolated func creationDate(of file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .now
    }
}
