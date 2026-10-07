import UIKit

/// The 512-pixel pieces of a page's paper that reach part of it, when it is drawn at `density` pixels per point.
struct PaperTiles: Equatable {
    static let side = 512

    let density: CGFloat
    private let width: Int
    private let height: Int
    private(set) var columns = 0..<0
    private(set) var rows = 0..<0

    init(size: CGSize, density: CGFloat, reaching keep: CGRect) {
        self.density = density
        width = Int((size.width * density).rounded(.up))
        height = Int((size.height * density).rounded(.up))
        let area = keep.intersection(CGRect(origin: .zero, size: size))
        guard density > 0, !area.isNull, !area.isEmpty else { return }
        let step = CGFloat(Self.side) / density
        func range(_ low: CGFloat, _ high: CGFloat, limit: Int) -> Range<Int> {
            let first = Int(low / step)
            return first..<max(first, min(Int((high / step).rounded(.up)), (limit + Self.side - 1) / Self.side))
        }
        columns = range(area.minX, area.maxX, limit: width)
        rows = range(area.minY, area.maxY, limit: height)
    }

    var count: Int { columns.count * rows.count }

    func contains(column: Int, row: Int) -> Bool { columns.contains(column) && rows.contains(row) }

    /// A piece's place on the page, in pixels. Pieces on the right and bottom edges stop where the page does.
    func pixels(column: Int, row: Int) -> CGRect {
        let x = column * Self.side, y = row * Self.side
        return CGRect(x: x, y: y, width: min(Self.side, width - x), height: min(Self.side, height - y))
    }
}

private final class PaperTileLayer: CALayer {
    override func action(forKey event: String) -> CAAction? { nil }
}

/// A page's paper near the viewport, drawn off the main thread and shown by plain layers. Unlike CATiledLayer, it commits nothing there.
final class PagePaperView: UIView {
    private struct Key: Hashable {
        let density: CGFloat
        let column: Int
        let row: Int
    }

    private final class Tile {
        let layer = PaperTileLayer()
        let pixels: CGRect
        var work: Operation?

        init(pixels: CGRect) { self.pixels = pixels }
        deinit { work?.cancel() }
    }

    /// Its own few threads, so a heavy PDF page never holds up loading ink.
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.owais.OwlLuna.paper"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        return queue
    }()

    private let page: NotebookPage
    private let assets: URL
    private var unit: CGFloat = 0
    private var tiles: [Key: Tile] = [:]
    private var shown: PaperTiles?

    init(page: NotebookPage, assets: URL) {
        self.page = page
        self.assets = assets
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        layer.anchorPoint = .zero
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `unit` is the points a page point takes at zoom 1. The view is scaled by the zoom, so its pieces never move.
    func fit(unit: CGFloat, zoom: CGFloat) {
        if unit != self.unit {
            clear()
            self.unit = unit
            bounds = CGRect(x: 0, y: 0, width: page.size.width * unit, height: page.size.height * unit)
        }
        let scale = CGAffineTransform(scaleX: zoom, y: zoom)
        if transform != scale { transform = scale }
    }

    /// Shows the pieces that reach `keep`, a part of this view, drawn at `density` pixels per point.
    func show(near keep: CGRect, density: CGFloat) {
        let wanted = PaperTiles(size: bounds.size, density: density, reaching: keep)
        guard wanted != shown else { return }
        shown = wanted
        for (key, tile) in tiles {
            let current = key.density == density
            if current ? !wanted.contains(column: key.column, row: key.row) : !tile.layer.frame.intersects(keep) { remove(key) }
        }
        var missing: [(key: Key, pixels: CGRect, distance: CGFloat)] = []
        for row in wanted.rows {
            for column in wanted.columns where tiles[Key(density: density, column: column, row: row)] == nil {
                let pixels = wanted.pixels(column: column, row: row)
                missing.append((Key(density: density, column: column, row: row), pixels,
                                hypot(pixels.midX / density - keep.midX, pixels.midY / density - keep.midY)))
            }
        }
        for piece in missing.sorted(by: { $0.distance < $1.distance }) { add(piece.key, pixels: piece.pixels) }
        dropStale()
    }

    func clear() {
        for key in Array(tiles.keys) { remove(key) }
        shown = nil
    }

    /// For tests: the pixels held, and whether every piece wanted has been drawn.
    var pixelCount: Int { tiles.values.reduce(0) { $0 + Int($1.pixels.width * $1.pixels.height) } }
    var isDrawn: Bool { shown?.count == tiles.count && tiles.values.allSatisfy { $0.work == nil } }

    private func add(_ key: Key, pixels: CGRect) {
        let tile = Tile(pixels: pixels)
        tile.layer.frame = CGRect(x: pixels.minX / key.density, y: pixels.minY / key.density,
                                  width: pixels.width / key.density, height: pixels.height / key.density)
        tile.layer.isOpaque = true
        layer.addSublayer(tile.layer)
        tiles[key] = tile
        let work = BlockOperation()
        work.addExecutionBlock { [weak self, weak work, page, assets, unit] in
            guard let work, !work.isCancelled else { return }
            let image = PagePaperView.image(of: page, assets: assets, unit: unit, density: key.density, pixels: pixels).map(SharedImage.init)
            DispatchQueue.main.async { self?.show(image, at: key, from: work) }
        }
        tile.work = work
        Self.queue.addOperation(work)
    }

    private func show(_ image: SharedImage?, at key: Key, from work: Operation) {
        guard let tile = tiles[key], tile.work === work else { return }
        tile.work = nil
        tile.layer.contents = image?.image
        dropStale()
    }

    /// Pieces drawn for another zoom stay under the new ones until those are all in.
    private func dropStale() {
        guard let shown, !tiles.contains(where: { $0.key.density == shown.density && $0.value.work != nil }) else { return }
        for key in Array(tiles.keys) where key.density != shown.density { remove(key) }
    }

    private func remove(_ key: Key) {
        tiles.removeValue(forKey: key)?.layer.removeFromSuperlayer()
    }

    /// One piece as an opaque image. Core Graphics only, so it is safe on any thread and touches no layer.
    nonisolated static func image(of page: NotebookPage, assets: URL, unit: CGFloat, density: CGFloat, pixels: CGRect) -> CGImage? {
        let width = Int(pixels.width), height = Int(pixels.height)
        let format = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: format)
        else { return nil }
        ctx.setFillColor(PageRenderer.paperColor(page.effectivePaperColor).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: -pixels.minX, y: pixels.maxY)
        ctx.scaleBy(x: density, y: -density)
        PageRenderer.drawBackground(page, assets: assets, in: ctx, size: CGSize(width: page.size.width * unit, height: page.size.height * unit), items: false)
        return ctx.makeImage()
    }
}
