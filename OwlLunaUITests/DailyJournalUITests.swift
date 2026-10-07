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

    func testTodaysEventsArePrintedOnTheDaysPage() {
        let app = launch(["-resetStorage", "-seedLibrary", "2", "-fakeCalendar", "-journalAgenda", "YES"])
        let start = app.buttons["Start a daily journal"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        start.tap()
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20))
        let printed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Lecture: Cell Biology'")).firstMatch
        XCTAssertTrue(printed.waitForExistence(timeout: 10), "the new day's page starts with the day's events")
        XCTAssertTrue(printed.label.hasPrefix("All day  Library books due"), printed.label)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "journal-agenda"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["editor.back"].tap()
        let notebook = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notebook.' AND NOT identifier CONTAINS 'Journal'")).firstMatch
        XCTAssertTrue(notebook.waitForExistence(timeout: 20))
        notebook.tap()
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20))
        app.buttons["Add"].firstMatch.tap()
        app.buttons["Today's Events"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editor.arrange.bar"].waitForExistence(timeout: 10), "on any other page they are added by hand, and selected")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Lab group'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testReopensWhereYouLeftOff() {
        var app = launch(["-resetStorage", "-seedLibrary", "2"])
        let notebook = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notebook.")).firstMatch
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)
        // Stopped straight away, before iPadOS has saved the window's own state.
        app.terminate()

        app = launch([])
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20), "the notebook reopens at its page")
    }
}
