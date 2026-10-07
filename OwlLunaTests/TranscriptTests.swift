import XCTest
import PencilKit
@testable import OwlLuna

/// What was said in a recording: how it is kept, broken into lines, written into the notebook and found by search.
@MainActor
final class TranscriptTests: XCTestCase {
    private let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)

    private struct Deaf: SpeechTranscribing {
        func transcribe(_ url: URL, locale: Locale, progress: @escaping @Sendable (Double) -> Void) async throws -> Transcript {
            throw TranscriptionError.nothingHeard
        }
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition(), Date.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func word(_ text: String, _ start: TimeInterval, _ duration: TimeInterval = 0.3) -> Transcript.Word {
        Transcript.Word(text: text, start: start, duration: duration)
    }

    func testATranscriptBreaksIntoLinesAtSentencesPausesAndLongBreaths() throws {
        var words = [word("Good", 0.5), word("morning.", 0.9), word("Today", 1.4), word("we", 1.8), word("begin", 4.0), word("again", 4.4)]
        words += (0..<20).map { word("and", 5 + Double($0) * 0.4) }
        let transcript = Transcript(locale: "en-US", words: words)
        let lines = transcript.lines
        XCTAssertEqual(lines.map(\.text).prefix(3), ["Good morning.", "Today we", "begin again " + Array(repeating: "and", count: 14).joined(separator: " ")])
        XCTAssertEqual(lines.count, 4, "a breath of more than sixteen words is split")
        XCTAssertEqual(lines.map(\.id), [0, 1, 2, 3])
        XCTAssertEqual(lines[1].start, 1.4, accuracy: 0.001)
        XCTAssertEqual(lines[1].end, 2.1, accuracy: 0.001)

        XCTAssertNil(Transcript.line(at: 0.2, in: lines), "nothing has been said yet")
        XCTAssertEqual(Transcript.line(at: 0.5, in: lines), 0)
        XCTAssertEqual(Transcript.line(at: 3, in: lines), 1, "a pause still belongs to the line before it")
        XCTAssertEqual(Transcript.line(at: 500, in: lines), 3)
        XCTAssertTrue(transcript.text.hasPrefix("Good morning.\nToday we\n"))

        let data = try JSONEncoder().encode(transcript)
        XCTAssertEqual(try JSONDecoder().decode(Transcript.self, from: data), transcript)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"t\":\"Good\""), "words are stored under short keys")
        XCTAssertTrue(Transcript(locale: "en-US", words: []).lines.isEmpty)
    }

    func testSettledWordsReplaceWhatWasHeldFromTheirMomentOn() {
        var transcript = Transcript(locale: "en-US", words: [])
        transcript.merge([word("one", 1), word("too", 2)])
        transcript.merge([word("one", 1), word("two", 2), word("three", 3)])
        XCTAssertEqual(transcript.words.map(\.text), ["one", "two", "three"], "the whole recording sent again replaces what was held")
        transcript.merge([word("four", 6), word("five", 7)])
        XCTAssertEqual(transcript.words.map(\.text), ["one", "two", "three", "four", "five"], "only the latest stretch is added to it")
        transcript.merge([])
        XCTAssertEqual(transcript.words.count, 5)

        let spread = Transcript.spread(["a", "b", "c", "d"], over: 20)
        XCTAssertEqual(spread.map(\.start), [0, 5, 10, 15], "words without times are spread over the recording")
        XCTAssertTrue(Transcript.spread([], over: 20).isEmpty)
    }

    func testTranscribingWritesTheWordsIntoTheNotebookWhereSearchFindsThem() async throws {
        let root = temporaryRoot(self)
        var manifest = NotebookManifest(title: "Biology", defaults: paper, pages: [paper.newPage(), paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        try FileManager.default.createDirectory(at: package.assetsDirectory, withIntermediateDirectories: true)
        try ReplaySeed.silence(seconds: 20).write(to: package.assetURL("talk.wav"))
        var entry = RecordingEntry(id: UUID(), file: "talk.wav", createdAt: .now, duration: 20)
        entry.inkedPages = [manifest.pages[1].id]
        manifest.recordings = [entry]
        try await package.writeManifest(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        let recorder = NotebookRecorder(document: document)
        recorder.transcriber = ScriptedTranscriber()
        var changes = 0
        recorder.onTranscriptChange = { changes += 1 }
        XCTAssertNil(recorder.transcript(for: entry))

        recorder.transcribe(entry, locale: Locale(identifier: "en-US"))
        XCTAssertNotNil(recorder.transcribing[entry.id])
        await waitUntil { recorder.recordings.first?.transcriptFile != nil }
        let transcribed = try XCTUnwrap(recorder.recordings.first)
        let file = try XCTUnwrap(transcribed.transcriptFile)
        XCTAssertNil(recorder.transcribing[entry.id])
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(recorder.transcript(for: transcribed)?.lines.map(\.text),
                       ["Today we cover the cell membrane.", "It keeps the cell together.", "Proteins carry signals across it."])
        XCTAssertEqual(package.readTranscript(file)?.locale, "en-US")
        XCTAssertFalse(document.undoManager.canUndo, "a transcript isn't something to undo")

        let saved = await document.save()
        XCTAssertTrue(saved)
        await document.collectGarbage()
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.assetURL(file).path(percentEncoded: false)), "the transcript is kept with the notebook")
        XCTAssertTrue(LibraryIndex.searchText(in: package.textDirectory).contains("cell membrane"), "and its words are in the notebook's search text")

        let hits = await PageSearch.hits(for: "membrane", in: [manifest.id], root: root)
        let hit = try XCTUnwrap(hits[manifest.id]?.first)
        XCTAssertEqual(hit.recording, 1)
        XCTAssertEqual(hit.index, 1, "it opens the page that was written on during the recording")
        XCTAssertEqual(hit.place, "Recording 1")
        XCTAssertTrue(hit.snippet.contains("membrane"))

        recorder.removeTranscript(transcribed)
        await waitUntil { changes == 2 }
        XCTAssertNil(recorder.recordings.first?.transcriptFile)
        XCTAssertFalse(LibraryIndex.searchText(in: package.textDirectory).contains("membrane"))
        let none = await PageSearch.hits(for: "membrane", in: [manifest.id], root: root)
        XCTAssertNil(none[manifest.id])
    }

    func testARecordingWithNoSpeechSaysSoAndIsLeftAsItWas() async throws {
        let root = temporaryRoot(self)
        var manifest = NotebookManifest(title: "Quiet", defaults: paper, pages: [paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        let entry = RecordingEntry(id: UUID(), file: "quiet.wav", createdAt: .now, duration: 5)
        manifest.recordings = [entry]
        try await package.create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)
        let recorder = NotebookRecorder(document: document)
        recorder.transcriber = Deaf()

        recorder.transcribe(entry, locale: Locale(identifier: "en-US"))
        await waitUntil { recorder.errorMessage != nil }
        XCTAssertEqual(recorder.errorMessage, "No speech was found in this recording.")
        XCTAssertNil(recorder.recordings.first?.transcriptFile)
        XCTAssertNil(recorder.transcribing[entry.id])

        recorder.transcriber = ScriptedTranscriber()
        recorder.transcribe(entry, locale: Locale(identifier: "en-US"))
        recorder.cancelTranscription(entry.id)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertNil(recorder.recordings.first?.transcriptFile, "a cancelled transcription writes nothing")
        XCTAssertFalse(Transcription.languages.isEmpty)
    }
}
