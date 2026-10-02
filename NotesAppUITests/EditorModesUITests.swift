import XCTest

/// Focus mode and presenting: what each hides, and that the laser leaves no ink.
@MainActor
final class EditorModesUITests: XCTestCase {
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

    private func drag(on canvas: XCUIElement, y: Double) {
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: y))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: y + 0.05)), withVelocity: 300, thenHoldForDuration: 0.2)
    }

    func testFocusModeAndPresenting() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "modes", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput"]
        app.launch()
        let notebook = app.buttons["notebook.Physics II 3"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        let ribbon = app.buttons["editor.ribbon"]
        XCTAssertTrue(ribbon.waitForExistence(timeout: 20))
        let canvas = app.descendants(matching: .any)["page.canvas.1"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let before = strokeCount(canvas)

        app.buttons["More"].firstMatch.tap()
        app.buttons["Focus Mode"].firstMatch.tap()
        let exitFocus = app.buttons["editor.focus.exit"]
        XCTAssertTrue(exitFocus.waitForExistence(timeout: 5))
        XCTAssertTrue(ribbon.waitForNonExistence(timeout: 5), "the ribbon and the bar are put away")
        XCTAssertFalse(app.buttons["editor.back"].exists)
        drag(on: canvas, y: 0.3)
        XCTAssertEqual(strokeCount(canvas), before + 1, "writing carries on in focus mode")
        attach(app, "focus-mode")
        exitFocus.tap()
        XCTAssertTrue(ribbon.waitForExistence(timeout: 5))

        app.buttons["More"].firstMatch.tap()
        app.buttons["Present"].firstMatch.tap()
        let done = app.buttons["editor.present.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Page 1 of 3"].waitForExistence(timeout: 5))
        drag(on: canvas, y: 0.5)
        XCTAssertEqual(strokeCount(canvas), before + 1, "the laser leaves no ink")
        attach(app, "presenting")
        app.buttons["editor.present.next"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 3"].waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(ribbon.waitForExistence(timeout: 5))
        XCTAssertEqual(ribbon.label, "Page 2 of 3")
        XCTAssertTrue(app.buttons["editor.back"].exists)
    }

    func testABookmarkedPageIsListedInTheOutline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "modes", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput"]
        app.launch()
        let notebook = app.buttons["notebook.Physics II 3"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        let bookmark = app.buttons["editor.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 20))
        XCTAssertEqual(bookmark.label, "Bookmark Page")
        bookmark.tap()
        XCTAssertEqual(bookmark.label, "Remove Bookmark")
        attach(app, "bookmarked")

        app.buttons["editor.ribbon"].tap()
        let outline = app.buttons["Outline"].firstMatch
        XCTAssertTrue(outline.waitForExistence(timeout: 10))
        attach(app, "navigator-pages")
        outline.tap()
        let row = app.buttons["Page 1, page 1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the bookmark is listed under its page")
        attach(app, "navigator-outline")
        row.tap()
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        app.buttons["editor.undo"].tap()
        XCTAssertEqual(bookmark.label, "Bookmark Page", "bookmarking is one undo step")
    }

    func testAStickerCanBePlacedMovedAndRemoved() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "modes", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput"]
        app.launch()
        let notebook = app.buttons["notebook.Physics II 3"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        let canvas = app.descendants(matching: .any)["page.canvas.1"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))

        func add(_ sticker: String) {
            app.buttons["Add"].firstMatch.tap()
            app.buttons["Sticker…"].firstMatch.tap()
            let tile = app.buttons["sticker.\(sticker)"]
            // Marks and tags sit below the fold, under your own stickers, the notes and the doodles.
            for _ in 0..<4 where !tile.waitForExistence(timeout: 3) { app.scrollViews["sticker.drawer"].swipeUp() }
            XCTAssertTrue(tile.waitForExistence(timeout: 10))
            if sticker == "noteYellow" { attach(app, "sticker-drawer") }
            tile.tap()
        }
        add("noteYellow")
        let note = app.images["Sticker, Yellow Sticky Note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        let done = app.buttons["editor.arrange.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "a new sticker arrives selected")
        let start = note.frame
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25)), withVelocity: 300, thenHoldForDuration: 0.1)
        XCTAssertLessThan(note.frame.midY, start.midY - 40, "dragging the selected sticker moves it")
        XCTAssertEqual(strokeCount(canvas), 0, "and draws nothing")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))

        drag(on: canvas, y: 0.22)
        XCTAssertEqual(strokeCount(canvas), 1, "ink goes over the sticker once it's put down")
        add("rainbow")
        add("stampImportant")
        app.buttons["Done"].firstMatch.tap()
        attach(app, "stickers-on-page")

        note.press(forDuration: 0.8)
        XCTAssertTrue(done.waitForExistence(timeout: 5), "touch and hold picks it up again")
        XCTAssertEqual(strokeCount(canvas), 1, "the hold leaves no dot")
        attach(app, "sticker-selected")
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 5))
        app.buttons["editor.undo"].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5), "deleting is one undo step")
    }

    func testWidgetLinksOpenTheRightNotebook() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "modes", "-resetStorage", "-seedLibrary", "3", "-seedJournal", "-drawingInput", "anyInput"]
        app.launch()
        XCTAssertTrue(app.buttons["notebook.Physics II 3"].waitForExistence(timeout: 30))

        app.open(URL(string: "swiftscribe://quicknote")!)
        let title = app.buttons["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "a quick note opens straight into the editor")
        XCTAssertTrue(title.label.hasPrefix("Note "), title.label)

        app.open(URL(string: "swiftscribe://today")!)
        let journal = NSPredicate(format: "label BEGINSWITH %@", "Journal")
        wait(for: [expectation(for: journal, evaluatedWith: title)], timeout: 30)
        XCTAssertEqual(app.buttons["editor.ribbon"].label, "Page 4 of 4", "the note is put away and the journal opens on today's new page")

        app.open(URL(string: "swiftscribe://today")!)
        sleep(2)
        XCTAssertEqual(app.buttons["editor.ribbon"].label, "Page 4 of 4", "asking again adds nothing")
    }

    func testAPictureFromPhotosLandsOnThePage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "modes", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput"]
        app.launch()
        let notebook = app.buttons["notebook.Physics II 3"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        XCTAssertTrue(app.descendants(matching: .any)["page.canvas.1"].waitForExistence(timeout: 20))
        app.buttons["Add"].firstMatch.tap()
        app.buttons["Picture on This Page…"].firstMatch.tap()
        let photo = app.scrollViews.images.firstMatch
        try XCTSkipUnless(photo.waitForExistence(timeout: 15), "this simulator's photo library is empty")
        photo.tap()
        let picture = app.images["Picture"]
        if !picture.waitForExistence(timeout: 20), photo.exists { photo.tap() }
        XCTAssertTrue(picture.waitForExistence(timeout: 30), "the photo is placed on the current page")
        XCTAssertTrue(app.buttons["editor.arrange.done"].waitForExistence(timeout: 5), "selected, ready to move")
        XCTAssertEqual(app.buttons["editor.ribbon"].label, "Page 1 of 3", "and no page was added")
        sleep(1)
        attach(app, "picture-on-page")
    }

    private func openNotebook(_ app: XCUIApplication, input: String) -> XCUIElement {
        app.launchArguments = ["-storageRoot", "modes", "-resetStorage", "-seedLibrary", "3", "-drawingInput", input]
        app.launch()
        let notebook = app.buttons["notebook.Physics II 3"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        let canvas = app.descendants(matching: .any)["page.canvas.1"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        return canvas
    }

    func testATextBoxCanBeTypedStyledAndEdited() throws {
        let app = XCUIApplication()
        let canvas = openNotebook(app, input: "anyInput")
        let strokes = strokeCount(canvas)

        app.buttons["Add"].firstMatch.tap()
        app.buttons["Text Box"].firstMatch.tap()
        let editor = app.textViews["page.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "a new text box opens ready to type in")
        editor.typeText("Molar mass")
        attach(app, "text-typing")
        let done = app.buttons["editor.arrange.done"]
        done.tap()
        let text = app.staticTexts["Molar mass"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "what was typed stays on the page")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertEqual(strokeCount(canvas), strokes, "typing draws nothing")

        text.press(forDuration: 0.8)
        XCTAssertTrue(done.waitForExistence(timeout: 5), "touch and hold picks the box up")
        let before = text.frame
        app.buttons["editor.arrange.style"].tap()
        let title = app.buttons["Title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        XCTAssertGreaterThan(text.frame.height, before.height * 1.5, "a larger size makes a taller box")
        attach(app, "text-selected")

        app.buttons["editor.arrange.edit"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText(" of water")
        done.tap()
        XCTAssertTrue(app.staticTexts["Molar mass of water"].waitForExistence(timeout: 5))
        app.buttons["editor.undo"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5), "an edit is one undo step")
        sleep(1)
        attach(app, "text-on-page")

        app.buttons["Add"].firstMatch.tap()
        app.buttons["Text Box"].firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "")).count, 0, "a box left empty isn't kept")
        XCTAssertTrue(text.exists)
    }

    func testALinkOpensItsPageAndComesBack() throws {
        let app = XCUIApplication()
        _ = openNotebook(app, input: "pencilOnly")
        let ribbon = app.buttons["editor.ribbon"]

        app.buttons["Add"].firstMatch.tap()
        app.buttons["Link to a Page…"].firstMatch.tap()
        let target = app.buttons["link.page.3"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["link.page.1"].isEnabled, "a page can't link to itself")
        attach(app, "link-picker")
        target.tap()
        let link = app.links["Link to Page 3"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        let done = app.buttons["editor.arrange.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "a new link arrives selected")
        attach(app, "link-selected")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))

        link.tap()
        let label = NSPredicate(format: "label == %@", "Page 3 of 3")
        wait(for: [expectation(for: label, evaluatedWith: ribbon)], timeout: 10)
        let back = app.buttons["editor.link.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the way back is offered")
        attach(app, "link-followed")
        back.tap()
        wait(for: [expectation(for: NSPredicate(format: "label == %@", "Page 1 of 3"), evaluatedWith: ribbon)], timeout: 10)
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        sleep(1)
        attach(app, "link-on-page")
    }

    func testAStickerOfYourOwnIsMadeFromAPhoto() throws {
        let app = XCUIApplication()
        _ = openNotebook(app, input: "anyInput")
        app.buttons["Add"].firstMatch.tap()
        app.buttons["Sticker…"].firstMatch.tap()
        let new = app.buttons["sticker.new"]
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        attach(app, "sticker-drawer-own-empty")
        new.tap()
        let photo = app.scrollViews.images.matching(NSPredicate(format: "label CONTAINS[c] %@", "photo")).firstMatch
        try XCTSkipUnless(photo.waitForExistence(timeout: 15), "this simulator's photo library is empty")
        photo.tap()
        let mine = app.buttons["sticker.mine.1"]
        let whole = app.buttons["Use Whole Photo"]
        if !mine.waitForExistence(timeout: 20), !whole.exists, photo.exists { photo.tap() }
        if !mine.waitForExistence(timeout: 20) {
            XCTAssertTrue(whole.waitForExistence(timeout: 20), "with no subject to lift, the whole photo is offered")
            whole.tap()
        }
        XCTAssertTrue(mine.waitForExistence(timeout: 20), "the new sticker is kept in the drawer")
        sleep(1)
        attach(app, "sticker-drawer-own")
        mine.tap()
        let placed = app.images["Sticker"]
        XCTAssertTrue(placed.waitForExistence(timeout: 20), "and lands on the page")
        XCTAssertTrue(app.buttons["editor.arrange.done"].waitForExistence(timeout: 5))
        sleep(1)
        let before = placed.frame
        let handle = app.descendants(matching: .any)["Resize and rotate"].firstMatch
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx: 2.5, dy: 2.2)), withVelocity: 200, thenHoldForDuration: 0.2)
        XCTAssertGreaterThan(placed.frame.width, before.width * 1.2, "the handle makes it larger")
        sleep(1)
        attach(app, "sticker-own-on-page")
    }

    func testPresentingTakesOverASecondScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "modes", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput", "-secondScreenInset"]
        app.launch()
        let notebook = app.buttons["notebook.Physics II 3"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        let canvas = app.descendants(matching: .any)["page.canvas.1"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        let stage = app.images["presentation.stage.page"]
        XCTAssertFalse(stage.exists, "nothing is put on the second screen until presenting starts")

        app.buttons["More"].firstMatch.tap()
        app.buttons["Present"].firstMatch.tap()
        let done = app.buttons["editor.present.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["editor.present.screen"].waitForExistence(timeout: 5), "the bar says the second screen is in use")
        XCTAssertTrue(stage.waitForExistence(timeout: 10), "the page goes up on the second screen")
        sleep(1)
        let whole = stage.frame
        XCTAssertEqual(whole.height, 270, accuracy: 2, "the whole page, as tall as the screen")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)), withVelocity: 600, thenHoldForDuration: 0.2)
        attach(app, "second-screen")

        canvas.pinch(withScale: 3, velocity: 1.5)
        sleep(1)
        attach(app, "second-screen-zoomed")
        XCTAssertGreaterThan(stage.frame.height, whole.height * 1.08, "zooming in on the iPad zooms the second screen")

        app.buttons["editor.present.next"].tap()
        XCTAssertTrue(app.staticTexts["Page 2 of 3"].waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertEqual(stage.frame.height, 270, accuracy: 2, "the next page is shown whole again")
        done.tap()
        XCTAssertTrue(stage.waitForNonExistence(timeout: 5), "the second screen is handed back when presenting ends")
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 5))
    }
}
