import Foundation
import SwiftData
import PencilKit

/// The v1 SwiftData schema, kept verbatim so the v1 store can be read for migration.
enum LegacyV1Schema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Notebook.self, Folder.self] }

    @Model
    final class Notebook {
        var id: UUID = UUID()
        var title: String = ""
        var createdAt: Date = Date()
        var modifiedAt: Date = Date()
        var isFavorite: Bool = false
        var deletedAt: Date?
        var folder: Folder?
        var pagesData: Data = Data()
        var recordingsData: Data = Data()
        var pageCount: Int = 0
        var searchText: String = ""
        var defaultTemplateRaw: String = "narrowRuled"
        var defaultColorRaw: String = "white"
        var defaultSizeRaw: String = "letter"

        init(id: UUID = UUID(), title: String) {
            self.id = id
            self.title = title
        }
    }

    @Model
    final class Folder {
        var id: UUID = UUID()
        var name: String = ""
        var colorRaw: String = "blue"
        var createdAt: Date = Date()
        @Relationship(deleteRule: .nullify, inverse: \LegacyV1Schema.Notebook.folder)
        var notebooks: [Notebook]? = []

        init(id: UUID = UUID(), name: String, colorRaw: String) {
            self.id = id
            self.name = name
            self.colorRaw = colorRaw
        }
    }
}

/// v1 page geometry: pages stacked at an 800-point width in one coordinate space.
enum LegacyV1Layout {
    static let pageWidth: CGFloat = 800
    static let horizontalMargin: CGFloat = 24
    static let topMargin: CGFloat = 24
    static let pageGap: CGFloat = 24

    static func frames(for sizes: [CGSize]) -> [CGRect] {
        var y = topMargin
        return sizes.map { size in
            let height = size.width > 0 ? (pageWidth * size.height / size.width).rounded() : (pageWidth * 11 / 8.5).rounded()
            defer { y += height + pageGap }
            return CGRect(x: horizontalMargin, y: y, width: pageWidth, height: height)
        }
    }

    static func pageIndex(atY y: CGFloat, frames: [CGRect]) -> Int {
        guard !frames.isEmpty else { return 0 }
        for (index, frame) in frames.enumerated() where y < frame.maxY + pageGap / 2 { return index }
        return frames.count - 1
    }

    /// Maps v1 canvas coordinates on the page at `frame` to page-local points for a page of `size`.
    static func pageLocalTransform(frame: CGRect, size: CGSize) -> CGAffineTransform {
        let scale = size.width / frame.width
        return CGAffineTransform(translationX: -frame.minX, y: -frame.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Reads a v1 `pagesData` blob without the strict synthesized decoder.
    static func decodePages(_ data: Data) -> [NotebookPage]? {
        guard let values = (try? JSONValue.parse(data))?.arrayValue else { return nil }
        let pages = values.compactMap(decodePage)
        return pages.count == values.count ? pages : nil
    }

    static func decodePage(_ raw: JSONValue) -> NotebookPage? {
        guard let object = raw.objectValue else { return nil }
        let id = object["id"]?.stringValue.flatMap(UUID.init(uuidString:)) ?? UUID()
        var background = PageBackground.template(.narrowRuled)
        if let value = object["background"]?.objectValue {
            if let template = value["template"]?["_0"]?.stringValue {
                background = .template(template)
            } else if let pdf = value["pdf"], let file = pdf["file"]?.stringValue, let index = pdf["pageIndex"]?.intValue {
                background = .pdf(file: file, index: index)
            } else if let file = value["image"]?["file"]?.stringValue {
                background = .image(file: file)
            } else {
                return nil
            }
        }
        var size = PageSize.letter.points
        if let pair = object["size"]?.arrayValue, pair.count == 2, let w = pair[0].doubleValue, let h = pair[1].doubleValue, w > 0, h > 0 {
            size = CGSize(width: w, height: h)
        } else if let value = object["size"]?.objectValue, let decoded = ManifestCodec.decodeSize(value) {
            size = decoded
        }
        var page = NotebookPage(id: id, background: background, paperColor: .white, size: size)
        page.paperColorRaw = object["paperColor"]?.stringValue ?? PaperColor.white.rawValue
        return page
    }

    static func decodeRecordings(_ data: Data) -> [RecordingEntry] {
        guard let values = (try? JSONValue.parse(data))?.arrayValue else { return [] }
        return values.compactMap { raw in
            guard let file = raw["fileName"]?.stringValue else { return nil }
            let created = raw["createdAt"]?.doubleValue.map { Date(timeIntervalSinceReferenceDate: $0) } ?? .distantPast
            return RecordingEntry(id: raw["id"]?.stringValue.flatMap(UUID.init(uuidString:)) ?? UUID(), file: file,
                                  createdAt: created, duration: raw["duration"]?.doubleValue ?? 0)
        }
    }
}

/// v1 folder colours, as stored in the v1 database.
enum FolderColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, blue, indigo, purple, pink, gray
    var id: String { rawValue }
}
extension FolderColor {
    /// One cloth per v1 colour, so folders that looked different in v1 still do.
    var cloth: ClothColor {
        switch self {
        case .red: .oxblood
        case .orange: .tomato
        case .yellow: .mustard
        case .green: .moss
        case .mint: .jade
        case .blue: .cobalt
        case .indigo: .navy
        case .purple: .plum
        case .pink: .rose
        case .gray: .slate
        }
    }
}
