import XCTest

/// The tool tray at the foot of the editor: a pen is taken up with one tap and opened with a second, the eraser and
/// the lasso stand beside the pens, and the shortcuts are chosen from the tray's own menu.
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

    private func waitUntilSelected(_ element: XCUIElement) {
        wait(for: [expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: element)], timeout: 5)
    }

    func testThePensTheEraserAndTheShortcutsStandInTheTray() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "tools", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput", "-freshToolPresets"]
        app.launch()
        let notebook = app.buttons["notebook.Studio Notes 2"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20))

        // The tray starts with the app's own four inks, the first of them in hand.
        let black = app.buttons["editor.tools.1"], cobalt = app.buttons["editor.tools.2"], highlighter = app.buttons["editor.tools.4"]
        let eraser = app.buttons["editor.tools.eraser"], lasso = app.buttons["editor.tools.lasso"], add = app.buttons["editor.tools.add"]
        XCTAssertTrue(cobalt.waitForExistence(timeout: 10), "the pens are in the tray")
        XCTAssertTrue(black.isSelected)
        XCTAssertEqual(cobalt.label, "Pen, Blue")
        XCTAssertEqual(highlighter.label, "Highlighter, Mustard")
        XCTAssertFalse(app.buttons["editor.tools.5"].exists)
        // It takes nothing from the page's width, and is one slim board at the foot of the window.
        let canvas = app.element("page.canvas.1"), window = app.windows.firstMatch, tray = app.element("editor.tools.tray")
        XCTAssertEqual(canvas.frame.midX, window.frame.midX, accuracy: 1)
        XCTAssertEqual(tray.frame.midX, window.frame.midX, accuracy: 1)
        XCTAssertLessThanOrEqual(tray.frame.height, 50)
        XCTAssertGreaterThan(tray.frame.minY, window.frame.maxY - 90)
        XCTAssertTrue(app.buttons["editor.tools.extra.picture"].isHittable, "a picture is one tap away")
        XCTAssertTrue(app.buttons["editor.tools.extra.text"].isHittable)
        attach(app, "tray")

        cobalt.tap()
        waitUntilSelected(cobalt)
        XCTAssertFalse(black.isSelected)
        highlighter.tap()
        waitUntilSelected(highlighter)
        try audit(app, screen: "tool tray", bar: tray)

        // Writing with it works, and the eraser takes the stroke off again.
        let left = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)), right = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3))
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: 400, thenHoldForDuration: 0.05)
        XCTAssertEqual(strokeCount(canvas), 1)
        eraser.tap()
        waitUntilSelected(eraser)
        XCTAssertEqual(eraser.value as? String, "Whole Strokes")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)), withVelocity: 400, thenHoldForDuration: 0.05)
        wait(for: [expectation(for: NSPredicate(format: "value == 'Empty'"), evaluatedWith: canvas)], timeout: 5)

        // Tapped again, the eraser opens: it can take part of a stroke, as wide as it is set.
        eraser.tap()
        let part = app.buttons["Part of a Stroke"]
        XCTAssertTrue(part.waitForExistence(timeout: 5))
        part.tap()
        XCTAssertTrue(app.sliders["editor.tools.eraser.width"].waitForExistence(timeout: 5))
        attach(app, "eraser-options")
        try audit(app, screen: "eraser options", popover: true)
        app.buttons["Whole Strokes"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2)).tap()
        XCTAssertTrue(part.waitForNonExistence(timeout: 5))
        lasso.tap()
        waitUntilSelected(lasso)

        // Tapped while in hand, a pen opens: its colour and its width are changed where it stands.
        cobalt.tap()
        waitUntilSelected(cobalt)
        cobalt.tap()
        let green = app.buttons["Green"]
        XCTAssertTrue(green.waitForExistence(timeout: 5), "the pen's options")
        XCTAssertTrue(app.buttons["Blue"].isSelected)
        green.tap()
        wait(for: [expectation(for: NSPredicate(format: "label == 'Pen, Green'"), evaluatedWith: cobalt)], timeout: 5)
        let width = app.sliders["editor.tools.pen.width"]
        let thin = width.value as? String
        width.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: width.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertNotEqual(width.value as? String, thin, "the knob slides along the strip")
        attach(app, "pen-options")
        try audit(app, screen: "pen options", popover: true)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2)).tap()
        XCTAssertTrue(green.waitForNonExistence(timeout: 5))
        XCTAssertEqual(strokeCount(canvas), 0, "the tap that closed the options left no mark")

        // A new pen is like the one in hand, in a colour of its own, and opens so that can be changed. It can be taken off again.
        add.tap()
        let fifth = app.buttons["editor.tools.5"]
        XCTAssertTrue(fifth.waitForExistence(timeout: 5))
        XCTAssertEqual(fifth.label, "Pen, Grey")
        XCTAssertTrue(fifth.isSelected)
        let remove = app.buttons["editor.tools.pen.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "the new pen opens")
        remove.tap()
        XCTAssertTrue(fifth.waitForNonExistence(timeout: 5))
        waitUntilSelected(highlighter)

        // The shortcuts beside the tools are chosen from the tray's own menu.
        XCTAssertFalse(app.buttons["editor.tools.extra.ruler"].exists)
        app.buttons["editor.tools.customise"].tap()
        let ruler = app.buttons["Ruler"].firstMatch
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        attach(app, "customise")
        // The menu stays open, so more than one can be changed.
        ruler.tap()
        app.buttons["Text Box"].firstMatch.tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2)).tap()
        let rulerButton = app.buttons["editor.tools.extra.ruler"]
        XCTAssertTrue(rulerButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["editor.tools.extra.text"].exists)
        rulerButton.tap()
        waitUntilSelected(rulerButton)
        rulerButton.tap()
        attach(app, "tray-customised")

        // The tools are put away from the bar, and brought back.
        app.buttons["Hide Tools"].firstMatch.tap()
        XCTAssertTrue(tray.waitForNonExistence(timeout: 5))
        attach(app, "tray-hidden")
        app.buttons["Show Tools"].firstMatch.tap()
        XCTAssertTrue(cobalt.waitForExistence(timeout: 5))
    }
}
