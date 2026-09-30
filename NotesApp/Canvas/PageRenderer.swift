import UIKit
import PencilKit
import os

/// A small least-recently-used cache that is safe to use from any thread.
final class LRUCache<Value: Sendable>: Sendable {
    private struct State {
        var values: [String: Value] = [:]
        var order: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let capacity: Int

    init(capacity: Int) { self.capacity = capacity }

    func value(_ key: String, create: () -> Value?) -> Value? {
        if let hit = state.withLock({ state -> Value? in
            guard let value = state.values[key] else { return nil }
            state.order.removeAll { $0 == key }
            state.order.append(key)
            return value
        }) { return hit }
        guard let created = create() else { return nil }
        state.withLock { state in
            state.values[key] = created
            state.order.removeAll { $0 == key }
            state.order.append(key)
            while state.order.count > capacity {
                state.values.removeValue(forKey: state.order.removeFirst())
            }
        }
        return created
    }

    var count: Int { state.withLock { $0.values.count } }

    func removeAll() { state.withLock { $0 = State() } }
}

/// `CGPDFDocument` is immutable once opened and safe to read from the tiling threads.
struct SharedPDF: @unchecked Sendable {
    let document: CGPDFDocument
}

struct SharedImage: @unchecked Sendable {
    let image: CGImage
}

/// Draws page backgrounds (paper templates, PDF pages, photos) in page-local points. Thread-safe.
enum PageRenderer {
    static let pdfs = LRUCache<SharedPDF>(capacity: 6)
    static let images = LRUCache<SharedImage>(capacity: 12)

    static func paperColor(_ color: PaperColor) -> UIColor {
        let (r, g, b) = color.rgb
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// Fills `rect` (whose size is the page size scaled by `rect.width / page.size.width`) with the page background.
    static func drawBackground(_ page: NotebookPage, assets: URL, in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(paperColor(page.effectivePaperColor).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        switch page.background {
        case .template:
            drawTemplate(page.template ?? .blank, color: page.paperColor, in: ctx, size: size)
        case .pdf(let file, let index):
            let url = assets.appending(path: file)
            guard let pdf = pdfs.value(url.path(percentEncoded: false), create: {
                CGPDFDocument(url as CFURL).map(SharedPDF.init)
            }), let pdfPage = pdf.document.page(at: index + 1) else { return }
            drawPDFPage(pdfPage, in: ctx, size: size)
        case .image(let file):
            let url = assets.appending(path: file)
            guard let image = images.value(url.path(percentEncoded: false), create: {
                UIImage(contentsOfFile: url.path(percentEncoded: false))?.cgImage.map(SharedImage.init)
            }) else { return }
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(image.image, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        case .unknown:
            break
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
        ctx.drawPDFPage(page)
        ctx.restoreGState()
    }

    /// Renders a page (background plus ink clipped to the page) to an image `width` points wide. Thread-safe.
    static func image(of page: NotebookPage, ink: PKDrawing, assets: URL, width: CGFloat, scale: CGFloat = 1,
                      includeBackground: Bool = true) -> UIImage {
        let factor = width / max(page.size.width, 1)
        let size = CGSize(width: width, height: (page.size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        var inkImage: UIImage?
        if !ink.strokes.isEmpty {
            UITraitCollection(userInterfaceStyle: includeBackground ? page.effectivePaperColor.inkAppearance : .light).performAsCurrent {
                inkImage = ink.image(from: CGRect(origin: .zero, size: page.size), scale: factor * scale)
            }
        }
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if includeBackground {
                drawBackground(page, assets: assets, in: context.cgContext, size: size)
            } else {
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            inkImage?.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
