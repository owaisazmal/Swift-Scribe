import SwiftUI
import VisionKit

/// Paper scanned with the camera, straightened and cropped by the system's scanner, becomes pages.
enum DocumentScan {
    @MainActor
    static var isAvailable: Bool {
        #if DEBUG
        if LaunchOptions.arguments.contains("-fakeScan") { return true }
        #endif
        return VNDocumentCameraViewController.isSupported
    }

    /// A scan as a page's picture: at most 2,400 px on the long side, as JPEG.
    static func picture(_ image: UIImage) throws -> (data: Data, size: CGSize) {
        guard image.size.width > 0, image.size.height > 0 else { throw ImportError.unreadable }
        let scale = min(1, 2400 / max(image.size.width * image.scale, image.size.height * image.scale))
        let target = CGSize(width: (image.size.width * image.scale * scale).rounded(), height: (image.size.height * image.scale * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let jpeg = UIGraphicsImageRenderer(size: target, format: format).jpegData(withCompressionQuality: 0.82) { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return (jpeg, target)
    }

    /// The page a scan fills: as wide as a letter page, as tall as the paper was.
    static func page(file: String, pictureSize: CGSize) -> NotebookPage {
        let width = PageSize.letter.points.width
        return NotebookPage(background: .image(file: file), paperColor: .white,
                            size: CGSize(width: width, height: (width * pictureSize.height / max(pictureSize.width, 1)).rounded()))
    }

    /// Stores each scan in the notebook and returns its pages, in the order they were scanned.
    static func pages(from images: [UIImage], in package: NotebookPackage) async throws -> [NotebookPage] {
        var pages: [NotebookPage] = []
        for image in images {
            let picture = try await Task.detached(priority: .userInitiated) { try picture(image) }.value
            let file = try await package.writeAsset(picture.data, ext: "jpg")
            pages.append(page(file: file, pictureSize: picture.size))
        }
        guard !pages.isEmpty else { throw ImportError.empty }
        return pages
    }

    #if DEBUG
    /// `-fakeScan` stands these in for the camera, which a simulator doesn't have: two sheets of printed text.
    static func samples() -> [UIImage] {
        [("QUARTERLY REPORT", ["Revenue grew in the north.", "Costs held steady."]), ("MEETING AGENDA", ["Budget review", "Hiring plan"])].map { title, lines in
            let size = CGSize(width: 1240, height: 1754)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor(white: 0.97, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                (title as NSString).draw(at: CGPoint(x: 120, y: 160), withAttributes: [.font: UIFont.systemFont(ofSize: 84, weight: .bold), .foregroundColor: UIColor.black])
                for (index, line) in lines.enumerated() {
                    (line as NSString).draw(at: CGPoint(x: 120, y: 340 + CGFloat(index) * 110),
                                            withAttributes: [.font: UIFont.systemFont(ofSize: 56), .foregroundColor: UIColor.darkGray])
                }
            }
        }
    }
    #endif
}

/// The system's document camera. `finish` gets the scanned sheets, or none when the scan was cancelled or failed.
struct DocumentScanner: UIViewControllerRepresentable {
    let finish: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let finish: ([UIImage]) -> Void

        init(finish: @escaping ([UIImage]) -> Void) { self.finish = finish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            finish((0..<scan.pageCount).map(scan.imageOfPage(at:)))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { finish([]) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { finish([]) }
    }
}
