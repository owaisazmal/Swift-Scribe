import XCTest

/// The M6 parity flows on a seeded 300-page textbook whose PDF text is indexed at launch.
@MainActor
final class ParityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func contextMenu(_ element: XCUIElement, choose item: String, in app: XCUIApplication) {
        element.press(forDuration: 1.2)
        let button = app.buttons[item].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(item) in the context menu")
        button.tap()
    }

    func testSearchOpensTheMatchingPageAndLibraryActionsWork() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "parity", "-resetStorage", "-seedLongPDF", "-indexSeed", "-drawingInput", "anyInput"]
        app.launch()
        let textbook = app.buttons["notebook.Textbook"]
        XCTAssertTrue(textbook.waitForExistence(timeout: 90))

        app.buttons["Search"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "library search opens")
        field.typeText("Chapter 142")
        let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Textbook, page 142:")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 20), "a page-level result for page 142")
        attach(app, "page-search")
        hit.tap()
        let ribbon = app.buttons["editor.ribbon"]
        XCTAssertTrue(ribbon.waitForExistence(timeout: 20))
        XCTAssertEqual(ribbon.label, "Page 142 of 300", "the notebook opens at the matching page")
        ribbon.tap()
        let current = app.buttons["Page 142 of 300, current"]
        let hittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: current)
        wait(for: [hittable], timeout: 5)
        app.buttons["Done"].firstMatch.tap()
        app.buttons["editor.back"].tap()
        XCTAssertTrue(textbook.waitForExistence(timeout: 20))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))

        app.typeKey("n", modifierFlags: [.command, .shift])
        let canvas = app.descendants(matching: .any)["page.canvas.1"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "Quick Note opens a new notebook straight away")
        XCTAssertTrue(app.buttons["editor.undo"].exists, "Undo stays in the toolbar while the tools are showing")
        XCTAssertTrue(app.buttons["Hide Tools"].exists)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.31)), withVelocity: 400, thenHoldForDuration: 0.05)
        XCTAssertTrue(app.buttons["editor.undo"].isEnabled)
        attach(app, "quick-note")
        app.buttons["editor.back"].tap()

        let note = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "notebook.Note ")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 20))
        contextMenu(note, choose: "Export as PDF", in: app)
        XCTAssertTrue(app.staticTexts["Your PDF is ready."].waitForExistence(timeout: 30), "export from the library")
        attach(app, "library-export")
        app.buttons["Done"].firstMatch.tap()

        contextMenu(note, choose: "Change Cover…", in: app)
        XCTAssertTrue(app.navigationBars["Change Cover"].waitForExistence(timeout: 10))
        app.buttons["Print"].firstMatch.tap()
        attach(app, "change-cover")
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(note.waitForExistence(timeout: 10))
    }
}
