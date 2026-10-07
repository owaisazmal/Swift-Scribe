import XCTest
@testable import OwlLuna

/// The zoom window's geometry: where it sits on the page and how it moves along a line and down to the next.
final class ZoomWindowTests: XCTestCase {
    private let page = CGSize(width: 600, height: 800)

    private func window(at center: CGPoint = CGPoint(x: 300, y: 400), size: CGSize = CGSize(width: 240, height: 60), lineHeight: CGFloat = 28) -> ZoomWindow {
        ZoomWindow(pageID: UUID(), pageSize: page, center: center, size: size, lineHeight: lineHeight)
    }

    func testItStaysOnThePage() {
        XCTAssertEqual(window().rect, CGRect(x: 180, y: 370, width: 240, height: 60))
        XCTAssertEqual(window(at: CGPoint(x: -50, y: 9000)).rect, CGRect(x: 0, y: 740, width: 240, height: 60), "placed past the edge, it is pulled back in")
        XCTAssertEqual(window(size: CGSize(width: 5000, height: 5000)).rect, CGRect(origin: .zero, size: page), "and it is never larger than the page")
        var moved = window()
        moved.move(to: CGPoint(x: 500, y: 100))
        XCTAssertEqual(moved.rect.origin, CGPoint(x: 360, y: 100))
        XCTAssertEqual(moved.lineStart, 360, "placed by hand, that is where its lines start")
    }

    func testItMovesAlongTheLineThenDownToTheNext() {
        var window = window(at: CGPoint(x: 120, y: 100))
        XCTAssertEqual(window.rect.minX, 0)
        XCTAssertTrue(window.advance())
        XCTAssertEqual(window.rect.minX, 132, "a little over half its width, so what was just written stays in view")
        XCTAssertEqual(window.rect.minY, 70)
        XCTAssertTrue(window.advance())
        XCTAssertTrue(window.advance())
        XCTAssertEqual(window.rect.maxX, 600, "it stops at the edge of the page")
        XCTAssertTrue(window.isAtLineEnd)
        XCTAssertTrue(window.advance())
        XCTAssertEqual(window.rect.origin, CGPoint(x: 0, y: 98), "and from there goes to the start of the next line")

        XCTAssertFalse(window.back(), "at the start of a line there is nowhere back to go")
        window.advance()
        XCTAssertTrue(window.back())
        XCTAssertEqual(window.rect.minX, 0)
    }

    func testItStopsAtTheFootOfThePage() {
        var window = window(at: CGPoint(x: 400, y: 770))
        XCTAssertTrue(window.isAtPageEnd)
        XCTAssertFalse(window.newLine(), "already on the last line and at its start")
        window.advance()
        XCTAssertTrue(window.isAtLineEnd)
        XCTAssertTrue(window.newLine(), "back to where the line started, though it can go no lower")
        XCTAssertEqual(window.rect.origin, CGPoint(x: 280, y: 740))
    }

    func testInkInTheBandOnTheRightMovesItOn() {
        let window = window()
        XCTAssertEqual(window.advanceBand.minX, 348, accuracy: 0.01)
        XCTAssertEqual(window.advanceBand.maxX, 420, accuracy: 0.01, "the last three tenths of the window")
        XCTAssertFalse(window.reachesAdvanceBand(CGRect(x: 200, y: 380, width: 100, height: 30)))
        XCTAssertTrue(window.reachesAdvanceBand(CGRect(x: 300, y: 380, width: 60, height: 30)))
        XCTAssertFalse(window.reachesAdvanceBand(CGRect(x: 360, y: 700, width: 20, height: 20)), "ink written elsewhere on the page doesn't count")
        XCTAssertFalse(window.reachesAdvanceBand(.null))
    }

    func testResizingKeepsItsCornerAndRuledPaperSetsTheLineHeight() {
        var window = window()
        window.resize(to: CGSize(width: 360, height: 90))
        XCTAssertEqual(window.rect, CGRect(x: 180, y: 370, width: 360, height: 90))
        window.resize(to: CGSize(width: 500, height: 90))
        XCTAssertEqual(window.rect.origin.x, 100, "pulled back when the new size would run off the page")
        window.fit(pageSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(window.rect, CGRect(x: 0, y: 210, width: 400, height: 90))

        let narrow = NotebookPage.template(.narrowRuled, color: .white, size: .letter), blank = NotebookPage.template(.blank, color: .white, size: .letter)
        XCTAssertEqual(ZoomWindow.lineHeight(for: narrow, windowHeight: 60), 28 * 612 / 800, accuracy: 0.01)
        XCTAssertEqual(ZoomWindow.lineHeight(for: blank, windowHeight: 60), 30)
    }
}
