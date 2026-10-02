import XCTest
@testable import NotesApp

/// Where the page is put on a second screen while presenting.
final class SecondScreenTests: XCTestCase {
    private let letter = CGSize(width: 612, height: 792)
    private let screen = CGSize(width: 1920, height: 1080)
    private let whole = CGRect(x: 0, y: 0, width: 1, height: 1)

    func testAWholePageIsCentredAndFillsTheHeight() {
        let frame = PresentationStage.pageFrame(pageSize: letter, viewport: whole, in: screen)
        XCTAssertEqual(frame.height, 1080, accuracy: 0.01)
        XCTAssertEqual(frame.midX, 960, accuracy: 0.01)
        XCTAssertEqual(frame.width / frame.height, 612.0 / 792, accuracy: 0.0001)

        let slide = PresentationStage.pageFrame(pageSize: CGSize(width: 960, height: 540), viewport: whole, in: screen)
        XCTAssertEqual(slide, CGRect(x: 0, y: 0, width: 1920, height: 1080), "a widescreen page fills a widescreen display")
    }

    func testTheZoomedPartFillsTheScreen() {
        let quarter = CGRect(x: 0.5, y: 0.25, width: 0.5, height: 0.25)
        let frame = PresentationStage.pageFrame(pageSize: letter, viewport: quarter, in: screen)
        let shown = CGRect(x: frame.minX + quarter.minX * frame.width, y: frame.minY + quarter.minY * frame.height,
                           width: quarter.width * frame.width, height: quarter.height * frame.height)
        XCTAssertEqual(shown.midX, 960, accuracy: 0.01, "what the iPad is looking at sits in the middle")
        XCTAssertEqual(shown.midY, 540, accuracy: 0.01)
        XCTAssertEqual(shown.height, 1080, accuracy: 0.01, "and is as large as fits")
        XCTAssertLessThanOrEqual(shown.width, 1920)
        XCTAssertEqual(PresentationStage.pageFrame(pageSize: letter, viewport: .zero, in: screen),
                       PresentationStage.pageFrame(pageSize: letter, viewport: whole, in: screen), "nothing sensible to zoom to shows the whole page")
        XCTAssertEqual(PresentationStage.pageFrame(pageSize: .zero, viewport: whole, in: screen), .zero)
    }

    func testThePageIsRenderedSharpEnoughToZoomWithoutRunningAway() {
        let width = PresentationStage.renderWidth(pageSize: letter, pixels: screen)
        XCTAssertEqual(width, (612 * 1080 / 792 * 2).rounded(), "twice what fits on a 1080p screen")
        let huge = PresentationStage.renderWidth(pageSize: letter, pixels: CGSize(width: 7680, height: 4320))
        XCTAssertLessThanOrEqual(huge * huge * 792 / 612, 12_000_001, "an 8K screen doesn't ask for more than twelve megapixels")
    }
}
