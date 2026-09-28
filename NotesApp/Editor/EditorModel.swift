import SwiftUI
import PencilKit
import Observation

enum DrawingInput: String, CaseIterable, Identifiable {
    case system, pencilOnly, anyInput
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System Setting"
        case .pencilOnly: "Apple Pencil Only"
        case .anyInput: "Pencil and Finger"
        }
    }

    var policy: PKCanvasViewDrawingPolicy {
        switch self {
        case .system: .default
        case .pencilOnly: .pencilOnly
        case .anyInput: .anyInput
        }
    }
}

@MainActor
@Observable
final class EditorModel {
    let notebook: Notebook
    let notebookID: UUID
    private(set) var pages: [PageSpec]
    var currentPage = 0
    var canUndo = false
    var canRedo = false
    var showsToolPicker = true
    var drawingInput: DrawingInput {
        didSet {
            UserDefaults.standard.set(drawingInput.rawValue, forKey: SettingsKey.drawingInput)
            canvas?.setDrawingPolicy(drawingInput.policy)
        }
    }

    @ObservationIgnored private(set) var drawing: PKDrawing
    @ObservationIgnored weak var canvas: NotebookCanvasViewController?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var hasUnsavedChanges = false

    init(notebook: Notebook) {
        self.notebook = notebook
        self.notebookID = notebook.id
        let pages = notebook.pages
        self.pages = pages.isEmpty ? [notebook.newPage()] : pages
        self.drawing = NotebookStore.loadDrawing(for: notebook.id)
        let stored = UserDefaults.standard.string(forKey: SettingsKey.drawingInput)
        self.drawingInput = stored.flatMap(DrawingInput.init(rawValue:)) ?? .system
    }

    var drawingPolicy: PKCanvasViewDrawingPolicy { drawingInput.policy }
    var layout: NotebookLayout { NotebookLayout(pages: pages) }

    // MARK: - Drawing

    func drawingDidChange(_ drawing: PKDrawing) {
        self.drawing = drawing
        scheduleSave()
    }

    func undo() { canvas?.undo() }
    func redo() { canvas?.redo() }

    func toggleToolPicker() {
        showsToolPicker.toggle()
        canvas?.setToolPickerVisible(showsToolPicker)
    }

    func scrollTo(page index: Int, animated: Bool = true) {
        currentPage = index
        canvas?.scrollToPage(index, animated: animated)
    }

    // MARK: - Pages

    func addPage(after index: Int? = nil, template: PaperTemplate? = nil) {
        var page = notebook.newPage()
        let anchor = index.flatMap { pages.indices.contains($0) ? pages[$0] : nil }
        if let anchor, anchor.template != nil {
            page.size = anchor.size
            page.paperColor = anchor.paperColor
            page.background = anchor.background
        }
        if let template { page.background = .template(template) }
        insertPages([page], at: (index ?? pages.count - 1) + 1)
    }

    func insertPages(_ newPages: [PageSpec], at index: Int) {
        let position = min(max(index, 0), pages.count)
        var entries = pages.map { ($0, Optional($0.id)) }
        entries.insert(contentsOf: newPages.map { ($0, UUID?.none) }, at: position)
        apply(entries, scrollTo: position)
    }

    func duplicatePage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        var copy = pages[index]
        copy.id = UUID()
        var entries = pages.map { ($0, Optional($0.id)) }
        entries.insert((copy, pages[index].id), at: index + 1)
        apply(entries, scrollTo: index + 1)
    }

    func deletePage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        var entries = pages.map { ($0, Optional($0.id)) }
        entries.remove(at: index)
        if entries.isEmpty { entries = [(notebook.newPage(), nil)] }
        apply(entries, scrollTo: min(index, entries.count - 1))
    }

    func movePage(from source: Int, to destination: Int) {
        guard pages.indices.contains(source), pages.indices.contains(destination), source != destination else { return }
        var entries = pages.map { ($0, Optional($0.id)) }
        let item = entries.remove(at: source)
        entries.insert(item, at: destination)
        apply(entries, scrollTo: nil)
    }

    func setTemplate(_ template: PaperTemplate, forPageAt index: Int) {
        guard pages.indices.contains(index), pages[index].template != nil else { return }
        pages[index].background = .template(template)
        canvas?.reloadPages()
        scheduleSave()
    }

    func setPaperColor(_ color: PaperColor, forPageAt index: Int) {
        guard pages.indices.contains(index) else { return }
        pages[index].paperColor = color
        canvas?.reloadPages()
        scheduleSave()
    }

    private func apply(_ entries: [(PageSpec, UUID?)], scrollTo index: Int?) {
        let remapped = PageRemapper.remap(drawing: drawing, oldPages: pages, newPages: entries.map { (page: $0.0, source: $0.1) })
        pages = entries.map(\.0)
        drawing = remapped
        canvas?.applyDrawing(remapped)
        canvas?.reloadPages()
        if let index { scrollTo(page: index) }
        scheduleSave(delay: .zero)
    }

    // MARK: - Import

    func importPDF(from url: URL, at index: Int) throws {
        let pages = try NotebookImporter.pdfPages(from: url, notebookID: notebookID)
        insertPages(pages, at: index)
    }

    func importImage(_ data: Data, at index: Int) throws {
        let page = try NotebookImporter.imagePage(from: data, notebookID: notebookID)
        insertPages([page], at: index)
    }

    // MARK: - Persistence

    func scheduleSave(delay: Duration = .seconds(1.5)) {
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        saveTask?.cancel()
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        NotebookStore.save(drawing, for: notebookID)
        notebook.pages = pages
        notebook.modifiedAt = .now
        if let first = pages.first, let frame = layout.frames.first {
            let thumb = PaperRenderer.renderPage(first, frame: frame, drawing: drawing, notebookID: notebookID, width: 360)
            NotebookStore.saveThumbnail(thumb, for: notebookID)
        }
    }

    func close() {
        save()
        SearchIndexer.reindex(notebook)
    }

    // MARK: - Export

    func exportPDF() throws -> URL {
        save()
        return try PDFExporter.export(title: notebook.title, pages: pages, drawing: drawing, notebookID: notebookID)
    }

    func pageThumbnail(at index: Int, width: CGFloat) -> UIImage? {
        let layout = layout
        guard pages.indices.contains(index) else { return nil }
        return PaperRenderer.renderPage(pages[index], frame: layout.frames[index], drawing: drawing, notebookID: notebookID, width: width)
    }
}

enum SettingsKey {
    static let drawingInput = "drawingInput"
    static let defaultTemplate = "defaultTemplate"
    static let defaultPaperColor = "defaultPaperColor"
    static let defaultPageSize = "defaultPageSize"
    static let librarySort = "librarySort"
}
