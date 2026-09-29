import Foundation

struct FolderEntry: Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var clothRaw: String
    var createdAt: Date
    var sortIndex: Int
    var extra: [String: JSONValue] = [:]

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
            file.folders.append(FolderEntry(id: id, name: name, clothRaw: reader.string("cloth", default: ClothColor.slate.rawValue),
                                            createdAt: reader.date("createdAt", default: .now),
                                            sortIndex: reader.int("sortIndex", default: file.folders.count),
                                            extra: reader.remaining))
        }
        return file
    }

    func write(_ root: StorageRoot) throws {
        try FileManager.default.createDirectory(at: root.library, withIntermediateDirectories: true)
        let encoded = folders.map { folder -> JSONValue in
            var object = folder.extra
            object["id"] = .string(folder.id.uuidString)
            object["name"] = .string(folder.name)
            object["cloth"] = .string(folder.clothRaw)
            object["createdAt"] = ManifestCodec.encodeDate(folder.createdAt)
            object["sortIndex"] = .number(Double(folder.sortIndex))
            return .object(object)
        }
        try JSONValue.object(["folders": .array(encoded + opaque)]).serialized().write(to: root.foldersFile, options: .atomic)
    }

    mutating func upsert(_ folder: FolderEntry) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) { folders[index] = folder } else { folders.append(folder) }
    }
}
