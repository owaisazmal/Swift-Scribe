import XCTest
import PencilKit
@testable import OwlLuna

/// Pictures and stickers on a page: the manifest, undo, hit testing and rendering.
@MainActor
final class PageItemTests: XCTestCase {
    private let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)

    private func makeDocument() async throws -> NotebookDocument {
        let root = temporaryRoot(self)
        let manifest = NotebookManifest(title: "Scrapbook", defaults: paper, pages: [paper.newPage(), paper.newPage()])
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        return try await NotebookDocument.open(manifest.id, root: root)
    }

    func testItemsSurviveTheManifestWithKeysTheyDoNotKnow() throws {
        var page = paper.newPage()
        XCTAssertFalse(page.hasItems)
        let star = PageItem(content: .sticker("star"), center: CGPoint(x: 100, y: 120), size: CGSize(width: 64, height: 64), rotation: 0.4)
        let photo = PageItem(content: .image(file: "a.jpg"), center: CGPoint(x: 300, y: 400), size: CGSize(width: 200, height: 150))
        page.items = [star, photo]
        let future: JSONValue = .object(["id": .string(UUID().uuidString), "kind": .string("hologram"), "x": .number(1), "y": .number(2),
                                         "w": .number(3), "h": .number(4), "depth": .number(9)])
        let broken: JSONValue = .object(["kind": .string("sticker")])
        page.extra["items"] = .array((page.extra["items"]?.arrayValue ?? []) + [future, broken])

        let decoded = try XCTUnwrap(ManifestCodec.decodePage(ManifestCodec.encodePage(page)))
        XCTAssertEqual(decoded.items.map(\.content), [.sticker("star"), .image(file: "a.jpg"), .unknown])
        XCTAssertEqual(decoded.items[0].rotation, 0.4, accuracy: 0.0001)
        XCTAssertEqual(decoded.items[2].json["depth"], .number(9), "a newer kind keeps its own keys")

        var edited = decoded
        edited.items = [decoded.items[1]]
        XCTAssertEqual(edited.extra["items"]?.arrayValue?.count, 2, "the entry that couldn't be read is never dropped")
        edited.items = []
        XCTAssertEqual(edited.extra["items"]?.arrayValue, [broken])
        page.extra["items"] = nil
        page.items = [star]
        page.items = []
        XCTAssertFalse(page.hasItems)
    }

    func testAppearanceKeyFollowsTheItems() {
        var page = paper.newPage()
        let plain = page.appearanceKey
        page.items = [PageItem(content: .sticker("heart"), center: CGPoint(x: 50, y: 50), size: CGSize(width: 64, height: 64))]
        let withHeart = page.appearanceKey
        XCTAssertNotEqual(withHeart, plain, "a thumbnail made before the sticker isn't served after it")
        page.items[0].center.x = 90
        XCTAssertNotEqual(page.appearanceKey, withHeart)
    }

    func testHitTestingAllowsForRotation() {
        var item = PageItem(content: .sticker("tapeTeal"), center: CGPoint(x: 200, y: 200), size: CGSize(width: 200, height: 40))
        XCTAssertTrue(item.contains(CGPoint(x: 290, y: 210)))
        XCTAssertFalse(item.contains(CGPoint(x: 200, y: 290)))
        item.rotation = .pi / 2
        XCTAssertTrue(item.contains(CGPoint(x: 200, y: 290)), "turned a quarter, it's tall")
        XCTAssertFalse(item.contains(CGPoint(x: 290, y: 210)))
    }

    func testScalingKeepsItGrabbableAndOnThePage() {
        let item = PageItem(content: .sticker("star"), center: .zero, size: CGSize(width: 100, height: 50))
        XCTAssertEqual(item.scaled(by: 0.01, limit: 1000).size, CGSize(width: 48, height: 24))
        XCTAssertEqual(item.scaled(by: 100, limit: 1000).size, CGSize(width: 1000, height: 500))
        XCTAssertEqual(item.scaled(by: 2, limit: 1000).size, CGSize(width: 200, height: 100))
        XCTAssertEqual(ItemSelectionView.snapped(.pi / 2 + 0.03), .pi / 2)
        XCTAssertEqual(ItemSelectionView.snapped(0.2), 0.2)
    }

    func testArrangingIsUndoableAndSaved() async throws {
        let document = try await makeDocument()
        let page = document.pages[0].id
        document.undoManager.groupsByEvent = false
        func step(_ name: String, _ change: (inout [PageItem]) -> Void) {
            document.undoManager.beginUndoGrouping()
            document.updateItems(onPage: page, actionName: name, change)
            document.undoManager.endUndoGrouping()
        }
        let star = PageItem(content: .sticker("star"), center: CGPoint(x: 100, y: 100), size: CGSize(width: 64, height: 64))
        step("Add to Page") { $0.append(star) }
        step("Arrange") { $0[0].center = CGPoint(x: 300, y: 300) }
        XCTAssertEqual(document.pages[0].items.first?.center, CGPoint(x: 300, y: 300))
        document.updateItems(onPage: page, actionName: "Arrange") { _ in }
        XCTAssertEqual(document.undoManager.undoActionName, "Arrange", "a change that changes nothing registers nothing")
        document.undoManager.undo()
        XCTAssertEqual(document.pages[0].items.first?.center, CGPoint(x: 100, y: 100))
        document.undoManager.undo()
        XCTAssertTrue(document.pages[0].items.isEmpty)
        document.undoManager.redo()
        document.undoManager.redo()
        let saved = await document.flush()
        XCTAssertTrue(saved)
        let reopened = try await document.package.readManifest().manifest
        XCTAssertEqual(reopened.pages[0].items.map(\.center), [CGPoint(x: 300, y: 300)])
        XCTAssertTrue(reopened.pages[1].items.isEmpty)
    }

    func testAPlacedPictureIsKeptWhenFilesAreTidied() async throws {
        let document = try await makeDocument()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 10))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 10, width: 40, height: 10))
        }
        let kept = try await document.package.writeAsset(png, ext: "png")
        let dropped = try await document.package.writeAsset(png, ext: "png")
        document.updateItems(onPage: document.pages[0].id, actionName: "Add to Page") {
            $0.append(PageItem(content: .image(file: kept), center: CGPoint(x: 306, y: 396), size: CGSize(width: 200, height: 100)))
        }
        let saved = await document.flush()
        XCTAssertTrue(saved)
        await document.collectGarbage()
        XCTAssertTrue(FileManager.default.fileExists(atPath: document.package.assetURL(kept).path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: document.package.assetURL(dropped).path(percentEncoded: false)))

        let image = PageRenderer.image(of: document.pages[0], ink: PKDrawing(), assets: document.package.assetsDirectory, width: 612)
        XCTAssertEqual(pixel(of: image, at: CGPoint(x: 306, y: 370)), [255, 0, 0], "the picture is drawn into thumbnails and exports, the right way up")
        XCTAssertEqual(pixel(of: image, at: CGPoint(x: 306, y: 420)), [0, 0, 255])
        XCTAssertEqual(pixel(of: image, at: CGPoint(x: 306, y: 200)), [255, 255, 255])
    }

    func testAPictureIsStoredSmallerAndPlacedToFitThePage() async throws {
        let document = try await makeDocument()
        let session = EditorSession(document: document)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1000), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1000))
        }
        try await session.addPicture(photo)
        let item = try XCTUnwrap(document.pages[0].items.first)
        XCTAssertEqual(item.size, CGSize(width: 337, height: 112), "55% of a Letter page's width")
        XCTAssertEqual(item.center, CGPoint(x: 306, y: 396))
        let file = try XCTUnwrap(item.assetFile)
        XCTAssertTrue(file.hasSuffix(".jpg"), "no transparency, so a JPEG")
        XCTAssertEqual(UIImage(contentsOfFile: document.package.assetURL(file).path(percentEncoded: false))?.size.width, 1600)

        format.opaque = false
        let cutout = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { context in
            UIColor.red.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        try await session.addPicture(cutout)
        XCTAssertEqual(document.pages[0].items.count, 2)
        XCTAssertTrue(document.pages[0].items[1].assetFile?.hasSuffix(".png") ?? false, "transparency is kept")
        XCTAssertNotEqual(document.pages[0].items[1].center, item.center, "the second doesn't hide the first")
    }

    func testEveryStickerDrawsInsideItsBox() {
        for sticker in Sticker.allCases {
            XCTAssertFalse(sticker.displayName.isEmpty)
            XCTAssertEqual(sticker.defaultSize.width / sticker.defaultSize.height, sticker.aspect, accuracy: 0.03, sticker.rawValue)
            let image = sticker.image(width: 100, scale: 1)
            guard let data = image.cgImage?.dataProvider?.data as Data?, let cg = image.cgImage else { return XCTFail(sticker.rawValue) }
            var painted = 0
            for offset in stride(from: 0, to: data.count, by: cg.bitsPerPixel / 8) where data[offset + 3] > 40 { painted += 1 }
            XCTAssertGreaterThan(painted, 150, "\(sticker.rawValue) draws something")
        }
        XCTAssertEqual(Set(Sticker.Family.allCases.flatMap(\.stickers)).count, Sticker.allCases.count, "every sticker is in a family")
    }

    private func pixel(of image: UIImage, at point: CGPoint) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: -point.x, y: point.y - image.size.height + 1)
        context.draw(image.cgImage!, in: CGRect(origin: .zero, size: image.size))
        return Array(bytes.prefix(3))
    }
}
