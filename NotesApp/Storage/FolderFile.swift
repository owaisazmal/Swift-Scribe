import Foundation

struct FolderEntry: Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var clothRaw: String
    var createdAt: Date
    var sortIndex: Int
    /// The folder this one sits inside. Older builds keep the key and show the folder at the top level.
    var parentID: UUID?
    var extra: [String: JSONValue] = [:]
    var undecoded: [String: UndecodedField] = [:]

    var cloth: ClothColor {
        get { ClothColor(rawValue: clothRaw) ?? .slate }
        set { clothRaw = newValue.rawValue }
    }
}

/// `Library/folders.json`, the durable list of folders the index is rebuilt from.
struct FolderFile: Sendable, Hashable {
    var folders: [FolderEntry] = []
    var opaque: [JSONValue] = []

    static func read(_ root: StorageRoot) -> FolderFile {
        guard let data = try? Data(contentsOf: root.foldersFile) else { return FolderFile() }
        guard let values = (try? JSONValue.parse(data))?["folders"]?.arrayValue else {
            _ = try? Quarantine.move(root.foldersFile)
            return FolderFile()
        }
        var file = FolderFile()
        for raw in values {
            guard let object = raw.objectValue,
                  let id = object["id"]?.stringValue.flatMap(UUID.init(uuidString:)),
                  let name = object["name"]?.stringValue else {
                file.opaque.append(raw)
                continue
            }
            var reader = ObjectReader(object)
            _ = reader.take("id")
            _ = reader.take("name")
            let cloth = reader.string("cloth", default: ClothColor.slate.rawValue)
            let createdAt = reader.date("createdAt", default: .now)
            let sortIndex = reader.int("sortIndex", default: file.folders.count)
            let parent = reader.take("parent")?.stringValue.flatMap(UUID.init(uuidString:))
            file.folders.append(FolderEntry(id: id, name: name, clothRaw: cloth, createdAt: createdAt, sortIndex: sortIndex, parentID: parent,
                                            extra: reader.remaining, undecoded: reader.undecoded))
        }
        return file
    }

    func write(_ root: StorageRoot) throws {
        try FileManager.default.createDirectory(at: root.library, withIntermediateDirectories: true)
        let encoded = folders.map { folder -> JSONValue in
            var writer = ObjectWriter(base: folder.extra, undecoded: folder.undecoded)
            writer.set("id", .string(folder.id.uuidString))
            writer.set("name", .string(folder.name))
            writer.set("cloth", .string(folder.clothRaw))
            writer.set("createdAt", ManifestCodec.encodeDate(folder.createdAt))
            writer.set("sortIndex", .number(Double(folder.sortIndex)))
            if let parent = folder.parentID { writer.set("parent", .string(parent.uuidString)) }
            return .object(writer.values)
        }
        try JSONValue.object(["folders": .array(encoded + opaque)]).serialized().write(to: root.foldersFile, options: .atomic)
    }

    /// Takes the app's folder list, keeping unknown keys and unreadable values of folders that still exist.
    mutating func merge(_ current: [FolderEntry]) {
        let existing = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        folders = current.map { entry in
            guard let old = existing[entry.id] else { return entry }
            var merged = entry
            merged.extra = old.extra
            merged.undecoded = old.undecoded
            return merged
        }
    }

    mutating func upsert(_ folder: FolderEntry) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) { folders[index] = folder } else { folders.append(folder) }
    }
}
