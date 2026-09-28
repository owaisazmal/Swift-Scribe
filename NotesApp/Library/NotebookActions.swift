import SwiftData
import PencilKit
import UIKit

@MainActor
enum NotebookActions {
    static func create(title: String, template: PaperTemplate, color: PaperColor, size: PageSize,
                       folder: Folder?, in context: ModelContext) -> Notebook {
        let notebook = Notebook(title: title, template: template, color: color, size: size, folder: folder)
        context.insert(notebook)
        refreshThumbnail(notebook)
        return notebook
    }

    static func importPDF(from url: URL, folder: Folder?, in context: ModelContext) throws -> Notebook {
        let title = url.deletingPathExtension().lastPathComponent
        let notebook = Notebook(title: title, template: .blank, color: .white, size: .letter, folder: folder)
        do {
            notebook.pages = try NotebookImporter.pdfPages(from: url, notebookID: notebook.id)
        } catch {
            NotebookStore.deleteFiles(for: notebook.id)
            throw error
        }
        context.insert(notebook)
        refreshThumbnail(notebook)
        SearchIndexer.reindex(notebook)
        return notebook
    }

    static func duplicate(_ notebook: Notebook, in context: ModelContext) {
        let copy = Notebook(title: "\(notebook.title) Copy", template: notebook.defaultTemplate,
                            color: notebook.defaultColor, size: notebook.defaultSize, folder: notebook.folder)
        NotebookStore.duplicate(from: notebook.id, to: copy.id)
        copy.pagesData = notebook.pagesData
        copy.pageCount = notebook.pageCount
        copy.recordingsData = notebook.recordingsData
        copy.searchText = notebook.searchText
        context.insert(copy)
    }

    static func moveToTrash(_ notebook: Notebook) {
        notebook.deletedAt = .now
    }

    static func restore(_ notebook: Notebook) {
        notebook.deletedAt = nil
    }

    static func deletePermanently(_ notebook: Notebook, in context: ModelContext) {
        NotebookStore.deleteFiles(for: notebook.id)
        context.delete(notebook)
    }

    static func purgeExpiredTrash(in context: ModelContext, olderThan days: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let descriptor = FetchDescriptor<Notebook>(predicate: #Predicate { $0.deletedAt != nil })
        for notebook in (try? context.fetch(descriptor)) ?? [] {
            if let deletedAt = notebook.deletedAt, deletedAt < cutoff {
                deletePermanently(notebook, in: context)
            }
        }
    }

    static func exportPDF(_ notebook: Notebook) throws -> URL {
        try PDFExporter.export(title: notebook.title, pages: notebook.pages,
                               drawing: NotebookStore.loadDrawing(for: notebook.id), notebookID: notebook.id)
    }

    static func refreshThumbnail(_ notebook: Notebook) {
        let pages = notebook.pages
        guard let first = pages.first else { return }
        let layout = NotebookLayout(pages: pages)
        let image = PaperRenderer.renderPage(first, frame: layout.frames[0],
                                             drawing: NotebookStore.loadDrawing(for: notebook.id),
                                             notebookID: notebook.id, width: 360)
        NotebookStore.saveThumbnail(image, for: notebook.id)
    }
}
