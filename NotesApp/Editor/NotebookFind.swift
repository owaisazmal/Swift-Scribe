import UIKit
import PDFKit
import Vision
import PencilKit

/// One place the words being looked for were found: a rectangle on a page, in page points.
struct FindMatch: Hashable, Sendable {
    let pageID: UUID
    let page: Int
    let rect: CGRect
}

/// A line the recogniser read, kept so each new search can ask it where its words are.
struct RecognizedLine: @unchecked Sendable {
    let text: VNRecognizedText
}

/// Where words are on a page: in what was typed, in a PDF's own text, and in what the recogniser reads of ink and scans.
enum NotebookFind {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func contains(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: options) != nil
    }

    /// A text box that holds the words is marked whole.
    static func typed(_ query: String, on page: NotebookPage) -> [CGRect] {
        guard page.hasItems else { return [] }
        return page.items.compactMap { item in
            guard let box = item.text, contains(box.string, query) else { return nil }
            let cosine = abs(cos(item.rotation)), sine = abs(sin(item.rotation))
            let width = item.size.width * cosine + item.size.height * sine, height = item.size.width * sine + item.size.height * cosine
            return CGRect(x: item.center.x - width / 2, y: item.center.y - height / 2, width: width, height: height)
        }
    }

    static func read(_ image: UIImage) -> [RecognizedLine]? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) } catch { return nil }
        return request.results?.compactMap { $0.topCandidates(1).first.map(RecognizedLine.init) } ?? []
    }

    /// The image the lines were read from filled the page, so their boxes are fractions of it, measured from the bottom.
    static func rects(for query: String, in lines: [RecognizedLine], pageSize: CGSize) -> [CGRect] {
        var rects: [CGRect] = []
        for line in lines {
            let string = line.text.string
            var range = string.startIndex..<string.endIndex
            while let found = string.range(of: query, options: options, range: range) {
                if let box = try? line.text.boundingBox(for: found)?.boundingBox {
                    rects.append(CGRect(x: box.minX * pageSize.width, y: (1 - box.maxY) * pageSize.height,
                                        width: box.width * pageSize.width, height: box.height * pageSize.height))
                }
                range = found.upperBound..<string.endIndex
            }
        }
        return rects
    }

    static func pdfRects(for query: String, on page: PDFPage, pageSize: CGSize) -> [CGRect] {
        guard let text = page.string as NSString? else { return [] }
        let toPage = transform(of: page, to: pageSize)
        var rects: [CGRect] = [], range = NSRange(location: 0, length: text.length)
        while range.length > 0 {
            let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: range)
            guard found.location != NSNotFound else { break }
            for line in page.selection(for: found)?.selectionsByLine() ?? [] {
                let rect = line.bounds(for: page).applying(toPage).standardized
                if rect.width > 0, rect.height > 0 { rects.append(rect) }
            }
            range = NSRange(location: found.upperBound, length: text.length - found.upperBound)
        }
        return rects
    }

    /// From a PDF page's own space to the page as it is shown: the same turn and flip the page is drawn with.
    static func transform(of page: PDFPage, to size: CGSize) -> CGAffineTransform {
        let box = page.bounds(for: .cropBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        let display = rotation == 90 || rotation == 270 ? CGSize(width: box.height, height: box.width) : box.size
        var transform = CGAffineTransform(translationX: 0, y: size.height)
            .scaledBy(x: size.width / max(display.width, 1), y: -size.height / max(display.height, 1))
        switch rotation {
        case 90: transform = transform.translatedBy(x: 0, y: display.height).rotated(by: -.pi / 2)
        case 180: transform = transform.translatedBy(x: display.width, y: display.height).rotated(by: .pi)
        case 270: transform = transform.translatedBy(x: display.width, y: 0).rotated(by: .pi / 2)
        default: break
        }
        return transform.translatedBy(x: -box.minX, y: -box.minY)
    }

    /// Changes whenever the ink does, without reading every stroke.
    static func fingerprint(_ ink: PKDrawing) -> String {
        "\(ink.strokes.count)|\(ink.bounds)|\(ink.strokes.last?.path.creationDate.timeIntervalSince1970 ?? 0)"
    }

    /// Top to bottom, then left to right, the way the page is read.
    static func inReadingOrder(_ rects: [CGRect]) -> [CGRect] {
        rects.sorted { abs($0.midY - $1.midY) > min($0.height, $1.height) / 2 ? $0.midY < $1.midY : $0.minX < $1.minX }
    }
}

/// Does the reading off the main thread, and keeps what it has read so the next search of the same page is quick.
actor FindReader {
    private var lines: [String: [RecognizedLine]] = [:]
    private var pdfs: [String: PDFDocument] = [:]

    func inkRects(for query: String, page: NotebookPage, ink: PKDrawing, assets: URL) -> [CGRect] {
        guard !ink.strokes.isEmpty else { return [] }
        let key = "ink-\(page.id.uuidString)-\(NotebookFind.fingerprint(ink))"
        return rects(for: query, key: key, pageSize: page.size) {
            PageRenderer.image(of: page, ink: ink, assets: assets, width: 1400, includeBackground: false)
        }
    }

    func pictureRects(for query: String, file: URL, pageSize: CGSize) -> [CGRect] {
        rects(for: query, key: "picture-\(file.lastPathComponent)", pageSize: pageSize) { UIImage(contentsOfFile: file.path(percentEncoded: false)) }
    }

    private func rects(for query: String, key: String, pageSize: CGSize, image: () -> UIImage?) -> [CGRect] {
        if lines[key] == nil {
            guard let image = image(), let read = NotebookFind.read(image) else { return [] }
            if lines.count > 400 { lines.removeAll() }
            lines[key] = read
        }
        return NotebookFind.rects(for: query, in: lines[key] ?? [], pageSize: pageSize)
    }

    func pdfRects(for query: String, file: URL, index: Int, pageSize: CGSize) -> [CGRect] {
        let key = file.path(percentEncoded: false)
        if pdfs[key] == nil { pdfs[key] = PDFDocument(url: file) }
        guard let page = pdfs[key]?.page(at: index) else { return [] }
        return NotebookFind.pdfRects(for: query, on: page, pageSize: pageSize)
    }
}

/// Find in the notebook that is open: what is being looked for, where it was found, and which match is shown.
@MainActor
@Observable
final class NotebookFinder {
    private(set) var query = ""
    private(set) var matches: [FindMatch] = []
    private(set) var current: FindMatch?
    private(set) var isSearching = false
    @ObservationIgnored private let document: NotebookDocument
    @ObservationIgnored private let reader = FindReader()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Called when the matches or the one being shown change.
    @ObservationIgnored var onChange: (() -> Void)?
    /// The page a search starts from, so the first match shown is the nearest one ahead.
    @ObservationIgnored var startPage: () -> Int = { 0 }
    @ObservationIgnored var delay = Duration.milliseconds(300)

    init(document: NotebookDocument) {
        self.document = document
    }

    var position: Int? { current.flatMap(matches.firstIndex(of:)) }

    func search(_ text: String) {
        task?.cancel()
        query = text
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return reset() }
        isSearching = true
        task = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.run(needle)
        }
    }

    func clear() {
        task?.cancel()
        query = ""
        reset()
    }

    private func reset() {
        matches = []
        current = nil
        isSearching = false
        onChange?()
    }

    /// Reads from the page being looked at to the end, then from the start, so the nearest match ahead comes first.
    private func run(_ needle: String) async {
        let pages = document.pages
        guard !pages.isEmpty else { return reset() }
        let start = min(max(startPage(), 0), pages.count - 1)
        var found: [Int: [FindMatch]] = [:]
        matches = []
        current = nil
        onChange?()
        for index in Array(start..<pages.count) + Array(0..<start) {
            let rects = await rects(for: needle, on: pages[index])
            if Task.isCancelled { return }
            guard !rects.isEmpty else { continue }
            found[index] = rects.map { FindMatch(pageID: pages[index].id, page: index, rect: $0) }
            matches = found.keys.sorted().flatMap { found[$0] ?? [] }
            if current == nil { current = found[index]?.first }
            onChange?()
        }
        isSearching = false
        let count = matches.count
        AccessibilityNotification.Announcement(count == 0 ? String(localized: "No matches") : count == 1 ? String(localized: "1 match")
                                                                                                         : String(localized: "\(count) matches")).post()
    }

    private func rects(for needle: String, on page: NotebookPage) async -> [CGRect] {
        var rects = NotebookFind.typed(needle, on: page)
        let package = document.package, unsaved = document.hasUnsavedInk(page.id)
        // What the page was last read as, while that is still what is on it, says whether it is worth reading again.
        if !unsaved, let text = await package.readText(page.id), text.hasPrefix(HandwritingIndexer.header(for: page)),
           !NotebookFind.contains(text, needle) { return rects }
        switch page.background {
        case .pdf(let file, let index):
            rects += await reader.pdfRects(for: needle, file: package.assetURL(file), index: index, pageSize: page.size)
        case .image(let file):
            rects += await reader.pictureRects(for: needle, file: package.assetURL(file), pageSize: page.size)
        case .template, .unknown:
            break
        }
        if page.inkHash != nil || unsaved {
            let ink = await document.ink(page.id)
            rects += await reader.inkRects(for: needle, page: page, ink: ink, assets: package.assetsDirectory)
        }
        return NotebookFind.inReadingOrder(rects)
    }

    /// The next match, or the one before; past either end it comes round again.
    func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        let index = ((position ?? (delta > 0 ? -1 : 0)) + delta + matches.count) % matches.count
        current = matches[index]
        onChange?()
        AccessibilityNotification.Announcement(String(localized: "Match \(index + 1) of \(matches.count), page \(matches[index].page + 1)")).post()
    }
}
