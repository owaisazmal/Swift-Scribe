import XCTest

/// The shelves and the desk cards fill the room beside the sidebar, and all of it once the sidebar is hidden.
@MainActor
final class ShelfWidthUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Where the shelves start and how many covers a row holds, once both the covers and the cards reach the trailing margin.
    private func fit(_ app: XCUIApplication, _ step: String, line: UInt = #line) -> (leading: CGFloat, columns: Int) {
        let trailing = app.windows.firstMatch.frame.maxX - 32
        let covers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notebook.'")).allElementsBoundByIndex.map(\.frame)
        let leading = covers.map(\.minX).min() ?? 0
        XCTAssertEqual(covers.map(\.maxX).max() ?? 0, trailing, accuracy: 6, "a full row of covers, \(step)", line: line)
        XCTAssertEqual(app.buttons["desk.today"].frame.minX, leading, accuracy: 1, "today's card, \(step)", line: line)
        XCTAssertEqual(app.buttons["desk.onThisDay"].frame.maxX, trailing, accuracy: 1, "the On This Day card, \(step)", line: line)
        return (leading, Set(covers.map { Int($0.minX) }).count)
    }

    private func toggleSidebar(_ app: XCUIApplication, _ label: String, line: UInt = #line) {
        let button = app.buttons.matching(identifier: "ToggleSidebar").allElementsBoundByIndex.first { $0.isHittable && $0.label == label }
        XCTAssertNotNil(button, label, line: line)
        button?.tap()
        sleep(2)
    }

    func testShelvesFillTheWidthAsTheSidebarHidesAndShows() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "shelfwidth", "-resetStorage", "-seedLibrary", "12", "-seedJournal", "-indexSeed", "-seedActivity",
                               "-drawingInput", "anyInput", "-librarySort", "title"]
        app.launch()
        XCTAssertTrue(app.buttons["notebook.Cell Biology 1"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["desk.onThisDay"].waitForExistence(timeout: 10))
        sleep(1)

        let beside = fit(app, "landscape, sidebar beside")
        XCTAssertGreaterThan(beside.leading, 200, "the sidebar stands beside the shelves in landscape")
        toggleSidebar(app, "Hide Sidebar")
        let hidden = fit(app, "landscape, sidebar hidden")
        XCTAssertEqual(hidden.leading, 32, accuracy: 1)
        XCTAssertGreaterThan(hidden.columns, beside.columns, "the wider shelf holds more covers a row")
        toggleSidebar(app, "Show Sidebar")
        let again = fit(app, "landscape, sidebar shown again")
        XCTAssertEqual(again.leading, beside.leading, accuracy: 1)
        XCTAssertEqual(again.columns, beside.columns)

        toggleSidebar(app, "Hide Sidebar")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        let portrait = fit(app, "portrait, sidebar hidden")
        XCTAssertEqual(portrait.leading, 32, accuracy: 1)
        XCTAssertLessThan(portrait.columns, hidden.columns)
        toggleSidebar(app, "Show Sidebar")
        _ = fit(app, "portrait, sidebar shown")
        toggleSidebar(app, "Hide Sidebar")
        XCTAssertEqual(fit(app, "portrait, sidebar hidden again").columns, portrait.columns)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertEqual(fit(app, "back in landscape").columns, hidden.columns)
    }
}
