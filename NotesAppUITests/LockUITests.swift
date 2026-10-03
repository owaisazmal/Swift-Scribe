import XCTest

/// A locked notebook: its cover says so, it only opens for whoever can unlock the iPad, and it is covered until then.
@MainActor
final class LockUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ app: XCUIApplication, reset: Bool, unlock: String) -> XCUIElement {
        app.launchArguments = ["-storageRoot", "lock", "-seedLibrary", "2", "-seedHandwriting", "-indexSeed", "-drawingInput", "anyInput", unlock] + (reset ? ["-resetStorage"] : [])
        app.launch()
        let notebook = app.buttons["notebook.Study Notes"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        return notebook
    }

    func testALockedNotebookOpensOnlyWhenUnlocked() throws {
        let app = XCUIApplication()
        var notebook = launch(app, reset: true, unlock: "-fakeUnlockOnce")
        XCTAssertFalse(notebook.label.contains("locked"))
        func search(_ text: String) {
            let field = app.openLibrarySearch()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            if !text.isEmpty { field.typeText(text) }
            sleep(3)
        }
        notebook.press(forDuration: 1.2)
        app.buttons["Lock…"].firstMatch.tap()
        let locked = NSPredicate(format: "label CONTAINS 'locked'")
        wait(for: [expectation(for: locked, evaluatedWith: notebook)], timeout: 10)
        attach(app, "locked-cover")

        // Face ID was used up locking it, so now it refuses.
        notebook.tap()
        sleep(2)
        XCTAssertFalse(app.buttons["editor.ribbon"].exists, "a notebook that isn't unlocked doesn't open")
        XCTAssertTrue(notebook.exists)

        search("hello")
        XCTAssertFalse(notebook.exists, "what is written in a locked notebook isn't searched")
        search("Study")
        XCTAssertTrue(notebook.waitForExistence(timeout: 10), "its title still is")
        search("")

        // Opened beside another notebook, it stays behind its lock screen.
        let other = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'notebook.' AND NOT identifier CONTAINS 'Study Notes'")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 10))
        other.tap()
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20))
        app.buttons["editor.title"].tap()
        app.buttons["Open Another Notebook Beside…"].firstMatch.tap()
        let pick = app.buttons["beside.notebook.Study Notes"]
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
        pick.tap()
        let unlock = app.buttons["lock.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10), "the lock screen stands in for the pages")
        XCTAssertTrue(app.staticTexts["“Study Notes” is locked"].exists)
        attach(app, "lock-screen")
        unlock.tap()
        sleep(1)
        XCTAssertTrue(unlock.exists, "and stays when the unlock is refused")
        app.buttons["lock.close"].tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 10))
        app.buttons["editor.back"].tap()
        XCTAssertTrue(notebook.waitForExistence(timeout: 15))
        app.terminate()

        notebook = launch(app, reset: false, unlock: "-fakeUnlock")
        XCTAssertTrue(notebook.label.contains("locked"), "the lock is saved with the notebook")
        notebook.tap()
        let canvas = app.descendants(matching: .any)["page.canvas.1"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "unlocked, it opens")
        XCTAssertFalse(app.buttons["lock.unlock"].exists)

        app.buttons["editor.title"].tap()
        app.buttons["Remove Lock…"].firstMatch.tap()
        sleep(1)
        app.buttons["editor.back"].tap()
        XCTAssertTrue(notebook.waitForExistence(timeout: 15))
        wait(for: [expectation(for: NSPredicate(format: "NOT (label CONTAINS 'locked')"), evaluatedWith: notebook)], timeout: 10)
        search("hello")
        XCTAssertTrue(notebook.waitForExistence(timeout: 10), "with the lock off, its handwriting is searched again")
    }
}
