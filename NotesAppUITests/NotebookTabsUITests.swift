import XCTest

/// Several notebooks open in one window as tabs: opened from the title menu and the bar, switched between with their
/// undo history kept, closed one by one, and still there after a visit to the library and after the app is stopped.
@MainActor
final class NotebookTabsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "tabs", "-drawingInput", "anyInput"] + extra
        app.launch()
        return app
    }

    private func pick(_ title: String, in app: XCUIApplication) {
        let row = app.buttons["beside.notebook.\(title)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the picker offers \(title)")
        row.tap()
    }

    private func title(_ app: XCUIApplication) -> String { app.buttons["editor.title"].label }

    func testNotebooksOpenInTabsAndStayOpenBehindTheBar() throws {
        var app = launch(["-resetStorage", "-seedLibrary", "4"])
        let studio = app.buttons["notebook.Studio Notes 2"]
        XCTAssertTrue(studio.waitForExistence(timeout: 30))
        studio.tap()
        let ribbon = app.buttons["editor.ribbon"]
        XCTAssertTrue(ribbon.waitForExistence(timeout: 20))
        let add = app.buttons["tabs.add"]
        XCTAssertFalse(add.exists, "a notebook on its own has no tab bar")

        // The title menu opens a second notebook in a tab, and the bar appears.
        app.buttons["editor.title"].tap()
        app.buttons["Open Another Notebook in a Tab…"].firstMatch.tap()
        XCTAssertFalse(app.buttons["beside.notebook.Studio Notes 2"].waitForExistence(timeout: 2), "the notebook already open isn't offered")
        pick("Physics II 3", in: app)
        let studioTab = app.buttons["tabs.tab.Studio Notes 2"], physicsTab = app.buttons["tabs.tab.Physics II 3"]
        XCTAssertTrue(physicsTab.waitForExistence(timeout: 10))
        XCTAssertTrue(physicsTab.isSelected)
        XCTAssertFalse(studioTab.isSelected)
        wait(for: [expectation(for: NSPredicate(format: "label BEGINSWITH 'Physics II 3'"), evaluatedWith: app.buttons["editor.title"])], timeout: 10)
        attach(app, "two-tabs")

        // Written in one tab, then away and back: the ink is there and so is its undo.
        let canvas = app.element("page.canvas.1")
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.4)), withVelocity: 400, thenHoldForDuration: 0.05)
        wait(for: [expectation(for: NSPredicate(format: "value == '1 stroke'"), evaluatedWith: canvas)], timeout: 5)
        studioTab.tap()
        wait(for: [expectation(for: NSPredicate(format: "label BEGINSWITH 'Studio Notes 2'"), evaluatedWith: app.buttons["editor.title"])], timeout: 10)
        XCTAssertTrue(studioTab.isSelected)
        wait(for: [expectation(for: NSPredicate(format: "value == 'Empty'"), evaluatedWith: app.element("page.canvas.1"))], timeout: 10)
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled, "each notebook has its own undo")
        physicsTab.tap()
        wait(for: [expectation(for: NSPredicate(format: "value == '1 stroke'"), evaluatedWith: app.element("page.canvas.1"))], timeout: 10)
        XCTAssertTrue(app.buttons["editor.undo"].isEnabled, "the tab comes back with its undo history")
        app.buttons["editor.undo"].tap()
        wait(for: [expectation(for: NSPredicate(format: "value == 'Empty'"), evaluatedWith: app.element("page.canvas.1"))], timeout: 5)

        // A third from the bar's own button.
        add.tap()
        XCTAssertFalse(app.buttons["beside.notebook.Physics II 3"].waitForExistence(timeout: 2), "nor is one that already has a tab")
        pick("Recipes 4", in: app)
        let recipesTab = app.buttons["tabs.tab.Recipes 4"]
        XCTAssertTrue(recipesTab.waitForExistence(timeout: 10))
        XCTAssertTrue(recipesTab.isSelected)
        attach(app, "three-tabs")
        try audit(app, screen: "tabs")

        // Closing the tab on show shows its neighbour; closing one behind the bar leaves the one on show alone.
        app.buttons["tabs.close.Recipes 4"].tap()
        XCTAssertTrue(recipesTab.waitForNonExistence(timeout: 10))
        XCTAssertTrue(physicsTab.isSelected)
        wait(for: [expectation(for: NSPredicate(format: "label BEGINSWITH 'Physics II 3'"), evaluatedWith: app.buttons["editor.title"])], timeout: 10)
        app.buttons["tabs.close.Studio Notes 2"].tap()
        XCTAssertTrue(add.waitForNonExistence(timeout: 10), "one notebook left: the bar goes")
        XCTAssertTrue(title(app).hasPrefix("Physics II 3"))
        XCTAssertTrue(ribbon.exists)

        // Two tabs wait in the library, and a notebook opened from the shelf joins them.
        app.buttons["editor.title"].tap()
        app.buttons["Open Another Notebook in a Tab…"].firstMatch.tap()
        pick("Studio Notes 2", in: app)
        XCTAssertTrue(studioTab.waitForExistence(timeout: 10))
        app.buttons["editor.back"].tap()
        let biology = app.buttons["notebook.Cell Biology 1"]
        XCTAssertTrue(biology.waitForExistence(timeout: 15), "back in the library")
        sleep(1)
        biology.tap()
        let biologyTab = app.buttons["tabs.tab.Cell Biology 1"]
        XCTAssertTrue(biologyTab.waitForExistence(timeout: 15), "the tabs are still there, with the notebook just opened among them")
        XCTAssertTrue(biologyTab.isSelected)
        XCTAssertTrue(physicsTab.exists)
        XCTAssertTrue(studioTab.exists)
        attach(app, "tabs-after-library")

        // Stopped and opened again, the window comes back with its tabs.
        physicsTab.tap()
        wait(for: [expectation(for: NSPredicate(format: "label BEGINSWITH 'Physics II 3'"), evaluatedWith: app.buttons["editor.title"])], timeout: 10)
        XCUIDevice.shared.press(.home)
        app.terminate()
        app = launch([])
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 30), "the notebook reopens")
        XCTAssertTrue(app.buttons["tabs.tab.Physics II 3"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tabs.tab.Physics II 3"].isSelected)
        XCTAssertTrue(app.buttons["tabs.tab.Cell Biology 1"].exists)
        XCTAssertTrue(app.buttons["tabs.tab.Studio Notes 2"].exists)
        XCTAssertTrue(title(app).hasPrefix("Physics II 3"))

        // In focus mode the bar goes with the rest of the chrome, and comes back with it.
        app.buttons["More"].firstMatch.tap()
        app.buttons["Focus Mode"].firstMatch.tap()
        XCTAssertTrue(app.buttons["tabs.add"].waitForNonExistence(timeout: 5))
        attach(app, "tabs-focus")
        app.buttons["editor.focus.exit"].tap()
        XCTAssertTrue(app.buttons["tabs.add"].waitForExistence(timeout: 5))
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["notebook.Cell Biology 1"].waitForExistence(timeout: 15))
    }
}
