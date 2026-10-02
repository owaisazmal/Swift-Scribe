import UIKit
import Vision
import CoreImage

/// Turns a photo into a sticker: the subject lifted off its background, with the white edge of a die-cut. Thread-safe.
enum StickerCutout {
    enum Failure: LocalizedError {
        case noSubject, unreadable

        var errorDescription: String? {
            switch self {
            case .noSubject: String(localized: "Swift Scribe couldn't find a clear subject in this photo.")
            case .unreadable: String(localized: "This photo couldn't be read.")
            }
        }
    }

    static let longSide: CGFloat = 900
    private static let context = CIContext()

    /// The photo's subject as a PNG. Throws `noSubject` when there is nothing to lift, or where Vision can't run.
    static func sticker(from photo: UIImage) throws -> Data {
        let upright = try flattened(photo, longSide: 2400)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: upright)
        do { try handler.perform([request]) } catch { throw Failure.noSubject }
        guard let result = request.results?.first, !result.allInstances.isEmpty,
              let buffer = try? result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true) else {
            throw Failure.noSubject
        }
        return try png(dieCut(CIImage(cvPixelBuffer: buffer)))
    }

    /// The whole photo with rounded corners and a white edge, for a photo with no subject to lift.
    static func wholePhoto(_ photo: UIImage) throws -> Data {
        let upright = try flattened(photo, longSide: longSide)
        let size = CGSize(width: upright.width, height: upright.height)
        let edge = (max(size.width, size.height) * 0.03).rounded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let canvas = CGSize(width: size.width + edge * 2, height: size.height + edge * 2)
        return UIGraphicsImageRenderer(size: canvas, format: format).pngData { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: edge * 2).fill()
            let inner = CGRect(x: edge, y: edge, width: size.width, height: size.height)
            UIBezierPath(roundedRect: inner, cornerRadius: edge).addClip()
            UIImage(cgImage: upright).draw(in: inner)
        }
    }

    /// Grows the cut-out's shape outwards in white and sets the cut-out on top.
    static func dieCut(_ cutout: CIImage) -> CIImage {
        let scale = min(1, longSide / max(cutout.extent.width, cutout.extent.height, 1))
        let subject = cutout.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let edge = max(5, (max(subject.extent.width, subject.extent.height) * 0.022).rounded())
        let frame = subject.extent.insetBy(dx: -edge - 2, dy: -edge - 2).integral
        let white = subject.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ])
        let padded = white.composited(over: CIImage(color: .clear).cropped(to: frame))
        let grown = padded.applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": edge]).cropped(to: frame)
        return subject.composited(over: grown).cropped(to: frame)
    }

    static func png(_ image: CIImage) throws -> Data {
        guard let cg = context.createCGImage(image, from: image.extent), let data = UIImage(cgImage: cg).pngData() else { throw Failure.unreadable }
        return data
    }

    /// Upright pixels at most `longSide` across.
    private static func flattened(_ photo: UIImage, longSide: CGFloat) throws -> CGImage {
        let pixels = CGSize(width: photo.size.width * photo.scale, height: photo.size.height * photo.scale)
        guard pixels.width > 0, pixels.height > 0 else { throw Failure.unreadable }
        let scale = min(1, longSide / max(pixels.width, pixels.height))
        let target = CGSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: target, format: format).image { _ in photo.draw(in: CGRect(origin: .zero, size: target)) }
        guard let cg = image.cgImage else { throw Failure.unreadable }
        return cg
    }
}

/// A sticker the user made. They are kept beside the library, not in a notebook, so every notebook can use them.
struct CustomSticker: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
}

enum StickerShelf {
    /// Newest first.
    static func list(_ root: StorageRoot) -> [CustomSticker] {
        let files = (try? FileManager.default.contentsOfDirectory(at: root.stickers, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let dated: [(url: URL, made: Date)] = files.filter { $0.pathExtension == "png" }.map { url in
            (url, (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }
        let sorted = dated.sorted { a, b in
            a.made == b.made ? a.url.lastPathComponent > b.url.lastPathComponent : a.made > b.made
        }
        return sorted.map { CustomSticker(id: $0.url.deletingPathExtension().lastPathComponent, url: $0.url) }
    }

    @discardableResult
    static func add(_ png: Data, to root: StorageRoot) throws -> CustomSticker {
        try FileManager.default.createDirectory(at: root.stickers, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let url = root.stickers.appending(path: "\(id).png")
        try png.write(to: url, options: .atomic)
        return CustomSticker(id: id, url: url)
    }

    /// Pages that already carry the sticker keep their own copy.
    static func remove(_ sticker: CustomSticker) {
        try? FileManager.default.removeItem(at: sticker.url)
    }
}
