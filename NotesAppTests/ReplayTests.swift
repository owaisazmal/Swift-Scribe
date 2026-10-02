import XCTest
import PencilKit
@testable import NotesApp

/// Replaying a recording with its ink: which strokes belong to it, what is faint at a given moment, and the transport.
@MainActor
final class ReplayTests: XCTestCase {
    private let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func recording(duration: TimeInterval = 20, file: String = "talk.wav") -> RecordingEntry {
        var entry = RecordingEntry(id: UUID(), file: file, createdAt: start.addingTimeInterval(duration), duration: duration)
        entry.startedAt = start
        return entry
    }

    private func stroke(y: CGFloat, at offset: TimeInterval) -> PKStroke {
        ReplaySeed.stroke(y: y, at: start.addingTimeInterval(offset))
    }

    func testOnlyInkWrittenDuringTheRecordingIsOnItsTimeline() {
        let first = UUID(), second = UUID()
        let drawings = [first: PKDrawing(strokes: [stroke(y: 100, at: -60), stroke(y: 200, at: 6), stroke(y: 300, at: 2), stroke(y: 400, at: 900)]),
                        second: PKDrawing(strokes: [stroke(y: 100, at: 14), stroke(y: 200, at: 20.2)])]
        let timeline = ReplayTimeline(recording: recording(), drawings: drawings)
        XCTAssertEqual(timeline.marks.map(\.time), [2, 6, 14, 20], "in the order written; a stroke begun as recording stopped counts at its end")
        XCTAssertEqual(timeline.marks.map(\.stroke), [2, 1, 0, 1])
        XCTAssertTrue(timeline.hasInk(onPage: first))

        XCTAssertEqual(timeline.written(by: 0), 0)
        XCTAssertEqual(timeline.written(by: 6), 2)
        XCTAssertEqual(timeline.written(by: 99), 4)
        XCTAssertEqual(timeline.pending(onPage: first, at: 0), [1, 2], "ink from before or after the recording is never faint")
        XCTAssertEqual(timeline.pending(onPage: first, at: 3), [1])
        XCTAssertEqual(timeline.pending(onPage: first, at: 6), [])
        XCTAssertEqual(timeline.pending(onPage: second, at: 6), [0, 1])
        XCTAssertEqual(timeline.page(at: 0), first, "before any ink, the page the first stroke is on")
        XCTAssertEqual(timeline.page(at: 13.9), first)
        XCTAssertEqual(timeline.page(at: 14), second)
        XCTAssertEqual(timeline.time(ofStroke: 1, onPage: first), 6)
        XCTAssertNil(timeline.time(ofStroke: 0, onPage: first), "a stroke from before the recording has no moment to jump to")
        XCTAssertTrue(ReplayTimeline(recording: recording(), drawings: [first: PKDrawing(strokes: [stroke(y: 100, at: -60)])]).isEmpty)
    }

    func testInkStillToComeIsFaintAndInkUnderATapIsFound() throws {
        let drawing = PKDrawing(strokes: [stroke(y: 100, at: 1), stroke(y: 300, at: 5)])
        let shown = ReplayInk.drawing(drawing, pending: [1])
        XCTAssertEqual(shown.strokes.count, 2, "nothing is removed, so the page keeps its shape")
        XCTAssertEqual(shown.strokes[0].ink.color.cgColor.alpha, 1)
        XCTAssertEqual(Double(shown.strokes[1].ink.color.cgColor.alpha), Double(ReplayInk.faint), accuracy: 0.01)
        XCTAssertEqual(ReplayInk.drawing(drawing, pending: []).strokes.map(\.ink.color), drawing.strokes.map(\.ink.color))

        XCTAssertEqual(ReplayInk.stroke(at: CGPoint(x: 300, y: 304), in: drawing), 1)
        XCTAssertEqual(ReplayInk.stroke(at: CGPoint(x: 300, y: 98), in: drawing), 0)
        XCTAssertNil(ReplayInk.stroke(at: CGPoint(x: 300, y: 200), in: drawing), "a tap between lines of writing finds nothing")
    }

    func testARecordingRemembersWhenItBeganAndWhereItWasWrittenOn() throws {
        let page = UUID()
        var entry = recording(duration: 30)
        entry.inkedPages = [page]
        let decoded = try XCTUnwrap(ManifestCodec.decodeRecording(ManifestCodec.encodeRecording(entry)))
        XCTAssertEqual(decoded.startedAt.timeIntervalSince(start), 0, accuracy: 0.01)
        XCTAssertEqual(decoded.inkedPages, [page])

        let old = RecordingEntry(id: UUID(), file: "old.m4a", createdAt: start.addingTimeInterval(30), duration: 30)
        XCTAssertEqual(old.startedAt, start, "an older entry is taken to have begun its length before it was saved")
        XCTAssertNil(old.inkedPages)
    }

    func testReplayingFollowsTheWritingAndEndsCleanly() async throws {
        let root = temporaryRoot(self)
        var manifest = NotebookManifest(title: "Talk", defaults: paper, pages: [paper.newPage(), paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        try FileManager.default.createDirectory(at: package.assetsDirectory, withIntermediateDirectories: true)
        try ReplaySeed.silence(seconds: 20).write(to: package.assetURL("talk.wav"))
        var entry = recording()
        entry.inkedPages = manifest.pages.map(\.id)
        manifest.recordings = [entry]
        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: PKDrawing(strokes: [stroke(y: 100, at: 2), stroke(y: 200, at: 6)]),
                                                                           manifest.pages[1].id: PKDrawing(strokes: [stroke(y: 100, at: 14)])]))
        let document = try await NotebookDocument.open(manifest.id, root: root)
        let session = EditorSession(document: document)

        let began = await session.beginReplay(entry)
        XCTAssertTrue(began)
        XCTAssertEqual(session.mode, .replaying)
        XCTAssertEqual(session.replay?.marks.count, 3)
        XCTAssertEqual(session.recorder.playingID, entry.id)
        XCTAssertEqual(session.currentPage, 0)

        session.recorder.pause()
        XCTAssertTrue(session.recorder.isPaused)
        session.seekReplay(to: 15)
        XCTAssertEqual(session.recorder.currentTime, 15, accuracy: 0.01)
        XCTAssertEqual(session.currentPage, 1, "the replay turns to the page being written on")
        session.go(to: 0)
        session.seekReplay(to: 16)
        XCTAssertEqual(session.currentPage, 0, "but leaves you where you went until the writing moves to another page")
        session.seekReplay(to: 3)
        XCTAssertEqual(session.currentPage, 0)
        session.seekReplay(to: 500)
        XCTAssertEqual(session.recorder.currentTime, 20, accuracy: 0.01, "a jump past the end stops at the end")

        session.enter(.writing)
        XCTAssertNil(session.replay)
        XCTAssertNil(session.recorder.playingID, "leaving the replay stops the sound")
        XCTAssertFalse(document.undoManager.canUndo, "replaying changes nothing on the pages")
        XCTAssertEqual(document.loadedInk(manifest.pages[0].id)?.strokes.map(\.ink.color.cgColor.alpha), [1, 1])
    }
}
