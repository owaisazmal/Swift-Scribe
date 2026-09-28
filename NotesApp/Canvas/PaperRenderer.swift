import UIKit
import PencilKit

final class PDFDocumentCache: @unchecked Sendable {
    static let shared = PDFDocumentCache()
    private var documents: [URL: CGPDFDocument] = [:]
    private let lock = NSLock()

    func document(at url: URL) -> CGPDFDocument? {
        lock.lock(); defer { lock.unlock() }
        if let doc = documents[url] { return doc }
        guard let doc = CGPDFDocument(url as CFURL) else { return nil }
        documents[url] = doc
        return doc
    }
}

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(at url: URL) -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

enum PaperRenderer {
    static func uiColor(_ color: PaperColor) -> UIColor {
        let (r, g, b) = color.rgb
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// Draws a page background into `ctx`, filling a rect of `size` at the origin (top-left, y down).
    static func drawBackground(_ page: PageSpec, notebookID: UUID, in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(uiColor(page.effectivePaperColor).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        switch page.background {
        case .template(let template):
            drawTemplate(template, color: page.paperColor, in: ctx, size: size)
        case .pdf(let file, let index):
            let url = NotebookStore.assetURL(file, notebook: notebookID)
            guard let doc = PDFDocumentCache.shared.document(at: url),
                  let pdfPage = doc.page(at: index + 1) else { return }
            drawPDFPage(pdfPage, in: ctx, size: size)
        case .image(let file):
            let url = NotebookStore.assetURL(file, notebook: notebookID)
            guard let image = ImageCache.shared.image(at: url) else { return }
            UIGraphicsPushContext(ctx)
            image.draw(in: CGRect(origin: .zero, size: size))
            UIGraphicsPopContext()
        }
    }

    static func displaySize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox)
        let rotation = ((page.rotationAngle % 360) + 360) % 360
        return rotation == 90 || rotation == 270 ? CGSize(width: box.height, height: box.width) : box.size
    }

    static func drawPDFPage(_ page: CGPDFPage, in ctx: CGContext, size: CGSize) {
        let box = page.getBoxRect(.cropBox)
        let display = displaySize(of: page)
        let rotation = ((page.rotationAngle % 360) + 360) % 360
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: size.width / display.width, y: -size.height / display.height)
        switch rotation {
        case 90:
            ctx.translateBy(x: 0, y: display.height)
            ctx.rotate(by: -.pi / 2)
        case 180:
            ctx.translateBy(x: display.width, y: display.height)
            ctx.rotate(by: .pi)
        case 270:
            ctx.translateBy(x: display.width, y: 0)
            ctx.rotate(by: .pi / 2)
        default:
            break
        }
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.clip(to: box)
        ctx.interpolationQuality = .high
        ctx.setRenderingIntent(.defaultIntent)
        ctx.drawPDFPage(page)
        ctx.restoreGState()
    }

    static func drawTemplate(_ template: PaperTemplate, color: PaperColor, in ctx: CGContext, size: CGSize) {
        let unit = size.width / NotebookLayout.pageWidth
        let line = color.isDark
            ? UIColor(white: 1, alpha: 0.16)
            : UIColor(red: 0.55, green: 0.68, blue: 0.84, alpha: 0.55)
        let accent = color.isDark
            ? UIColor(red: 1, green: 0.45, blue: 0.45, alpha: 0.35)
            : UIColor(red: 0.9, green: 0.35, blue: 0.35, alpha: 0.45)
        ctx.saveGState()
        ctx.setLineWidth(max(0.5, 1 * unit))

        func hLines(spacing: CGFloat, from top: CGFloat) {
            var y = top
            while y < size.height - 20 * unit {
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            ctx.setStrokeColor(line.cgColor)
            ctx.strokePath()
        }

        func marginLine(x: CGFloat) {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: size.height))
            ctx.setStrokeColor(accent.cgColor)
            ctx.strokePath()
        }

        switch template {
        case .blank:
            break
        case .narrowRuled:
            hLines(spacing: 28 * unit, from: 120 * unit)
            marginLine(x: 104 * unit)
        case .wideRuled:
            hLines(spacing: 38 * unit, from: 120 * unit)
            marginLine(x: 104 * unit)
        case .grid:
            let spacing = 26 * unit
            var x = spacing
            while x < size.width {
                ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: size.height)); x += spacing
            }
            var y = spacing
            while y < size.height {
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y)); y += spacing
            }
            ctx.setStrokeColor(line.withAlphaComponent(color.isDark ? 0.12 : 0.35).cgColor)
            ctx.strokePath()
        case .dotted:
            let spacing = 26 * unit
            let r = max(0.8, 1.6 * unit)
            ctx.setFillColor(line.withAlphaComponent(color.isDark ? 0.35 : 0.9).cgColor)
            var y = spacing
            while y < size.height {
                var x = spacing
                while x < size.width {
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += spacing
                }
                y += spacing
            }
        case .cornell:
            let summaryTop = size.height * 0.8
            let cueRight = 240 * unit
            var y = 120 * unit
            while y < summaryTop {
                ctx.move(to: CGPoint(x: cueRight, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y)); y += 30 * unit
            }
            ctx.setStrokeColor(line.cgColor)
            ctx.strokePath()
            ctx.setLineWidth(max(1, 2 * unit))
            ctx.move(to: CGPoint(x: 0, y: 90 * unit)); ctx.addLine(to: CGPoint(x: size.width, y: 90 * unit))
            ctx.move(to: CGPoint(x: cueRight, y: 90 * unit)); ctx.addLine(to: CGPoint(x: cueRight, y: summaryTop))
            ctx.move(to: CGPoint(x: 0, y: summaryTop)); ctx.addLine(to: CGPoint(x: size.width, y: summaryTop))
            ctx.setStrokeColor(accent.cgColor)
            ctx.strokePath()
        case .music:
            let staffGap = 10 * unit
            let staffHeight = staffGap * 4
            var top = 100 * unit
            while top + staffHeight < size.height - 60 * unit {
                for i in 0..<5 {
                    let y = top + CGFloat(i) * staffGap
                    ctx.move(to: CGPoint(x: 60 * unit, y: y)); ctx.addLine(to: CGPoint(x: size.width - 60 * unit, y: y))
                }
                top += staffHeight + 60 * unit
            }
            ctx.setStrokeColor((color.isDark ? UIColor(white: 1, alpha: 0.3) : UIColor(white: 0.35, alpha: 0.7)).cgColor)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Renders a page (background + ink) to an image. `drawing` must be in canvas coordinates.
    static func renderPage(_ page: PageSpec, frame: CGRect, drawing: PKDrawing, notebookID: UUID,
                           width: CGFloat, includeBackground: Bool = true) -> UIImage {
        let scale = width / frame.width
        let size = CGSize(width: width, height: (frame.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var ink: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: frame, scale: scale)
        }
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if includeBackground {
                drawBackground(page, notebookID: notebookID, in: context.cgContext, size: size)
            } else {
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            ink?.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
