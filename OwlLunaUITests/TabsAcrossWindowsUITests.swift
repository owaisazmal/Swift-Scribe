import XCTest

/// One window writes in a notebook: a tab or a link that would open it in a second window brings the first forward instead.
@MainActor
final class TabsAcrossWindowsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// One window to start with, whatever an earlier run left behind, and one again when the test is over.
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "windows", "-resetStorage", "-seedLibrary", "4", "-drawingInput", "anyInput", "-windowButtons"] + extra
        app.launch()
        let close = app.buttons["debug.window.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 30))
        close.tap()
        addTeardownBlock { @MainActor in
            if app.state == .runningForeground, close.exists { close.tap() }
        }
        return app
    }

    /// Waits for a window to be the one in front.
    private func expectWindow(_ number: String, in app: XCUIApplication, _ message: String = "") {
        let label = app.staticTexts["debug.window.number"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        let front = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", number), object: label)
        XCTAssertEqual(XCTWaiter.wait(for: [front], timeout: 10), .completed, message.isEmpty ? "window \(number) is in front" : message)
    }

    private func expectTitle(_ title: String, in app: XCUIApplication, _ message: String = "") {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", title), object: app.buttons["editor.title"])
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 15), .completed, message.isEmpty ? "\(title) is on show" : message)
    }

    private func open(_ title: String, in app: XCUIApplication) {
        let cover = app.buttons["notebook.\(title)"]
        XCTAssertTrue(cover.waitForExistence(timeout: 30))
        sleep(1)
        if cover.frame.maxY > app.frame.maxY { app.swipeUp(velocity: .slow) }
        cover.tap()
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20))
        expectTitle(title, in: app)
    }

    private func addTab(_ title: String, in app: XCUIApplication) {
        app.buttons["editor.title"].tap()
        app.buttons["Open Another Notebook in a Tab…"].firstMatch.tap()
        let row = app.buttons["beside.notebook.\(title)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the picker offers \(title)")
        row.tap()
        XCTAssertTrue(app.buttons["tabs.tab.\(title)"].waitForExistence(timeout: 10))
        expectTitle(title, in: app)
    }

    private func newWindow(in app: XCUIApplication) {
        app.buttons["debug.window.new"].tap()
        expectWindow("2", in: app)
    }

    private func otherWindow(_ number: String, in app: XCUIApplication) {
        app.buttons["debug.window.other"].tap()
        expectWindow(number, in: app)
    }

    func testAWaitingTabGoesToTheWindowThatHasItsNotebookOpen() throws {
        let app = launch()
        // Two tabs wait in the first window's library, and a second window opens one of their notebooks.
        open("Physics II 3", in: app)
        addTab("Studio Notes 2", in: app)
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["notebook.Studio Notes 2"].waitForExistence(timeout: 15), "back in the library")
        newWindow(in: app)
        open("Studio Notes 2", in: app)
        XCTAssertFalse(app.buttons["tabs.add"].exists, "a notebook on its own has no tab bar")

        // The first window opens a third notebook, which joins the tabs that waited.
        otherWindow("1", in: app)
        open("Recipes 4", in: app)
        let studioTab = app.buttons["tabs.tab.Studio Notes 2"]
        XCTAssertTrue(studioTab.waitForExistence(timeout: 15), "the tabs that waited are back")
        attach("first-window-tabs")

        // Its tab for the notebook the second window has open goes there.
        studioTab.tap()
        expectWindow("2", in: app, "the window that has the notebook open comes forward")
        expectTitle("Studio Notes 2", in: app)
        XCTAssertFalse(app.buttons["tabs.add"].exists)
        attach("second-window-forward")
        otherWindow("1", in: app)
        expectTitle("Recipes 4", in: app, "the first window still shows what it showed")
        XCTAssertTrue(app.buttons["tabs.tab.Recipes 4"].isSelected)
        XCTAssertTrue(app.buttons["tabs.tab.Physics II 3"].exists)
        XCTAssertFalse(studioTab.exists, "and has let go of the tab for a notebook that is the other window's now")
        attach("first-window-after")
    }

    func testClosingATabNeverLandsOnANotebookAnotherWindowHasOpen() throws {
        let app = launch()
        open("Physics II 3", in: app)
        addTab("Studio Notes 2", in: app)
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["notebook.Studio Notes 2"].waitForExistence(timeout: 15), "back in the library")
        newWindow(in: app)
        open("Studio Notes 2", in: app)
        otherWindow("1", in: app)
        open("Recipes 4", in: app)
        XCTAssertTrue(app.buttons["tabs.tab.Studio Notes 2"].waitForExistence(timeout: 15))

        // The tab on show stands after the one whose notebook the second window has open: closed, it makes way for another.
        app.buttons["tabs.close.Recipes 4"].tap()
        XCTAssertTrue(app.buttons["tabs.tab.Recipes 4"].waitForNonExistence(timeout: 10))
        expectTitle("Physics II 3", in: app, "the tab that takes its place is one this window can write in")
        expectWindow("1", in: app, "and the window stays in front")
        XCTAssertFalse(app.buttons["tabs.add"].exists, "with the other window's notebook let go of, one notebook is left and the bar goes")
        attach("first-window-after-close")
        otherWindow("2", in: app)
        expectTitle("Studio Notes 2", in: app, "the second window still has its notebook")
    }

    func testClosingTheLastTabThisWindowCanShowGoesBackToTheLibrary() throws {
        let app = launch()
        open("Physics II 3", in: app)
        addTab("Studio Notes 2", in: app)
        app.buttons["editor.back"].tap()
        XCTAssertTrue(app.buttons["notebook.Studio Notes 2"].waitForExistence(timeout: 15), "back in the library")
        newWindow(in: app)
        open("Studio Notes 2", in: app)
        otherWindow("1", in: app)
        open("Physics II 3", in: app)
        XCTAssertTrue(app.buttons["tabs.tab.Studio Notes 2"].waitForExistence(timeout: 15), "the tab that waited is back")

        // The only other tab is the second window's notebook now, so closing this one leaves nothing to show.
        app.buttons["tabs.close.Physics II 3"].tap()
        XCTAssertTrue(app.buttons["notebook.Physics II 3"].waitForExistence(timeout: 20), "the window goes back to its library")
        expectWindow("1", in: app, "and stays in front")
        attach("first-window-library")
        open("Physics II 3", in: app)
        XCTAssertFalse(app.buttons["tabs.add"].exists, "no tab was left waiting")
        otherWindow("2", in: app)
        expectTitle("Studio Notes 2", in: app, "the second window still has its notebook")
    }

    func testALinkOutOfANotebookOnItsOwnLeavesItOpen() throws {
        let app = launch(["-seedJournal"])
        open("Physics II 3", in: app)
        newWindow(in: app)
        open("Journal", in: app)
        otherWindow("1", in: app)
        expectTitle("Physics II 3", in: app)

        // On its own a notebook makes way for a link's, but not for one another window is writing in.
        XCUIDevice.shared.system.open(URL(string: "owlluna://today")!)
        expectWindow("2", in: app, "the window that has the notebook open comes forward")
        expectTitle("Journal", in: app)
        wait(for: [expectation(for: NSPredicate(format: "label == 'Page 4 of 4'"), evaluatedWith: app.buttons["editor.ribbon"])], timeout: 10)
        otherWindow("1", in: app)
        expectTitle("Physics II 3", in: app, "the first window still has its notebook open")
        attach("first-window-after")
    }

    func testALinkToANotebookOpenInAnotherWindowIsShownThere() throws {
        let app = launch(["-seedJournal"])
        // The first window has two tabs; the second opens the journal, which a link will ask for.
        open("Physics II 3", in: app)
        addTab("Recipes 4", in: app)
        newWindow(in: app)
        open("Journal", in: app)
        otherWindow("1", in: app)
        expectTitle("Recipes 4", in: app)

        // With tabs open a link shows its notebook in a tab, unless another window is writing in it.
        XCUIDevice.shared.system.open(URL(string: "owlluna://today")!)
        expectWindow("2", in: app, "the window that has the notebook open comes forward")
        expectTitle("Journal", in: app)
        XCTAssertFalse(app.buttons["tabs.add"].exists)
        wait(for: [expectation(for: NSPredicate(format: "label == 'Page 4 of 4'"), evaluatedWith: app.buttons["editor.ribbon"])], timeout: 10)
        attach("second-window-forward")
        otherWindow("1", in: app)
        expectTitle("Recipes 4", in: app, "the first window still shows what it showed")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tabs.tab.'")).count, 2, "and has no tab for a notebook it can't write in")
        attach("first-window-after")
    }
}
