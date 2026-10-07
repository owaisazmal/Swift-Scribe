import XCTest

/// A recording is transcribed, its lines lead the replay, and search finds what was said.
@MainActor
final class TranscriptUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testARecordingIsTranscribedAndItsLinesLeadTheReplay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "transcript", "-resetStorage", "-seedLibrary", "2", "-seedReplay", "-fakeTranscript", "-drawingInput", "anyInput"]
        app.launch()
        let notebook = app.buttons["notebook.Lecture Replay"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        XCTAssertTrue(app.descendants(matching: .any)["page.canvas.1"].waitForExistence(timeout: 20))

        app.buttons["Recordings"].firstMatch.tap()
        let open = app.buttons["recording.transcript.1"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        XCTAssertEqual(open.value as? String, "Not transcribed")
        open.tap()
        let start = app.buttons["transcript.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        attach(app, "transcript-offer")
        start.tap()
        let second = app.buttons["transcript.line.2"]
        XCTAssertTrue(second.waitForExistence(timeout: 15), "the recording is written down")
        XCTAssertEqual(app.buttons["transcript.line.1"].label, "0:01, Today we cover the cell membrane.")
        attach(app, "transcript-written")

        second.tap()
        let bar = app.descendants(matching: .any)["editor.replay.bar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "a line starts the replay")
        app.buttons["editor.replay.play"].tap()
        let position = app.sliders["editor.replay.position"]
        XCTAssertTrue((position.value as? String ?? "").hasPrefix("0:0"), "\(String(describing: position.value))")
        XCTAssertFalse((position.value as? String ?? "").hasPrefix("0:00"), "from that line's moment, not from the start")
        let panel = app.descendants(matching: .any)["replay.transcript"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "what was said sits beside the page")
        XCTAssertTrue(app.buttons["transcript.line.2"].isSelected, "with the line being said marked")
        sleep(1)
        attach(app, "replay-with-transcript")

        app.buttons["transcript.line.3"].tap()
        XCTAssertTrue((position.value as? String ?? "").hasPrefix("0:11"), "a tap on a line jumps the sound there: \(String(describing: position.value))")
        XCTAssertTrue(app.buttons["transcript.line.3"].isSelected)
        XCTAssertEqual(bar.value as? String, "3 of 5 strokes written", "and the ink follows")

        app.buttons["editor.replay.transcript"].tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        app.buttons["editor.replay.done"].tap()
        let back = app.buttons["editor.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()

        XCTAssertTrue(notebook.waitForExistence(timeout: 20))
        let field = app.openLibrarySearch()
        field.typeText("membrane")
        let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Lecture Replay, recording 1'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 15), "search finds what was said")
        attach(app, "transcript-search")
    }
}
