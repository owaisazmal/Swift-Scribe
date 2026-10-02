import XCTest
import PencilKit
@testable import NotesApp

/// Study tape over the ink, and handwriting read as text.
@MainActor
final class StudyTests: XCTestCase {
    private let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)

    private func pixel(_ image: UIImage, at point: CGPoint) throws -> (r: Int, g: Int, b: Int) {
        let cgImage = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: -point.x, y: point.y - CGFloat(cgImage.height) + 1, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    func testTapeIsKeptInTheManifestAndANewerColourIsLeftAlone() throws {
        var page = paper.newPage()
        let tape = PageItem(content: .tape(.sage), center: CGPoint(x: 200, y: 100), size: TapeArt.defaultSize, rotation: 0.1)
        let future: JSONValue = .object(["id": .string(UUID().uuidString), "kind": .string("tape"), "tint": .string("holographic"),
                                         "x": .number(10), "y": .number(20), "w": .number(100), "h": .number(30)])
        page.items = [tape]
        page.extra["items"] = .array((page.extra["items"]?.arrayValue ?? []) + [future])

        let decoded = try XCTUnwrap(ManifestCodec.decodePage(ManifestCodec.encodePage(page)))
        XCTAssertEqual(decoded.items.map(\.content), [.tape(.sage), .unknown])
        XCTAssertTrue(decoded.items[0].isOverInk)
        XCTAssertFalse(PageItem(content: .sticker("star"), center: .zero, size: CGSize(width: 40, height: 40)).isOverInk)
        XCTAssertEqual(decoded.items[1].json["tint"], .string("holographic"), "a colour this version doesn't know is written back as it was read")
        XCTAssertEqual(decoded.typedText, "", "tape has no words to search for")
    }

    func testTapeCoversTheInkUntilItIsLifted() throws {
        var page = paper.newPage()
        let tape = PageItem(content: .tape(.mustard), center: CGPoint(x: 200, y: 200), size: CGSize(width: 240, height: 40))
        let sticker = PageItem(content: .sticker("noteYellow"), center: CGPoint(x: 200, y: 400), size: CGSize(width: 120, height: 120))
        page.items = [tape, sticker]
        let ink = PKDrawing(strokes: [stroke(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 200), width: 8),
                                      stroke(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 400), width: 8)])
        let assets = FileManager.default.temporaryDirectory

        let covered = PageRenderer.image(of: page, ink: ink, assets: assets, width: page.size.width)
        let onTape = try pixel(covered, at: CGPoint(x: 150, y: 200))
        XCTAssertGreaterThan(onTape.r, 150, "the tape is drawn over the ink")
        XCTAssertLessThan(try pixel(covered, at: CGPoint(x: 200, y: 400)).r, 90, "ink still goes over a sticker")

        let lifted = PageRenderer.image(of: page, ink: ink, assets: assets, width: page.size.width, lifted: [tape.id])
        XCTAssertLessThan(try pixel(lifted, at: CGPoint(x: 150, y: 200)).r, 90, "lifted, the ink under it shows")
    }

    func testHandwritingIsReadAsText() throws {
        let ink = PKDrawing(strokes: BlockLetters.strokes("HELLO", origin: CGPoint(x: 120, y: 140)))
        let image = try XCTUnwrap(InkText.image(of: ink))
        XCTAssertGreaterThan(image.size.width, ink.bounds.width, "there is room round the ink")
        guard let text = InkText.recognize([ink]) else { throw XCTSkip("Vision's text recogniser isn't available here") }
        XCTAssertTrue(text.uppercased().contains("HELLO"), "read as \(text)")
        XCTAssertEqual(InkText.recognize([]), "")
        XCTAssertNil(InkText.image(of: PKDrawing()))
    }

    func testTheTextBoxTakesThePlaceOfTheHandwriting() {
        let page = PageSize.letter.points
        let item = InkText.box(for: "Hello there", replacing: CGRect(x: 120, y: 140, width: 260, height: 48), pageSize: page)
        XCTAssertEqual(item.text?.string, "Hello there")
        XCTAssertEqual(item.center.x - item.size.width / 2, 120, accuracy: 0.5, "it starts where the ink started")
        XCTAssertEqual(item.center.y - item.size.height / 2, 140, accuracy: 0.5)
        XCTAssertEqual(item.text?.fontSize ?? 0, 30, accuracy: 0.5, "about as tall as the writing was")

        let edge = InkText.box(for: String(repeating: "word ", count: 60), replacing: CGRect(x: 560, y: 770, width: 400, height: 500), pageSize: page)
        let box = CGRect(x: edge.center.x - edge.size.width / 2, y: edge.center.y - edge.size.height / 2, width: edge.size.width, height: edge.size.height)
        XCTAssertGreaterThanOrEqual(box.minX, 12)
        XCTAssertLessThanOrEqual(box.maxX, page.width - 12 + 0.5, "a long line wraps inside the page")
        XCTAssertEqual(edge.text?.fontSize, 34, "tall ink doesn't make giant type")
        XCTAssertEqual(InkText.box(for: "a\nb\nc\nd", replacing: CGRect(x: 0, y: 0, width: 100, height: 40), pageSize: page).text?.fontSize, 13)
    }
}
