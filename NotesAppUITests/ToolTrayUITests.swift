import XCTest

/// The favourite tools beside the page: a saved tool is taken up with one tap, and the tool in use can be saved.
@MainActor
final class ToolTrayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func strokeCount(_ canvas: XCUIElement) -> Int {
        Int(((canvas.value as? String) ?? "").split(separator: " ").first ?? "") ?? 0
    }

    func testASavedToolIsTakenUpWithOneTapAndTheToolInUseCanBeSaved() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "tools", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput", "-freshToolPresets"]
        app.launch()
        let notebook = app.buttons["notebook.Studio Notes 2"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20))

        // The shelf starts with the app's own four inks; the pen the picker starts with is none of them.
        let cobalt = app.buttons["editor.tools.2"], highlighter = app.buttons["editor.tools.4"], save = app.buttons["editor.tools.save"]
        XCTAssertTrue(cobalt.waitForExistence(timeout: 10), "the favourite tools stand beside the page")
        XCTAssertEqual(cobalt.label, "Pen, Blue")
        XCTAssertEqual(highlighter.label, "Highlighter, Yellow")
        XCTAssertFalse(app.buttons["editor.tools.5"].exists)
        attach(app, "tray")

        cobalt.tap()
        wait(for: [expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: cobalt)], timeout: 5)
        XCTAssertFalse(save.isEnabled, "a tool that is already kept can't be saved again")
        highlighter.tap()
        wait(for: [expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: highlighter)], timeout: 5)
        XCTAssertFalse(cobalt.isSelected)
        attach(app, "tray-highlighter")
        try audit(app, screen: "favourite tools")

        // Writing with it still works, and the page keeps the stroke.
        let canvas = app.element("page.canvas.1")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3)), withVelocity: 400, thenHoldForDuration: 0.05)
        XCTAssertEqual(strokeCount(canvas), 1)
        attach(app, "tray-written")

        // Taken off the shelf, the highlighter is still the tool in use, so it can be saved again.
        highlighter.press(forDuration: 1.0)
        let remove = app.buttons["Remove"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()
        XCTAssertTrue(highlighter.waitForNonExistence(timeout: 10))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(highlighter.waitForExistence(timeout: 5), "saved, it is back at the end of the shelf")
        XCTAssertEqual(highlighter.label, "Highlighter, Yellow")
        XCTAssertTrue(highlighter.isSelected)

        // The tray can be put away from the More menu, and the page takes the room.
        app.buttons["More"].firstMatch.tap()
        app.buttons["Favourite Tools"].firstMatch.tap()
        XCTAssertTrue(cobalt.waitForNonExistence(timeout: 5))
        attach(app, "tray-hidden")
        app.buttons["More"].firstMatch.tap()
        app.buttons["Favourite Tools"].firstMatch.tap()
        XCTAssertTrue(cobalt.waitForExistence(timeout: 5))
        // The picker remembers its tool between launches: leave it with a pen for whatever runs next.
        app.buttons["editor.tools.1"].tap()
    }
}
