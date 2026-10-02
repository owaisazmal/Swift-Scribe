import XCTest

/// Folders inside folders, from the sidebar.
@MainActor
final class FoldersUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAFolderCanHoldFolders() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "folders", "-resetStorage", "-seedLibrary", "12"]
        app.launch()
        XCTAssertTrue(app.buttons["notebook.Physics II 3"].waitForExistence(timeout: 30))
        let physics = app.descendants(matching: .any)["folder.Physics"]
        func showSidebar() {
            guard !physics.isHittable else { return }
            app.buttons["ToggleSidebar"].firstMatch.tap()
            XCTAssertTrue(physics.waitForExistence(timeout: 10))
        }
        showSidebar()
        physics.press(forDuration: 1)
        let inside = app.buttons["New Folder Inside"]
        XCTAssertTrue(inside.waitForExistence(timeout: 5))
        inside.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Labs")
        app.buttons["Create"].tap()
        let labs = app.descendants(matching: .any)["folder.Labs"]
        XCTAssertTrue(labs.waitForExistence(timeout: 5), "the new folder is listed under its parent")
        XCTAssertGreaterThan(labs.frame.minY, physics.frame.minY)
        XCTAssertEqual(labs.value as? String, "Inside Physics")
        attach(app, "folders-nested")

        physics.tap()
        let notebook = app.buttons["notebook.Genetics 7"]
        if !notebook.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertTrue(notebook.waitForExistence(timeout: 10))
        notebook.press(forDuration: 1)
        app.buttons["Move to Shelf"].tap()
        let target = app.buttons["Physics › Labs"]
        XCTAssertTrue(target.waitForExistence(timeout: 5), "the move menu names folders by their path")
        target.tap()
        XCTAssertTrue(notebook.waitForExistence(timeout: 5), "a folder still shows what is in the folders inside it")
        showSidebar()
        XCTAssertTrue(physics.label.contains("1 notebook"), physics.label)
        labs.tap()
        XCTAssertTrue(notebook.waitForExistence(timeout: 5))
        attach(app, "folders-inside")

        showSidebar()
        labs.press(forDuration: 1)
        app.buttons["Delete Folder"].tap()
        XCTAssertTrue(labs.waitForNonExistence(timeout: 5))
        physics.tap()
        XCTAssertTrue(notebook.waitForExistence(timeout: 5), "deleting the folder moves its notebook up, not out")
    }
}
