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

    /// The tray and what opens from it, at night and at an accessibility text size.
    func testTheTrayAndItsOptionsAtNightAndInLargeText() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        addTeardownBlock { @MainActor in XCUIDevice.shared.appearance = .light }
        let modes: [(name: String, appearance: XCUIDevice.Appearance, size: String?, checks: XCUIAccessibilityAuditType)] = [
            ("dark", .dark, nil, .all),
            ("large", .light, "UICTContentSizeCategoryAccessibilityL", [.dynamicType, .textClipped, .contrast]),
            ("largest", .light, "UICTContentSizeCategoryAccessibilityXXXL", [.dynamicType, .textClipped])]
        for mode in modes {
            XCUIDevice.shared.appearance = mode.appearance
            let app = XCUIApplication()
            app.launchArguments = ["-storageRoot", "tools", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput", "-freshToolPresets"]
                + (mode.size.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
            app.launch()
            let notebook = app.buttons["notebook.Studio Notes 2"]
            XCTAssertTrue(notebook.waitForExistence(timeout: 30))
            notebook.tap()
            let black = app.buttons["editor.tools.1"], eraser = app.buttons["editor.tools.eraser"]
            XCTAssertTrue(black.waitForExistence(timeout: 20))
            let canvas = app.element("page.canvas.1"), tray = app.element("editor.tools.tray"), large = mode.size != nil
            func close(_ element: XCUIElement) {
                canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1)).tap()
                XCTAssertTrue(element.waitForNonExistence(timeout: 5))
            }
            attach(app, "\(mode.name)-tray")
            try audit(app, mode.checks, screen: "\(mode.name) tool tray", largeText: large, bar: tray)

            black.tap()
            let remove = app.buttons["editor.tools.pen.remove"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            XCTAssertTrue(remove.isHittable, "the options fit on the screen")
            app.buttons["Fountain Pen"].tap()
            attach(app, "\(mode.name)-pen-options")
            try audit(app, mode.checks, screen: "\(mode.name) pen options", popover: true, largeText: large)
            close(remove)

            eraser.tap()
            eraser.tap()
            let part = app.buttons["Part of a Stroke"]
            XCTAssertTrue(part.waitForExistence(timeout: 5))
            part.tap()
            XCTAssertTrue(app.sliders["editor.tools.eraser.width"].waitForExistence(timeout: 5))
            attach(app, "\(mode.name)-eraser-options")
            try audit(app, mode.checks, screen: "\(mode.name) eraser options", popover: true, largeText: large)
            close(part)

            app.buttons["editor.tools.customise"].tap()
            let zoom = app.buttons["editor.tools.shortcut.zoomWindow"]
            XCTAssertTrue(zoom.waitForExistence(timeout: 5))
            XCTAssertTrue(zoom.isHittable, "every tag fits on the screen")
            attach(app, "\(mode.name)-shortcut-tags")
            try audit(app, mode.checks, screen: "\(mode.name) shortcut tags", popover: true, largeText: large)
            close(zoom)

            // On its side the screen is at its shortest: what doesn't fit scrolls, and nothing is cut short.
            if mode.name == "largest" {
                XCUIDevice.shared.orientation = .landscapeLeft
                defer { XCUIDevice.shared.orientation = .portrait }
                let window = app.windows.firstMatch
                wait(for: [expectation(for: NSPredicate { _, _ in window.frame.width > window.frame.height }, evaluatedWith: nil)], timeout: 10)
                sleep(2)
                black.tap()
                black.tap()
                XCTAssertTrue(remove.waitForExistence(timeout: 5))
                sleep(2)
                if remove.exists, !remove.isHittable { app.element("editor.tools.pen.kind").swipeUp() }
                sleep(2)
                XCTAssertTrue(remove.isHittable, "the end of the options is reached on a screen on its side")
                try audit(app, mode.checks, screen: "largest pen options on its side", popover: true, largeText: true)
                close(remove)
                app.buttons["editor.tools.customise"].tap()
                XCTAssertTrue(app.buttons["editor.tools.shortcut.picture"].waitForExistence(timeout: 5))
                sleep(2)
                try audit(app, mode.checks, screen: "largest shortcut tags on its side", popover: true, largeText: true)
                if !zoom.isHittable { app.buttons["editor.tools.shortcut.sticker"].swipeUp() }
                sleep(2)
                XCTAssertTrue(zoom.isHittable, "the last tag is reached on a screen on its side")
                close(zoom)
            }
            app.terminate()
        }
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

        // Touch and hold takes a pen up and opens it in one go.
        let remove = app.buttons["editor.tools.pen.remove"]
        black.press(forDuration: 0.8)
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "a held pen opens")
        XCTAssertTrue(black.isSelected)
        XCTAssertFalse(app.buttons["editor.tools.pen.left"].isEnabled, "the first pen has nowhere to go on the left")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2)).tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))

        // Tapped while in hand, a pen opens: its colour and its width are changed where it stands.
        cobalt.tap()
        waitUntilSelected(cobalt)
        cobalt.tap()
        let green = app.buttons["Green"]
        XCTAssertTrue(green.waitForExistence(timeout: 5), "the pen's options")
        XCTAssertTrue(app.buttons["Blue"].isSelected)
        green.tap()
        wait(for: [expectation(for: NSPredicate(format: "label == 'Pen, Green'"), evaluatedWith: cobalt)], timeout: 5)
        // Its kind is chosen from the tools standing in the roll.
        let pencil = app.buttons["Pencil"], plain = app.buttons["Pen"]
        XCTAssertTrue(plain.isSelected)
        pencil.tap()
        wait(for: [expectation(for: NSPredicate(format: "label == 'Pencil, Green'"), evaluatedWith: cobalt)], timeout: 5)
        XCTAssertTrue(pencil.isSelected)
        attach(app, "pen-kind")
        plain.tap()
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
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "the new pen opens")
        // From its options it is moved along the tray, and taken off it.
        XCTAssertFalse(app.buttons["editor.tools.pen.right"].isEnabled, "the last pen has nowhere to go on the right")
        app.buttons["editor.tools.pen.left"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label == 'Pen, Grey'"), evaluatedWith: highlighter)], timeout: 5)
        attach(app, "pen-moved")
        app.buttons["editor.tools.pen.right"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label == 'Pen, Grey'"), evaluatedWith: fifth)], timeout: 5)
        remove.tap()
        XCTAssertTrue(fifth.waitForNonExistence(timeout: 5))
        waitUntilSelected(highlighter)

        // The shortcuts beside the tools are tags, tied on and taken off from the end of the tray.
        XCTAssertFalse(app.buttons["editor.tools.extra.ruler"].exists)
        app.buttons["editor.tools.customise"].tap()
        let ruler = app.buttons["editor.tools.shortcut.ruler"], text = app.buttons["editor.tools.shortcut.text"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))
        XCTAssertFalse(ruler.isSelected)
        XCTAssertTrue(text.isSelected)
        // The tags stay open, so more than one can be changed.
        ruler.tap()
        text.tap()
        XCTAssertTrue(ruler.isSelected)
        attach(app, "customise")
        try audit(app, screen: "shortcut tags", popover: true)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2)).tap()
        XCTAssertTrue(ruler.waitForNonExistence(timeout: 5))
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
