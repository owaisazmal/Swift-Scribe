import XCTest

/// Frame pacing while scrolling a 500-notebook library and a 300-page PDF, read from the app's debug probe.
/// On the simulator this is a proxy for hitches; the device run with Instruments is the real measure.
@MainActor
final class ScrollPerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SCRIBE_PERF"] == "1", "Set SCRIBE_PERF=1 to run")
        continueAfterFailure = false
    }

    private func pacing(_ app: XCUIApplication, during work: () -> Void) -> String {
        app.buttons["debug.framePacing.reset"].tap()
        work()
        app.buttons["debug.framePacing.read"].tap()
        return app.staticTexts["debug.framePacing.summary"].label
    }

    /// Drives the scroll view from inside the app for 6 s, so XCUITest's per-gesture snapshots don't count as hitches.
    private func autoScroll(_ app: XCUIApplication) -> String {
        app.buttons["debug.framePacing.autoscroll"].tap()
        sleep(8)
        return app.staticTexts["debug.framePacing.summary"].label
    }

    func testScrollingFiveHundredNotebooks() {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "perf500", "-resetStorage", "-seedLibrary", "500", "-framePacing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["All notebooks"].firstMatch.waitForExistence(timeout: 60))
        sleep(3)
        let cold = pacing(app) {
            for _ in 0..<4 { app.swipeUp(velocity: .fast) }
            for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        }
        print("PERF-UI library 500 notebooks, 8 fast swipes, first visit (covers rendering): \(cold)")
        let warm = pacing(app) {
            for _ in 0..<4 { app.swipeUp(velocity: .fast) }
            for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        }
        print("PERF-UI library 500 notebooks, same 8 swipes again (covers cached): \(warm)")
        print("PERF-UI library 500 notebooks, in-app scroll 2,400 pt/s down and back, first pass: \(autoScroll(app))")
        print("PERF-UI library 500 notebooks, in-app scroll, second pass: \(autoScroll(app))")
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) { app.swipeUp(velocity: .fast) }
    }

    func testScrollingAndZoomingLongPDF() {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "perfpdf", "-resetStorage", "-seedLongPDF", "-framePacing", "-drawingInput", "pencilOnly"]
        app.launch()
        let notebook = app.buttons["notebook.Textbook"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 60))
        notebook.tap()
        XCTAssertTrue(app.descendants(matching: .any)["page.canvas.1"].waitForExistence(timeout: 20))
        sleep(2)
        let scroll = pacing(app) {
            for _ in 0..<6 { app.swipeUp(velocity: .fast) }
        }
        print("PERF-UI 300-page PDF, 6 fast swipes, first visit: \(scroll)")
        let back = pacing(app) {
            for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        }
        print("PERF-UI 300-page PDF, 6 fast swipes back over the same pages: \(back)")
        print("PERF-UI 300-page PDF, in-app scroll 2,400 pt/s down and back, first pass: \(autoScroll(app))")
        print("PERF-UI 300-page PDF, in-app scroll, second pass: \(autoScroll(app))")
        let zoom = pacing(app) {
            app.pinch(withScale: 2.5, velocity: 2)
            app.pinch(withScale: 0.5, velocity: -2)
        }
        print("PERF-UI 300-page PDF, pinch in and out: \(zoom)")
        let zoomAgain = pacing(app) {
            app.pinch(withScale: 2.5, velocity: 2)
            app.pinch(withScale: 0.5, velocity: -2)
        }
        print("PERF-UI 300-page PDF, pinch in and out again: \(zoomAgain)")
    }
}
