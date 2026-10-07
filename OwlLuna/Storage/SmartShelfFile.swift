import Foundation

/// A saved filter: everything tagged with any, or all, of its tags.
struct SmartShelf: Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var tags: [String]
    /// "any" or "all". A kind this build doesn't know is kept and read as "any".
    var matchRaw: String
    var createdAt: Date
    var extra: [String: JSONValue] = [:]
    var undecoded: [String: UndecodedField] = [:]

    init(id: UUID = UUID(), name: String, tags: [String], match: TagRule.Match = .any, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.tags = Tags.merged(tags)
        self.matchRaw = match.rawValue
        self.createdAt = createdAt
    }

    var match: TagRule.Match {
        get { TagRule.Match(rawValue: matchRaw) ?? .any }
        set { matchRaw = newValue.rawValue }
    }

    var rule: TagRule { TagRule(tags: tags, match: match) }
}

/// `Library/smart-shelves.json`, the saved filters. Read as tolerantly as `folders.json`.
struct SmartShelfFile: Sendable, Hashable {
    var shelves: [SmartShelf] = []
    var opaque: [JSONValue] = []
    var extra: [String: JSONValue] = [:]

    static func read(_ root: StorageRoot) -> SmartShelfFile {
        guard let data = try? Data(contentsOf: root.smartShelvesFile) else { return SmartShelfFile() }
        guard var object = (try? JSONValue.parse(data))?.objectValue, object["shelves"].map({ $0.arrayValue != nil }) ?? true else {
            _ = try? Quarantine.move(root.smartShelvesFile)
            return SmartShelfFile()
        }
        let values = object.removeValue(forKey: "shelves")?.arrayValue ?? []
        var file = SmartShelfFile(extra: object)
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
            let tags = reader.value("tags", default: [], encode: { .array($0.map(JSONValue.string)) }) { raw in
                raw.arrayValue.flatMap { values in
                    let names = values.compactMap(\.stringValue)
                    return names.count == values.count ? names : nil
                }
            }
            var shelf = SmartShelf(id: id, name: name, tags: tags, createdAt: reader.date("createdAt", default: .now))
            shelf.matchRaw = reader.string("match", default: TagRule.Match.any.rawValue)
            shelf.extra = reader.remaining
            shelf.undecoded = reader.undecoded
            file.shelves.append(shelf)
        }
        return file
    }

    func write(_ root: StorageRoot) throws {
        try FileManager.default.createDirectory(at: root.library, withIntermediateDirectories: true)
        let encoded = shelves.map { shelf -> JSONValue in
            var writer = ObjectWriter(base: shelf.extra, undecoded: shelf.undecoded)
            writer.set("id", .string(shelf.id.uuidString))
            writer.set("name", .string(shelf.name))
            writer.set("tags", .array(shelf.tags.map(JSONValue.string)))
            writer.set("match", .string(shelf.matchRaw))
            writer.set("createdAt", ManifestCodec.encodeDate(shelf.createdAt))
            return .object(writer.values)
        }
        var object = extra
        object["shelves"] = .array(encoded + opaque)
        try JSONValue.object(object).serialized().write(to: root.smartShelvesFile, options: .atomic)
    }
}
