import UIKit

enum NotebookImporter {
    static func pdfPages(from url: URL, notebookID: UUID) throws -> [PageSpec] {
        let file = try NotebookStore.importAsset(from: url, notebook: notebookID, ext: "pdf")
        let stored = NotebookStore.assetURL(file, notebook: notebookID)
        guard let document = CGPDFDocument(stored as CFURL) else { throw ImportError.unreadable }
        if document.isEncrypted && !document.isUnlocked && !document.unlockWithPassword("") {
            try? FileManager.default.removeItem(at: stored)
            throw ImportError.locked
        }
        let pages = (0..<document.numberOfPages).compactMap { index -> PageSpec? in
            guard let page = document.page(at: index + 1) else { return nil }
            return PageSpec(background: .pdf(file: file, pageIndex: index), paperColor: .white,
                            size: PaperRenderer.displaySize(of: page))
        }
        guard !pages.isEmpty else { throw ImportError.empty }
        return pages
    }

    static func imagePage(from data: Data, notebookID: UUID) throws -> PageSpec {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw ImportError.unreadable
        }
        let maxSide: CGFloat = 2400
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = normalized.jpegData(compressionQuality: 0.88) else { throw ImportError.unreadable }
        let file = try NotebookStore.writeAsset(jpeg, notebook: notebookID, ext: "jpg")
        let width = PageSize.letter.points.width
        return PageSpec(background: .image(file: file), paperColor: .white,
                        size: CGSize(width: width, height: (width * target.height / target.width).rounded()))
    }
}
