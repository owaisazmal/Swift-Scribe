import Foundation
import CoreGraphics

enum ManifestError: Error, Equatable {
    case notJSON
    case notAnObject
    case pagesUnreadable
}

/// Reads and writes `manifest.json`. Unknown keys, unknown enum values and malformed fields never fail
/// the whole manifest: they fall back to defaults, and their raw JSON is written back unless the app changed them.
enum ManifestCodec {
    static func decode(_ data: Data, fallbackID: UUID, fallbackDate: Date = .now) throws -> (manifest: NotebookManifest, warnings: [String]) {
        let root: JSONValue
        do { root = try JSONValue.parse(data) } catch { throw ManifestError.notJSON }
        guard let object = root.objectValue else { throw ManifestError.notAnObject }
        var reader = ObjectReader(object)
        var warnings: [String] = []

        let rawPages = reader.take("pages")
        guard let pageValues = rawPages.map({ $0.arrayValue }) ?? [] else { throw ManifestError.pagesUnreadable }
        var pages: [NotebookPage] = []
        var opaque: [OpaquePage] = []
        for raw in pageValues {
            if let page = decodePage(raw) {
                pages.append(page)
            } else {
                opaque.append(OpaquePage(anchor: pages.last?.id, raw: raw))
            }
        }
        if !opaque.isEmpty { warnings.append("\(opaque.count) page(s) could not be read and are kept as-is") }

        let id = reader.uuid("id", default: fallbackID)
        let createdAt = reader.date("createdAt", default: fallbackDate)
        var manifest = NotebookManifest(id: id, title: reader.string("title", default: "Untitled Notebook"),
                                        createdAt: createdAt,
                                        cover: reader.nested("cover", default: CoverSpec.defaultCloth(for: id),
                                                             decode: { decodeCover($0, id: id) }, encode: encodeCover),
                                        defaults: reader.nested("defaults", default: PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter),
                                                                decode: decodeDefaults, encode: encodeDefaults),
                                        pages: pages)
        manifest.schemaVersion = reader.int("schemaVersion", default: NotebookManifest.currentSchemaVersion)
        manifest.modifiedAt = reader.date("modifiedAt", default: createdAt)
        manifest.opaquePages = opaque
        for raw in reader.array("recordings") {
            if let recording = decodeRecording(raw) { manifest.recordings.append(recording) } else { manifest.opaqueRecordings.append(raw) }
        }
        if !manifest.opaqueRecordings.isEmpty { warnings.append("\(manifest.opaqueRecordings.count) recording(s) could not be read and are kept as-is") }
        manifest.library = reader.nested("library", default: LibraryState(), decode: decodeLibrary, encode: encodeLibrary)
        manifest.migratedFrom = reader.optionalString("migratedFrom")
        manifest.undecoded = reader.undecoded
        manifest.extra = reader.remaining
        if !reader.undecoded.isEmpty {
            warnings.append("unreadable fields kept as-is: \(reader.undecoded.keys.sorted().joined(separator: ", "))")
        }
        if manifest.isNewerThanSupported {
            warnings.append("schema \(manifest.schemaVersion) is newer than \(NotebookManifest.currentSchemaVersion); opened read-only")
        }
        return (manifest, warnings)
    }

    static func encode(_ manifest: NotebookManifest) throws -> Data {
        var writer = ObjectWriter(base: manifest.extra, undecoded: manifest.undecoded)
        writer.set("schemaVersion", .number(Double(manifest.schemaVersion)))
        writer.set("id", .string(manifest.id.uuidString))
        writer.set("title", .string(manifest.title))
        writer.set("createdAt", encodeDate(manifest.createdAt))
        writer.set("modifiedAt", encodeDate(manifest.modifiedAt))
        writer.set("cover", encodeCover(manifest.cover))
        writer.set("defaults", encodeDefaults(manifest.defaults))
        writer.set("pages", .array(interleave(manifest.pages, opaque: manifest.opaquePages)))
        writer.set("recordings", .array(manifest.recordings.map(encodeRecording) + manifest.opaqueRecordings))
        writer.set("library", encodeLibrary(manifest.library))
        if let migratedFrom = manifest.migratedFrom { writer.set("migratedFrom", .string(migratedFrom)) }
        return try JSONValue.object(writer.values).serialized()
    }

    // MARK: Pages

    static func decodePage(_ raw: JSONValue) -> NotebookPage? {
        guard let object = raw.objectValue, let id = object["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else { return nil }
        var reader = ObjectReader(object)
        _ = reader.take("id")
        _ = reader.take("ink")
        let background = decodeBackground(reader.take("background"))
        var page = NotebookPage(id: id, background: background, paperColor: .white,
                                size: reader.nested("size", default: PageSize.letter.points, decode: decodeSize, encode: encodeSize))
        page.paperColorRaw = reader.string("paperColor", default: PaperColor.white.rawValue)
        page.inkHash = reader.optionalString("inkHash")
        page.undecoded = reader.undecoded
        page.extra = reader.remaining
        return page
    }

    static func encodePage(_ page: NotebookPage) -> JSONValue {
        var writer = ObjectWriter(base: page.extra, undecoded: page.undecoded)
        writer.set("id", .string(page.id.uuidString))
        writer.set("background", encodeBackground(page.background))
        writer.set("paperColor", .string(page.paperColorRaw))
        writer.set("size", encodeSize(page.size))
        writer.set("ink", page.inkHash == nil ? .null : .string(page.inkFile))
        writer.set("inkHash", page.inkHash.map(JSONValue.string) ?? .null)
        return .object(writer.values)
    }

    private static func interleave(_ pages: [NotebookPage], opaque: [OpaquePage]) -> [JSONValue] {
        guard !opaque.isEmpty else { return pages.map(encodePage) }
        let known = Set(pages.map(\.id))
        var result = opaque.filter { $0.anchor == nil }.map(\.raw)
        for page in pages {
            result.append(encodePage(page))
            result += opaque.filter { $0.anchor == page.id }.map(\.raw)
        }
        result += opaque.filter { $0.anchor.map { !known.contains($0) } ?? false }.map(\.raw)
        return result
    }

    static func decodeBackground(_ raw: JSONValue?) -> PageBackground {
        guard let raw else { return .template(.blank) }
        guard let object = raw.objectValue, let kind = object["kind"]?.stringValue else { return .unknown(raw) }
        switch kind {
        case "template":
            guard let template = object["template"]?.stringValue else { return .unknown(raw) }
            return .template(template)
        case "pdf":
            guard let file = object["file"]?.stringValue, let index = object["index"]?.intValue, index >= 0 else { return .unknown(raw) }
            return .pdf(file: file, index: index)
        case "image":
            guard let file = object["file"]?.stringValue else { return .unknown(raw) }
            return .image(file: file)
        default:
            return .unknown(raw)
        }
    }

    static func encodeBackground(_ background: PageBackground) -> JSONValue {
        switch background {
        case .template(let raw): .object(["kind": .string("template"), "template": .string(raw)])
        case .pdf(let file, let index): .object(["kind": .string("pdf"), "file": .string(file), "index": .number(Double(index))])
        case .image(let file): .object(["kind": .string("image"), "file": .string(file)])
        case .unknown(let raw): raw
        }
    }

    // MARK: Nested objects

    static func decodeCover(_ object: [String: JSONValue], id: UUID) -> CoverSpec {
        let fallback = CoverSpec.defaultCloth(for: id)
        var reader = ObjectReader(object)
        let seed = reader.take("seed")?.doubleValue.flatMap { $0 >= 0 && $0 <= Double(UInt32.max) ? UInt32($0) : nil }
        let inks = reader.take("inks")?.arrayValue?.compactMap(\.stringValue)
        return CoverSpec(styleRaw: reader.string("style", default: fallback.styleRaw),
                         clothRaw: reader.string("cloth", default: fallback.clothRaw),
                         inksRaw: inks ?? fallback.inksRaw, seed: seed ?? fallback.seed, extra: reader.remaining)
    }

    static func encodeCover(_ cover: CoverSpec) -> JSONValue {
        var object = cover.extra
        object["style"] = .string(cover.styleRaw)
        object["cloth"] = .string(cover.clothRaw)
        object["inks"] = .array(cover.inksRaw.map(JSONValue.string))
        object["seed"] = .number(Double(cover.seed))
        return .object(object)
    }

    static func decodeDefaults(_ object: [String: JSONValue]) -> PageDefaults {
        var reader = ObjectReader(object)
        return PageDefaults(templateRaw: reader.string("template", default: PaperTemplate.narrowRuled.rawValue),
                            paperColorRaw: reader.string("paperColor", default: PaperColor.white.rawValue),
                            pageSizeRaw: reader.string("pageSize", default: PageSize.letter.rawValue),
                            extra: reader.remaining)
    }

    static func encodeDefaults(_ defaults: PageDefaults) -> JSONValue {
        var object = defaults.extra
        object["template"] = .string(defaults.templateRaw)
        object["paperColor"] = .string(defaults.paperColorRaw)
        object["pageSize"] = .string(defaults.pageSizeRaw)
        return .object(object)
    }

    static func decodeRecording(_ raw: JSONValue) -> RecordingEntry? {
        guard let object = raw.objectValue,
              let id = object["id"]?.stringValue.flatMap(UUID.init(uuidString:)),
              let file = object["file"]?.stringValue else { return nil }
        var reader = ObjectReader(object)
        _ = reader.take("id")
        _ = reader.take("file")
        return RecordingEntry(id: id, file: file, createdAt: reader.date("createdAt", default: .distantPast),
                              duration: reader.take("duration")?.doubleValue ?? 0, extra: reader.remaining)
    }

    static func encodeRecording(_ recording: RecordingEntry) -> JSONValue {
        var object = recording.extra
        object["id"] = .string(recording.id.uuidString)
        object["file"] = .string(recording.file)
        object["createdAt"] = encodeDate(recording.createdAt)
        object["duration"] = .number(recording.duration)
        return .object(object)
    }

    static func decodeLibrary(_ object: [String: JSONValue]) -> LibraryState {
        var reader = ObjectReader(object)
        var state = LibraryState()
        state.isFavorite = reader.take("favorite")?.boolValue ?? false
        state.deletedAt = reader.optionalDate("deletedAt")
        state.folderID = reader.optionalUUID("folderID")
        state.lastOpenedAt = reader.optionalDate("lastOpenedAt")
        state.currentPage = max(0, reader.int("currentPage", default: 0))
        state.extra = reader.remaining
        return state
    }

    static func encodeLibrary(_ state: LibraryState) -> JSONValue {
        var object = state.extra
        object["favorite"] = .bool(state.isFavorite)
        object["deletedAt"] = state.deletedAt.map(encodeDate) ?? .null
        object["folderID"] = state.folderID.map { .string($0.uuidString) } ?? .null
        object["lastOpenedAt"] = state.lastOpenedAt.map(encodeDate) ?? .null
        object["currentPage"] = .number(Double(state.currentPage))
        return .object(object)
    }

    // MARK: Scalars

    static func encodeDate(_ date: Date) -> JSONValue {
        .string(date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true)))
    }

    static func parseDate(_ string: String) -> Date? {
        (try? Date(string, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
            ?? (try? Date(string, strategy: .iso8601))
    }

    static func decodeSize(_ object: [String: JSONValue]) -> CGSize? {
        guard let w = object["width"]?.doubleValue, let h = object["height"]?.doubleValue,
              w.isFinite, h.isFinite, w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    static func encodeSize(_ size: CGSize) -> JSONValue {
        .object(["width": .number(Double(size.width)), "height": .number(Double(size.height))])
    }
}

/// Pulls typed values out of a JSON object. Keys it reads are removed from `remaining`;
/// values it can't read are remembered with the default used in their place.
struct ObjectReader {
    private(set) var remaining: [String: JSONValue]
    private(set) var undecoded: [String: UndecodedField] = [:]

    init(_ object: [String: JSONValue]) { remaining = object }

    mutating func take(_ key: String) -> JSONValue? {
        remaining.removeValue(forKey: key)
    }

    private mutating func read<T>(_ key: String, default value: T, encode: (T) -> JSONValue, _ transform: (JSONValue) -> T?) -> T {
        guard let raw = take(key), raw != .null else { return value }
        if let decoded = transform(raw) { return decoded }
        undecoded[key] = UndecodedField(raw: raw, fallback: encode(value))
        return value
    }

    private mutating func readOptional<T>(_ key: String, _ transform: (JSONValue) -> T?) -> T? {
        guard let raw = take(key), raw != .null else { return nil }
        if let decoded = transform(raw) { return decoded }
        undecoded[key] = UndecodedField(raw: raw, fallback: .null)
        return nil
    }

    mutating func string(_ key: String, default value: String) -> String {
        read(key, default: value, encode: JSONValue.string) { $0.stringValue }
    }

    mutating func optionalString(_ key: String) -> String? { readOptional(key) { $0.stringValue } }

    mutating func int(_ key: String, default value: Int) -> Int {
        read(key, default: value, encode: { .number(Double($0)) }) { $0.intValue }
    }

    mutating func uuid(_ key: String, default value: UUID) -> UUID {
        read(key, default: value, encode: { .string($0.uuidString) }) { $0.stringValue.flatMap(UUID.init(uuidString:)) }
    }

    mutating func optionalUUID(_ key: String) -> UUID? { readOptional(key) { $0.stringValue.flatMap(UUID.init(uuidString:)) } }

    mutating func date(_ key: String, default value: Date) -> Date {
        read(key, default: value, encode: ManifestCodec.encodeDate) { $0.stringValue.flatMap(ManifestCodec.parseDate) }
    }

    mutating func optionalDate(_ key: String) -> Date? { readOptional(key) { $0.stringValue.flatMap(ManifestCodec.parseDate) } }

    mutating func array(_ key: String) -> [JSONValue] {
        read(key, default: [], encode: JSONValue.array) { $0.arrayValue }
    }

    mutating func nested<T>(_ key: String, default value: T, decode: ([String: JSONValue]) -> T?,
                            encode: (T) -> JSONValue) -> T {
        read(key, default: value, encode: encode) { $0.objectValue.flatMap(decode) }
    }
}

/// Writes known keys over the unknown ones, restoring a field's raw value when it couldn't be read
/// and still holds the default it was given.
struct ObjectWriter {
    private let undecoded: [String: UndecodedField]
    private(set) var values: [String: JSONValue]

    init(base: [String: JSONValue], undecoded: [String: UndecodedField]) {
        values = base
        self.undecoded = undecoded
        for (key, field) in undecoded { values[key] = field.raw }
    }

    mutating func set(_ key: String, _ value: JSONValue) {
        if let field = undecoded[key], field.fallback == value { return }
        values[key] = value
    }
}
