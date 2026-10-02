import Foundation
import CoreGraphics

enum PageBackground: Sendable, Hashable {
    case template(String)
    case pdf(file: String, index: Int)
    case image(file: String)
    case unknown(JSONValue)

    static func template(_ template: PaperTemplate) -> PageBackground { .template(template.rawValue) }

    var template: PaperTemplate? {
        if case .template(let raw) = self { return PaperTemplate(rawValue: raw) ?? .blank }
        return nil
    }

    var assetFile: String? {
        switch self {
        case .pdf(let file, _), .image(let file): file
        case .template, .unknown: nil
        }
    }
}

struct NotebookPage: Sendable, Hashable, Identifiable {
    var id: UUID
    var background: PageBackground
    var paperColorRaw: String
    var size: CGSize
    var inkHash: String?
    var extra: [String: JSONValue] = [:]
    var undecoded: [String: UndecodedField] = [:]

    init(id: UUID = UUID(), background: PageBackground, paperColor: PaperColor, size: CGSize, inkHash: String? = nil) {
        self.id = id
        self.background = background
        self.paperColorRaw = paperColor.rawValue
        self.size = size
        self.inkHash = inkHash
    }

    static func template(_ template: PaperTemplate, color: PaperColor, size: PageSize) -> NotebookPage {
        NotebookPage(background: .template(template), paperColor: color, size: size.points)
    }

    var paperColor: PaperColor {
        get { PaperColor(rawValue: paperColorRaw) ?? .white }
        set { paperColorRaw = newValue.rawValue }
    }

    var template: PaperTemplate? { background.template }

    var effectivePaperColor: PaperColor { template == nil ? .white : paperColor }

    var inkFile: String { "ink/\(id.uuidString).pkdrawing" }

    /// A copy with a new identity and no ink, for duplicating structure.
    func duplicated() -> NotebookPage {
        var copy = self
        copy.id = UUID()
        copy.day = nil
        copy.extra["bookmark"] = nil
        return copy
    }

    /// Names a thumbnail by the page's ink and by how the page looks, so a template or paper change isn't served stale.
    var thumbnailKey: String { "\(inkHash?.prefix(12) ?? "blank")-\(appearanceKey)" }

    var appearanceKey: String {
        let backgroundKey = switch background {
        case .template(let raw): "t:\(raw)"
        case .pdf(let file, let index): "p:\(file)#\(index)"
        case .image(let file): "i:\(file)"
        case .unknown(let raw): "u:" + ((try? raw.serialized(pretty: false)).map { String(decoding: $0, as: UTF8.self) } ?? "")
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let dayKey = day.map { "|d:\($0)" } ?? ""
        let itemsKey = extra["items"].flatMap { try? $0.serialized(pretty: false) }.map { "|i:" + String(decoding: $0, as: UTF8.self) } ?? ""
        for byte in "\(backgroundKey)|\(paperColorRaw)|\(Int(size.width))x\(Int(size.height))\(dayKey)\(itemsKey)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0100_0000_01b3
        }
        return String(hash, radix: 16).prefix(8).description
    }
}

extension NotebookPage {
    /// "yyyy-MM-dd" on a daily-journal page; older builds keep it as an unknown key.
    var day: String? {
        get { extra["date"]?.stringValue }
        set { extra["date"] = newValue.map(JSONValue.string) }
    }
}

struct PageDefaults: Sendable, Hashable {
    var templateRaw: String
    var paperColorRaw: String
    var pageSizeRaw: String
    var extra: [String: JSONValue] = [:]
    var undecoded: [String: UndecodedField] = [:]

    init(template: PaperTemplate, paperColor: PaperColor, pageSize: PageSize) {
        templateRaw = template.rawValue
        paperColorRaw = paperColor.rawValue
        pageSizeRaw = pageSize.rawValue
    }

    init(templateRaw: String, paperColorRaw: String, pageSizeRaw: String, extra: [String: JSONValue],
         undecoded: [String: UndecodedField] = [:]) {
        self.templateRaw = templateRaw
        self.paperColorRaw = paperColorRaw
        self.pageSizeRaw = pageSizeRaw
        self.extra = extra
        self.undecoded = undecoded
    }

    var template: PaperTemplate { PaperTemplate(rawValue: templateRaw) ?? .narrowRuled }
    var paperColor: PaperColor { PaperColor(rawValue: paperColorRaw) ?? .white }
    var pageSize: PageSize { PageSize(rawValue: pageSizeRaw) ?? .letter }

    func newPage() -> NotebookPage { .template(template, color: paperColor, size: pageSize) }
}

struct RecordingEntry: Sendable, Hashable, Identifiable {
    var id: UUID
    var file: String
    var createdAt: Date
    var duration: TimeInterval
    var extra: [String: JSONValue] = [:]
    var undecoded: [String: UndecodedField] = [:]
}

struct LibraryState: Sendable, Hashable {
    var isFavorite = false
    var deletedAt: Date?
    var folderID: UUID?
    var lastOpenedAt: Date?
    var currentPage = 0
    var extra: [String: JSONValue] = [:]
    var undecoded: [String: UndecodedField] = [:]
}

struct UndecodedField: Sendable, Hashable {
    var raw: JSONValue
    var fallback: JSONValue
}

/// A page from the manifest that this version can't read. Kept verbatim and written back after `anchor`.
struct OpaquePage: Sendable, Hashable {
    var anchor: UUID?
    var raw: JSONValue
}

struct NotebookManifest: Sendable, Hashable {
    static let currentSchemaVersion = 2

    var schemaVersion = NotebookManifest.currentSchemaVersion
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var cover: CoverSpec
    var defaults: PageDefaults
    var pages: [NotebookPage]
    var opaquePages: [OpaquePage] = []
    var recordings: [RecordingEntry] = []
    var opaqueRecordings: [JSONValue] = []
    var library = LibraryState()
    var extra: [String: JSONValue] = [:]
    var undecoded: [String: UndecodedField] = [:]

    init(id: UUID = UUID(), title: String, createdAt: Date = .now, cover: CoverSpec? = nil,
         defaults: PageDefaults, pages: [NotebookPage]) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.cover = cover ?? .defaultCloth(for: id)
        self.defaults = defaults
        self.pages = pages
    }

    /// Newer schema versions open read-only so an older build never rewrites data it doesn't understand.
    var isNewerThanSupported: Bool { schemaVersion > Self.currentSchemaVersion }
}
