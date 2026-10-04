import XCTest

/// A whiteboard from the starter, written on far apart, then kept as a card among ordinary pages and opened again.
@MainActor
final class WhiteboardUITests: XCTestCase {
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

    private func draw(on canvas: XCUIElement, from start: CGVector, to end: CGVector) {
        canvas.coordinate(withNormalizedOffset: start)
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: end), withVelocity: 400, thenHoldForDuration: 0.05)
    }

    func testWhiteboardIsWrittenOnWithoutEdgesAndStandsAsACardAmongPages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "whiteboard", "-drawingInput", "anyInput", "-resetStorage", "-freshWhiteboardTip"]
        app.launch()
        XCTAssertTrue(app.buttons["New"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["New"].firstMatch.tap()
        let starter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Whiteboard starter")).firstMatch
        XCTAssertTrue(starter.waitForExistence(timeout: 10), "the Whiteboard starter")
        XCTAssertTrue(starter.isHittable, "the Whiteboard starter stands beside Journal, without scrolling")
        attach(app, "starters")
        starter.tap()
        app.buttons["Create"].firstMatch.tap()

        let board = app.element("page.canvas.1")
        XCTAssertTrue(board.waitForExistence(timeout: 15), "the notebook opens on its whiteboard")
        XCTAssertTrue(board.label.hasPrefix("Whiteboard"), board.label)

        // The first time, a tip says what a whiteboard is and leads to the guide that names every button.
        XCTAssertTrue(app.buttons["editor.board.tip.guide"].waitForExistence(timeout: 5), "the first whiteboard comes with a tip")
        attach(app, "board-tip")
        app.buttons["editor.board.tip.guide"].tap()
        XCTAssertTrue(app.buttons["editor.board.guide.done"].waitForExistence(timeout: 5), "the guide")
        XCTAssertTrue(app.staticTexts["Whiteboard Guide"].exists)
        attach(app, "board-guide")
        try audit(app, [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription], screen: "whiteboard guide", modal: true, popover: true)
        app.buttons["editor.board.guide.done"].tap()
        app.buttons["editor.board.tip.done"].tap()
        XCTAssertTrue(app.buttons["editor.board.tip.done"].waitForNonExistence(timeout: 5), "the tip is put away for good")
        // The board's own controls are behind one button in the bar, and nothing stands over the board.
        let menu = app.buttons["editor.board.menu"]
        XCTAssertEqual(menu.label, "Whiteboard")
        XCTAssertLessThanOrEqual(menu.frame.maxY, board.frame.minY, "the button is in the bar, above the board")
        XCTAssertFalse(app.buttons["editor.board.everything"].exists)

        draw(on: board, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.6, dy: 0.32))
        draw(on: board, from: CGVector(dx: 0.3, dy: 0.4), to: CGVector(dx: 0.6, dy: 0.5))
        XCTAssertEqual(strokeCount(board), 2)
        attach(app, "board-written")
        try audit(app, [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription], screen: "whiteboard", bar: app.otherElements["editor.tools.tray"])

        // Zoomed out, a corner of the screen is far from where the board was first written on.
        board.pinch(withScale: 0.3, velocity: -1)
        draw(on: board, from: CGVector(dx: 0.08, dy: 0.2), to: CGVector(dx: 0.2, dy: 0.24))
        draw(on: board, from: CGVector(dx: 0.8, dy: 0.86), to: CGVector(dx: 0.92, dy: 0.9))
        XCTAssertEqual(strokeCount(board), 4, "there is room to write wherever the board is moved to")
        attach(app, "board-zoomed-out")

        menu.tap()
        XCTAssertTrue(app.buttons["editor.board.everything"].waitForExistence(timeout: 5), "a board is fitted by what is on it")
        XCTAssertEqual(app.buttons["editor.board.everything"].label, "Show Everything")
        XCTAssertTrue(app.buttons["editor.board.pages"].exists)
        XCTAssertTrue(app.buttons["editor.board.guide"].exists)
        attach(app, "board-menu")
        app.buttons["editor.board.actual"].tap()
        menu.tap()
        app.buttons["editor.board.everything"].tap()
        attach(app, "board-everything")
        app.buttons["More"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Find in Notebook…"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Show Everything"].exists, "with its own button in the bar, the board's controls aren't in More as well")
        app.buttons["Find in Notebook…"].firstMatch.tap()
        app.buttons["editor.find.done"].tap()

        // An ordinary page after it: the pages are a stack again and the board is a card in it.
        app.buttons["Add"].firstMatch.tap()
        app.buttons["Page at End"].tap()
        XCTAssertTrue(app.element("page.canvas.2").waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["editor.ribbon"].label, "Page 2 of 2")
        app.buttons["editor.ribbon"].tap()
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Page 1 of 2")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertEqual(first.value as? String, "Whiteboard")
        attach(app, "navigator")
        app.buttons["Done"].firstMatch.tap()

        // With the Pencil alone drawing, a finger scrolls back up to the card.
        app.terminate()
        app.launchArguments = ["-storageRoot", "whiteboard", "-drawingInput", "pencilOnly"]
        app.launch()
        XCTAssertTrue(app.element("page.canvas.2").waitForExistence(timeout: 30), "the notebook is opened again where it was left")
        app.swipeDown()
        let card = app.element("page.board.1")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "among the pages the board is a card")
        attach(app, "board-card")
        try audit(app, [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription], screen: "whiteboard card")
        card.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 10), "the card opens the board")
        XCTAssertEqual(strokeCount(board), 4)
        XCTAssertEqual(app.buttons["editor.ribbon"].label, "Page 1 of 2")

        // A second board from the Add menu, straight from the first.
        app.buttons["Add"].firstMatch.tap()
        app.buttons["editor.add.board"].tap()
        let second = app.element("page.canvas.2")
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertTrue(second.label.hasPrefix("Whiteboard"), second.label)
        XCTAssertEqual(app.buttons["editor.ribbon"].label, "Page 2 of 3")
        attach(app, "board-second")
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["notebook.Whiteboard"].waitForExistence(timeout: 15))
    }
}
