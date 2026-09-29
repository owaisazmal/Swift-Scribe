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
        return copy
    }
}

struct PageDefaults: Sendable, Hashable {
    var templateRaw: String
    var paperColorRaw: String
    var pageSizeRaw: String
    var extra: [String: JSONValue] = [:]

    init(template: PaperTemplate, paperColor: PaperColor, pageSize: PageSize) {
        templateRaw = template.rawValue
        paperColorRaw = paperColor.rawValue
        pageSizeRaw = pageSize.rawValue
    }

    init(templateRaw: String, paperColorRaw: String, pageSizeRaw: String, extra: [String: JSONValue]) {
        self.templateRaw = templateRaw
        self.paperColorRaw = paperColorRaw
        self.pageSizeRaw = pageSizeRaw
        self.extra = extra
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
}

struct LibraryState: Sendable, Hashable {
    var isFavorite = false
    var deletedAt: Date?
    var folderID: UUID?
    var lastOpenedAt: Date?
    var currentPage = 0
    var extra: [String: JSONValue] = [:]
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
    var migratedFrom: String?
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
