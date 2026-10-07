import XCTest
import CoreImage
@testable import OwlLuna

/// Stickers of your own: the die-cut edge, the shelf they are kept on, and placing one in a notebook.
@MainActor
final class StickerCutoutTests: XCTestCase {
    private let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)

    private func disc(_ size: CGFloat = 200, opaque: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            if opaque {
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            }
            UIColor.red.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    private func pixel(of image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: CGFloat(-x), y: CGFloat(y - image.height + 1))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    func testADieCutPutsAWhiteEdgeRoundTheSubject() throws {
        let cutout = CIImage(cgImage: try XCTUnwrap(disc().cgImage))
        let data = try StickerCutout.png(StickerCutout.dieCut(cutout))
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, 214, "five points of edge and a little air on every side")
        XCTAssertEqual(image.height, 214)
        XCTAssertEqual(pixel(of: image, x: 107, y: 107), [255, 0, 0, 255], "the subject is untouched")
        XCTAssertEqual(pixel(of: image, x: 107, y: 4), [255, 255, 255, 255], "white just outside it")
        XCTAssertEqual(pixel(of: image, x: 2, y: 2)[3], 0, "and nothing in the corners")

        let big = StickerCutout.dieCut(CIImage(cgImage: try XCTUnwrap(disc(2000).cgImage)))
        XCTAssertLessThanOrEqual(max(big.extent.width, big.extent.height), StickerCutout.longSide + 60, "a large photo makes a sticker of a sensible size")
    }

    func testAPhotoWithNoSubjectCanBeKeptWhole() throws {
        let whole = try XCTUnwrap(UIImage(data: StickerCutout.wholePhoto(disc(300, opaque: true)))?.cgImage)
        XCTAssertEqual(whole.width, 318)
        XCTAssertEqual(pixel(of: whole, x: 159, y: 4), [255, 255, 255, 255], "a white edge")
        XCTAssertEqual(pixel(of: whole, x: 159, y: 159), [255, 0, 0, 255])
        XCTAssertEqual(pixel(of: whole, x: 0, y: 0)[3], 0, "with rounded corners")
    }

    func testTheSubjectIsLiftedWhereVisionCanRun() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400), format: format).image { context in
            UIColor(white: 0.92, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
            UIColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 200, y: 100, width: 200, height: 200))
        }
        do {
            let data = try StickerCutout.sticker(from: photo)
            let image = try XCTUnwrap(UIImage(data: data))
            XCTAssertLessThan(image.size.width, 600, "cropped to the subject")
        } catch StickerCutout.Failure.noSubject {
            throw XCTSkip("Vision found no subject here; the drawer offers the whole photo instead")
        }
    }

    func testTheShelfKeepsStickersNewestFirst() throws {
        let root = temporaryRoot(self)
        XCTAssertTrue(StickerShelf.list(root).isEmpty)
        let first = try StickerShelf.add(try XCTUnwrap(disc(40).pngData()), to: root)
        Thread.sleep(forTimeInterval: 0.05)
        let second = try StickerShelf.add(try XCTUnwrap(disc(60).pngData()), to: root)
        XCTAssertEqual(StickerShelf.list(root).map(\.id), [second.id, first.id])
        StickerShelf.remove(first)
        XCTAssertEqual(StickerShelf.list(root), [second])
    }

    func testPlacingAStickerTwiceKeepsOneCopyInTheNotebook() async throws {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Scrapbook", defaults: paper, pages: [paper.newPage(), paper.newPage()])
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        let session = EditorSession(document: document)
        let sticker = try StickerShelf.add(try XCTUnwrap(disc(400).pngData()), to: root)

        try await session.addSticker(sticker)
        session.go(to: 1)
        try await session.addSticker(sticker)
        let first = try XCTUnwrap(document.pages[0].items.first), second = try XCTUnwrap(document.pages[1].items.first)
        XCTAssertEqual(first.size, CGSize(width: 150, height: 150))
        XCTAssertEqual(first.source, sticker.id)
        XCTAssertTrue(first.assetFile?.hasSuffix(".png") ?? false, "the cut-out keeps its transparency")
        XCTAssertEqual(first.assetFile, second.assetFile, "the second placement reuses the first one's file")

        StickerShelf.remove(sticker)
        let saved = await document.flush()
        XCTAssertTrue(saved)
        await document.collectGarbage()
        let file = try XCTUnwrap(first.assetFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: document.package.assetURL(file).path(percentEncoded: false)), "deleting it from the shelf leaves pages alone")
        XCTAssertEqual(PageItem(json: first.json)?.source, sticker.id)
    }
}
