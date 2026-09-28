import CoreGraphics
import PencilKit

struct NotebookLayout {
    static let pageWidth: CGFloat = 800
    static let horizontalMargin: CGFloat = 24
    static let topMargin: CGFloat = 24
    static let pageGap: CGFloat = 24
    static let bottomMargin: CGFloat = 160
    static let contentWidth = pageWidth + horizontalMargin * 2

    let frames: [CGRect]
    let contentHeight: CGFloat

    init(pages: [PageSpec]) {
        var y = Self.topMargin
        var frames: [CGRect] = []
        for page in pages {
            let height = Self.pageHeight(for: page)
            frames.append(CGRect(x: Self.horizontalMargin, y: y, width: Self.pageWidth, height: height))
            y += height + Self.pageGap
        }
        self.frames = frames
        self.contentHeight = y - Self.pageGap + Self.bottomMargin
    }

    static func pageHeight(for page: PageSpec) -> CGFloat {
        guard page.size.width > 0 else { return pageWidth * 11 / 8.5 }
        return (pageWidth * page.size.height / page.size.width).rounded()
    }

    func pageIndex(atY y: CGFloat) -> Int {
        guard !frames.isEmpty else { return 0 }
        for (index, frame) in frames.enumerated() where y < frame.maxY + Self.pageGap / 2 {
            return index
        }
        return frames.count - 1
    }
}

enum PageRemapper {
    /// Rebuilds a drawing after pages were inserted, removed, reordered or duplicated.
    /// `newPages` pairs each resulting page with the id of the page its strokes should come from.
    static func remap(drawing: PKDrawing, oldPages: [PageSpec], newPages: [(page: PageSpec, source: UUID?)]) -> PKDrawing {
        let oldLayout = NotebookLayout(pages: oldPages)
        let newLayout = NotebookLayout(pages: newPages.map(\.page))

        var strokesBySource: [UUID: [PKStroke]] = [:]
        for stroke in drawing.strokes {
            let index = oldLayout.pageIndex(atY: stroke.renderBounds.midY)
            guard oldPages.indices.contains(index) else { continue }
            strokesBySource[oldPages[index].id, default: []].append(stroke)
        }
        var oldFrameByID: [UUID: CGRect] = [:]
        for (page, frame) in zip(oldPages, oldLayout.frames) { oldFrameByID[page.id] = frame }

        var result: [PKStroke] = []
        for (entry, newFrame) in zip(newPages, newLayout.frames) {
            guard let source = entry.source,
                  let oldFrame = oldFrameByID[source],
                  let strokes = strokesBySource[source] else { continue }
            let dy = newFrame.minY - oldFrame.minY
            for var stroke in strokes {
                if dy != 0 {
                    stroke.transform = stroke.transform.concatenating(CGAffineTransform(translationX: 0, y: dy))
                }
                result.append(stroke)
            }
        }
        return PKDrawing(strokes: result)
    }

    static func strokes(of drawing: PKDrawing, onPage index: Int, layout: NotebookLayout) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes.filter { layout.pageIndex(atY: $0.renderBounds.midY) == index })
    }
}
