import XCTest

/// The app in its other languages. German is the long one, so it is the one looked at for text that no longer fits.
@MainActor
final class LocalizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ language: String, locale: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "languages", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        return app
    }

    private func tour(_ app: XCUIApplication, _ tag: String, settings: String, allNotebooks: String, undo: String) {
        let notebook = app.buttons["notebook.Physics II 3"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts[allNotebooks].firstMatch.waitForExistence(timeout: 10), "the library's heading is translated")
        sleep(1)
        attach(app, "\(tag)-library")

        notebook.tap()
        XCTAssertTrue(app.buttons["editor.ribbon"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["editor.undo"].label, undo)
        app.buttons["editor.title"].tap()
        sleep(1)
        attach(app, "\(tag)-title-menu")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
        app.buttons["editor.back"].tap()

        let gear = app.buttons[settings].firstMatch
        if !gear.waitForExistence(timeout: 10) || !gear.isHittable { app.buttons["ToggleSidebar"].firstMatch.tap() }
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        sleep(1)
        attach(app, "\(tag)-sidebar")
        gear.tap()
        XCTAssertTrue(app.navigationBars[settings].waitForExistence(timeout: 10), "Settings is translated")
        sleep(1)
        attach(app, "\(tag)-settings")
        app.swipeUp()
        sleep(1)
        attach(app, "\(tag)-settings-end")
    }

    func testTheAppSpeaksGerman() throws {
        tour(launch("de", locale: "de_DE"), "de", settings: "Einstellungen", allNotebooks: "Alle Notizbücher", undo: "Widerrufen")
    }

    func testTheAppSpeaksSpanish() throws {
        tour(launch("es", locale: "es_ES"), "es", settings: "Ajustes", allNotebooks: "Todos los cuadernos", undo: "Deshacer")
    }

    func testTheAppSpeaksFrench() throws {
        tour(launch("fr", locale: "fr_FR"), "fr", settings: "Réglages", allNotebooks: "Tous les carnets", undo: "Annuler")
    }
}
