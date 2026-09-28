import UIKit
import PencilKit
import SwiftUI

private final class TiledPageLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0 }
}

private final class PageContentView: UIView {
    override class var layerClass: AnyClass { TiledPageLayer.self }

    private let page: PageSpec
    private let notebookID: UUID
    private let size: CGSize

    init(page: PageSpec, notebookID: UUID, size: CGSize) {
        self.page = page
        self.notebookID = notebookID
        self.size = size
        super.init(frame: CGRect(origin: .zero, size: size))
        isOpaque = true
        isUserInteractionEnabled = false
        let tiled = layer as! CATiledLayer
        tiled.levelsOfDetail = 4
        tiled.levelsOfDetailBias = 4
        tiled.tileSize = CGSize(width: 512, height: 512)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        PaperRenderer.drawBackground(page, notebookID: notebookID, in: ctx, size: size)
    }
}

private final class PageView: UIView {
    let page: PageSpec

    init(page: PageSpec, notebookID: UUID, frame: CGRect) {
        self.page = page
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowPath = UIBezierPath(rect: CGRect(origin: .zero, size: frame.size)).cgPath
        addSubview(PageContentView(page: page, notebookID: notebookID, size: frame.size))
    }

    required init?(coder: NSCoder) { fatalError() }
}

@MainActor
final class NotebookCanvasViewController: UIViewController, PKCanvasViewDelegate, PKToolPickerObserver {
    let canvasView = PKCanvasView()
    let toolPicker = PKToolPicker()
    private let pagesContainer = UIView()
    private var pageViews: [UUID: PageView] = [:]
    private var layout = NotebookLayout(pages: [])
    private var lastWidth: CGFloat = 0
    private var isApplyingDrawing = false
    private var isToolPickerSuppressed = false
    private let model: EditorModel

    init(model: EditorModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        canvasView.frame = view.bounds
        canvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvasView.delegate = self
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.alwaysBounceVertical = true
        canvasView.drawingPolicy = model.drawingPolicy
        canvasView.drawing = model.drawing
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
        view.addSubview(canvasView)

        pagesContainer.isUserInteractionEnabled = false
        pagesContainer.layer.anchorPoint = .zero
        canvasView.insertSubview(pagesContainer, at: 0)

        toolPicker.colorUserInterfaceStyle = .light
        toolPicker.addObserver(canvasView)
        toolPicker.addObserver(self)

        reloadPages()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setToolPickerVisible(model.showsToolPicker)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        toolPicker.setVisible(false, forFirstResponder: canvasView)
        canvasView.resignFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = canvasView.bounds.width
        guard width > 0, abs(width - lastWidth) > 0.5 else { return }
        let fit = width / NotebookLayout.contentWidth
        let relative = lastWidth > 0 ? canvasView.zoomScale / (lastWidth / NotebookLayout.contentWidth) : 1
        let pageBeforeResize = model.currentPage
        canvasView.minimumZoomScale = fit
        canvasView.maximumZoomScale = fit * 5
        canvasView.zoomScale = min(max(fit * relative, fit), fit * 5)
        lastWidth = width
        updateContentSize()
        if pageBeforeResize > 0 { scrollToPage(pageBeforeResize, animated: false) }
    }

    // MARK: - Pages

    func reloadPages() {
        layout = NotebookLayout(pages: model.pages)
        var next: [UUID: PageView] = [:]
        for (page, frame) in zip(model.pages, layout.frames) {
            if let existing = pageViews[page.id], existing.page == page, existing.bounds.size == frame.size {
                existing.frame = frame
                next[page.id] = existing
            } else {
                pageViews[page.id]?.removeFromSuperview()
                let view = PageView(page: page, notebookID: model.notebookID, frame: frame)
                pagesContainer.addSubview(view)
                next[page.id] = view
            }
        }
        for (id, view) in pageViews where next[id] == nil { view.removeFromSuperview() }
        pageViews = next
        pagesContainer.bounds = CGRect(x: 0, y: 0, width: NotebookLayout.contentWidth, height: layout.contentHeight)
        updateContentSize()
    }

    private func updateContentSize() {
        let zoom = canvasView.zoomScale
        pagesContainer.layer.position = .zero
        pagesContainer.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        canvasView.contentSize = CGSize(width: NotebookLayout.contentWidth * zoom, height: layout.contentHeight * zoom)
    }

    func scrollToPage(_ index: Int, animated: Bool) {
        guard layout.frames.indices.contains(index) else { return }
        let zoom = canvasView.zoomScale
        let target = (layout.frames[index].minY - NotebookLayout.topMargin) * zoom - canvasView.adjustedContentInset.top
        let maxY = max(-canvasView.adjustedContentInset.top,
                       canvasView.contentSize.height + canvasView.adjustedContentInset.bottom - canvasView.bounds.height)
        canvasView.setContentOffset(CGPoint(x: canvasView.contentOffset.x, y: min(target, maxY)), animated: animated)
    }

    func applyDrawing(_ drawing: PKDrawing) {
        isApplyingDrawing = true
        canvasView.drawing = drawing
        isApplyingDrawing = false
        canvasView.undoManager?.removeAllActions()
        refreshUndoState()
    }

    // MARK: - Tools

    func setToolPickerVisible(_ visible: Bool) {
        toolPicker.setVisible(visible && !isToolPickerSuppressed, forFirstResponder: canvasView)
        canvasView.becomeFirstResponder()
    }

    func setToolPickerSuppressed(_ suppressed: Bool) {
        guard suppressed != isToolPickerSuppressed else { return }
        isToolPickerSuppressed = suppressed
        setToolPickerVisible(model.showsToolPicker)
    }

    func setDrawingPolicy(_ policy: PKCanvasViewDrawingPolicy) {
        canvasView.drawingPolicy = policy
    }

    func undo() { canvasView.undoManager?.undo(); refreshUndoState() }
    func redo() { canvasView.undoManager?.redo(); refreshUndoState() }

    private func refreshUndoState() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            model.canUndo = canvasView.undoManager?.canUndo ?? false
            model.canRedo = canvasView.undoManager?.canRedo ?? false
        }
    }

    // MARK: - PKCanvasViewDelegate

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        refreshUndoState()
        guard !isApplyingDrawing else { return }
        model.drawingDidChange(canvasView.drawing)
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentSize()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let zoom = max(canvasView.zoomScale, 0.01)
        let probe = (scrollView.contentOffset.y + scrollView.adjustedContentInset.top + scrollView.bounds.height * 0.35) / zoom
        let index = layout.pageIndex(atY: probe)
        if index != model.currentPage { model.currentPage = index }
    }

    // MARK: - PKToolPickerObserver

    func toolPickerVisibilityDidChange(_ toolPicker: PKToolPicker) {
        if !isToolPickerSuppressed, model.showsToolPicker != toolPicker.isVisible {
            model.showsToolPicker = toolPicker.isVisible
        }
        toolPickerFramesObscuredDidChange(toolPicker)
    }

    func toolPickerFramesObscuredDidChange(_ toolPicker: PKToolPicker) {
        let obscured = toolPicker.frameObscured(in: view)
        let inset = obscured.isNull ? 0 : max(0, view.bounds.maxY - obscured.minY)
        canvasView.contentInset.bottom = inset
        canvasView.verticalScrollIndicatorInsets.bottom = inset
    }
}

struct NotebookCanvas: UIViewControllerRepresentable {
    let model: EditorModel

    func makeUIViewController(context: Context) -> NotebookCanvasViewController {
        let controller = NotebookCanvasViewController(model: model)
        model.canvas = controller
        return controller
    }

    func updateUIViewController(_ controller: NotebookCanvasViewController, context: Context) {}
}
