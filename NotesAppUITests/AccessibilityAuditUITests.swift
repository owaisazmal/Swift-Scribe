import XCTest

/// Apple's full accessibility audit on every main screen in light, dark and both with Increase Contrast,
/// then Dynamic Type, clipping and contrast again at a large text size, where the list layouts take over.
@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    private static let colourChecks: XCUIAccessibilityAuditType = .all
    private static let textSizeChecks: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .contrast]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testAuditLight() throws { try tour("light", appearance: .light, checks: Self.colourChecks) }
    func testAuditDark() throws { try tour("dark", appearance: .dark, checks: Self.colourChecks) }
    func testAuditLightIncreaseContrast() throws { try tour("light+IC", appearance: .light, checks: Self.colourChecks, extra: ["-increaseContrast"]) }
    func testAuditDarkIncreaseContrast() throws { try tour("dark+IC", appearance: .dark, checks: Self.colourChecks, extra: ["-increaseContrast"]) }
    func testAuditLargeText() throws {
        try tour("AX-L", appearance: .light, checks: Self.textSizeChecks,
                 extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
    }

    private func tour(_ mode: String, appearance: XCUIDevice.Appearance, checks: XCUIAccessibilityAuditType, extra: [String] = []) throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.appearance = appearance
        addTeardownBlock { @MainActor in
            XCUIDevice.shared.appearance = .light
            XCUIDevice.shared.orientation = .portrait
        }
        let empty = XCUIApplication()
        empty.launchArguments = ["-storageRoot", "audit-empty", "-resetStorage"] + extra
        empty.launch()
        XCTAssertTrue(empty.buttons["Import PDF"].firstMatch.waitForExistence(timeout: 30))
        try audit(empty, checks, screen: "\(mode) empty library")
        empty.terminate()

        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "audit", "-resetStorage", "-seedLibrary", "6", "-seedLongPDF", "-indexSeed", "-drawingInput", "anyInput"] + extra
        app.launch()
        let textbook = app.buttons["notebook.Textbook"]
        XCTAssertTrue(textbook.waitForExistence(timeout: 90))
        sleep(1)

        func check(_ screen: String, modal: Bool = false, scrolled: Bool = false, formEnd: [String] = []) throws {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "\(mode) \(screen)"
            attachment.lifetime = .keepAlways
            add(attachment)
            try audit(app, checks, screen: "\(mode) \(screen)", modal: modal, scrolled: scrolled, formEnd: formEnd)
        }

        /// Audits a sheet at the top, then again scrolled to the end, so text below the fold is checked while it's on screen.
        func checkSheet(_ screen: String, scrolling container: XCUIElement, formEnd: [String] = []) throws {
            try check(screen, modal: true, formEnd: formEnd)
            guard container.exists else { return }
            container.swipeUp(velocity: .fast)
            container.swipeUp(velocity: .fast)
            sleep(3)
            try check("\(screen) (end)", modal: true, scrolled: true, formEnd: formEnd)
        }

        func dismissKeyboard() {
            let keyboard = app.keyboards.firstMatch
            guard keyboard.waitForExistence(timeout: 3), keyboard.frame.intersects(app.windows.firstMatch.frame) else { sleep(1); return }
            let hide = app.keyboards.buttons["Hide keyboard"]
            let hittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: hide)
            wait(for: [hittable], timeout: 5)
            hide.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "audit without the keyboard over the screen")
            sleep(1)
        }

        try check("library")

        let field = app.searchFields.firstMatch
        if !field.exists { app.buttons["Search"].firstMatch.tap() }
        field.tap()
        field.typeText("Chapter 142")
        field.typeText("\n")
        let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Textbook, page 142:")).firstMatch
        for _ in 0..<4 where !hit.waitForExistence(timeout: 5) { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.6)).press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.25))) }
        XCTAssertTrue(hit.exists)
        try check("search")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-resetStorage" }
        app.launch()
        XCTAssertTrue(textbook.waitForExistence(timeout: 30))
        sleep(3)

        func sidebar(_ title: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        }
        sidebar("Recently deleted").tap()
        sleep(1)
        try check("recently deleted")
        sidebar("All notebooks").tap()

        app.buttons["New"].firstMatch.tap()
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 30))
        dismissKeyboard()
        sleep(1)
        try checkSheet("new notebook", scrolling: app.scrollViews.firstMatch)
        app.buttons["Cancel"].firstMatch.tap()

        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        sleep(1)
        try checkSheet("settings", scrolling: app.collectionViews.firstMatch,
                       formEnd: ["Report a Problem or Request a Feature", "Swift Scribe is free and open source"])
        app.buttons["Done"].firstMatch.tap()

        textbook.press(forDuration: 1.2)
        let changeCover = app.buttons["Change Cover…"].firstMatch
        XCTAssertTrue(changeCover.waitForExistence(timeout: 5))
        changeCover.tap()
        XCTAssertTrue(app.navigationBars["Change Cover"].waitForExistence(timeout: 10))
        sleep(1)
        try checkSheet("change cover", scrolling: app.scrollViews.firstMatch)
        app.buttons["Cancel"].firstMatch.tap()

        textbook.tap()
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20))
        sleep(1)
        try check("editor")
        app.buttons["Pages"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        try check("page navigator", modal: true)
        app.buttons["Done"].firstMatch.tap()
        app.buttons["Recordings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No Recordings"].firstMatch.waitForExistence(timeout: 5))
        try check("recordings", modal: true)
    }
}
