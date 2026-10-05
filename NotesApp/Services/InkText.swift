import UIKit
import PencilKit

/// Reads selected handwriting as text, on the device, with the recogniser that indexes pages for search.
enum InkText {
    /// Each piece is the ink picked on one page, top page first. Nil when the recogniser failed.
    static func recognize(_ pieces: [PKDrawing]) -> String? {
        #if DEBUG
        // A UI test can only drag straight lines; `-scriptedInkText` says what they read as.
        if let scripted = LaunchOptions.value("-scriptedInkText") { return pieces.contains { !$0.strokes.isEmpty } ? scripted : "" }
        #endif
        var lines: [String] = []
        for piece in pieces {
            guard let image = image(of: piece) else { continue }
            guard let found = HandwritingIndexer.recognizeText(in: image) else { return nil }
            lines += found
        }
        return lines.joined(separator: "\n")
    }

    /// The ink as dark writing on white with room round it, large enough for small handwriting to be read.
    static func image(of drawing: PKDrawing) -> UIImage? {
        let bounds = drawing.bounds
        guard !drawing.strokes.isEmpty, !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        let frame = bounds.insetBy(dx: -24, dy: -24)
        let scale = min(max(2400 / max(frame.width, frame.height), 1), 3)
        var ink: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: frame, scale: scale)
        }
        guard let ink else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: frame.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: frame.size))
            ink.draw(in: CGRect(origin: .zero, size: frame.size))
        }
    }

    /// A text box that takes the place of handwriting: where it was, about as large, and kept on the page.
    static func box(for text: String, replacing bounds: CGRect, pageSize: CGSize) -> PageItem {
        let lines = max(text.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        var box = TextBox(string: text)
        box.fontSize = min(max((bounds.height / CGFloat(lines) * 0.62).rounded(), 13), 34)
        let room = max(pageSize.width - 24, 60)
        let width = min(max(box.naturalWidth(limit: room), min(bounds.width, room), 60), room)
        let size = CGSize(width: width, height: box.height(width: width))
        let x = min(max(bounds.minX, 12), max(pageSize.width - 12 - width, 12))
        let y = min(max(bounds.minY, 12), max(pageSize.height - 12 - size.height, 12))
        return PageItem(content: .text(box), center: CGPoint(x: x + width / 2, y: y + size.height / 2), size: size)
    }
}
