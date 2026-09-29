import SwiftUI
import UIKit
import PencilKit
import os

struct PageStack: UIViewControllerRepresentable {
    let session: EditorSession

    func makeUIViewController(context: Context) -> PageStackController {
        let controller = PageStackController(session: session)
        session.canvas = controller
        return controller
    }

    func updateUIViewController(_ controller: PageStackController, context: Context) {}
}

/// Page frames in page points, stacked vertically and centred on the widest page.
struct PageStackLayout {
    static let margin: CGFloat = 16

    private(set) var frames: [CGRect] = []
    private(set) var size = CGSize(width: 1, height: 1)

    init(pages: [NotebookPage] = []) {
        let width = (pages.map(\.size.width).max() ?? PageSize.letter.points.width) + Self.margin * 2
        var y = Self.margin
        frames = pages.map { page in
            defer { y += page.size.height + Self.margin }
            return CGRect(x: ((width - page.size.width) / 2).rounded(), y: y, width: page.size.width, height: page.size.height)
        }
        size = CGSize(width: width, height: max(y, 1))
    }

    /// The page at `y`, counting the gap below a page as part of it.
    func pageIndex(atY y: CGFloat) -> Int {
        guard !frames.isEmpty else { return 0 }
        var low = 0, high = frames.count - 1
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].maxY + Self.margin / 2 < y { low = mid + 1 } else { high = mid }
        }
        return low
    }

    func range(from top: CGFloat, to bottom: CGFloat) -> ClosedRange<Int>? {
        guard !frames.isEmpty else { return nil }
        let first = pageIndex(atY: top)
        var last = first
        while last + 1 < frames.count, frames[last + 1].minY <= bottom { last += 1 }
        return first...last
    }
}

/// A canvas bound to one page. Its undo manager is a proxy so PencilKit never writes to the document stack.
final class PageCanvasView: PKCanvasView {
    var pageID: UUID?
    var isLoaded = false
    weak var undoProxy: UndoManager?

    override var undoManager: UndoManager? { undoProxy ?? super.undoManager }

    override var accessibilityValue: String? {
        get {
            let count = drawing.strokes.count
            return count == 0 ? String(localized: "Empty") : count == 1 ? String(localized: "1 stroke") : String(localized: "\(count) strokes")
        }
        set {}
    }
}

/// Stays first responder so one tool picker serves every page, and routes ⌘Z and the picker's undo to the document.
final class ToolPickerAnchor: UIView {
    weak var undoProxy: UndoManager?
    override var canBecomeFirstResponder: Bool { true }
    override var undoManager: UndoManager? { undoProxy ?? super.undoManager }
}

private final class ChunkTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0 }
}

/// A 256-point piece of a page background. Pieces exist only near the viewport, so tile caches stay bounded at 5×.
final class PageBackgroundChunk: UIView {
    override class var layerClass: AnyClass { ChunkTiledLayer.self }

    static let size: CGFloat = 256
    let region: CGRect
    private let page: NotebookPage
    private let assets: URL
    private let unit: CGFloat

    init(page: NotebookPage, assets: URL, region: CGRect, unit: CGFloat) {
        self.page = page
        self.assets = assets
        self.region = region
        self.unit = unit
        super.init(frame: CGRect(x: 0, y: 0, width: region.width * unit, height: region.height * unit))
        isOpaque = true
        isUserInteractionEnabled = false
        layer.anchorPoint = .zero
        let tiled = layer as! CATiledLayer
        tiled.levelsOfDetail = 7
        tiled.levelsOfDetailBias = 4
        tiled.tileSize = CGSize(width: 512, height: 512)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.translateBy(x: -region.minX * unit, y: -region.minY * unit)
        PageRenderer.drawBackground(page, assets: assets, in: ctx, size: CGSize(width: page.size.width * unit, height: page.size.height * unit))
    }
}

final class PageSlotView: UIView {
    let page: NotebookPage
    var chunks: [Int: PageBackgroundChunk] = [:]
    weak var canvas: PageCanvasView?

    init(page: NotebookPage) {
        self.page = page
        super.init(frame: .zero)
        backgroundColor = PageRenderer.paperColor(page.effectivePaperColor)
        clipsToBounds = true
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError() }
}

@MainActor
final class PageStackController: UIViewController, UIScrollViewDelegate, PKCanvasViewDelegate, PKToolPickerObserver,
                                 InkObserver, EditorCanvasControlling {
    private let session: EditorSession
    private var document: NotebookDocument { session.document }
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let anchor = ToolPickerAnchor()
    private let toolPicker = PKToolPicker()
    private let undoProxy: CanvasUndoProxy
    private let signposter = OSSignposter(subsystem: "com.owais.NotesApp", category: "editor")

    private var layout = PageStackLayout()
    private var pages: [NotebookPage] = []
    private var fitScale: CGFloat = 1
    private var bakedScale: CGFloat = 1
    private(set) var zoom: CGFloat = 1
    private(set) var minimumZoom: CGFloat = 1
    let maximumZoom: CGFloat = 5

    private var slots: [UUID: PageSlotView] = [:]
    private var canvases: [UUID: PageCanvasView] = [:]
    private var pool: [PageCanvasView] = []
    private var canvasWindow: ClosedRange<Int>?
    private var isApplyingDrawing = false
    private var isBaking = false
    private var lastBounds: CGRect = .zero
    private var toolPickerSuppressed = false
    private var firstInkPage: UUID?
    private var firstInkReported = false
    private let openedAt = CACurrentMediaTime()
    private var openInterval: OSSignpostIntervalState?

    /// Called once when the first visible page has its ink on screen (for tests and the open signpost).
    var onFirstInk: ((TimeInterval) -> Void)?

    init(session: EditorSession) {
        self.session = session
        undoProxy = CanvasUndoProxy(document: session.document.undoManager)
        super.init(nibName: nil, bundle: nil)
        openInterval = signposter.beginInterval("Open to first ink")
        document.inkObserver = self
        document.onStructureChange = { [weak self] in self?.pagesDidChange() }
        pages = document.pages
        layout = PageStackLayout(pages: pages)
    }

    required init?(coder: NSCoder) { fatalError() }

    var liveCanvasCount: Int { canvases.count }

    func canvas(forPage index: Int) -> PageCanvasView? {
        pages.indices.contains(index) ? canvases[pages[index].id] : nil
    }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .desk
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.bouncesZoom = true
        let fingers = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.panGestureRecognizer.allowedTouchTypes = fingers
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        anchor.undoProxy = undoProxy
        anchor.frame = .zero
        view.addSubview(anchor)
        toolPicker.addObserver(self)
        toolPicker.colorUserInterfaceStyle = .light
        toolPicker.stateAutosaveName = "SwiftScribe.ToolPicker"
        applyDrawingPolicy(session.drawingInput.policy)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (self: Self, _) in
            self.updatePageEdges()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setToolPickerVisible(session.isToolPickerVisible)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        toolPicker.setVisible(false, forFirstResponder: anchor)
        for canvas in canvases.values { toolPicker.setVisible(false, forFirstResponder: canvas) }
        anchor.resignFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0, bounds.size != lastBounds.size else { return }
        let isFirst = lastBounds == .zero
        let page = isFirst ? session.currentPage : currentPage
        lastBounds = bounds
        fitScale = bounds.width / layout.size.width
        let tallest = layout.frames.map(\.height).max() ?? 1
        minimumZoom = min(1, bounds.height / (tallest + PageStackLayout.margin * 2) / fitScale)
        for slot in slots.values { removeChunks(slot) }
        if isFirst { firstInkPage = pages.indices.contains(page) ? pages[page].id : nil }
        bake(zoom: zoom)
        scrollToPage(page, animated: false)
        updateWindow(force: true)
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(title: String(localized: "Next Page"), action: #selector(nextPage), input: UIKeyCommand.inputPageDown),
         UIKeyCommand(title: String(localized: "Previous Page"), action: #selector(previousPage), input: UIKeyCommand.inputPageUp)]
    }

    @objc private func nextPage() { session.go(to: min(currentPage + 1, pages.count - 1)) }
    @objc private func previousPage() { session.go(to: max(currentPage - 1, 0)) }

    // MARK: Layout and zoom

    private var effectiveScale: CGFloat { bakedScale * scrollView.zoomScale }

    private func bake(zoom newZoom: CGFloat) {
        zoom = min(max(newZoom, minimumZoom), maximumZoom)
        bakedScale = zoom * fitScale
        isBaking = true
        scrollView.minimumZoomScale = min(scrollView.minimumZoomScale, 1)
        scrollView.maximumZoomScale = max(scrollView.maximumZoomScale, 1)
        scrollView.zoomScale = 1
        contentView.transform = .identity
        contentView.frame = CGRect(x: 0, y: 0, width: layout.size.width * bakedScale, height: layout.size.height * bakedScale)
        scrollView.contentSize = contentView.frame.size
        scrollView.minimumZoomScale = minimumZoom / zoom
        scrollView.maximumZoomScale = maximumZoom / zoom
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        for (id, slot) in slots {
            guard let index = index(of: id) else { continue }
            position(slot, at: index)
            for chunk in slot.chunks.values { position(chunk) }
            if let canvas = slot.canvas { place(canvas, in: slot) }
        }
        updateInsets()
        isBaking = false
    }

    private func position(_ slot: PageSlotView, at index: Int) {
        let frame = layout.frames[index]
        slot.frame = CGRect(x: frame.minX * bakedScale, y: frame.minY * bakedScale, width: frame.width * bakedScale, height: frame.height * bakedScale)
    }

    private func position(_ chunk: PageBackgroundChunk) {
        chunk.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        chunk.layer.position = CGPoint(x: chunk.region.minX * bakedScale, y: chunk.region.minY * bakedScale)
    }

    private func updateInsets() {
        let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
        let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
        let obscured = toolPicker.isVisible ? toolPicker.frameObscured(in: view) : .null
        let bottom = obscured.isNull ? vertical : max(vertical, view.bounds.maxY - obscured.minY)
        scrollView.contentInset = UIEdgeInsets(top: vertical + view.safeAreaInsets.top, left: horizontal, bottom: bottom, right: horizontal)
    }

    private func clamped(_ offset: CGPoint) -> CGPoint {
        let inset = scrollView.contentInset
        let minX = -inset.left, minY = -inset.top
        let maxX = max(minX, scrollView.contentSize.width + inset.right - scrollView.bounds.width)
        let maxY = max(minY, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        return CGPoint(x: min(max(offset.x, minX), maxX), y: min(max(offset.y, minY), maxY))
    }

    private func index(of id: UUID) -> Int? { pages.firstIndex { $0.id == id } }

    var currentPage: Int {
        guard effectiveScale > 0, !pages.isEmpty else { return 0 }
        return layout.pageIndex(atY: (scrollView.contentOffset.y + scrollView.adjustedContentInset.top + scrollView.bounds.height * 0.3) / effectiveScale)
    }

    func setZoom(_ newZoom: CGFloat) {
        guard !pages.isEmpty else { return }
        let page = currentPage
        bake(zoom: newZoom)
        let frame = layout.frames[page]
        scrollView.contentOffset = clamped(CGPoint(x: (frame.minX + 40) * bakedScale - scrollView.contentInset.left,
                                                   y: (frame.minY + 40) * bakedScale - scrollView.contentInset.top))
        updateWindow(force: true)
    }

    func scrollToPage(_ index: Int, animated: Bool = false) {
        guard layout.frames.indices.contains(index) else { return }
        let y = (layout.frames[index].minY - PageStackLayout.margin / 2) * effectiveScale - scrollView.contentInset.top
        scrollView.setContentOffset(clamped(CGPoint(x: scrollView.contentOffset.x, y: y)), animated: animated)
        if !animated { updateWindow() }
    }

    func scrollBy(viewportFraction: CGFloat) {
        let offset = scrollView.contentOffset
        scrollView.contentOffset = clamped(CGPoint(x: offset.x, y: offset.y + viewportFraction * scrollView.bounds.height))
        updateWindow()
    }

    // MARK: Window of live pages

    private func visibleRange() -> ClosedRange<Int>? {
        guard effectiveScale > 0 else { return nil }
        return layout.range(from: scrollView.bounds.minY / effectiveScale, to: scrollView.bounds.maxY / effectiveScale)
    }

    private func updateWindow(force: Bool = false) {
        guard isViewLoaded, !isBaking, let visible = visibleRange() else { return }
        let count = pages.count
        let window = max(0, visible.lowerBound - 1)...min(count - 1, visible.upperBound + 1)
        if force || window != canvasWindow {
            canvasWindow = window
            let keep = Set(pages[window].map(\.id))
            for id in Array(slots.keys) where !keep.contains(id) { removeSlot(id) }
            for index in window {
                let page = pages[index]
                let slot = slots[page.id] ?? makeSlot(page, at: index)
                if slot.canvas == nil { attachCanvas(page, to: slot) }
            }
            let prefetch = max(0, visible.lowerBound - 3)...min(count - 1, visible.upperBound + 3)
            for index in prefetch where document.loadedInk(pages[index].id) == nil {
                let id = pages[index].id
                Task { _ = await document.ink(id) }
            }
        }
        for index in canvasWindow ?? window {
            guard let slot = slots[pages[index].id] else { continue }
            if let canvas = slot.canvas { place(canvas, in: slot) }
            updateChunks(in: slot)
        }
        let page = currentPage
        if page != session.currentPage { session.pageDidChange(page) }
    }

    private func makeSlot(_ page: NotebookPage, at index: Int) -> PageSlotView {
        let slot = PageSlotView(page: page)
        slot.layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
        slot.layer.borderColor = UIColor.hairline.resolvedColor(with: traitCollection).cgColor
        position(slot, at: index)
        contentView.addSubview(slot)
        slots[page.id] = slot
        return slot
    }

    private func removeSlot(_ id: UUID) {
        recycleCanvas(id)
        guard let slot = slots.removeValue(forKey: id) else { return }
        removeChunks(slot)
        slot.removeFromSuperview()
    }

    private func removeChunks(_ slot: PageSlotView) {
        slot.chunks.values.forEach { $0.removeFromSuperview() }
        slot.chunks.removeAll()
    }

    private func updatePageEdges() {
        for slot in slots.values { slot.layer.borderColor = UIColor.hairline.resolvedColor(with: traitCollection).cgColor }
    }

    private func updateChunks(in slot: PageSlotView) {
        let page = slot.page
        let viewport = slot.convert(scrollView.bounds, from: scrollView)
        let keep = viewport.insetBy(dx: -viewport.width / 2, dy: -viewport.height / 2).intersection(slot.bounds)
        var needed = Set<Int>()
        let size = PageBackgroundChunk.size
        if !keep.isNull, !keep.isEmpty, bakedScale > 0 {
            let columns = Int((page.size.width / size).rounded(.up)), rows = Int((page.size.height / size).rounded(.up))
            let c0 = max(0, Int(keep.minX / bakedScale / size)), c1 = min(columns - 1, Int(keep.maxX / bakedScale / size))
            let r0 = max(0, Int(keep.minY / bakedScale / size)), r1 = min(rows - 1, Int(keep.maxY / bakedScale / size))
            if c0 <= c1, r0 <= r1 {
                for row in r0...r1 { for column in c0...c1 { needed.insert(row * 1000 + column) } }
            }
        }
        for (key, chunk) in slot.chunks where !needed.contains(key) {
            chunk.removeFromSuperview()
            slot.chunks.removeValue(forKey: key)
        }
        for key in needed where slot.chunks[key] == nil {
            let x = CGFloat(key % 1000) * size, y = CGFloat(key / 1000) * size
            let region = CGRect(x: x, y: y, width: min(size, page.size.width - x), height: min(size, page.size.height - y))
            let chunk = PageBackgroundChunk(page: page, assets: document.package.assetsDirectory, region: region, unit: fitScale)
            position(chunk)
            slot.insertSubview(chunk, at: 0)
            slot.chunks[key] = chunk
        }
    }

    // MARK: Canvases

    private func makeCanvas() -> PageCanvasView {
        let canvas = PageCanvasView()
        canvas.undoProxy = undoProxy
        canvas.delegate = self
        canvas.isScrollEnabled = false
        canvas.bounces = false
        canvas.bouncesZoom = false
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.clipsToBounds = true
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = session.drawingInput.policy
        canvas.maximumSupportedContentVersion = .latest
        canvas.isAccessibilityElement = true
        canvas.accessibilityTraits = .allowsDirectInteraction
        toolPicker.addObserver(canvas)
        return canvas
    }

    private func attachCanvas(_ page: NotebookPage, to slot: PageSlotView) {
        let canvas = pool.popLast() ?? makeCanvas()
        canvas.pageID = page.id
        let number = (index(of: page.id) ?? 0) + 1
        canvas.accessibilityLabel = String(localized: "Page \(number), handwriting")
        canvas.accessibilityIdentifier = "page.canvas.\(number)"
        place(canvas, in: slot)
        slot.addSubview(canvas)
        slot.canvas = canvas
        canvases[page.id] = canvas
        if toolPicker.isVisible { toolPicker.setVisible(true, forFirstResponder: canvas) }
        if let ink = document.loadedInk(page.id) {
            show(ink, in: canvas)
        } else {
            setDrawingEnabled(false, canvas)
            let id = page.id
            Task { [weak self] in
                guard let self else { return }
                let ink = await document.ink(id)
                if canvas.pageID == id { show(ink, in: canvas) }
            }
        }
    }

    private func show(_ ink: PKDrawing, in canvas: PageCanvasView) {
        isApplyingDrawing = true
        canvas.drawing = ink
        isApplyingDrawing = false
        canvas.isLoaded = true
        setDrawingEnabled(!document.isReadOnly, canvas)
        if !firstInkReported, canvas.pageID == firstInkPage, ink.strokes.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.reportFirstInk() }
        }
    }

    private func setDrawingEnabled(_ enabled: Bool, _ canvas: PageCanvasView) {
        canvas.drawingGestureRecognizer.isEnabled = enabled
    }

    private func recycleCanvas(_ id: UUID) {
        guard let canvas = canvases.removeValue(forKey: id) else { return }
        toolPicker.setVisible(false, forFirstResponder: canvas)
        if canvas.isFirstResponder { anchor.becomeFirstResponder() }
        canvas.removeFromSuperview()
        canvas.pageID = nil
        canvas.isLoaded = false
        slots[id]?.canvas = nil
        isApplyingDrawing = true
        canvas.drawing = PKDrawing()
        isApplyingDrawing = false
        if pool.count < 3 { pool.append(canvas) } else { toolPicker.removeObserver(canvas) }
    }

    /// Canvases are a viewport-sized window onto their page: PencilKit only backs what can be seen, even at 5×.
    private func place(_ canvas: PageCanvasView, in slot: PageSlotView) {
        let s = bakedScale
        if canvas.zoomScale != s || canvas.minimumZoomScale != s || canvas.maximumZoomScale != s {
            canvas.minimumZoomScale = min(canvas.minimumZoomScale, s)
            canvas.maximumZoomScale = max(canvas.maximumZoomScale, s)
            canvas.zoomScale = s
            canvas.minimumZoomScale = s
            canvas.maximumZoomScale = s
        }
        let full = slot.bounds
        let pixel = 1 / max(traitCollection.displayScale, 1)
        let viewport = slot.convert(scrollView.bounds, from: scrollView)
        let width = min(full.width, (viewport.width / pixel).rounded(.up) * pixel)
        let height = min(full.height, (viewport.height / pixel).rounded(.up) * pixel)
        let x = min(max((viewport.minX / pixel).rounded(.down) * pixel, 0), full.width - width)
        let y = min(max((viewport.minY / pixel).rounded(.down) * pixel, 0), full.height - height)
        let target = CGRect(x: x, y: y, width: width, height: height)
        if canvas.frame != target { canvas.frame = target }
        let size = CGSize(width: slot.page.size.width * s, height: slot.page.size.height * s)
        if canvas.contentSize != size { canvas.contentSize = size }
        if canvas.contentOffset != target.origin { canvas.contentOffset = target.origin }
    }

    // MARK: PKCanvasViewDelegate

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingDrawing, let canvas = canvasView as? PageCanvasView, canvas.isLoaded, let id = canvas.pageID,
              let page = pages.first(where: { $0.id == id }) else { return }
        var drawing = canvas.drawing
        if let confined = Self.confine(drawing, to: page.size) {
            drawing = confined
            isApplyingDrawing = true
            canvas.drawing = confined
            isApplyingDrawing = false
        }
        document.canvasDidChangeInk(id, to: drawing)
    }

    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        guard !firstInkReported, (canvasView as? PageCanvasView)?.pageID == firstInkPage,
              (canvasView as? PageCanvasView)?.isLoaded == true else { return }
        reportFirstInk()
    }

    private func reportFirstInk() {
        guard !firstInkReported else { return }
        firstInkReported = true
        if let openInterval { signposter.endInterval("Open to first ink", openInterval) }
        onFirstInk?(CACurrentMediaTime() - openedAt)
    }

    /// Keeps ink on its page: a new stroke that runs past the edge gets a mask at the page bounds.
    static func confine(_ drawing: PKDrawing, to size: CGSize) -> PKDrawing? {
        let page = CGRect(origin: .zero, size: size)
        guard !drawing.bounds.isNull, !page.contains(drawing.bounds) else { return nil }
        var strokes = drawing.strokes
        guard let last = strokes.last, last.mask == nil, !page.contains(last.renderBounds) else { return nil }
        strokes[strokes.count - 1].mask = UIBezierPath(rect: page.applying(last.transform.inverted()))
        return PKDrawing(strokes: strokes)
    }

    // MARK: InkObserver

    func document(_ document: NotebookDocument, didReplaceInkOf pageID: UUID) {
        guard let canvas = canvases[pageID], let ink = document.loadedInk(pageID) else { return }
        show(ink, in: canvas)
    }

    // MARK: Structure

    private func pagesDidChange() {
        let updated = document.pages
        guard updated != pages else { return }
        let anchorID = pages.indices.contains(currentPage) ? pages[currentPage].id : nil
        let anchorOffset = anchorID.flatMap { id in index(of: id).map { scrollView.contentOffset.y - layout.frames[$0].minY * effectiveScale } }
        let changed = Set(updated.map { $0 }).symmetricDifference(Set(pages)).map(\.id)
        pages = updated
        layout = PageStackLayout(pages: pages)
        for id in Set(changed) where slots[id] != nil { removeSlot(id) }
        for (id, slot) in slots {
            guard let index = index(of: id) else { removeSlot(id); continue }
            position(slot, at: index)
            slot.canvas?.accessibilityLabel = String(localized: "Page \(index + 1), handwriting")
            slot.canvas?.accessibilityIdentifier = "page.canvas.\(index + 1)"
        }
        contentView.frame = CGRect(x: 0, y: 0, width: layout.size.width * effectiveScale, height: layout.size.height * effectiveScale)
        scrollView.contentSize = contentView.frame.size
        if let anchorID, let index = index(of: anchorID), let anchorOffset {
            scrollView.contentOffset = clamped(CGPoint(x: scrollView.contentOffset.x, y: layout.frames[index].minY * effectiveScale + anchorOffset))
        } else {
            scrollView.contentOffset = clamped(scrollView.contentOffset)
        }
        updateInsets()
        updateWindow(force: true)
    }

    // MARK: EditorCanvasControlling

    func setToolPickerVisible(_ visible: Bool) {
        let shown = visible && !toolPickerSuppressed && !document.isReadOnly
        toolPicker.setVisible(shown, forFirstResponder: anchor)
        for canvas in canvases.values { toolPicker.setVisible(shown, forFirstResponder: canvas) }
        anchor.becomeFirstResponder()
    }

    func setToolPickerSuppressed(_ suppressed: Bool) {
        guard suppressed != toolPickerSuppressed else { return }
        toolPickerSuppressed = suppressed
        setToolPickerVisible(session.isToolPickerVisible)
    }

    func setDrawingPolicy(_ policy: PKCanvasViewDrawingPolicy) {
        applyDrawingPolicy(policy)
    }

    private func applyDrawingPolicy(_ policy: PKCanvasViewDrawingPolicy) {
        for canvas in canvases.values + pool { canvas.drawingPolicy = policy }
        scrollView.panGestureRecognizer.minimumNumberOfTouches = policy == .anyInput ? 2 : 1
    }

    // MARK: PKToolPickerObserver

    func toolPickerVisibilityDidChange(_ toolPicker: PKToolPicker) {
        if !toolPickerSuppressed, session.isToolPickerVisible != toolPicker.isVisible {
            session.isToolPickerVisible = toolPicker.isVisible
        }
        updateInsets()
    }

    func toolPickerFramesObscuredDidChange(_ toolPicker: PKToolPicker) {
        updateInsets()
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isBaking else { return }
        updateWindow()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !isBaking else { return }
        updateInsets()
        updateWindow()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        let before = effectiveScale
        let offset = scrollView.contentOffset
        let inset = scrollView.contentInset
        bake(zoom: zoom * scale)
        let ratio = bakedScale / before
        scrollView.contentOffset = clamped(CGPoint(x: (offset.x + inset.left) * ratio - scrollView.contentInset.left,
                                                   y: (offset.y + inset.top) * ratio - scrollView.contentInset.top))
        updateWindow(force: true)
    }
}
