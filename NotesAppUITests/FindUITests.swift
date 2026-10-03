import XCTest

/// ⌘F inside a notebook: handwriting and typed text are found and stepped through.
@MainActor
final class FindUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func ribbonPage(_ app: XCUIApplication) -> String? {
        let ribbon = app.buttons["editor.ribbon"]
        return ribbon.exists ? ribbon.label : nil
    }

    func testWordsAreFoundInHandwritingAndTypedText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "find", "-resetStorage", "-seedLibrary", "2", "-seedHandwriting", "-drawingInput", "anyInput"]
        app.launch()
        let notebook = app.buttons["notebook.Study Notes"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        let ribbon = app.buttons["editor.ribbon"]
        XCTAssertTrue(ribbon.waitForExistence(timeout: 20))

        // A text box on the second page says the same word as the handwriting on the first.
        app.buttons["Add"].firstMatch.tap()
        app.buttons["Page at End"].firstMatch.tap()
        wait(for: [expectation(for: NSPredicate(format: "label == 'Page 3 of 3'"), evaluatedWith: ribbon)], timeout: 10)
        app.buttons["Add"].firstMatch.tap()
        app.buttons["Text Box"].firstMatch.tap()
        let editor = app.textViews["page.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("hello again")
        app.buttons["editor.arrange.done"].tap()

        app.buttons["More"].firstMatch.tap()
        app.buttons["Find in Notebook…"].firstMatch.tap()
        let field = app.textFields["editor.find.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("hello")
        let status = app.staticTexts["editor.find.status"]
        wait(for: [expectation(for: NSPredicate(format: "label == '2 of 2'"), evaluatedWith: status)], timeout: 40)
        sleep(1)
        XCTAssertEqual(ribbonPage(app), nil, "the bar is put away while finding")
        attach(app, "find-typed")

        // The first match shown is the one on the page being read; the next comes round to the handwriting on page 1.
        app.buttons["editor.find.next"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label == '1 of 2'"), evaluatedWith: status)], timeout: 5)
        sleep(2)
        XCTAssertTrue(app.descendants(matching: .any)["page.canvas.1"].isHittable, "the page with the match is brought into view")
        attach(app, "find-handwriting")
        app.buttons["editor.find.previous"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label == '2 of 2'"), evaluatedWith: status)], timeout: 5)

        field.typeText("zzz")
        wait(for: [expectation(for: NSPredicate(format: "label == 'No matches'"), evaluatedWith: status)], timeout: 20)
        app.buttons["editor.find.done"].tap()
        XCTAssertTrue(ribbon.waitForExistence(timeout: 5), "back to writing")
        XCTAssertFalse(app.textFields["editor.find.field"].exists)
    }
}
