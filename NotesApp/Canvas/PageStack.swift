import SwiftUI
import UIKit
import PencilKit
import os

private struct SharedSlide: @unchecked Sendable {
    let image: UIImage
}

struct PageStack: UIViewControllerRepresentable {
    let session: EditorSession
    /// The window the editor is in: its panes share one tool picker.
    var window: EditorWindow?

    func makeUIViewController(context: Context) -> PageStackController {
        let picker = window?.toolPicker ?? PKToolPicker()
        window?.toolPicker = picker
        let controller = PageStackController(session: session, toolPicker: picker)
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
    /// Counted lazily, only when an assistive technology asks, and reset whenever the drawing changes.
    var strokeCount: Int?

    override var undoManager: UndoManager? { undoProxy ?? super.undoManager }

    override var accessibilityValue: String? {
        get {
            let count = strokeCount ?? drawing.strokes.count
            strokeCount = count
            return count == 0 ? String(localized: "canvas.empty", defaultValue: "Empty") : count == 1 ? String(localized: "1 stroke") : String(localized: "\(count) strokes")
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

    /// CATiledLayer draws on background threads.
    nonisolated override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.translateBy(x: -region.minX * unit, y: -region.minY * unit)
        PageRenderer.drawBackground(page, assets: assets, in: ctx, size: CGSize(width: page.size.width * unit, height: page.size.height * unit), items: false)
    }
}

final class PageSlotView: UIView {
    var page: NotebookPage
    var chunks: [Int: PageBackgroundChunk] = [:]
    weak var canvas: PageCanvasView?
    private(set) var itemViews: [UUID: PageItemView] = [:]

    /// Pictures, stickers, text and links sit above the paper and below the canvas, back to front. Study tape sits
    /// above the canvas, so it covers the ink.
    func syncItems(assets: URL, scale: CGFloat, links: LinkTitles, lifted: Set<UUID>, onActivate: @escaping (UUID) -> Void) {
        let items = page.items.filter { $0.content != .unknown }
        let keep = Set(items.map(\.id))
        for (id, view) in itemViews where !keep.contains(id) {
            view.removeFromSuperview()
            itemViews[id] = nil
        }
        for item in items {
            let view = itemViews[item.id] ?? PageItemView(item: item, assets: assets)
            view.update(item, onDark: page.effectivePaperColor.isDark, links: links, lifted: lifted.contains(item.id))
            view.onActivate = onActivate
            view.layout(scale: scale)
            itemViews[item.id] = view
            if item.isOverInk {
                continue
            } else if let canvas, canvas.superview === self {
                insertSubview(view, belowSubview: canvas)
            } else {
                addSubview(view)
            }
        }
        raiseTape()
    }

    /// Puts the tape back over the canvas, after either was added. Each goes in just above the canvas, so the last
    /// strip in the page's list ends on top and whatever is selected stays above them all.
    func raiseTape() {
        for item in page.items.reversed() where item.isOverInk {
            guard let view = itemViews[item.id] else { continue }
            if let canvas, canvas.superview === self { insertSubview(view, aboveSubview: canvas) } else { addSubview(view) }
        }
    }

    func showLifted(_ lifted: Set<UUID>, links: LinkTitles) {
        for item in page.items where item.isOverInk {
            itemViews[item.id]?.update(item, onDark: page.effectivePaperColor.isDark, links: links, lifted: lifted.contains(item.id))
        }
    }

    func layoutItems(scale: CGFloat) {
        for view in itemViews.values { view.layout(scale: scale) }
    }

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
                                 InkObserver, EditorCanvasControlling, UIGestureRecognizerDelegate, UIDropInteractionDelegate, UITextViewDelegate {
    private let session: EditorSession
    private var document: NotebookDocument { session.document }
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let anchor = ToolPickerAnchor()
    private let toolPicker: PKToolPicker
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
    private let laser = LaserTrailView()
    private lazy var laserGesture = UILongPressGestureRecognizer(target: self, action: #selector(pointLaser))
    private(set) var isPresenting = false
    /// The recording being replayed with its ink, and how far it has got.
    private var replay: (timeline: ReplayTimeline, time: TimeInterval)?
    /// The strokes each live canvas is showing faintly.
    private var replayPending: [UUID: Set<Int>] = [:]
    /// The overlay for selecting ink across pages, while that is on, and what has been caught.
    private var inkLasso: InkLassoOverlay?
    private var inkSelection: InkSelection = [:]
    private var lassoMoveOrigin: CGPoint?
    private var isMovingInk = false
    private lazy var lassoPan = UIPanGestureRecognizer(target: self, action: #selector(lassoPanned))
    /// Nothing on the page can be changed by hand while it is presented or replayed, or while ink is being selected.
    private var isLocked: Bool { isPresenting || replay != nil || inkLasso != nil }
    private var selectionView: ItemSelectionView?
    private var linkTitles = LinkTitles()
    private var textView: UITextView?
    private var typing: ItemSelection?
    private var keyboardOverlap: CGFloat = 0
    private var mirrored: String?
    private var fingersDraw = false
    private let strokeHold = StrokeHoldRecognizer()
    private lazy var itemTap = UITapGestureRecognizer(target: self, action: #selector(tappedPage))
    private lazy var itemHold = UILongPressGestureRecognizer(target: self, action: #selector(heldPage))
    private lazy var tapeTap = UITapGestureRecognizer(target: self, action: #selector(tappedTape))
    private var zoomBeforePresenting: CGFloat?
    private var lastSafeTop: CGFloat = 0
    private var firstInkPage: UUID?
    private var firstInkReported = false
    private let openedAt = CACurrentMediaTime()
    private var openInterval: OSSignpostIntervalState?

    /// Called once when the first visible page has its ink on screen (for tests and the open signpost).
    var onFirstInk: ((TimeInterval) -> Void)?

    init(session: EditorSession, toolPicker: PKToolPicker = PKToolPicker()) {
        self.session = session
        self.toolPicker = toolPicker
        undoProxy = CanvasUndoProxy(document: session.document.undoManager)
        super.init(nibName: nil, bundle: nil)
        openInterval = signposter.beginInterval("Open to first ink")
        document.inkObserver = self
        document.onStructureChange = { [weak self] in self?.pagesDidChange() }
        pages = document.pages
        linkTitles = LinkTitles(pages: pages, notebooks: session.notebookTitles)
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
        scrollView.panGestureRecognizer.allowedTouchTypes = Self.scrollTouchTypes
        scrollView.scrollsToTop = true
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        anchor.undoProxy = undoProxy
        anchor.frame = .zero
        view.addSubview(anchor)
        laser.frame = view.bounds
        laser.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(laser)
        laserGesture.minimumPressDuration = 0
        laserGesture.allowableMovement = .greatestFiniteMagnitude
        laserGesture.cancelsTouchesInView = false
        laserGesture.delegate = self
        laserGesture.isEnabled = false
        view.addGestureRecognizer(laserGesture)
        view.addInteraction(UIDropInteraction(delegate: self))
        itemTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        itemHold.minimumPressDuration = 0.45
        for recognizer in [itemTap, itemHold, strokeHold, tapeTap] {
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            scrollView.addGestureRecognizer(recognizer)
        }
        strokeHold.onTouchDown = { [weak self] in self?.session.onTouchDown?() }
        lassoPan.maximumNumberOfTouches = 1
        lassoPan.allowedTouchTypes = Self.scrollTouchTypes + [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        toolPicker.addObserver(self)
        toolPicker.colorUserInterfaceStyle = .light
        toolPicker.stateAutosaveName = "SwiftScribe.ToolPicker"
        toolPicker.showsDrawingPolicyControls = false
        applyDrawingPolicy(session.drawingInput.policy)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (self: Self, _) in
            self.updatePageEdges()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(sceneDidActivate), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(secondScreenChanged), name: .scribeExternalDisplayChanged, object: nil)
        for name in [UIScene.willDeactivateNotification, Notification.Name.scribeCloseEditor] {
            NotificationCenter.default.addObserver(self, selector: #selector(finishTyping), name: name, object: nil)
        }
    }

    /// Fingers and the trackpad scroll and zoom; the Pencil never does.
    private static let scrollTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                           NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]

    @objc private func sceneDidActivate() { updateScrollTouches() }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setToolPickerVisible(session.isToolPickerVisible)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        endTextEditing()
        ExternalDisplay.shared.end(for: self)
        toolPicker.setVisible(false, forFirstResponder: anchor)
        for canvas in canvases.values { toolPicker.setVisible(false, forFirstResponder: canvas) }
        anchor.resignFirstResponder()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let top = view.safeAreaInsets.top
        guard lastBounds != .zero, top != lastSafeTop else { return }
        lastSafeTop = top
        if isPresenting {
            present(page: pendingPage ?? currentPage)
        } else {
            updateInsets()
            scrollView.contentOffset = clamped(scrollView.contentOffset)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0, bounds.size != lastBounds.size else { return }
        let isFirst = lastBounds == .zero
        // While presenting or replaying, the page being shown is the session's: a panel comes in beside the pages,
        // and the scroll position is mid-change when the view resizes.
        let page = isFirst ? session.currentPage : isPresenting || replay != nil ? pendingPage ?? session.currentPage : currentPage
        lastBounds = bounds
        fitScale = bounds.width / layout.size.width
        let tallest = layout.frames.map(\.height).max() ?? 1
        minimumZoom = min(1, bounds.height / (tallest + PageStackLayout.margin * 2) / fitScale)
        for slot in slots.values { removeChunks(slot) }
        if isFirst {
            firstInkPage = pages.indices.contains(page) ? pages[page].id : nil
            lastSafeTop = view.safeAreaInsets.top
        }
        bake(zoom: zoom)
        scrollToPage(page, animated: false)
        updateWindow(force: true)
        if isPresenting { present(page: page) }
    }

    override var keyCommands: [UIKeyCommand]? {
        guard !toolPickerSuppressed else { return [] }
        // While typing, every key belongs to the text box.
        guard textView == nil else { return [UIKeyCommand(title: String(localized: "Done"), action: #selector(finishTyping), input: UIKeyCommand.inputEscape)] }
        let commands = [
            UIKeyCommand(title: String(localized: "Next Page"), action: #selector(nextPage), input: UIKeyCommand.inputPageDown),
            UIKeyCommand(title: String(localized: "Previous Page"), action: #selector(previousPage), input: UIKeyCommand.inputPageUp),
            UIKeyCommand(title: String(localized: "Scroll Down"), action: #selector(lineDown), input: UIKeyCommand.inputDownArrow),
            UIKeyCommand(title: String(localized: "Scroll Up"), action: #selector(lineUp), input: UIKeyCommand.inputUpArrow),
            UIKeyCommand(title: String(localized: "Scroll Down a Screen"), action: #selector(screenDown), input: " "),
            UIKeyCommand(title: String(localized: "Scroll Up a Screen"), action: #selector(screenUp), input: " ", modifierFlags: .shift),
            UIKeyCommand(title: String(localized: "First Page"), action: #selector(firstPage), input: UIKeyCommand.inputUpArrow, modifierFlags: .command),
            UIKeyCommand(title: String(localized: "Last Page"), action: #selector(lastPage), input: UIKeyCommand.inputDownArrow, modifierFlags: .command),
            UIKeyCommand(title: String(localized: "First Page"), action: #selector(firstPage), input: UIKeyCommand.inputHome),
            UIKeyCommand(title: String(localized: "Last Page"), action: #selector(lastPage), input: UIKeyCommand.inputEnd),
            UIKeyCommand(title: String(localized: "Fit Width"), action: #selector(fitWidth), input: "0", modifierFlags: .command),
            UIKeyCommand(title: String(localized: "Fit Page"), action: #selector(fitWholePage), input: "9", modifierFlags: .command),
        ]
        let presenting = !isPresenting ? [] : [
            UIKeyCommand(title: String(localized: "Next Page"), action: #selector(nextPage), input: UIKeyCommand.inputRightArrow),
            UIKeyCommand(title: String(localized: "Previous Page"), action: #selector(previousPage), input: UIKeyCommand.inputLeftArrow),
        ]
        let selected = session.selection == nil ? [] : [
            UIKeyCommand(title: String(localized: "Delete"), action: #selector(deleteSelectedItem), input: UIKeyCommand.inputDelete),
            UIKeyCommand(action: #selector(deleteSelectedItem), input: "\u{8}"),
            UIKeyCommand(title: String(localized: "Done"), action: #selector(clearSelection), input: UIKeyCommand.inputEscape),
        ]
        for command in commands + presenting + selected { command.wantsPriorityOverSystemBehavior = true }
        return commands + presenting + selected
    }

    @objc private func nextPage() { session.step(1) }
    @objc private func previousPage() { session.step(-1) }
    @objc private func lineDown() { scrollBy(viewportFraction: 0.12, animated: true) }
    @objc private func lineUp() { scrollBy(viewportFraction: -0.12, animated: true) }
    @objc private func screenDown() { scrollBy(viewportFraction: 0.9, animated: true) }
    @objc private func screenUp() { scrollBy(viewportFraction: -0.9, animated: true) }
    @objc private func firstPage() { session.go(to: 0) }
    @objc private func lastPage() { session.go(to: pages.count - 1) }
    @objc private func fitWidth() { fit(.width) }
    @objc private func fitWholePage() { fit(.page) }

    // MARK: Layout and zoom

    private var effectiveScale: CGFloat { bakedScale * scrollView.zoomScale }

    /// What a slot is drawn from. Ink hashes change on every save and never need a slot rebuilt.
    private struct SlotKey {
        let id: UUID
        let background: PageBackground
        let paperColorRaw: String
        let size: CGSize
        let day: String?

        init(_ page: NotebookPage) {
            id = page.id
            background = page.background
            paperColorRaw = page.paperColorRaw
            size = page.size
            day = page.day
        }
    }

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
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = Self.scrollTouchTypes
        for (id, slot) in slots {
            guard let index = index(of: id) else { continue }
            position(slot, at: index)
            for chunk in slot.chunks.values { position(chunk) }
            if let canvas = slot.canvas { place(canvas, in: slot) }
            slot.layoutItems(scale: bakedScale)
        }
        showSelection()
        inkLasso?.scale = bakedScale
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
        // Room to centre the first and last page while presenting.
        let slack = isPresenting ? scrollView.bounds.height / 2 : 0
        scrollView.contentInset = UIEdgeInsets(top: max(vertical + view.safeAreaInsets.top, slack), left: horizontal,
                                               bottom: max(bottom, slack, textView == nil ? 0 : keyboardOverlap), right: horizontal)
    }

    private func clamped(_ offset: CGPoint) -> CGPoint {
        let inset = scrollView.contentInset
        let minX = -inset.left, minY = -inset.top
        let maxX = max(minX, scrollView.contentSize.width + inset.right - scrollView.bounds.width)
        let maxY = max(minY, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        return CGPoint(x: min(max(offset.x, minX), maxX), y: min(max(offset.y, minY), maxY))
    }

    private func index(of id: UUID) -> Int? { pages.firstIndex { $0.id == id } }

    /// The page under a line 30% down the viewport, or the last page once the scroll can't go further,
    /// so a short last page can still become current.
    var currentPage: Int {
        guard effectiveScale > 0, !pages.isEmpty else { return 0 }
        let inset = scrollView.adjustedContentInset
        let maxY = scrollView.contentSize.height + inset.bottom - scrollView.bounds.height
        if maxY > -inset.top + 1, scrollView.contentOffset.y >= maxY - 1 { return pages.count - 1 }
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

    /// The part of the view pages can be read in: below the bar, above a docked tool picker.
    private var readableArea: CGRect {
        var area = view.bounds.inset(by: UIEdgeInsets(top: view.safeAreaInsets.top, left: 0, bottom: 0, right: 0))
        let obscured = toolPicker.isVisible ? toolPicker.frameObscured(in: view) : .null
        if !obscured.isNull, obscured.minY > area.minY { area.size.height = obscured.minY - area.minY }
        return area
    }

    /// The zoom that fits the current page, not the widest one, so a small page can fill the screen.
    func fitZoom(_ fit: PageFit, page index: Int) -> CGFloat {
        guard layout.frames.indices.contains(index), fitScale > 0 else { return 1 }
        let frame = layout.frames[index], area = readableArea, margin = PageStackLayout.margin
        let width = area.width / ((frame.width + margin * 2) * fitScale)
        return fit == .width ? width : min(width, area.height / ((frame.height + margin * 2) * fitScale))
    }

    func fit(_ fit: PageFit) {
        guard !pages.isEmpty, fitScale > 0 else { return }
        let index = pendingPage ?? currentPage, frame = layout.frames[index], area = readableArea
        let line = scrollView.bounds.height * 0.3
        let anchor = (scrollView.contentOffset.y + scrollView.adjustedContentInset.top + line) / effectiveScale
        let target = min(fitZoom(fit, page: index), maximumZoom)
        minimumZoom = min(minimumZoom, target)
        pendingPage = nil
        bake(zoom: target)
        let y: CGFloat = if fit == .page {
            frame.midY * bakedScale - area.midY
        } else if (frame.minY...frame.maxY).contains(anchor) {
            anchor * bakedScale - scrollView.adjustedContentInset.top - line
        } else {
            (frame.minY - PageStackLayout.margin / 2) * bakedScale - area.minY
        }
        scrollView.contentOffset = clamped(CGPoint(x: frame.midX * bakedScale - area.midX, y: y))
        // A short page centred by Fit Page can sit below the line that picks the current page; it stays current until the next scroll.
        if currentPage != index { pendingPage = index }
        updateWindow(force: true)
        session.pageDidChange(index)
    }

    /// The page an animated scroll is heading for. While it's set, the pages passed on the way don't become current.
    private var pendingPage: Int?

    func scrollToPage(_ index: Int, animated: Bool = false) {
        guard layout.frames.indices.contains(index) else { return }
        let y = (layout.frames[index].minY - PageStackLayout.margin / 2) * effectiveScale - scrollView.contentInset.top
        let target = clamped(CGPoint(x: scrollView.contentOffset.x, y: y))
        let moves = animated && abs(target.y - scrollView.contentOffset.y) > 0.5
        pendingPage = moves ? index : nil
        scrollView.setContentOffset(target, animated: moves)
        if !moves { updateWindow() }
    }

    func scrollBy(viewportFraction: CGFloat, animated: Bool = false) {
        let offset = scrollView.contentOffset
        let visible = scrollView.bounds.inset(by: scrollView.adjustedContentInset).height
        let target = clamped(CGPoint(x: offset.x, y: offset.y + viewportFraction * visible))
        scrollView.setContentOffset(target, animated: animated)
        if !animated { updateWindow() }
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
            document.pinInk(keep)
            let prefetch = max(0, visible.lowerBound - 3)...min(count - 1, visible.upperBound + 3)
            document.prefetchInk(pages[prefetch].map(\.id))
        }
        for index in canvasWindow ?? window {
            guard let slot = slots[pages[index].id] else { continue }
            if let canvas = slot.canvas { place(canvas, in: slot) }
            updateChunks(in: slot)
        }
        let page = currentPage
        if pendingPage == nil, page != session.currentPage { session.pageDidChange(page) }
        updateInkAppearance()
        dimOtherPages()
        mirrorPresentation()
    }

    /// While presenting, the pages either side of the one being shown step back.
    private func dimOtherPages() {
        let shown = pendingPage ?? session.currentPage
        let shownID = isPresenting && pages.indices.contains(shown) ? pages[shown].id : nil
        for (id, slot) in slots {
            let alpha: CGFloat = shownID == nil || id == shownID ? 1 : 0.25
            if slot.alpha != alpha { slot.alpha = alpha }
        }
    }

    /// The picker's swatches show ink as the current page will: light on Chalkboard.
    private func updateInkAppearance() {
        let index = pendingPage ?? session.currentPage
        guard pages.indices.contains(index) else { return }
        let style = pages[index].effectivePaperColor.inkAppearance
        if toolPicker.colorUserInterfaceStyle != style { toolPicker.colorUserInterfaceStyle = style }
    }

    private func makeSlot(_ page: NotebookPage, at index: Int) -> PageSlotView {
        let slot = PageSlotView(page: page)
        slot.layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
        slot.layer.borderColor = UIColor.hairline.resolvedColor(with: traitCollection).cgColor
        position(slot, at: index)
        contentView.addSubview(slot)
        if let inkLasso { contentView.bringSubviewToFront(inkLasso) }
        slots[page.id] = slot
        if page.hasItems { syncItems(in: slot) }
        return slot
    }

    private func removeSlot(_ id: UUID) {
        if session.selection?.pageID == id { select(nil) }
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
        canvas.scrollsToTop = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = session.drawingInput.policy
        canvas.maximumSupportedContentVersion = .latest
        canvas.isAccessibilityElement = true
        canvas.accessibilityTraits = .allowsDirectInteraction
        toolPicker.addObserver(canvas)
        return canvas
    }

    /// Observers only hear about later picker changes, so a new or reused canvas starts from the picker's current tool.
    private func syncTool(_ canvas: PageCanvasView) {
        switch toolPicker.selectedToolItem {
        case let item as PKToolPickerInkingItem: canvas.tool = item.inkingTool
        case let item as PKToolPickerEraserItem: canvas.tool = item.eraserTool
        case let item as PKToolPickerLassoItem: canvas.tool = item.lassoTool
        default: break
        }
        canvas.isRulerActive = toolPicker.isRulerActive
    }

    private func attachCanvas(_ page: NotebookPage, to slot: PageSlotView) {
        let canvas = pool.popLast() ?? makeCanvas()
        syncTool(canvas)
        canvas.pageID = page.id
        canvas.overrideUserInterfaceStyle = page.effectivePaperColor.inkAppearance
        let number = (index(of: page.id) ?? 0) + 1
        canvas.accessibilityLabel = DailyJournal.canvasLabel(page: number, day: page.day)
        canvas.accessibilityIdentifier = "page.canvas.\(number)"
        place(canvas, in: slot)
        slot.addSubview(canvas)
        slot.canvas = canvas
        canvases[page.id] = canvas
        slot.raiseTape()
        if let selectionView, selectionView.superview === slot { slot.bringSubviewToFront(selectionView) }
        if let textView, textView.superview === slot { slot.bringSubviewToFront(textView) }
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
        canvas.drawing = replayed(ink, on: canvas.pageID)
        canvas.strokeCount = nil
        isApplyingDrawing = false
        canvas.isLoaded = true
        setDrawingEnabled(!document.isReadOnly && !isLocked, canvas)
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
        replayPending[id] = nil
        canvas.isLoaded = false
        canvas.overrideUserInterfaceStyle = .light
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

    /// The stroke-end path. Ink past the page edge is kept but never shown: the slot clips it, and every
    /// renderer draws only the page rectangle.
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingDrawing, let canvas = canvasView as? PageCanvasView, canvas.isLoaded, let id = canvas.pageID else { return }
        canvas.strokeCount = nil
        let before = document.loadedInk(id)
        document.canvasDidChangeInk(id, to: canvas.drawing)
        straightenLastStroke(on: canvas, pageID: id, before: before)
    }

    /// Draw and hold: a stroke that ended with the pen at rest is redrawn as the line, circle or figure it looks like.
    /// The tidied stroke is an undo step of its own, so Undo gives the hand-drawn one back. For that it has to wait
    /// until the stroke's own undo group has closed, which happens at the end of this pass of the run loop.
    private func straightenLastStroke(on canvas: PageCanvasView, pageID: UUID, before: PKDrawing?) {
        guard let rest = strokeHold.takeHold(), rest >= ShapeSnap.holdDuration, ShapeSnap.isEnabled, canvas.tool is PKInkingTool, !canvas.isRulerActive,
              let before, canvas.drawing.strokes.count == before.strokes.count + 1, let drawn = canvas.drawing.strokes.last,
              let snapped = ShapeSnap.snapped(drawn) else { return }
        let count = canvas.drawing.strokes.count, stamp = drawn.path.creationDate
        func apply(tries: Int) {
            guard canvas.pageID == pageID, canvas.drawing.strokes.count == count, canvas.drawing.strokes.last?.path.creationDate == stamp else { return }
            guard document.undoManager.groupingLevel == 0 || tries == 0 else {
                return DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { apply(tries: tries - 1) }
            }
            var strokes = canvas.drawing.strokes
            strokes[count - 1] = snapped.stroke
            let drawing = PKDrawing(strokes: strokes)
            isApplyingDrawing = true
            canvas.drawing = drawing
            isApplyingDrawing = false
            document.canvasDidChangeInk(pageID, to: drawing)
            document.undoManager.setActionName(String(localized: "Straighten Shape"))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            AccessibilityNotification.Announcement(String(localized: "Straightened into a \(snapped.shape.displayName)")).post()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { apply(tries: 5) }
    }

    /// Writing anywhere puts a selected picture down.
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        if session.selection != nil { select(nil) }
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

    // MARK: InkObserver

    func document(_ document: NotebookDocument, didReplaceInkOf pageID: UUID) {
        // An undo or redo under the selection moves strokes about, so what was caught is let go.
        if inkLasso != nil, !isMovingInk, !inkSelection.isEmpty { setInkSelection([:]) }
        guard let canvas = canvases[pageID], let ink = document.loadedInk(pageID) else { return }
        show(ink, in: canvas)
    }

    // MARK: Structure

    private func pagesDidChange() {
        let updated = document.pages
        let updatedKeys = updated.map(SlotKey.init), currentKeys = pages.map(SlotKey.init)
        let titles = LinkTitles(pages: updated, notebooks: session.notebookTitles)
        let renamed = titles != linkTitles
        linkTitles = titles
        guard updatedKeys.elementsEqual(currentKeys, by: Self.sameSlot) else {
            relayout(updated, changed: Self.changedIDs(updatedKeys, currentKeys))
            refreshItems(all: renamed)
            return
        }
        pages = updated
        refreshItems(all: renamed)
    }

    // MARK: Pictures, stickers, text and links

    /// A linked notebook was renamed, deleted or brought back.
    func linksDidChange() {
        let titles = LinkTitles(pages: pages, notebooks: session.notebookTitles)
        guard titles != linkTitles else { return }
        linkTitles = titles
        mirrored = nil
        refreshItems(all: true)
        mirrorPresentation()
    }

    private func syncItems(in slot: PageSlotView) {
        slot.syncItems(assets: document.package.assetsDirectory, scale: bakedScale, links: linkTitles, lifted: session.liftedTapes) { [weak self, weak slot] itemID in
            guard let self, let slot else { return }
            self.activate(ItemSelection(pageID: slot.page.id, itemID: itemID))
        }
        if let typing, typing.pageID == slot.page.id { slot.itemViews[typing.itemID]?.isHidden = true }
    }

    /// After any change to the pages: slots pick up their page's current items, and the selection follows its item.
    /// A page that moved or was renamed changes what the links to it say, so then every slot is gone over.
    private func refreshItems(all: Bool = false) {
        for (id, slot) in slots {
            guard let index = index(of: id) else { continue }
            let page = pages[index]
            let changed = slot.page.extra["items"] != page.extra["items"]
            slot.page = page
            if changed || (all && page.hasItems) { syncItems(in: slot) }
        }
        showSelection()
    }

    private func item(_ selection: ItemSelection) -> PageItem? {
        slots[selection.pageID]?.page.items.first { $0.id == selection.itemID }
    }

    /// What VoiceOver's double tap does: a link opens its page, tape lifts, anything else is picked up.
    private func activate(_ selection: ItemSelection) {
        if let link = item(selection)?.link {
            session.follow(link, from: selection.pageID)
        } else if item(selection)?.tape != nil {
            if replay == nil, inkLasso == nil { session.toggleTape(selection.itemID) }
        } else if !isLocked, !document.isReadOnly {
            select(selection)
        }
    }

    private func selectedItem() -> (slot: PageSlotView, item: PageItem)? {
        guard let selection = session.selection, let slot = slots[selection.pageID],
              let item = slot.page.items.first(where: { $0.id == selection.itemID }) else { return nil }
        return (slot, item)
    }

    func select(_ selection: ItemSelection?) {
        if textView != nil, selection != typing { endTextEditing() }
        if session.selection != selection { session.selection = selection }
        showSelection()
    }

    /// Puts the stitched outline round the selected item, or takes it away when the item or its page is gone.
    private func showSelection() {
        guard !isLocked, !document.isReadOnly, let (slot, item) = selectedItem() else {
            discardTextEditor()
            selectionView?.removeFromSuperview()
            selectionView = nil
            if session.selection != nil { session.selection = nil }
            return
        }
        let view = selectionView ?? ItemSelectionView(item: item, pageSize: slot.page.size)
        if view.superview !== slot {
            view.removeFromSuperview()
            slot.addSubview(view)
        }
        slot.bringSubviewToFront(view)
        view.pageSize = slot.page.size
        view.scale = bakedScale
        if !view.isChanging { view.show(item) }
        view.onChange = { [weak self] item, final in self?.selectedItemChanged(item, final: final) }
        view.onTap = { [weak self] in self?.editText() }
        selectionView = view
        layoutTextEditor()
    }

    private func selectedItemChanged(_ item: PageItem, final: Bool) {
        guard let selection = session.selection, let slot = slots[selection.pageID] else { return }
        slot.itemViews[item.id]?.update(item, onDark: slot.page.effectivePaperColor.isDark, links: linkTitles, lifted: session.liftedTapes.contains(item.id))
        slot.itemViews[item.id]?.layout(scale: bakedScale)
        selectionView?.show(item)
        guard final else { return }
        document.updateItems(onPage: selection.pageID, actionName: String(localized: "Arrange")) { items in
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        }
    }

    /// The topmost thing under a point in the scroll view: tape first, since it lies over the rest.
    private func item(at point: CGPoint, tapeOnly: Bool = false) -> ItemSelection? {
        guard bakedScale > 0 else { return nil }
        for slot in slots.values where slot.page.hasItems {
            let local = contentView.convert(point, from: scrollView)
            guard slot.frame.contains(local) else { continue }
            let onPage = CGPoint(x: (local.x - slot.frame.minX) / bakedScale, y: (local.y - slot.frame.minY) / bakedScale)
            let items = slot.page.items
            let hit = items.last { $0.isOverInk && $0.contains(onPage, slop: tapeOnly ? 0 : 6) }
                ?? (tapeOnly ? nil : items.last { $0.content != .unknown && $0.contains(onPage, slop: 6) })
            if let hit { return ItemSelection(pageID: slot.page.id, itemID: hit.id) }
        }
        return nil
    }

    // MARK: Study tape

    /// A tap on tape, with a finger or the Pencil, lifts it or puts it back. Nothing is saved: lifting is for looking.
    @objc private func tappedTape(_ gesture: UITapGestureRecognizer) {
        guard let hit = item(at: gesture.location(in: scrollView), tapeOnly: true) else { return }
        session.toggleTape(hit.itemID)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === tapeTap else { return true }
        return replay == nil && inkLasso == nil && !isOnSelection(gestureRecognizer)
            && item(at: gestureRecognizer.location(in: scrollView), tapeOnly: true) != nil
    }

    func tapesDidChange() {
        for slot in slots.values where slot.page.hasItems { slot.showLifted(session.liftedTapes, links: linkTitles) }
        mirrored = nil
        mirrorPresentation()
    }

    private func isOnSelection(_ gesture: UIGestureRecognizer) -> Bool {
        guard let selectionView else { return false }
        return selectionView.point(inside: gesture.location(in: selectionView), with: nil)
    }

    /// A finger tap opens a link or picks up a picture when fingers don't draw; any tap elsewhere puts the selected one down.
    /// While presenting nothing is drawn, so a tap on a link always opens it.
    @objc private func tappedPage(_ gesture: UITapGestureRecognizer) {
        guard !isOnSelection(gesture) else { return }
        if replay != nil { return seekReplay(to: gesture.location(in: scrollView)) }
        if inkLasso != nil { return setInkSelection([:]) }
        let hit = isPresenting || !fingersDraw ? item(at: gesture.location(in: scrollView)) : nil
        if let hit, item(hit)?.tape != nil { return }
        if let hit, let link = item(hit)?.link { return session.follow(link, from: hit.pageID) }
        guard !isPresenting, !document.isReadOnly else { return }
        if hit != nil || session.selection != nil { select(hit) }
    }

    /// Touch and hold picks one up with a finger or the Pencil, and drops the dot the hold would have drawn.
    @objc private func heldPage(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isLocked, !document.isReadOnly, !isOnSelection(gesture),
              let hit = item(at: gesture.location(in: scrollView)) else { return }
        if let canvas = canvases[hit.pageID], canvas.drawingGestureRecognizer.isEnabled {
            canvas.drawingGestureRecognizer.isEnabled = false
            canvas.drawingGestureRecognizer.isEnabled = true
        }
        select(hit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: Typing in a text box

    /// Puts a text view over the selected text box. The page keeps the old text until typing ends.
    func editText() {
        guard textView == nil, !isLocked, !document.isReadOnly, let selection = session.selection,
              let (slot, item) = selectedItem(), let box = item.text else { return }
        let view = UITextView()
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.text = box.string
        view.delegate = self
        view.accessibilityIdentifier = "page.text.editor"
        view.accessibilityLabel = String(localized: "Text box")
        slot.addSubview(view)
        textView = view
        typing = selection
        slot.itemViews[item.id]?.isHidden = true
        selectionView?.isEditing = true
        session.isEditingText = true
        layoutTextEditor()
        view.becomeFirstResponder()
        view.selectedRange = NSRange(location: (view.text as NSString).length, length: 0)
    }

    /// The box as it would be saved now: what has been typed, as tall as that needs.
    private func liveTextItem() -> (slot: PageSlotView, item: PageItem)? {
        guard let textView, let (slot, item) = selectedItem(), var box = item.text else { return nil }
        box.string = textView.text
        var live = item
        live.content = .text(box)
        return (slot, live.fittedToText())
    }

    private func layoutTextEditor() {
        guard let textView, let (slot, item) = liveTextItem(), let box = item.text else { return }
        let font = box.font(scale: bakedScale), color = box.tint.color(onDark: slot.page.effectivePaperColor.isDark)
        if textView.font != font { textView.font = font }
        if textView.textColor != color { textView.textColor = color }
        if textView.textAlignment != box.alignment.textAlignment { textView.textAlignment = box.alignment.textAlignment }
        textView.transform = .identity
        textView.bounds = CGRect(x: 0, y: 0, width: item.size.width * bakedScale, height: item.size.height * bakedScale)
        textView.center = CGPoint(x: item.center.x * bakedScale, y: item.center.y * bakedScale)
        textView.transform = CGAffineTransform(rotationAngle: item.rotation)
        selectionView?.show(item)
        slot.bringSubviewToFront(textView)
    }

    func textViewDidChange(_ textView: UITextView) {
        layoutTextEditor()
        revealTextEditor()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        endTextEditing()
    }

    @objc private func finishTyping() { endTextEditing() }

    /// Saves what was typed as one undo step. A box left empty is taken off the page.
    private func endTextEditing() {
        guard let textView, let typing else { return }
        let string = textView.text ?? ""
        discardTextEditor()
        if !toolPickerSuppressed { anchor.becomeFirstResponder() }
        if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if document.undoManager.canUndo, document.undoManager.undoActionName == EditorSession.addTextAction, item(typing)?.text?.string.isEmpty == true {
                document.undoManager.undo()
            } else {
                document.updateItems(onPage: typing.pageID, actionName: String(localized: "Delete")) { $0.removeAll { $0.id == typing.itemID } }
            }
        } else {
            document.updateItems(onPage: typing.pageID, actionName: String(localized: "Edit Text")) { items in
                guard let index = items.firstIndex(where: { $0.id == typing.itemID }), var box = items[index].text else { return }
                box.string = string
                items[index].content = .text(box)
                items[index] = items[index].fittedToText()
            }
        }
    }

    private func discardTextEditor() {
        guard let textView else { return }
        self.textView = nil
        textView.delegate = nil
        textView.removeFromSuperview()
        if let typing { slots[typing.pageID]?.itemViews[typing.itemID]?.isHidden = false }
        typing = nil
        selectionView?.isEditing = false
        if session.isEditingText { session.isEditingText = false }
        updateInsets()
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue, let window = view.window else { return }
        let covered = view.convert(frame, from: window.screen.coordinateSpace).intersection(view.bounds)
        keyboardOverlap = covered.isNull ? 0 : max(0, view.bounds.maxY - covered.minY)
        guard textView != nil else { return }
        updateInsets()
        revealTextEditor()
    }

    private func revealTextEditor() {
        guard let textView, let slot = textView.superview else { return }
        scrollView.scrollRectToVisible(scrollView.convert(textView.frame, from: slot).insetBy(dx: 0, dy: -24), animated: true)
    }

    // MARK: Dropping and pasting pictures

    private var acceptsPictures: Bool { !document.isReadOnly && !isLocked }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        acceptsPictures && session.canLoadObjects(ofClass: UIImage.self)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: acceptsPictures ? .copy : .forbidden)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        let local = contentView.convert(session.location(in: view), from: view)
        guard effectiveScale > 0, let index = layout.frames.indices.first(where: {
            layout.frames[$0].insetBy(dx: -PageStackLayout.margin, dy: -PageStackLayout.margin / 2).contains(CGPoint(x: local.x / bakedScale, y: local.y / bakedScale))
        }) else { return }
        let frame = layout.frames[index]
        let point = CGPoint(x: min(max(local.x / bakedScale - frame.minX, 0), frame.width), y: min(max(local.y / bakedScale - frame.minY, 0), frame.height))
        session.loadObjects(ofClass: UIImage.self) { [weak self] objects in
            self?.place(objects.compactMap { $0 as? UIImage }, onPage: index, at: point)
        }
    }

    private func place(_ images: [UIImage], onPage index: Int?, at point: CGPoint?) {
        let editor = session
        document.perform {
            for image in images { try? await editor.addPicture(image, onPage: index, at: point) }
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) { return acceptsPictures && !toolPickerSuppressed && UIPasteboard.general.hasImages }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        guard acceptsPictures, let images = UIPasteboard.general.images, !images.isEmpty else { return }
        place(images, onPage: nil, at: nil)
    }

    @objc private func deleteSelectedItem() { session.deleteSelection() }
    @objc private func clearSelection() { select(nil) }

    /// The middle of what's showing of a page, in page points: where a new picture or sticker lands.
    func visibleCenter(ofPage index: Int) -> CGPoint? {
        guard pages.indices.contains(index), effectiveScale > 0 else { return nil }
        let frame = layout.frames[index]
        let area = readableArea
        let visible = CGRect(x: (scrollView.contentOffset.x + area.minX) / effectiveScale, y: (scrollView.contentOffset.y + area.minY) / effectiveScale,
                             width: area.width / effectiveScale, height: area.height / effectiveScale).intersection(frame)
        guard !visible.isNull, !visible.isEmpty else { return CGPoint(x: frame.width / 2, y: frame.height / 2) }
        return CGPoint(x: visible.midX - frame.minX, y: visible.midY - frame.minY)
    }

    private static func sameSlot(_ a: SlotKey, _ b: SlotKey) -> Bool {
        a.id == b.id && a.background == b.background && a.paperColorRaw == b.paperColorRaw && a.size == b.size && a.day == b.day
    }

    private static func changedIDs(_ updated: [SlotKey], _ current: [SlotKey]) -> Set<UUID> {
        let before = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = Set(current.map(\.id)).subtracting(updated.map(\.id))
        for key in updated where before[key.id].map({ !sameSlot($0, key) }) ?? true { changed.insert(key.id) }
        return changed
    }

    private func relayout(_ updated: [NotebookPage], changed: Set<UUID>) {
        let anchorID = pages.indices.contains(currentPage) ? pages[currentPage].id : nil
        let anchorOffset = anchorID.flatMap { id in index(of: id).map { scrollView.contentOffset.y - layout.frames[$0].minY * effectiveScale } }
        pages = updated
        layout = PageStackLayout(pages: pages)
        for id in changed where slots[id] != nil { removeSlot(id) }
        for (id, slot) in slots {
            guard let index = index(of: id) else { removeSlot(id); continue }
            position(slot, at: index)
            slot.canvas?.accessibilityLabel = DailyJournal.canvasLabel(page: index + 1, day: pages[index].day)
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
        let shown = visible && !toolPickerSuppressed && !document.isReadOnly && !isLocked
        toolPicker.setVisible(shown, forFirstResponder: anchor)
        for canvas in canvases.values { toolPicker.setVisible(shown, forFirstResponder: canvas) }
        if !toolPickerSuppressed, textView == nil { anchor.becomeFirstResponder() }
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
        drawingPolicy = policy
        for canvas in canvases.values + pool { canvas.drawingPolicy = policy }
        updateScrollTouches()
    }

    private var drawingPolicy: PKCanvasViewDrawingPolicy = .default

    /// When a finger can draw, scrolling takes two. "System Setting" follows the system's Only Draw with Apple Pencil
    /// switch, which only applies while the tool picker is showing.
    private func updateScrollTouches() {
        let fingersDraw = switch drawingPolicy {
        case _ where isPresenting: fingersPoint
        case _ where inkLasso != nil: true
        case _ where document.isReadOnly || replay != nil: false
        case .anyInput: true
        case .pencilOnly: false
        default: toolPicker.isVisible && !UIPencilInteraction.prefersPencilOnlyDrawing
        }
        self.fingersDraw = fingersDraw
        scrollView.panGestureRecognizer.minimumNumberOfTouches = fingersDraw ? 2 : 1
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        laserGesture.allowedTouchTypes = fingersPoint ? Self.scrollTouchTypes + [pencil] : [pencil]
    }

    /// This editor's pane was touched while another had the keyboard: key commands and undo come here now.
    func paneBecameActive() {
        if textView == nil, !toolPickerSuppressed { anchor.becomeFirstResponder() }
    }

    // MARK: Selecting ink across pages

    private var stackFrames: [UUID: CGRect] {
        Dictionary(zip(pages.map(\.id), layout.frames), uniquingKeysWith: { first, _ in first })
    }

    /// The ink of the pages that have a canvas: the pages a lasso can reach and a drag can land on.
    private var liveInk: [UUID: PKDrawing] {
        var result: [UUID: PKDrawing] = [:]
        for id in canvases.keys { result[id] = document.loadedInk(id) }
        return result
    }

    func setSelectingInk(_ selecting: Bool) {
        guard selecting != (inkLasso != nil), isViewLoaded else { return }
        if selecting {
            select(nil)
            let overlay = InkLassoOverlay(frame: contentView.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.scale = bakedScale
            // The overlay takes the touches itself: a canvas underneath would hold a drag back for half a second.
            overlay.addGestureRecognizer(lassoPan)
            contentView.addSubview(overlay)
            inkLasso = overlay
        } else {
            restoreLiftedInk()
            inkLasso?.removeFromSuperview()
            inkLasso = nil
            setInkSelection([:])
        }
        for canvas in canvases.values where canvas.isLoaded { setDrawingEnabled(!document.isReadOnly && !isLocked, canvas) }
        setToolPickerVisible(session.isToolPickerVisible)
        updateScrollTouches()
    }

    private func setInkSelection(_ selection: InkSelection) {
        inkSelection = selection.filter { !$0.value.isEmpty }
        inkLasso?.showSelection(InkLasso.bounds(of: inkSelection, drawings: liveInk, frames: stackFrames))
        let count = inkSelection.values.reduce(0) { $0 + $1.count }
        if session.inkSelectionCount != count { session.inkSelectionCount = count }
    }

    private func stackPoint(_ gesture: UIGestureRecognizer) -> CGPoint {
        let point = gesture.location(in: contentView)
        return CGPoint(x: point.x / bakedScale, y: point.y / bakedScale)
    }

    /// A drag that starts on what is selected moves it; one that starts anywhere else draws a new lasso.
    @objc private func lassoPanned(_ gesture: UIPanGestureRecognizer) {
        guard let overlay = inkLasso, bakedScale > 0 else { return }
        let point = stackPoint(gesture)
        switch gesture.state {
        case .began:
            if let bounds = overlay.selectionBounds, bounds.insetBy(dx: -14, dy: -14).contains(point) {
                lassoMoveOrigin = point
                liftInk()
            } else {
                lassoMoveOrigin = nil
                setInkSelection([:])
                overlay.begin(at: point)
            }
        case .changed:
            if let origin = lassoMoveOrigin {
                overlay.drag(by: CGSize(width: point.x - origin.x, height: point.y - origin.y))
            } else {
                overlay.add(point)
            }
        case .ended:
            if let origin = lassoMoveOrigin {
                lassoMoveOrigin = nil
                moveInkSelection(by: CGSize(width: point.x - origin.x, height: point.y - origin.y), copying: false)
            } else {
                catchInk(inside: InkLasso.outline(from: overlay.end()))
            }
        default:
            lassoMoveOrigin = nil
            _ = overlay.end()
            restoreLiftedInk()
        }
    }

    private func catchInk(inside outline: [CGPoint]) {
        guard outline.count >= 3 else { return }
        var caught: InkSelection = [:]
        let box = ShapeRecognizer.bounds(of: outline)
        for (id, frame) in stackFrames where frame.intersects(box) {
            guard let ink = document.loadedInk(id), !ink.strokes.isEmpty else { continue }
            let local = outline.map { CGPoint(x: $0.x - frame.minX, y: $0.y - frame.minY) }
            caught[id] = InkLasso.strokes(in: ink, inside: local)
        }
        setInkSelection(caught)
        let count = session.inkSelectionCount
        AccessibilityNotification.Announcement(count == 0 ? String(localized: "No ink selected")
                                               : count == 1 ? String(localized: "1 stroke selected") : String(localized: "\(count) strokes selected")).post()
    }

    /// While it is dragged the selected ink is drawn by the overlay, and the canvases draw their pages without it.
    private func liftInk() {
        guard let overlay = inkLasso else { return }
        var images: [(image: UIImage, rect: CGRect)] = []
        let frames = stackFrames, screen = traitCollection.displayScale
        for (id, indices) in inkSelection {
            guard let ink = document.loadedInk(id), let frame = frames[id], let page = pages.first(where: { $0.id == id }) else { continue }
            let chosen = Set(indices)
            let picked = PKDrawing(strokes: ink.strokes.enumerated().filter { chosen.contains($0.offset) }.map(\.element))
            let bounds = picked.bounds.insetBy(dx: -2, dy: -2)
            guard !bounds.isNull, !bounds.isEmpty else { continue }
            var image: UIImage?
            UITraitCollection(userInterfaceStyle: page.effectivePaperColor.inkAppearance).performAsCurrent {
                image = picked.image(from: bounds, scale: min(screen * bakedScale, 6))
            }
            if let image { images.append((image, bounds.offsetBy(dx: frame.minX, dy: frame.minY))) }
            if let canvas = canvases[id] {
                isApplyingDrawing = true
                canvas.drawing = InkLasso.removing([id: indices], from: [id: ink])[id] ?? ink
                isApplyingDrawing = false
            }
        }
        overlay.lift(images)
    }

    private func restoreLiftedInk() {
        inkLasso?.drop()
        for id in inkSelection.keys {
            if let canvas = canvases[id], let ink = document.loadedInk(id) { show(ink, in: canvas) }
        }
    }

    /// Commits a drag, or a copy, as one undo step across every page it touched.
    private func moveInkSelection(by delta: CGSize, copying: Bool) {
        guard !inkSelection.isEmpty, copying || abs(delta.width) + abs(delta.height) >= 1 else { return restoreLiftedInk() }
        let moved = InkLasso.moved(inkSelection, by: delta, copying: copying, drawings: liveInk, frames: stackFrames)
        isMovingInk = true
        let done = document.updateInk(moved.drawings, actionName: copying ? String(localized: "Duplicate Ink") : String(localized: "Move Ink"))
        isMovingInk = false
        inkLasso?.drop()
        if done { setInkSelection(moved.selection) } else { restoreLiftedInk() }
    }

    func duplicateInkSelection() {
        moveInkSelection(by: CGSize(width: 18, height: 18), copying: true)
    }

    func deleteInkSelection() {
        guard !inkSelection.isEmpty else { return }
        let removed = InkLasso.removing(inkSelection, from: liveInk)
        isMovingInk = true
        document.updateInk(removed, actionName: String(localized: "Delete Ink"))
        isMovingInk = false
        setInkSelection([:])
    }

    /// The ink that is selected, page by page from the top, for reading as text.
    func selectedInk() -> [PKDrawing] {
        pages.compactMap { page in
            guard let indices = inkSelection[page.id], let ink = document.loadedInk(page.id) else { return nil }
            let chosen = Set(indices)
            let strokes = ink.strokes.enumerated().filter { chosen.contains($0.offset) }.map(\.element)
            return strokes.isEmpty ? nil : PKDrawing(strokes: strokes)
        }
    }

    /// Takes the selected ink off its pages and types `text` where the first of it was, as one undo step.
    func replaceInkSelection(with text: String) -> ItemSelection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let page = pages.first(where: { inkSelection[$0.id]?.isEmpty == false }),
              let bounds = selectedInk().first?.bounds, !bounds.isNull else { return nil }
        let item = InkText.box(for: trimmed, replacing: bounds, pageSize: page.size)
        let action = String(localized: "Turn Ink into Text")
        isMovingInk = true
        let done = document.updateInk(InkLasso.removing(inkSelection, from: liveInk), actionName: action)
        isMovingInk = false
        guard done else { return nil }
        document.updateItems(onPage: page.id, actionName: action) { $0.append(item) }
        setInkSelection([:])
        return ItemSelection(pageID: page.id, itemID: item.id)
    }

    // MARK: Replaying a recording

    /// Shows the page as it was at `time` into the recording: ink written later is faint. Nil ends the replay.
    func showReplay(_ timeline: ReplayTimeline?, at time: TimeInterval) {
        let changed = (replay == nil) != (timeline == nil)
        replay = timeline.map { ($0, time) }
        if changed {
            undoProxy.isSuspended = replay != nil
            if replay != nil { select(nil) }
            for canvas in canvases.values where canvas.isLoaded { setDrawingEnabled(!document.isReadOnly && !isLocked, canvas) }
            setToolPickerVisible(session.isToolPickerVisible)
            updateScrollTouches()
        }
        for (id, canvas) in canvases where canvas.isLoaded {
            guard let ink = document.loadedInk(id) else { continue }
            let pending = replay?.timeline.pending(onPage: id, at: time)
            guard pending != replayPending[id] else { continue }
            replayPending[id] = pending
            isApplyingDrawing = true
            canvas.drawing = ReplayInk.drawing(ink, pending: pending ?? [])
            isApplyingDrawing = false
        }
    }

    private func replayed(_ ink: PKDrawing, on pageID: UUID?) -> PKDrawing {
        guard let replay, let pageID else { return ink }
        let pending = replay.timeline.pending(onPage: pageID, at: replay.time)
        replayPending[pageID] = pending
        return ReplayInk.drawing(ink, pending: pending)
    }

    /// A tap on ink written during the recording jumps the sound to when it was written.
    private func seekReplay(to point: CGPoint) {
        guard let replay, bakedScale > 0 else { return }
        let local = contentView.convert(point, from: scrollView)
        for slot in slots.values where slot.frame.contains(local) {
            let onPage = CGPoint(x: (local.x - slot.frame.minX) / bakedScale, y: (local.y - slot.frame.minY) / bakedScale)
            guard let ink = document.loadedInk(slot.page.id), let stroke = ReplayInk.stroke(at: onPage, in: ink),
                  let time = replay.timeline.time(ofStroke: stroke, onPage: slot.page.id) else { return }
            session.seekReplay(to: time)
        }
    }

    // MARK: Presenting

    /// While presenting, whatever writes in the editor points instead: the Pencil always, a finger when fingers draw.
    private var fingersPoint: Bool {
        switch drawingPolicy {
        case .anyInput: true
        case .pencilOnly: false
        default: !UIPencilInteraction.prefersPencilOnlyDrawing
        }
    }

    func setPresenting(_ presenting: Bool) {
        guard presenting != isPresenting else { return }
        isPresenting = presenting
        UIApplication.shared.isIdleTimerDisabled = presenting
        laserGesture.isEnabled = presenting
        laser.clear()
        mirrored = nil
        if presenting { ExternalDisplay.shared.begin(for: self) } else { ExternalDisplay.shared.end(for: self) }
        if presenting { select(nil) }
        for canvas in canvases.values where canvas.isLoaded { setDrawingEnabled(!document.isReadOnly && !isLocked, canvas) }
        setToolPickerVisible(session.isToolPickerVisible)
        updateScrollTouches()
        guard isViewLoaded, lastBounds != .zero else { return }
        if presenting {
            zoomBeforePresenting = zoom
            updateInsets()
            present(page: currentPage)
        } else {
            let page = currentPage
            updateInsets()
            if let zoomBeforePresenting { bake(zoom: zoomBeforePresenting) }
            zoomBeforePresenting = nil
            scrollToPage(page, animated: false)
            updateWindow(force: true)
        }
    }

    /// Shows one whole page, the way a slide is shown.
    func present(page index: Int) {
        guard pages.indices.contains(index) else { return }
        pendingPage = index
        fit(.page)
    }

    func setLaserColor(_ color: LaserColor) {
        laser.color = color.uiColor
    }

    @objc private func pointLaser(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: laser)
        switch gesture.state {
        case .began:
            laser.begin(at: point)
            mirrorLaser(.began(onPresentedPage(point)))
        case .changed:
            laser.move(to: point)
            mirrorLaser(.moved(onPresentedPage(point)))
        default:
            laser.end()
            mirrorLaser(.ended)
        }
    }

    // MARK: The second screen

    private var presentedPage: Int? {
        let index = pendingPage ?? session.currentPage
        return isPresenting && pages.indices.contains(index) ? index : nil
    }

    /// A point in the laser's view as a fraction of the presented page.
    private func onPresentedPage(_ point: CGPoint) -> CGPoint {
        guard let index = presentedPage, effectiveScale > 0 else { return .zero }
        let frame = layout.frames[index], local = contentView.convert(point, from: laser)
        return CGPoint(x: (local.x / bakedScale - frame.minX) / frame.width, y: (local.y / bakedScale - frame.minY) / frame.height)
    }

    private func mirrorLaser(_ event: LaserEvent) {
        ExternalDisplay.shared.laser(event, color: laser.color, by: self)
    }

    @objc private func secondScreenChanged() {
        mirrored = nil
        mirrorPresentation()
    }

    /// Keeps a second screen on the page being presented, and on the part of it the iPad is zoomed in on.
    private func mirrorPresentation() {
        guard let index = presentedPage, effectiveScale > 0, let pixels = ExternalDisplay.shared.pixelSize(for: self) else { return }
        let page = pages[index], frame = layout.frames[index], area = readableArea
        let visible = CGRect(x: (scrollView.contentOffset.x + area.minX) / effectiveScale, y: (scrollView.contentOffset.y + area.minY) / effectiveScale,
                             width: area.width / effectiveScale, height: area.height / effectiveScale).intersection(frame)
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        ExternalDisplay.shared.setViewport(visible.isNull || visible.isEmpty ? whole : CGRect(
            x: (visible.minX - frame.minX) / frame.width, y: (visible.minY - frame.minY) / frame.height,
            width: visible.width / frame.width, height: visible.height / frame.height), by: self)
        let lifted = session.liftedTapes
        let liftedKey = page.hasItems ? page.items.filter { lifted.contains($0.id) }.map(\.id.uuidString).joined() : ""
        let key = "\(page.id)-\(page.thumbnailKey)-\(Int(pixels.width))x\(Int(pixels.height))-\(liftedKey)"
        guard key != mirrored else { return }
        mirrored = key
        let assets = document.package.assetsDirectory, titles = linkTitles
        let width = PresentationStage.renderWidth(pageSize: page.size, pixels: pixels)
        Task { [weak self] in
            guard let self else { return }
            let ink = await self.document.ink(page.id)
            let image = await Task.detached(priority: .userInitiated) {
                SharedSlide(image: PageRenderer.image(of: page, ink: ink, assets: assets, width: width, links: titles, lifted: lifted))
            }.value.image
            guard self.mirrored == key else { return }
            ExternalDisplay.shared.show(image, pageSize: page.size, by: self)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        [laserGesture, itemTap, itemHold, strokeHold, tapeTap].contains { $0 === gestureRecognizer || $0 === other }
    }

    /// Two fingers are scrolling or zooming, not pointing.
    private func dropLaser() {
        guard isPresenting, laser.isTracking else { return }
        laser.clear()
        mirrorLaser(.cleared)
        laserGesture.isEnabled = false
        laserGesture.isEnabled = true
    }

    // MARK: PKToolPickerObserver

    func toolPickerVisibilityDidChange(_ toolPicker: PKToolPicker) {
        if !toolPickerSuppressed, textView == nil, session.isToolPickerVisible != toolPicker.isVisible {
            session.isToolPickerVisible = toolPicker.isVisible
        }
        updateInsets()
        updateScrollTouches()
    }

    func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
        updateScrollTouches()
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

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        pendingPage = nil
        updateWindow()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        pendingPage = nil
        dropLaser()
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        pendingPage = nil
        dropLaser()
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
