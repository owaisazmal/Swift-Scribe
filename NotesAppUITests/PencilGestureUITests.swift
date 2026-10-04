import XCTest

/// Scribble to erase and circle and hold to select, on a real canvas. XCUITest can only drag in straight lines, so
/// `-fakePencilGestures` lets a straight stroke stand in for the zigzag and for the loop.
@MainActor
final class PencilGestureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func strokeCount(_ canvas: XCUIElement) -> Int {
        Int(((canvas.value as? String) ?? "").split(separator: " ").first ?? "") ?? 0
    }

    func testAScribbleErasesAndALoopSelects() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-storageRoot", "gestures", "-resetStorage", "-seedLibrary", "3", "-drawingInput", "anyInput", "-fakePencilGestures", "-freshToolPresets"]
        app.launch()
        let notebook = app.buttons["notebook.Physics II 3"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 30))
        notebook.tap()
        let canvas = app.descendants(matching: .any)["page.canvas.1"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        // The picker keeps the tool another test left it with, and a highlighter never erases: take up a pen.
        app.buttons["editor.tools.1"].tap()
        let undo = app.buttons["editor.undo"]
        func draw(_ from: CGVector, _ to: CGVector, hold: TimeInterval = 0.05) {
            canvas.coordinate(withNormalizedOffset: from).press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: to), withVelocity: 400, thenHoldForDuration: hold)
        }
        let start = strokeCount(canvas)

        draw(CGVector(dx: 0.25, dy: 0.3), CGVector(dx: 0.7, dy: 0.3))
        draw(CGVector(dx: 0.25, dy: 0.5), CGVector(dx: 0.7, dy: 0.5))
        XCTAssertEqual(strokeCount(canvas), start + 2)

        draw(CGVector(dx: 0.25, dy: 0.3), CGVector(dx: 0.7, dy: 0.3))
        XCTAssertEqual(strokeCount(canvas), start + 1, "a stroke over the first line takes it away, and is not kept itself")
        undo.tap()
        XCTAssertEqual(strokeCount(canvas), start + 2, "one undo brings the line back without the scribble")
        draw(CGVector(dx: 0.25, dy: 0.7), CGVector(dx: 0.7, dy: 0.7))
        XCTAssertEqual(strokeCount(canvas), start + 3, "and writing on doesn't bring the scribble back")

        draw(CGVector(dx: 0.15, dy: 0.45), CGVector(dx: 0.8, dy: 0.55), hold: 1.2)
        let status = app.staticTexts["editor.ink.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), "a held loop round ink starts selecting")
        XCTAssertEqual(status.label, "1 stroke. Drag it to move it.")
        XCTAssertEqual(strokeCount(canvas), start + 3, "and the loop is not kept as ink")
        app.buttons["editor.ink.delete"].tap()
        XCTAssertEqual(strokeCount(canvas), start + 2)
        app.buttons["editor.ink.done"].tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertEqual(strokeCount(canvas), start + 3, "undo brings back what was deleted")
        undo.tap()
        XCTAssertEqual(strokeCount(canvas), start + 2, "and then goes straight to the stroke before the loop: the loop left no step")
        draw(CGVector(dx: 0.25, dy: 0.8), CGVector(dx: 0.7, dy: 0.8))
        XCTAssertEqual(strokeCount(canvas), start + 3, "writing carries on, and the loop doesn't come back")
    }
}
