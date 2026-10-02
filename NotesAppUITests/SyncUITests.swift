import XCTest

/// Sync, with a folder standing in for iCloud and two storage roots standing in for two iPads.
@MainActor
final class SyncUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["Settings"].firstMatch
        if !settings.waitForExistence(timeout: 10) || !settings.isHittable { app.buttons["ToggleSidebar"].firstMatch.tap() }
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
    }

    func testALibraryArrivesOnASecondDevice() throws {
        XCUIDevice.shared.orientation = .portrait
        let first = XCUIApplication()
        first.launchArguments = ["-storageRoot", "syncA", "-resetStorage", "-seedLibrary", "3", "-cloudFolder", "ui", "-resetCloud", "-syncsWithICloud", "YES"]
        first.launch()
        XCTAssertTrue(first.buttons["notebook.Physics II 3"].waitForExistence(timeout: 30))
        openSettings(first)
        let status = first.staticTexts["settings.sync.status"]
        for _ in 0..<6 where !status.exists { first.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 30), "the first sync finishes")
        attach(first, "sync-settings")
        first.terminate()

        let second = XCUIApplication()
        second.launchArguments = ["-storageRoot", "syncB", "-resetStorage", "-cloudFolder", "ui", "-syncsWithICloud", "YES"]
        second.launch()
        XCTAssertTrue(second.buttons["notebook.Physics II 3"].waitForExistence(timeout: 60), "an empty library fills from the synced copy")
        XCTAssertTrue(second.buttons["notebook.Cell Biology 1"].exists)
        XCTAssertTrue(second.buttons["notebook.Studio Notes 2"].exists)
        sleep(1)
        attach(second, "sync-arrived")
        openSettings(second)
        let received = second.staticTexts["settings.sync.status"]
        for _ in 0..<6 where !received.exists { second.swipeUp() }
        XCTAssertTrue(received.waitForExistence(timeout: 30))
        XCTAssertTrue(received.label.contains("3 notebooks received") || received.label.contains("up to date"), received.label)
    }

    func testSyncSaysWhyItIsUnavailable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "syncNone", "-resetStorage", "-seedLibrary", "3"]
        app.launch()
        XCTAssertTrue(app.buttons["notebook.Physics II 3"].waitForExistence(timeout: 30))
        openSettings(app)
        let toggle = app.switches["settings.sync.toggle"]
        for _ in 0..<6 where !toggle.exists { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertFalse(toggle.isEnabled, "without iCloud the switch can't be turned on")
        attach(app, "sync-unavailable")
    }
}
