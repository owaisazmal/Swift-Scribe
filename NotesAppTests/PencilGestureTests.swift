import XCTest
import PencilKit
@testable import NotesApp

/// Scribble to erase, circle and hold to select, and what a double-tap of the Pencil does.
@MainActor
final class PencilGestureTests: XCTestCase {
    private func along(_ corners: [CGPoint], spacing: CGFloat = 4) -> [CGPoint] {
        var points: [CGPoint] = []
        for (a, b) in zip(corners, corners.dropFirst()) {
            let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) / spacing))
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps), wobble = sin(CGFloat(points.count) * 12.9898) * 1.2
                points.append(CGPoint(x: a.x + (b.x - a.x) * t + wobble, y: a.y + (b.y - a.y) * t - wobble))
            }
        }
        return points + [corners[corners.count - 1]]
    }

    /// Back and forth between x = `left` and x = `right`, drifting down from `top` by `drift` in all.
    private func scratch(left: CGFloat = 100, right: CGFloat = 220, top: CGFloat = 100, drift: CGFloat = 24, sweeps: Int = 8) -> [CGPoint] {
        along((0...sweeps).map { CGPoint(x: $0 % 2 == 0 ? left : right, y: top + drift * CGFloat($0) / CGFloat(sweeps)) })
    }

    private func curve(_ count: Int = 160, _ point: (CGFloat) -> CGPoint) -> [CGPoint] {
        (0...count).map { point(CGFloat($0) / CGFloat(count)) }
    }

    private func ring(centre: CGPoint, radius: CGFloat, turns: CGFloat = 1.03) -> [CGPoint] {
        curve(90) { CGPoint(x: centre.x + radius * cos($0 * turns * 2 * .pi), y: centre.y + radius * sin($0 * turns * 2 * .pi)) }
    }

    private func pen(_ points: [CGPoint], ink: PKInkingTool.InkType = .pen) -> PKStroke {
        let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.005, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSince1970: 1_790_000_100))
        return PKStroke(ink: PKInk(ink, color: .black), path: path)
    }

    private var mmm: [CGPoint] {
        curve { CGPoint(x: 100 + 90 * $0, y: 120 - 18 * abs(sin($0 * 6 * .pi))) }
    }

    private var www: [CGPoint] {
        along((0...12).map { CGPoint(x: 100 + 9 * CGFloat($0), y: $0 % 2 == 0 ? 100 : 124) })
    }

    private var spring: [CGPoint] {
        curve(300) { CGPoint(x: 100 + 150 * $0 + 14 * cos($0 * 16 * .pi), y: 120 + 14 * sin($0 * 16 * .pi)) }
    }

    func testAScratchingOutIsToldFromWriting() {
        XCTAssertTrue(ScribbleRecognizer.isZigzag(scratch()))
        XCTAssertGreaterThanOrEqual(ScribbleRecognizer.reversals(scratch()), 7)
        XCTAssertTrue(ScribbleRecognizer.isZigzag(scratch(sweeps: 6)), "five turns are enough")
        XCTAssertTrue(ScribbleRecognizer.isZigzag(scratch(left: 100, right: 130, top: 100, drift: 6)), "a small one over one letter")
        let slanted = scratch().map { ShapeRecognizer.rotate($0, about: CGPoint(x: 160, y: 110), by: 0.7) }
        XCTAssertTrue(ScribbleRecognizer.isZigzag(slanted), "whichever way it runs")
        let round = curve(400) { CGPoint(x: 160 + 50 * cos($0 * 10 * .pi) + 8 * $0, y: 110 + 12 * sin($0 * 10 * .pi)) }
        XCTAssertTrue(ScribbleRecognizer.isZigzag(round), "scratching in flat loops counts too")

        XCTAssertFalse(ScribbleRecognizer.isZigzag(scratch(sweeps: 4)), "a few passes could be a letter")
        XCTAssertFalse(ScribbleRecognizer.isZigzag(mmm))
        XCTAssertEqual(ScribbleRecognizer.reversals(mmm), 0)
        XCTAssertFalse(ScribbleRecognizer.isZigzag(www), "a row of letters runs one way along its length")
        XCTAssertFalse(ScribbleRecognizer.isZigzag(spring))
        XCTAssertFalse(ScribbleRecognizer.isZigzag(curve { CGPoint(x: 100 + 200 * $0, y: 150 + 5 * sin($0 * 14 * .pi)) }), "a wavy underline")
        XCTAssertFalse(ScribbleRecognizer.isZigzag(along([CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 110)])))
        XCTAssertFalse(ScribbleRecognizer.isZigzag(ring(centre: CGPoint(x: 200, y: 200), radius: 60)))
        XCTAssertFalse(ScribbleRecognizer.isZigzag(along([CGPoint(x: 100, y: 100), CGPoint(x: 104, y: 100), CGPoint(x: 100, y: 101), CGPoint(x: 104, y: 101)])), "a dot")
        XCTAssertFalse(ScribbleRecognizer.isZigzag([]))
    }

    func testAScribbleErasesOnlyTheInkUnderIt() {
        let word = [along([CGPoint(x: 110, y: 104), CGPoint(x: 118, y: 120)]), along([CGPoint(x: 130, y: 104), CGPoint(x: 150, y: 118)]),
                    along([CGPoint(x: 170, y: 106), CGPoint(x: 205, y: 116)])]
        let elsewhere = along([CGPoint(x: 100, y: 300), CGPoint(x: 220, y: 300)])
        let margin = along([CGPoint(x: 160, y: 20), CGPoint(x: 160, y: 700)])
        let beside = along([CGPoint(x: 226, y: 100), CGPoint(x: 232, y: 124)])
        XCTAssertEqual(ScribbleRecognizer.erased(by: scratch(), from: word + [elsewhere, margin, beside]), [0, 1, 2],
                       "ink elsewhere, a long line only crossed, and a stroke just beside the scribble all stay")
        XCTAssertEqual(ScribbleRecognizer.erased(by: scratch(), from: []), [], "on bare paper it is writing")
        XCTAssertEqual(ScribbleRecognizer.erased(by: scratch(), from: [elsewhere]), [])

        let thin = scratch(top: 110, drift: 2)
        XCTAssertEqual(ScribbleRecognizer.erased(by: thin, from: [along([CGPoint(x: 105, y: 114), CGPoint(x: 215, y: 115)])]), [0], "scratching along a line takes the line")

        let upright = scratch().map { ShapeRecognizer.rotate($0, about: CGPoint(x: 160, y: 112), by: .pi / 2) }
        XCTAssertEqual(ScribbleRecognizer.erased(by: upright, from: [scratch()]), [], "cross-hatching: shading over shading erases nothing")
        XCTAssertEqual(ScribbleRecognizer.erased(by: scratch(top: 104), from: [scratch()]), [], "nor does going over it again")

        let box = along([CGPoint(x: 96, y: 96), CGPoint(x: 224, y: 96), CGPoint(x: 224, y: 128), CGPoint(x: 96, y: 128), CGPoint(x: 96, y: 97)])
        XCTAssertEqual(ScribbleRecognizer.erased(by: scratch(left: 90, right: 230, top: 99), from: [box]), [], "a shape being filled in keeps its outline")
        let letter = ring(centre: CGPoint(x: 140, y: 112), radius: 9)
        XCTAssertEqual(ScribbleRecognizer.erased(by: scratch(), from: [letter]), [0], "an o in a word that is scratched out goes")

        for writing in [mmm, www, spring] {
            let under = [along([CGPoint(x: 110, y: 112), CGPoint(x: 180, y: 114)])]
            XCTAssertEqual(ScribbleRecognizer.erased(by: writing, from: under), [], "writing over ink is still writing")
            XCTAssertFalse(ScribbleRecognizer.covered(by: writing, in: under).isEmpty, "though it does lie over it")
        }
        let underline = curve { CGPoint(x: 100 + 120 * $0, y: 126 + 3 * sin($0 * 14 * .pi)) }
        XCTAssertEqual(ScribbleRecognizer.erased(by: underline, from: word), [])
    }

    func testStrokesAreErasedFromADrawing() throws {
        let drawing = PKDrawing(strokes: [stroke(from: CGPoint(x: 110, y: 110), to: CGPoint(x: 200, y: 114)),
                                          stroke(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 400)),
                                          stroke(from: CGPoint(x: 120, y: 104), to: CGPoint(x: 150, y: 120))])
        let erased = try XCTUnwrap(PencilGestures.erasing(pen(scratch()), from: drawing))
        XCTAssertEqual(erased.count, 2)
        XCTAssertEqual(erased.drawing.strokes.count, 1)
        XCTAssertEqual(erased.drawing.strokes[0].renderBounds.midY, 400, accuracy: 3)
        XCTAssertNil(PencilGestures.erasing(pen(scratch(top: 500)), from: drawing), "nothing under it: it stays as ink")
        XCTAssertNil(PencilGestures.erasing(pen(mmm), from: drawing))

        XCTAssertTrue(PencilGestures.writes(PKInkingTool(.pen)))
        XCTAssertTrue(PencilGestures.writes(PKInkingTool(.pencil)))
        XCTAssertTrue(PencilGestures.writes(PKInkingTool(.fountainPen)))
        XCTAssertFalse(PencilGestures.writes(PKInkingTool(.marker)), "highlighting goes back and forth over words")
        XCTAssertFalse(PencilGestures.writes(PKInkingTool(.crayon)))
        XCTAssertFalse(PencilGestures.writes(PKEraserTool(.vector)))
        XCTAssertFalse(PencilGestures.writes(PKLassoTool()))
        XCTAssertTrue(PencilGestures.scribbleErases && PencilGestures.circleSelects, "both are on until they are turned off")
    }

    func testALoopRoundInkSelectsItAndAnEmptyOneIsLeftToBecomeACircle() throws {
        XCTAssertNotNil(LoopRecognizer.outline(ring(centre: CGPoint(x: 200, y: 200), radius: 70)))
        XCTAssertNotNil(LoopRecognizer.outline(ring(centre: CGPoint(x: 200, y: 200), radius: 70, turns: 0.94)), "a loop that doesn't quite close")
        XCTAssertNotNil(LoopRecognizer.outline(along([CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 104), CGPoint(x: 296, y: 220), CGPoint(x: 98, y: 216), CGPoint(x: 101, y: 106)])))
        XCTAssertNil(LoopRecognizer.outline(ring(centre: CGPoint(x: 200, y: 200), radius: 70, turns: 0.6)), "an arc")
        XCTAssertNil(LoopRecognizer.outline(along([CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 110), CGPoint(x: 102, y: 103)])), "there and back goes round nothing")
        XCTAssertNil(LoopRecognizer.outline(ring(centre: CGPoint(x: 200, y: 200), radius: 6)), "too small")
        XCTAssertNil(LoopRecognizer.outline(scratch()))

        let drawing = PKDrawing(strokes: [stroke(from: CGPoint(x: 170, y: 190), to: CGPoint(x: 230, y: 195)), dot(at: CGPoint(x: 200, y: 215)),
                                          stroke(from: CGPoint(x: 100, y: 500), to: CGPoint(x: 300, y: 500))])
        let loop = pen(ring(centre: CGPoint(x: 200, y: 200), radius: 70))
        let outline = try XCTUnwrap(PencilGestures.outline(of: loop, roundInkIn: drawing))
        XCTAssertEqual(InkLasso.strokes(in: drawing, inside: outline), [0, 1])
        XCTAssertNil(PencilGestures.outline(of: pen(ring(centre: CGPoint(x: 450, y: 200), radius: 70)), roundInkIn: drawing), "nothing inside: shape snapping has it")
        XCTAssertNil(PencilGestures.outline(of: pen(ring(centre: CGPoint(x: 200, y: 500), radius: 40)), roundInkIn: drawing), "a line it only crosses isn't inside")
        XCTAssertNil(PencilGestures.outline(of: pen(along([CGPoint(x: 120, y: 150), CGPoint(x: 280, y: 250)])), roundInkIn: drawing), "a straight stroke is no loop")
    }

    func testTheToolIsPutBackWhenThePickerSwitchesOnATapMeantForSomethingElse() {
        var memory = PencilToolMemory()
        memory.select("pen", isEraser: false)
        XCTAssertNil(memory.pickerChanged(to: "marker", isEraser: false, at: 1), "a tool chosen by hand is kept")
        XCTAssertEqual(memory.current, "marker")
        XCTAssertEqual(memory.previous, "pen")

        XCTAssertNil(memory.tapped(at: 10), "nothing switched before the tap")
        XCTAssertEqual(memory.pickerChanged(to: "eraser", isEraser: true, at: 10.1), "marker", "the picker switched just after it: put the marker back")
        XCTAssertEqual(memory.current, "marker")
        XCTAssertNil(memory.pickerChanged(to: "marker", isEraser: false, at: 10.15), "putting it back is no change")
        XCTAssertNil(memory.pickerChanged(to: "eraser", isEraser: true, at: 10.2), "and one tap undoes one switch")
        XCTAssertNil(memory.pickerChanged(to: "marker", isEraser: false, at: 12))

        XCTAssertNil(memory.pickerChanged(to: "eraser", isEraser: true, at: 20))
        XCTAssertEqual(memory.tapped(at: 20.2), "marker", "the picker switched just before the tap")
        XCTAssertEqual(memory.current, "marker")
        XCTAssertEqual(memory.previous, "eraser", "and what came before the marker is as it was")

        XCTAssertNil(memory.pickerChanged(to: "pen", isEraser: false, at: 30))
        XCTAssertNil(memory.tapped(at: 31), "a switch a second ago was the user's own")
        XCTAssertNil(memory.pickerChanged(to: "pencil", isEraser: false, at: 32), "and so is one a second after")
        XCTAssertEqual(memory.current, "pencil")
    }

    func testTheEraserSwitchGoesBackToTheToolBeforeIt() {
        var memory = PencilToolMemory()
        XCTAssertEqual(memory.eraserSwitch(eraser: "eraser"), "eraser")
        memory.select("pen", isEraser: false)
        memory.select("pencil", isEraser: false)
        XCTAssertEqual(memory.eraserSwitch(eraser: "eraser"), "eraser")
        XCTAssertNil(memory.eraserSwitch(eraser: nil), "a picker with no eraser has nothing to switch to")
        memory.select("eraser", isEraser: true)
        memory.select("bigEraser", isEraser: true)
        XCTAssertEqual(memory.eraserSwitch(eraser: "eraser"), "pencil", "from one eraser to another, the tool before both is remembered")
        memory.select("pencil", isEraser: false)
        XCTAssertEqual(memory.eraserSwitch(eraser: "eraser"), "eraser")

        XCTAssertEqual(PencilAction.setting("pencil.test.unset"), .system)
        XCTAssertEqual(PencilAction.allCases.count, 6)
        XCTAssertEqual(Set(PencilAction.allCases.map(\.displayName)).count, 6)
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// The stroke-end path on a real canvas: the scribble never reaches the document, and one undo brings the ink back.
    func testAScribbleOnTheCanvasErasesAsOneUndoStepAndALoopStartsASelection() async throws {
        let root = temporaryRoot(self)
        let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)
        let manifest = NotebookManifest(title: "Gestures", defaults: paper, pages: [paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        let page = manifest.pages[0].id
        let written = [stroke(from: CGPoint(x: 110, y: 110), to: CGPoint(x: 200, y: 114)), stroke(from: CGPoint(x: 120, y: 104), to: CGPoint(x: 150, y: 120)),
                       stroke(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 400))]
        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: [page: PKDrawing(strokes: written)]))
        let document = try await NotebookDocument.open(manifest.id, root: root)
        let session = EditorSession(document: document)
        let controller = PageStackController(session: session)
        session.canvas = controller
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in window.isHidden = true }
        controller.view.layoutIfNeeded()
        for _ in 0..<100 where controller.canvas(forPage: 0)?.isLoaded != true { await pause(0.05) }
        let canvas = try XCTUnwrap(controller.canvas(forPage: 0))
        XCTAssertEqual(canvas.drawing.strokes.count, 3)

        canvas.tool = PKInkingTool(.marker, color: .yellow, width: 20)
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [pen(scratch(), ink: .marker)])
        await pause(0.2)
        XCTAssertEqual(document.loadedInk(page)?.strokes.count, 4, "the highlighter never erases")
        document.undoManager.undo()
        await pause(0.2)
        XCTAssertEqual(canvas.drawing.strokes.count, 3)

        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [pen(mmm)])
        await pause(0.2)
        XCTAssertEqual(document.loadedInk(page)?.strokes.count, 4, "writing over ink is kept")
        document.undoManager.undo()
        await pause(0.2)

        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [pen(scratch())])
        await pause(0.2)
        XCTAssertEqual(document.loadedInk(page)?.strokes.count, 1, "the scratched-out strokes and the scribble are gone")
        XCTAssertEqual(canvas.drawing.strokes.count, 1)
        XCTAssertEqual(document.undoManager.undoActionName, "Scribble Erase")
        document.undoManager.undo()
        await pause(0.2)
        XCTAssertEqual(document.loadedInk(page)?.strokes.count, 3, "one undo brings the ink back without the scribble")
        XCTAssertEqual(canvas.drawing.strokes.count, 3)
        document.undoManager.redo()
        await pause(0.2)
        XCTAssertEqual(canvas.drawing.strokes.count, 1)
        document.undoManager.undo()
        await pause(0.2)

        let frame = PageStackLayout(pages: document.pages).frames[0]
        let loop = ring(centre: CGPoint(x: 155, y: 112), radius: 70).map { CGPoint(x: $0.x + frame.minX, y: $0.y + frame.minY) }
        session.selectInk(inside: loop)
        XCTAssertEqual(session.mode, .selecting)
        XCTAssertEqual(session.inkSelectionCount, 2, "the ink inside the loop is caught as the selection starts")
        XCTAssertEqual(document.loadedInk(page)?.strokes.count, 3)
        controller.deleteInkSelection()
        XCTAssertEqual(document.loadedInk(page)?.strokes.count, 1, "and the ink bar's actions apply to it")
        session.enter(.writing)
        XCTAssertEqual(session.inkSelectionCount, 0)
    }
}
