import Foundation
import CoreGraphics

/// Typed text on a page. The box's width is the item's; its height follows the text.
struct TextBox: Sendable, Hashable {
    enum Tint: String, Sendable, CaseIterable, Identifiable {
        case ink, tomato, cobalt, moss, plum
        var id: String { rawValue }
    }

    enum Alignment: String, Sendable, CaseIterable, Identifiable {
        case leading, center, trailing
        var id: String { rawValue }
    }

    static let fontSizes: ClosedRange<CGFloat> = 8...200

    var string: String
    var fontSize: CGFloat = 17
    var isBold = false
    var tint = Tint.ink
    var alignment = Alignment.leading
}

/// A tab on a page that opens another page, a page of another notebook, or a web address.
struct PageLink: Sendable, Hashable {
    enum Destination: Sendable, Hashable {
        case page(UUID)
        /// `name` is the notebook's title when the link was made, for when the notebook can't be looked up.
        case notebook(UUID, page: UUID?, name: String)
        case web(URL)
    }

    var destination: Destination
    /// Empty while the link is named after what it opens.
    var label = ""

    init(_ destination: Destination, label: String = "") {
        self.destination = destination
        self.label = label
    }

    init(target: UUID, label: String = "") {
        self.init(.page(target), label: label)
    }

    /// The page of this notebook the link opens, if that is what it opens.
    var target: UUID? {
        if case .page(let id) = destination { return id }
        return nil
    }
}

/// Reading a web address the way someone types it.
enum WebAddress {
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), host.contains(".") || host == "localhost" else { return nil }
        return url
    }

    /// "example.com/guide" for "https://www.example.com/guide".
    static func display(_ url: URL) -> String {
        var host = url.host() ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path()
        return path.count > 1 && path.count <= 24 ? host + path : host
    }
}

/// The colours study tape comes in. Raw values are stored in notebooks.
enum TapeColor: String, Sendable, CaseIterable, Identifiable {
    case mustard, rose, sage, sky
    var id: String { rawValue }
}

/// A picture, sticker, text box or link placed on a page, under the ink, or a strip of study tape over it.
/// Geometry is in page points.
struct PageItem: Sendable, Hashable, Identifiable {
    enum Content: Sendable, Hashable {
        case image(file: String)
        case sticker(String)
        case text(TextBox)
        case link(PageLink)
        /// Covers what is under it, ink included, until it is tapped.
        case tape(TapeColor)
        /// Made by a newer version; kept as read and not drawn.
        case unknown
    }

    var id: UUID
    var content: Content
    var center: CGPoint
    var size: CGSize
    var rotation: CGFloat = 0
    var raw: [String: JSONValue] = [:]

    init(id: UUID = UUID(), content: Content, center: CGPoint, size: CGSize, rotation: CGFloat = 0) {
        self.id = id
        self.content = content
        self.center = center
        self.size = size
        self.rotation = rotation
    }

    static let minimumSide: CGFloat = 24

    var sticker: Sticker? {
        if case .sticker(let name) = content { return Sticker(rawValue: name) }
        return nil
    }

    var assetFile: String? {
        if case .image(let file) = content { return file }
        return nil
    }

    var text: TextBox? {
        if case .text(let box) = content { return box }
        return nil
    }

    var link: PageLink? {
        if case .link(let link) = content { return link }
        return nil
    }

    var tape: TapeColor? {
        if case .tape(let color) = content { return color }
        return nil
    }

    /// Study tape lies over the ink; everything else lies under it.
    var isOverInk: Bool { tape != nil }

    /// The sticker of your own this picture was placed from, so placing it again reuses the same file.
    var source: String? {
        get { raw["source"]?.stringValue }
        set { raw["source"] = newValue.map(JSONValue.string) }
    }

    /// Whether a point on the page falls on the item, allowing for its rotation.
    func contains(_ point: CGPoint, slop: CGFloat = 0) -> Bool {
        let dx = point.x - center.x, dy = point.y - center.y
        let x = dx * cos(-rotation) - dy * sin(-rotation), y = dx * sin(-rotation) + dy * cos(-rotation)
        return abs(x) <= size.width / 2 + slop && abs(y) <= size.height / 2 + slop
    }

    /// Scaled about its centre, never smaller than a fingertip can grab or larger than `limit` on its long side.
    func scaled(by factor: CGFloat, limit: CGFloat) -> PageItem {
        let long = max(size.width, size.height), short = max(min(size.width, size.height), 1)
        let clamped = min(max(factor, Self.minimumSide / short), max(limit / long, Self.minimumSide / short))
        var copy = self
        copy.size = CGSize(width: size.width * clamped, height: size.height * clamped)
        if case .text(var box) = content {
            box.fontSize = min(max(box.fontSize * clamped, TextBox.fontSizes.lowerBound), TextBox.fontSizes.upperBound)
            copy.content = .text(box)
            copy.size = CGSize(width: copy.size.width, height: box.height(width: copy.size.width))
        }
        return copy
    }

    /// A new size with one point of the box held still: (0, 0) is its top leading corner, (0.5, 0.5) its centre.
    func resized(to newSize: CGSize, holding unit: CGPoint = .zero) -> PageItem {
        let dx = (newSize.width - size.width) * (0.5 - unit.x), dy = (newSize.height - size.height) * (0.5 - unit.y)
        var copy = self
        copy.size = newSize
        copy.center = CGPoint(x: center.x + dx * cos(rotation) - dy * sin(rotation), y: center.y + dx * sin(rotation) + dy * cos(rotation))
        return copy
    }

    /// A text box as tall as its text needs at its width, growing downwards.
    func fittedToText() -> PageItem {
        guard let text else { return self }
        return resized(to: CGSize(width: size.width, height: text.height(width: size.width)))
    }

    init?(json: JSONValue) {
        guard let object = json.objectValue, let id = object["id"]?.stringValue.flatMap(UUID.init(uuidString:)),
              let x = object["x"]?.doubleValue, let y = object["y"]?.doubleValue,
              let w = object["w"]?.doubleValue, let h = object["h"]?.doubleValue,
              [x, y, w, h].allSatisfy(\.isFinite), w > 0, h > 0 else { return nil }
        self.id = id
        center = CGPoint(x: x, y: y)
        size = CGSize(width: w, height: h)
        rotation = object["r"]?.doubleValue.flatMap { $0.isFinite ? CGFloat($0) : nil } ?? 0
        switch (object["kind"]?.stringValue, object["file"]?.stringValue, object["name"]?.stringValue) {
        case ("image", let file?, _): content = .image(file: file)
        case ("sticker", _, let name?): content = .sticker(name)
        case ("text", _, _):
            guard let string = object["text"]?.stringValue else { content = .unknown; break }
            var box = TextBox(string: string)
            if let size = object["fs"]?.doubleValue, size.isFinite, size > 0 {
                box.fontSize = min(max(CGFloat(size), TextBox.fontSizes.lowerBound), TextBox.fontSizes.upperBound)
            }
            box.isBold = object["bold"]?.boolValue ?? false
            box.tint = object["color"]?.stringValue.flatMap(TextBox.Tint.init(rawValue:)) ?? .ink
            box.alignment = object["align"]?.stringValue.flatMap(TextBox.Alignment.init(rawValue:)) ?? .leading
            content = .text(box)
        case ("link", _, _):
            let label = object["label"]?.stringValue ?? ""
            if let url = object["url"]?.stringValue.flatMap(WebAddress.url(from:)) {
                content = .link(PageLink(.web(url), label: label))
            } else if let notebook = object["notebook"]?.stringValue.flatMap(UUID.init(uuidString:)) {
                let page = object["page"]?.stringValue.flatMap(UUID.init(uuidString:))
                content = .link(PageLink(.notebook(notebook, page: page, name: object["name"]?.stringValue ?? ""), label: label))
            } else if let target = object["target"]?.stringValue.flatMap(UUID.init(uuidString:)) {
                content = .link(PageLink(target: target, label: label))
            } else {
                content = .unknown
            }
        case ("tape", _, _):
            content = object["tint"]?.stringValue.flatMap(TapeColor.init(rawValue:)).map(Content.tape) ?? .unknown
        default: content = .unknown
        }
        raw = object
    }

    var json: JSONValue {
        var object = raw
        object["id"] = .string(id.uuidString)
        object["x"] = .number(Double(center.x))
        object["y"] = .number(Double(center.y))
        object["w"] = .number(Double(size.width))
        object["h"] = .number(Double(size.height))
        object["r"] = .number(Double(rotation))
        switch content {
        case .image(let file):
            object["kind"] = .string("image")
            object["file"] = .string(file)
        case .sticker(let name):
            object["kind"] = .string("sticker")
            object["name"] = .string(name)
        case .text(let box):
            object["kind"] = .string("text")
            object["text"] = .string(box.string)
            object["fs"] = .number(Double(box.fontSize))
            object["bold"] = .bool(box.isBold)
            object["color"] = .string(box.tint.rawValue)
            object["align"] = .string(box.alignment.rawValue)
        case .link(let link):
            object["kind"] = .string("link")
            object["label"] = .string(link.label)
            for key in ["target", "notebook", "page", "name", "url"] { object[key] = nil }
            switch link.destination {
            case .page(let target):
                object["target"] = .string(target.uuidString)
            case .notebook(let notebook, let page, let name):
                object["notebook"] = .string(notebook.uuidString)
                object["page"] = page.map { .string($0.uuidString) }
                object["name"] = .string(name)
            case .web(let url):
                object["url"] = .string(url.absoluteString)
            }
        case .tape(let color):
            object["kind"] = .string("tape")
            object["tint"] = .string(color.rawValue)
        case .unknown:
            break
        }
        return .object(object)
    }
}

extension NotebookPage {
    /// Back to front. Entries this version can't read stay in the manifest untouched, behind the rest.
    var items: [PageItem] {
        get { extra["items"]?.arrayValue?.compactMap(PageItem.init(json:)) ?? [] }
        set {
            let unreadable = extra["items"]?.arrayValue?.filter { PageItem(json: $0) == nil } ?? []
            let all = unreadable + newValue.map(\.json)
            extra["items"] = all.isEmpty ? nil : .array(all)
        }
    }

    var hasItems: Bool { extra["items"] != nil }

    /// Everything typed on the page or in its presenter notes, for search.
    var typedText: String {
        let notes = notes
        guard hasItems else { return notes }
        let boxes = items.compactMap { $0.text?.string.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return (boxes + (notes.isEmpty ? [] : [notes])).joined(separator: "\n")
    }
}
