import UIKit
import PencilKit

/// A whiteboard is a page with no edges to run into: a sheet far larger than anyone fills, opened on its own and
/// moved about freely. Wherever a whole page is wanted (thumbnails, exports, search), the part with something on it stands in.
enum Whiteboard {
    static let side: CGFloat = 40_000
    static let size = CGSize(width: side, height: side)
    static let center = CGPoint(x: side / 2, y: side / 2)
    /// What new things are sized against, and the width the editor counts a board as when it sets the scale.
    static let sheet = PageSize.letter.points
    /// The shape a board has wherever it is shown as a page: its card among the pages, thumbnails, exports.
    static let shownSize = CGSize(width: 1024, height: 768)
    static let templates: [PaperTemplate] = [.blank, .dotted, .grid, .narrowRuled]
    static let minimumZoom: CGFloat = 0.15
    /// Rules and dots are as far apart as on a Letter page.
    static let unit = sheet.width / 800

    /// Round everything written or placed on the board, or nil while it is empty.
    static func contentBounds(of page: NotebookPage, ink: PKDrawing) -> CGRect? {
        var bounds = ink.strokes.isEmpty ? CGRect.null : ink.bounds
        if page.hasItems {
            for item in page.items where item.content != .unknown { bounds = bounds.union(item.boundingBox) }
        }
        return bounds.isNull || bounds.isEmpty ? nil : bounds
    }

    /// The part of the board that stands in for the whole: what is on it with room round it, never less than a
    /// screenful, in the board's shown shape. An empty board gives its middle.
    static func frame(of page: NotebookPage, ink: PKDrawing) -> CGRect {
        let content = (contentBounds(of: page, ink: ink) ?? CGRect(origin: center, size: .zero)).insetBy(dx: -48, dy: -48)
        var width = max(content.width, shownSize.width), height = max(content.height, shownSize.height)
        let aspect = shownSize.width / shownSize.height
        if width / height > aspect { height = width / aspect } else { width = height * aspect }
        width = min(width.rounded(.up), side)
        height = min(height.rounded(.up), side)
        return CGRect(x: min(max((content.midX - width / 2).rounded(), 0), side - width),
                      y: min(max((content.midY - height / 2).rounded(), 0), side - height), width: width, height: height)
    }

    /// `rect` of the board as a page of its own. Its ink stays where it is: renderers draw `inkRect` of it.
    static func piece(of page: NotebookPage, in rect: CGRect) -> NotebookPage {
        var piece = page
        piece.size = rect.size
        piece.cut = rect.origin
        if page.hasItems {
            piece.items = page.items.map { item in
                var moved = item
                moved.center = CGPoint(x: item.center.x - rect.minX, y: item.center.y - rect.minY)
                return moved
            }
        }
        return piece
    }

    /// A board cut down to what is on it; any other page as it is.
    static func whole(_ page: NotebookPage, ink: PKDrawing) -> NotebookPage {
        page.isBoard && page.cut == nil ? piece(of: page, in: frame(of: page, ink: ink)) : page
    }

    /// How wide a page is drawn for its handwriting to be read: more for a large piece of a board, so the words stay legible.
    static func readingWidth(for page: NotebookPage) -> CGFloat {
        page.cut == nil ? 1400 : min(max(1400, page.size.width * 1.4), 4000)
    }

    /// How many pixels per point a piece `size` large can be drawn at without its long side passing `limit` pixels.
    static func scale(for size: CGSize, wanted: CGFloat, limit: CGFloat = 6000) -> CGFloat {
        min(wanted, limit / max(size.width, size.height, 1))
    }
}

extension NotebookPage {
    static func board(template: PaperTemplate, color: PaperColor) -> NotebookPage {
        var page = NotebookPage(background: .template(Whiteboard.templates.contains(template) ? template : .dotted), paperColor: color, size: Whiteboard.size)
        page.extra["board"] = .bool(true)
        return page
    }

    var isBoard: Bool { extra["board"]?.boolValue ?? false }

    /// Where on its board a piece was cut from. Never saved: only pieces made for drawing carry it.
    var cut: CGPoint? {
        get {
            guard let values = extra["cut"]?.arrayValue, values.count == 2, let x = values[0].doubleValue, let y = values[1].doubleValue else { return nil }
            return CGPoint(x: x, y: y)
        }
        set { extra["cut"] = newValue.map { .array([.number($0.x), .number($0.y)]) } }
    }

    /// The part of the page's ink a renderer draws.
    var inkRect: CGRect { CGRect(origin: cut ?? .zero, size: size) }

    /// The page's shape wherever it is shown small. A board has no shape of its own.
    var shownSize: CGSize { isBoard && cut == nil ? Whiteboard.shownSize : size }

    /// What new pictures, text and the zoom window are sized against.
    var sheetSize: CGSize { isBoard ? Whiteboard.sheet : size }
}
