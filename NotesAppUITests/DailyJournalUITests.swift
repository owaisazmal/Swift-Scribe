import XCTest

@MainActor
final class DailyJournalUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "journal", "-drawingInput", "anyInput"] + arguments
        app.launch()
        return app
    }

    func testTodaysPage() {
        let app = launch(["-resetStorage", "-seedLibrary", "2"])
        let start = app.buttons["Start a daily journal"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        start.tap()
        let ribbon = app.buttons["editor.ribbon"]
        XCTAssertTrue(ribbon.waitForExistence(timeout: 20))
        XCTAssertEqual(ribbon.label, "Page 1 of 1")
        let canvas = app.descendants(matching: .any)["page.canvas.1"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertNotEqual(canvas.label, "Page 1, handwriting", "the canvas reads the page's date")

        app.buttons["editor.back"].tap()
        let today = app.buttons["desk.today"]
        XCTAssertTrue(today.waitForExistence(timeout: 20))
        XCTAssertTrue(today.label.hasPrefix("Today's page in Journal"), today.label)
        today.tap()
        XCTAssertTrue(ribbon.waitForExistence(timeout: 20))
        XCTAssertEqual(ribbon.label, "Page 1 of 1", "the same page, not another")
    }

    func testReopensWhereYouLeftOff() {
        var app = launch(["-resetStorage", "-seedLibrary", "2"])
        let notebook = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notebook.")).firstMatch
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()

        app = launch([])
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20), "the notebook reopens at its page")
    }
}
