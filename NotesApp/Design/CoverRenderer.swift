import UIKit
import CryptoKit
import os

struct CoverRequest: Sendable, Hashable {
    var notebookID: UUID
    var spec: CoverSpec
    var title: String
    var meta: String
    var width: CGFloat
    var scale: CGFloat
    var dark: Bool
    var highContrast: Bool
    var firstPage: URL?
    var firstPageKey: String?
    var firstPageIsPDF: Bool

    var size: CGSize { CGSize(width: width, height: (width * 4 / 3).rounded()) }

    var key: String {
        let raw = [notebookID.uuidString, spec.styleRaw, spec.clothRaw, spec.inksRaw.joined(separator: "+"), "\(spec.seed)",
                   title, meta, "\(Int(width))@\(scale)", dark ? "d" : "l", highContrast ? "hc" : "", firstPageKey ?? "",
                   firstPageIsPDF ? "pdf" : "", "r\(CoverRenderer.version)"].joined(separator: "|")
        return SHA256.hash(data: Data(raw.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// Draws covers with Core Graphics. Pure and thread-safe: every cover is a function of its request.
enum CoverRenderer {
    static let version = 2

    static func render(_ request: CoverRequest, firstPage: CGImage? = nil) -> UIImage {
        let size = request.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = request.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext
            let bounds = CGRect(origin: .zero, size: size)
            let shape = coverPath(bounds)
            ctx.addPath(shape.cgPath)
            ctx.clip()
            switch request.spec.style {
            case .cloth: drawCloth(request, in: ctx, bounds: bounds)
            case .print: drawPrint(request, in: ctx, bounds: bounds)
            case .firstPage: drawFirstPage(request, image: firstPage, in: ctx, bounds: bounds)
            }
            if request.dark, request.spec.style != .cloth { dim(ctx, bounds) }
        }
    }

    /// Night desk: covers sit about 10% darker so they don't glow, while cloth labels stay light.
    private static func dim(_ ctx: CGContext, _ bounds: CGRect) {
        ctx.setFillColor(UIColor(white: 0, alpha: 0.1).cgColor)
        ctx.fill(bounds)
    }

    static func coverPath(_ bounds: CGRect) -> UIBezierPath {
        let spine = bounds.width * 0.013, edge = bounds.width * 0.035
        let path = UIBezierPath()
        path.move(to: CGPoint(x: spine, y: 0))
        path.addLine(to: CGPoint(x: bounds.maxX - edge, y: 0))
        path.addQuadCurve(to: CGPoint(x: bounds.maxX, y: edge), controlPoint: CGPoint(x: bounds.maxX, y: 0))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - edge))
        path.addQuadCurve(to: CGPoint(x: bounds.maxX - edge, y: bounds.maxY), controlPoint: CGPoint(x: bounds.maxX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: spine, y: bounds.maxY))
        path.addQuadCurve(to: CGPoint(x: 0, y: bounds.maxY - spine), controlPoint: CGPoint(x: 0, y: bounds.maxY))
        path.addLine(to: CGPoint(x: 0, y: spine))
        path.addQuadCurve(to: CGPoint(x: spine, y: 0), controlPoint: .zero)
        path.close()
        return path
    }

    // MARK: Cloth

    private static func drawCloth(_ request: CoverRequest, in ctx: CGContext, bounds: CGRect) {
        let w = bounds.width
        ctx.setFillColor(request.spec.cloth.uiColor.cgColor)
        ctx.fill(bounds)
        if !request.highContrast { drawWeave(in: ctx, bounds: bounds) }
        drawSpine(in: ctx, bounds: bounds, width: 0.08, color: UIColor(white: 0, alpha: 0.2))
        if request.dark { dim(ctx, bounds) }

        let labelX = w * 0.17, labelWidth = w * (1 - 0.17 - 0.09), padding = w * 0.045
        let titleFont = ScribeFonts.coverLabel(size: w * 0.105) as UIFont
        let metaFont = smallCaps(size: w * 0.058, weight: .medium)
        let title = NSAttributedString(string: request.title, attributes: [
            .font: titleFont, .foregroundColor: UIColor(hex: 0x1B2230), .paragraphStyle: paragraph(lineHeight: 1.08),
        ])
        let meta = NSAttributedString(string: request.meta.uppercased(), attributes: [
            .font: metaFont, .kern: w * 0.004,
            .foregroundColor: UIColor(hex: request.highContrast ? 0x444A59 : (request.dark ? 0x505665 : 0x5A6070)),
        ])
        let textWidth = labelWidth - padding * 2
        let titleHeight = min(title.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin], context: nil).height,
                              titleFont.lineHeight * 3.3)
        let metaHeight = request.meta.isEmpty ? 0 : metaFont.lineHeight
        let gap = request.meta.isEmpty ? 0 : w * 0.02
        let label = CGRect(x: labelX, y: bounds.height * 0.17, width: labelWidth, height: padding * 2 + titleHeight + gap + metaHeight)

        ctx.setFillColor(UIColor(hex: request.dark ? 0xE9E1CE : 0xF7F1E3).cgColor)
        ctx.fill(label)
        let rule = UIColor(hex: 0x1B2230, alpha: request.highContrast ? 0.55 : 0.3)
        ctx.setStrokeColor(rule.cgColor)
        ctx.setLineWidth(max(0.5, w * 0.005))
        ctx.stroke(label.insetBy(dx: w * 0.004, dy: w * 0.004))
        ctx.setStrokeColor(rule.withAlphaComponent(request.highContrast ? 0.45 : 0.18).cgColor)
        ctx.stroke(label.insetBy(dx: w * 0.02, dy: w * 0.02))

        UIGraphicsPushContext(ctx)
        title.draw(with: CGRect(x: label.minX + padding, y: label.minY + padding, width: textWidth, height: titleHeight),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        if metaHeight > 0 {
            meta.draw(with: CGRect(x: label.minX + padding, y: label.minY + padding + titleHeight + gap, width: textWidth, height: metaHeight),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
        UIGraphicsPopContext()
    }

    private static func drawWeave(in ctx: CGContext, bounds: CGRect) {
        let w = bounds.width
        let period = max(2, w * 0.023), line = max(0.5, w * 0.011)
        ctx.saveGState()
        ctx.setLineWidth(line)
        for (alpha, white, direction) in [(0.06, 1.0, 1.0), (0.07, 0.0, -1.0)] {
            ctx.setStrokeColor(UIColor(white: white, alpha: alpha).cgColor)
            var offset = -bounds.height
            while offset < bounds.width + bounds.height {
                if direction > 0 {
                    ctx.move(to: CGPoint(x: offset, y: 0))
                    ctx.addLine(to: CGPoint(x: offset + bounds.height, y: bounds.height))
                } else {
                    ctx.move(to: CGPoint(x: offset + bounds.height, y: 0))
                    ctx.addLine(to: CGPoint(x: offset, y: bounds.height))
                }
                offset += period
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func drawSpine(in ctx: CGContext, bounds: CGRect, width fraction: CGFloat, color: UIColor) {
        let spine = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        ctx.setFillColor(color.cgColor)
        ctx.fill(spine)
        ctx.setFillColor(UIColor(white: 1, alpha: 0.12).cgColor)
        ctx.fill(CGRect(x: spine.maxX, y: 0, width: max(0.5, bounds.width * 0.005), height: bounds.height))
    }

    // MARK: Print

    enum PrintPattern: CaseIterable, Sendable { case dots, stripes, rings, halftone, disc, band, fill }

    struct PrintPlan: Sendable, Equatable {
        var base: PrintPattern
        var overlay: PrintPattern
        var baseInk: RisoInk
        var overlayInk: RisoInk
        var misregistration: CGSize
        var jitter: [CGFloat]
    }

    static func printPlan(for request: CoverRequest) -> PrintPlan {
        var rng = CoverRNG(id: request.notebookID, seed: request.spec.seed)
        let inks = request.spec.inks
        let bases: [PrintPattern] = [.dots, .stripes, .rings, .halftone, .fill]
        let overlays: [PrintPattern] = [.disc, .band, .dots, .stripes]
        let base = bases[Int(rng.next() % UInt64(bases.count))]
        var overlay = overlays[Int(rng.next() % UInt64(overlays.count))]
        if overlay == base { overlay = base == .dots ? .disc : .band }
        let swap = rng.next() % 2 == 0
        let dx = CGFloat(Double(rng.next() % 601) / 1000 - 0.3), dy = CGFloat(Double(rng.next() % 601) / 1000 - 0.3)
        let jitter = (0..<6).map { _ in CGFloat(Double(rng.next() % 1001) / 1000) }
        return PrintPlan(base: base, overlay: overlay, baseInk: swap ? inks.1 : inks.0, overlayInk: swap ? inks.0 : inks.1,
                         misregistration: CGSize(width: dx, height: dy), jitter: jitter)
    }

    private static func drawPrint(_ request: CoverRequest, in ctx: CGContext, bounds: CGRect) {
        let stock = UIColor(hex: RisoInk.paperStock)
        ctx.setFillColor(stock.cgColor)
        ctx.fill(bounds)
        let plan = printPlan(for: request)
        ctx.saveGState()
        ctx.setBlendMode(.multiply)
        if request.highContrast {
            ctx.setFillColor(plan.baseInk.uiColor.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.52))
            ctx.setFillColor(plan.overlayInk.uiColor.cgColor)
            ctx.fill(CGRect(x: 0, y: bounds.height * 0.52, width: bounds.width, height: bounds.height * 0.2))
        } else {
            drawPattern(plan.base, ink: plan.baseInk, jitter: plan.jitter, in: ctx, bounds: bounds)
            ctx.translateBy(x: plan.misregistration.width, y: plan.misregistration.height)
            drawPattern(plan.overlay, ink: plan.overlayInk, jitter: Array(plan.jitter.reversed()), in: ctx, bounds: bounds)
        }
        ctx.restoreGState()
        drawSpine(in: ctx, bounds: bounds, width: 0.08, color: UIColor(hex: 0x1C1C21, alpha: 0.24))
        drawPrintTitle(request.title, in: ctx, bounds: bounds)
    }

    private static func drawPattern(_ pattern: PrintPattern, ink: RisoInk, jitter j: [CGFloat], in ctx: CGContext, bounds: CGRect) {
        let w = bounds.width, h = bounds.height
        ctx.setFillColor(ink.uiColor.cgColor)
        ctx.setStrokeColor(ink.uiColor.cgColor)
        switch pattern {
        case .fill:
            ctx.setFillColor(ink.uiColor.withAlphaComponent(0.9).cgColor)
            ctx.fill(bounds)
        case .dots:
            let cell = w * (0.11 + 0.03 * j[0]), radius = cell * 0.36
            var y = cell / 2 - cell * j[1]
            while y < h + cell {
                var x = cell / 2 - cell * j[2]
                while x < w + cell {
                    ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += cell
                }
                y += cell
            }
        case .halftone:
            let cell = w * (0.085 + 0.02 * j[0])
            let angle = (165 + 20 * (j[3] - 0.5)) * .pi / 180
            let direction = CGPoint(x: sin(angle), y: -cos(angle))
            var y = cell / 2
            while y < h + cell {
                var x = cell / 2
                while x < w + cell {
                    let t = ((x - w / 2) * direction.x + (y - h / 2) * direction.y) / (h * 0.6) + 0.5
                    let radius = cell * 0.48 * max(0, min(1, 1 - t))
                    if radius > cell * 0.05 {
                        ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    }
                    x += cell
                }
                y += cell
            }
        case .stripes:
            let period = w * (0.1 + 0.03 * j[0]), band = period * 0.48
            ctx.saveGState()
            ctx.translateBy(x: w / 2, y: h / 2)
            ctx.rotate(by: (-45 + 30 * (j[4] - 0.5)) * .pi / 180)
            let reach = hypot(w, h)
            var x = -reach
            while x < reach {
                ctx.fill(CGRect(x: x, y: -reach, width: band, height: reach * 2))
                x += period
            }
            ctx.restoreGState()
        case .rings:
            let centre = CGPoint(x: w * (0.1 + 0.2 * j[0]), y: h * (0.78 + 0.15 * j[1]))
            let period = w * (0.1 + 0.02 * j[2]), ring = period * 0.46
            ctx.setLineWidth(ring)
            var radius = ring / 2
            while radius < hypot(w, h) {
                ctx.strokeEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
                radius += period
            }
        case .disc:
            let radius = w * (0.34 + 0.12 * j[0])
            let centre = CGPoint(x: w * (0.62 + 0.2 * j[1]), y: h * (0.2 + 0.15 * j[2]))
            ctx.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        case .band:
            let top = h * (0.44 + 0.2 * j[3])
            ctx.fill(CGRect(x: 0, y: top, width: w, height: h * (0.24 + 0.1 * j[4])))
        }
    }

    private static func drawPrintTitle(_ title: String, in ctx: CGContext, bounds: CGRect) {
        let w = bounds.width
        let font = ScribeFonts.printTitle(size: w * 0.14) as UIFont
        let text = NSAttributedString(string: title.uppercased(), attributes: [
            .font: font, .foregroundColor: UIColor(hex: 0x1C1C21), .paragraphStyle: paragraph(lineHeight: 0.92),
        ])
        let maxWidth = w * 0.72, pad = w * 0.035
        let measured = text.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        let height = min(measured.height, font.lineHeight * 0.92 * 3 + 1)
        let box = CGRect(x: w * 0.15, y: bounds.height * 0.93 - height - pad * 1.6, width: min(measured.width, maxWidth) + pad * 2, height: height + pad * 1.6)
        ctx.setFillColor(UIColor(hex: RisoInk.paperStock).cgColor)
        ctx.fill(box)
        UIGraphicsPushContext(ctx)
        text.draw(with: CGRect(x: box.minX + pad, y: box.minY + pad * 0.9, width: maxWidth, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        UIGraphicsPopContext()
    }

    // MARK: First page

    private static func drawFirstPage(_ request: CoverRequest, image: CGImage?, in ctx: CGContext, bounds: CGRect) {
        let w = bounds.width
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(bounds)
        let area = CGRect(x: w * 0.09, y: 0, width: w * 0.91, height: bounds.height)
        if let image {
            let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
            let drawWidth = max(area.width, area.height * aspect)
            let rect = CGRect(x: area.minX, y: 0, width: drawWidth, height: drawWidth / aspect)
            ctx.saveGState()
            ctx.clip(to: area)
            ctx.translateBy(x: 0, y: rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
            ctx.restoreGState()
        } else {
            ctx.setFillColor(UIColor(hex: 0xFFFDF8).cgColor)
            ctx.fill(area)
        }
        ctx.setFillColor(request.spec.cloth.uiColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w * 0.09, height: bounds.height))
        if request.firstPageIsPDF {
            let font = UIFont.systemFont(ofSize: w * 0.07, weight: .bold)
            let tag = NSAttributedString(string: "PDF", attributes: [.font: font, .kern: w * 0.006, .foregroundColor: UIColor(hex: 0xF7F1E3)])
            let size = tag.size()
            let box = CGRect(x: w * 0.93 - size.width - w * 0.05, y: bounds.height * 0.95 - size.height - w * 0.02,
                             width: size.width + w * 0.05, height: size.height + w * 0.02)
            ctx.setFillColor(UIColor(hex: 0x1B2230).cgColor)
            ctx.addPath(UIBezierPath(roundedRect: box, cornerRadius: w * 0.02).cgPath)
            ctx.fillPath()
            UIGraphicsPushContext(ctx)
            tag.draw(at: CGPoint(x: box.minX + w * 0.025, y: box.minY + w * 0.01))
            UIGraphicsPopContext()
        }
    }

    // MARK: Text helpers

    private static func paragraph(lineHeight multiple: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = multiple
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private static func smallCaps(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let features: [[UIFontDescriptor.FeatureKey: Int]] = [
            [.type: kUpperCaseType, .selector: kUpperCaseSmallCapsSelector],
            [.type: kNumberSpacingType, .selector: kMonospacedNumbersSelector],
        ]
        return UIFont(descriptor: base.fontDescriptor.addingAttributes([.featureSettings: features]), size: size)
    }
}

/// Deterministic generator seeded from a notebook's ID and its cover seed, so a cover never changes on its own.
struct CoverRNG: RandomNumberGenerator {
    private var state: UInt64

    init(id: UUID, seed: UInt32) {
        let bytes = id.uuid
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7,
                     bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15] {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        state = hash ^ (UInt64(seed) << 17)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Covers rendered once per request, kept in a bounded in-memory LRU and on disk in Caches.
final class CoverCache: Sendable {
    static let shared = CoverCache()

    private struct Memory {
        var images: [String: UIImage] = [:]
        var order: [String] = []
        var cost = 0
    }

    private let memory = OSAllocatedUnfairLock(initialState: Memory())
    private let limit = 80 * 1_048_576
    private let directory = URL.cachesDirectory.appending(path: "Covers", directoryHint: .isDirectory)
    private let signposter = OSSignposter(subsystem: "com.owais.NotesApp", category: "covers")

    func cached(_ key: String) -> UIImage? {
        memory.withLock { state in
            guard let image = state.images[key] else { return nil }
            if let index = state.order.lastIndex(of: key) { state.order.remove(at: index) }
            state.order.append(key)
            return image
        }
    }

    func image(for request: CoverRequest) async -> UIImage {
        let key = request.key
        if let image = cached(key) { return image }
        let directory = directory
        let signposter = signposter
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage in
            let file = directory.appending(path: "\(key).png")
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data, scale: request.scale) {
                return image
            }
            let interval = signposter.beginInterval("Cover render")
            var firstPage: CGImage?
            if let url = request.firstPage, let data = try? Data(contentsOf: url) {
                firstPage = UIImage(data: data)?.cgImage
            }
            let image = CoverRenderer.render(request, firstPage: firstPage)
            signposter.endInterval("Cover render", interval)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let png = image.pngData() { try? png.write(to: file, options: .atomic) }
            return image
        }.value
        store(image, key: key)
        return image
    }

    private func store(_ image: UIImage, key: String) {
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        memory.withLock { state in
            if state.images[key] == nil { state.cost += cost }
            state.images[key] = image
            state.order.removeAll { $0 == key }
            state.order.append(key)
            while state.cost > limit, let oldest = state.order.first {
                state.order.removeFirst()
                if let evicted = state.images.removeValue(forKey: oldest) {
                    state.cost -= Int(evicted.size.width * evicted.scale * evicted.size.height * evicted.scale * 4)
                }
            }
        }
    }

    func removeAll() {
        memory.withLock { $0 = Memory() }
        try? FileManager.default.removeItem(at: directory)
    }
}
