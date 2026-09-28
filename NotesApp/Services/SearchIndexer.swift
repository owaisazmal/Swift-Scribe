import UIKit
import PDFKit
import Vision
import PencilKit

enum SearchIndexer {
    @MainActor
    static func reindex(_ notebook: Notebook) {
        let id = notebook.id
        let pages = notebook.pages
        Task {
            let text = await Task.detached(priority: .utility) {
                recognizeText(notebookID: id, pages: pages)
            }.value
            if notebook.modelContext != nil { notebook.searchText = text }
        }
    }

    nonisolated static func recognizeText(notebookID: UUID, pages: [PageSpec]) -> String {
        let drawing = NotebookStore.loadDrawing(for: notebookID)
        let layout = NotebookLayout(pages: pages)
        var documents: [String: PDFDocument] = [:]
        var chunks: [String] = []

        for (index, page) in pages.enumerated() {
            if case .pdf(let file, let pageIndex) = page.background {
                if documents[file] == nil {
                    documents[file] = PDFDocument(url: NotebookStore.assetURL(file, notebook: notebookID))
                }
                if let text = documents[file]?.page(at: pageIndex)?.string { chunks.append(text) }
            }
            let ink = PageRemapper.strokes(of: drawing, onPage: index, layout: layout)
            guard !ink.strokes.isEmpty else { continue }
            let image = PaperRenderer.renderPage(page, frame: layout.frames[index], drawing: ink,
                                                 notebookID: notebookID, width: 1400, includeBackground: false)
            chunks.append(contentsOf: recognize(image))
        }
        return chunks.joined(separator: "\n")
    }

    private static func recognize(_ image: UIImage) -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        return request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
    }
}
