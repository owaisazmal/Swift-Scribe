import XCTest

/// The Phase 2 vertical slice: launch, library, new notebook, write, autosave, back, relaunch, and a migrated v1 notebook.
@MainActor
final class SliceUITests: XCTestCase {
    private let root = "slice"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(reset: Bool, seed: Bool = false, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", root, "-drawingInput", "anyInput"] + (reset ? ["-resetStorage"] : []) + (seed ? ["-seedV1Fixture"] : []) + extra
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Runs the audit. Contrast and Dynamic Type issues on the system Liquid Glass navigation bar are logged instead
    /// of failing: the audit can't measure text on glass (the flagged "Select" measured 7.7:1 in the rendered screenshot),
    /// and system bars cap their text size by design and offer the Large Content Viewer instead.
    @available(iOS 17.0, *)
    private func audit(_ app: XCUIApplication, _ types: XCUIAccessibilityAuditType) throws {
        let barMaxY = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? 0
        try app.performAccessibilityAudit(for: types) { issue in
            print("AUDIT issue: \(issue.compactDescription) | element: \(issue.element.map { String($0.elementType.rawValue) } ?? "-") '\(issue.element?.label ?? "nil")' \(issue.element?.frame ?? .zero)")
            if issue.auditType == .contrast || issue.auditType == .dynamicType, let element = issue.element, element.frame.maxY <= barMaxY + 1 {
                print("AUDIT ignored \(issue.auditType == .contrast ? "contrast" : "dynamic type") on system bar element: \(element.label)")
                return true
            }
            return false
        }
    }

    private func waitForLibrary(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["All notebooks"].firstMatch.waitForExistence(timeout: 30), "library heading")
    }

    private func write(_ strokes: Int, on canvas: XCUIElement) {
        for index in 0..<strokes {
            let y = 0.18 + Double(index) * 0.06
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: y))
                .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: y + 0.01)),
                       withVelocity: 400, thenHoldForDuration: 0.05)
        }
    }

    private func strokeCount(_ canvas: XCUIElement) -> Int {
        let value = (canvas.value as? String) ?? ""
        return Int(value.split(separator: " ").first ?? "") ?? 0
    }

    func testVerticalSlice() throws {
        var app = launch(reset: true, seed: true)
        waitForLibrary(app)
        let migrated = app.buttons["notebook.Migrated Lecture"]
        XCTAssertTrue(migrated.waitForExistence(timeout: 10), "the v1 notebook is migrated at launch")
        attach(app, "library-light")
        if #available(iOS 17.0, *) { try audit(app, [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription]) }

        app.buttons["New"].firstMatch.tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText("Slice Test")
        app.buttons["Print"].firstMatch.tap()
        attach(app, "new-notebook-print")
        app.buttons["Create"].firstMatch.tap()

        let canvas = app.descendants(matching: .any)["page.canvas.1"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 15), "the editor opens on page 1")
        write(3, on: canvas)
        XCTAssertEqual(strokeCount(canvas), 3)
        attach(app, "editor-written")
        if #available(iOS 17.0, *) { try audit(app, [.contrast, .elementDetection, .sufficientElementDescription]) }
        sleep(3)

        app.buttons["editor.back"].tap()
        waitForLibrary(app)
        let created = app.buttons["notebook.Slice Test"]
        XCTAssertTrue(created.waitForExistence(timeout: 10))
        XCTAssertTrue(created.label.contains("1 page"), created.label)

        app.terminate()
        app = launch(reset: false)
        waitForLibrary(app)
        XCTAssertTrue(app.buttons["notebook.Slice Test"].waitForExistence(timeout: 10), "the notebook survives a relaunch")
        app.buttons["notebook.Slice Test"].tap()
        let reopened = app.descendants(matching: .any)["page.canvas.1"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(5)
        while strokeCount(reopened) < 3, Date() < deadline { usleep(200_000) }
        XCTAssertEqual(strokeCount(reopened), 3, "the ink survives a relaunch")
        app.buttons["editor.back"].tap()
        waitForLibrary(app)

        app.buttons["notebook.Migrated Lecture"].tap()
        let migratedPage = app.descendants(matching: .any)["page.canvas.1"]
        XCTAssertTrue(migratedPage.waitForExistence(timeout: 15))
        XCTAssertEqual(strokeCount(migratedPage), 2, "migrated ink lands on its own page")
        XCTAssertTrue(app.buttons["editor.ribbon"].label.contains("of 3"), app.buttons["editor.ribbon"].label)
        attach(app, "migrated-notebook")
    }

    /// Runs only on an iPhone destination: every cover swatch in New Notebook must be on screen, not clipped off a narrow sheet.
    func testNewNotebookSwatchesFitOnIPhone() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone layout check")
        let app = launch(reset: true)
        let new = app.buttons["New"].firstMatch
        if !new.waitForExistence(timeout: 10) { app.cells.firstMatch.tap() }
        XCTAssertTrue(new.waitForExistence(timeout: 10), "the shelf and its New button")
        new.tap()
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 10))
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        app.buttons["Cloth"].firstMatch.tap()
        let screen = app.windows.firstMatch.frame
        for name in ["Oxblood", "Tomato", "Mustard", "Moss", "Jade", "Cobalt", "Navy", "Slate", "Rose", "Oat"] {
            let swatch = app.buttons[name].firstMatch
            XCTAssertTrue(swatch.exists, name)
            XCTAssertTrue(screen.contains(swatch.frame), "\(name) at \(swatch.frame) is outside \(screen)")
        }
        attach(app, "new-notebook-iphone")
    }

    func testDarkModeAndLargestTextScreenshots() throws {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        var app = launch(reset: true, seed: true)
        waitForLibrary(app)
        _ = app.buttons["notebook.Migrated Lecture"].waitForExistence(timeout: 10)
        attach(app, "library-dark")
        app.buttons["notebook.Migrated Lecture"].tap()
        _ = app.descendants(matching: .any)["page.canvas.1"].waitForExistence(timeout: 15)
        sleep(1)
        attach(app, "editor-dark")
        app.terminate()

        XCUIDevice.shared.appearance = .light
        app = launch(reset: false, extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["notebook.Migrated Lecture"].waitForExistence(timeout: 30) || app.staticTexts["Migrated Lecture"].waitForExistence(timeout: 5))
        attach(app, "library-largest-text")
        if #available(iOS 17.0, *) { try audit(app, [.dynamicType, .textClipped]) }
    }
}
