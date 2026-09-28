import UIKit
import PencilKit

enum PDFExporter {
    static func export(title: String, pages: [PageSpec], drawing: PKDrawing, notebookID: UUID) throws -> URL {
        let layout = NotebookLayout(pages: pages)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name.isEmpty ? "Untitled" : name).pdf")

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "Swift Scribe",
        ]
        let firstSize = pages.first?.size ?? PageSize.letter.points
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: firstSize), format: format)
        try renderer.writePDF(to: url) { context in
            for (page, frame) in zip(pages, layout.frames) {
                let bounds = CGRect(origin: .zero, size: page.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                PaperRenderer.drawBackground(page, notebookID: notebookID, in: context.cgContext, size: page.size)
                let scale = page.size.width / frame.width * 3
                var ink: UIImage?
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                    ink = drawing.image(from: frame, scale: scale)
                }
                ink?.draw(in: bounds)
            }
        }
        return url
    }
}
