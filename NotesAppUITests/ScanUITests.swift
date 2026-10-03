import XCTest

/// Scanning paper into a notebook, and into a new one from the library.
@MainActor
final class ScanUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testScannedSheetsBecomePagesAndCanBeSearched() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "scan", "-resetStorage", "-seedLibrary", "2", "-seedHandwriting", "-fakeScan", "-drawingInput", "anyInput"]
        app.launch()
        let notebook = app.buttons["notebook.Study Notes"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        let ribbon = app.buttons["editor.ribbon"]
        XCTAssertTrue(ribbon.waitForExistence(timeout: 20))
        XCTAssertEqual(ribbon.label, "Page 1 of 2")

        app.buttons["Add"].firstMatch.tap()
        app.buttons["Scan Documents…"].firstMatch.tap()
        wait(for: [expectation(for: NSPredicate(format: "label == 'Page 2 of 4'"), evaluatedWith: ribbon)], timeout: 20)
        sleep(1)
        attach(app, "scan-in-notebook")
        app.buttons["editor.undo"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label ENDSWITH 'of 2'"), evaluatedWith: ribbon)], timeout: 10)
        app.buttons["editor.redo"].tap()
        wait(for: [expectation(for: NSPredicate(format: "label ENDSWITH 'of 4'"), evaluatedWith: ribbon)], timeout: 10)
        app.buttons["editor.back"].tap()
        XCTAssertTrue(notebook.waitForExistence(timeout: 20))

        app.buttons["New"].firstMatch.press(forDuration: 1)
        app.buttons["Scan Documents…"].firstMatch.tap()
        let scanned = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notebook.Scan '")).firstMatch
        XCTAssertTrue(scanned.waitForExistence(timeout: 20), "a scan from the library is a notebook of its own")
        XCTAssertTrue(scanned.label.contains("2 pages"))

        let field = app.openLibrarySearch()
        field.typeText("quarterly")
        let hit = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'page 1: ' AND label CONTAINS[c] 'quarterly'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 40), "the words printed on a scan are found")
        attach(app, "scan-search")
    }
}
