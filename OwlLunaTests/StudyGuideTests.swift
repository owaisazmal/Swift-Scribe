import XCTest
#if canImport(FoundationModels)
import FoundationModels
#endif
@testable import OwlLuna

/// Study guides: how notes are cut into pieces the model can take, and how the pieces' answers are put together.
@MainActor
final class StudyGuideTests: XCTestCase {
    /// Answers with the notes' own lines, and counts how it was asked.
    private final class Recorder: StudyModel, @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        var limit = Int.max
        var prompts: [String] { lock.withLock { asked } }

        func keyPoints(in text: String, atMost limit: Int) async throws -> [String] {
            lock.withLock { asked.append(text) }
            if text.count > self.limit { throw StudyGuideError.tooLong }
            return Array(text.split(separator: "\n").map { String($0).replacingOccurrences(of: "- ", with: "") }.prefix(limit))
        }

        func questions(about text: String, count: Int) async throws -> [QuizItem] {
            lock.withLock { asked.append(text) }
            if text.count > self.limit { throw StudyGuideError.tooLong }
            return text.split(separator: "\n").prefix(count).map { QuizItem(question: "What about \($0)?", answer: String($0)) }
        }
    }

    private func notes(_ lines: Int) -> String {
        (1...lines).map { "Fact number \($0) is that cells divide by mitosis in stage \($0)." }.joined(separator: "\n")
    }

    func testNotesAreCutBetweenLinesAndALongLineBetweenWords() {
        let chunks = StudyGuide.chunks(of: notes(10), limit: 200)
        XCTAssertEqual(chunks.count, 4)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 200 })
        XCTAssertEqual(chunks.joined(separator: "\n"), notes(10), "nothing is lost and nothing is cut mid-line")

        let long = Array(repeating: "word", count: 100).joined(separator: " ")
        let pieces = StudyGuide.chunks(of: long, limit: 120)
        XCTAssertTrue(pieces.allSatisfy { $0.count <= 120 && !$0.hasPrefix(" ") && !$0.hasSuffix("wor") })
        XCTAssertEqual(pieces.joined(separator: " "), long)
        XCTAssertEqual(StudyGuide.chunks(of: " \n\n  \n"), [])
    }

    func testThePageStampIsNotPartOfTheNotes() {
        XCTAssertEqual(StudyGuide.body(ofPageText: "#ink:abc123+img\nHello\nthere"), "Hello\nthere")
        XCTAssertEqual(StudyGuide.body(ofPageText: "#ink:none"), "")
        XCTAssertEqual(StudyGuide.body(ofPageText: "No stamp"), "No stamp")
    }

    func testAShortNotebookIsSummarisedInOneGo() async throws {
        let model = Recorder()
        let points = try await StudyGuide.summary(of: notes(4) + "\n" + notes(1), using: model, limit: 7)
        XCTAssertEqual(model.prompts.count, 1)
        XCTAssertEqual(points.count, 4, "a point said twice is kept once")
    }

    func testALongNotebookIsReadInPiecesAndThenBoiledDown() async throws {
        let model = Recorder()
        let text = notes(150)
        var progress: [Double] = []
        let points = try await StudyGuide.summary(of: text, using: model, limit: 6) { progress.append($0) }
        let pieces = StudyGuide.chunks(of: text).count
        XCTAssertGreaterThan(pieces, 2)
        XCTAssertEqual(model.prompts.count, pieces + 1, "each piece, then one pass over their points")
        XCTAssertTrue(model.prompts.allSatisfy { $0.count <= StudyGuide.chunkLimit })
        XCTAssertEqual(points.count, 6)
        XCTAssertEqual(progress.last, 1)
        XCTAssertEqual(progress, progress.sorted())
    }

    func testAPieceTheModelFindsTooLongIsReadInHalves() async throws {
        let model = Recorder()
        model.limit = 400
        let points = try await StudyGuide.summary(of: notes(10), using: model, limit: 6)
        XCTAssertGreaterThanOrEqual(model.prompts.count, 3, "the whole, then smaller pieces of it")
        XCTAssertTrue(model.prompts.dropFirst().allSatisfy { $0.count <= 400 })
        XCTAssertEqual(points.count, 6)
        XCTAssertTrue(model.prompts.dropFirst().contains { $0.contains("number 10 ") }, "the last piece was read too")
        model.limit = 10
        do {
            _ = try await StudyGuide.summary(of: notes(10), using: model)
            XCTFail("notes that can't be cut small enough are refused")
        } catch {
            XCTAssertEqual(error as? StudyGuideError, .tooLong)
        }
    }

    func testTooLittleWritingIsNotGuessedAt() async {
        for text in ["", "HELLO", "   \n "] {
            do {
                _ = try await StudyGuide.summary(of: text, using: Recorder())
                XCTFail("nothing to summarise in \(text.debugDescription)")
            } catch {
                XCTAssertEqual(error as? StudyGuideError, .nothingToRead)
            }
        }
    }

    func testQuestionsAreSpreadOverTheNotesAndNeverRepeated() async throws {
        let model = Recorder()
        let text = notes(150)
        let items = try await StudyGuide.quiz(of: text, using: model, count: 8)
        XCTAssertEqual(items.count, 8)
        XCTAssertEqual(Set(items.map(\.question)).count, 8)
        XCTAssertTrue(items.contains { $0.answer.contains("Fact number 1 ") })
        XCTAssertTrue(items.contains { ($0.answer.split(separator: " ").dropFirst(2).first.flatMap { Int($0) } ?? 0) > 100 }, "the end of the notes is asked about too")

        let repeated = try await StudyGuide.quiz(of: notes(1) + "\n" + notes(1) + "\n" + notes(2), using: Recorder(), count: 8)
        XCTAssertEqual(repeated.count, 2)
    }

    func testTheScriptedModelAnswersFromTheNotes() async throws {
        let model = ScriptedStudyModel()
        let points = try await StudyGuide.summary(of: "Mitochondria make ATP for the cell.\nRibosomes build proteins.", using: model)
        XCTAssertEqual(points, ["Mitochondria make ATP for the cell.", "Ribosomes build proteins."])
        XCTAssertEqual(StudyGuide.listed(points), "• Mitochondria make ATP for the cell.\n• Ribosomes build proteins.")
        let quiz = try await StudyGuide.quiz(of: "Mitochondria make ATP for the cell.\nRibosomes build proteins.", using: model)
        XCTAssertEqual(quiz.map(\.question), ["What do the notes say about Mitochondria make?", "What do the notes say about Ribosomes build?"])
    }

    /// Why the machine's model can't answer even a plain request, if it can't. CI's simulators report a model and then fail every request.
    private func modelFault() async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            do {
                _ = try await LanguageModelSession().respond(to: "Reply with the one word yes.")
                return nil
            } catch {
                return String(describing: error)
            }
        }
        #endif
        return "no model"
    }

    func testTheModelOnThisMachineWritesAboutNotes() async throws {
        guard StudyGuide.status == .ready, let model = StudyGuide.model() else {
            throw XCTSkip("no on-device language model here: \(StudyGuide.status)")
        }
        if let fault = await modelFault() {
            throw XCTSkip("the language model here is reported ready but answers nothing: \(fault)")
        }
        let notes = """
            Mitochondria make ATP, the cell's energy.
            Ribosomes build proteins from amino acids.
            The nucleus holds the cell's DNA.
            Chloroplasts turn light into sugar in plants.
            """
        let points = try await StudyGuide.summary(of: notes, using: model, limit: 4)
        XCTAssertFalse(points.isEmpty)
        XCTAssertLessThanOrEqual(points.count, 4)
        let quiz = try await StudyGuide.quiz(of: notes, using: model, count: 3)
        XCTAssertFalse(quiz.isEmpty)
        print("STUDY MODEL points: \(points)\nquiz: \(quiz.map { "\($0.question) -> \($0.answer)" })")
    }

    func testAStudyGuideReadsTypedTextAndHandwritingFromThePages() async throws {
        let root = temporaryRoot(self)
        let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)
        var first = paper.newPage(), second = paper.newPage()
        first.items = [PageItem(content: .text(TextBox(string: "Mitochondria make ATP.")), center: CGPoint(x: 200, y: 200), size: CGSize(width: 240, height: 40))]
        second.items = [PageItem(content: .text(TextBox(string: "Ribosomes build proteins.")), center: CGPoint(x: 200, y: 200), size: CGSize(width: 240, height: 40))]
        let manifest = NotebookManifest(title: "Biology", defaults: paper, pages: [first, second])
        try await NotebookPackage(root: root, id: manifest.id).create(manifest)
        let document = try await NotebookDocument.open(manifest.id, root: root)

        let whole = await StudyGuide.text(for: .notebook, in: document)
        XCTAssertEqual(whole, "Mitochondria make ATP.\n\nRibosomes build proteins.")
        let page = await StudyGuide.text(for: .page(second.id), in: document)
        XCTAssertEqual(page, "Ribosomes build proteins.")
        let recording = await StudyGuide.text(for: .recording(UUID()), in: document)
        XCTAssertEqual(recording, "")
    }
}
