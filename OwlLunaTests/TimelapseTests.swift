import XCTest
import PencilKit
import AVFoundation
@testable import OwlLuna

/// The film of a page being written: its timing, its size, and the file it makes.
@MainActor
final class TimelapseTests: XCTestCase {
    private let paper = PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter)
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// How much of the top third of a frame is ink.
    nonisolated private static func darkPixels(in url: URL, at time: TimeInterval) async throws -> Int {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        let width = image.width, height = image.height / 3
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: height - image.height, width: image.width, height: image.height))
        return stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] < 70 && bytes[$0 + 1] < 70 && bytes[$0 + 2] < 70 }.count
    }

    func testStrokesAreFilmedInTheOrderTheyWereWrittenWithTheWaitsTakenOut() {
        let plan = InkTimelapse.Plan(strokes: [(start.addingTimeInterval(3600), 2), (start, 1), (start.addingTimeInterval(5), 1)])
        XCTAssertEqual(plan.spans.map(\.stroke), [1, 2, 0], "by when they were written, not by where they sit in the drawing")
        XCTAssertEqual(plan.duration, 3, accuracy: 0.001, "four seconds of writing is shown in three: a short page isn't rushed")
        XCTAssertEqual(plan.spans[0].start, 0)
        XCTAssertEqual(plan.spans[1].start, plan.spans[0].end, accuracy: 0.001, "an hour's wait between strokes takes no time")
        XCTAssertEqual(plan.spans[2].end - plan.spans[2].start, 1.5, accuracy: 0.001, "a stroke that took twice as long is on screen twice as long")
        XCTAssertEqual(plan.frameCount, 90)

        XCTAssertEqual(plan.state(at: 0).finished, 0)
        XCTAssertEqual(plan.state(at: 0.375).partial, 0.5, accuracy: 0.001)
        XCTAssertEqual(plan.state(at: 0.75).finished, 1)
        XCTAssertEqual(plan.state(at: 2.9).finished, 2)
        XCTAssertEqual(plan.state(at: 3).finished, 3)
        XCTAssertEqual(plan.state(at: 99).partial, 0)

        let long = InkTimelapse.Plan(strokes: (0..<2000).map { (start.addingTimeInterval(Double($0)), 0.5) })
        XCTAssertEqual(long.duration, 20, accuracy: 0.001, "a full page is sped up to twenty seconds")
        let slow = InkTimelapse.Plan(strokes: [(start, 900), (start.addingTimeInterval(1000), 4)])
        XCTAssertEqual(slow.spans[0].end, slow.spans[1].end - slow.spans[1].start, accuracy: 0.001, "a pen left resting on the page counts as four seconds")
        XCTAssertTrue(InkTimelapse.Plan(strokes: []).spans.isEmpty)
        XCTAssertEqual(InkTimelapse.Plan(strokes: []).frameCount, 0)
    }

    func testTheFilmKeepsThePagesShapeAndAStrokeGrowsFromItsStart() throws {
        let letter = InkTimelapse.frameSize(for: PageSize.letter.points)
        XCTAssertEqual(letter.width, 1080)
        XCTAssertEqual(Double(letter.height) / Double(letter.width), 792.0 / 612.0, accuracy: 0.01)
        let wide = InkTimelapse.frameSize(for: CGSize(width: 1280, height: 720))
        XCTAssertEqual(wide.width, 1920)
        XCTAssertEqual(wide.height, 1080)
        XCTAssertEqual(InkTimelapse.frameSize(for: CGSize(width: 333, height: 777)).width % 2, 0, "the encoder wants even sides")

        let stroke = ReplaySeed.stroke(y: 200, at: start)
        XCTAssertNil(InkTimelapse.partial(stroke, fraction: 0.05), "nothing is drawn until there are two points to join")
        let half = try XCTUnwrap(InkTimelapse.partial(stroke, fraction: 0.5))
        XCTAssertEqual(half.path.count, 6)
        XCTAssertEqual(half.path.first?.location, stroke.path.first?.location)
        XCTAssertLessThan(half.renderBounds.width, stroke.renderBounds.width * 0.6)
        XCTAssertEqual(InkTimelapse.partial(stroke, fraction: 1)?.path.count, stroke.path.count)
    }

    func testAPageIsFilmedAsAVideo() async throws {
        let root = temporaryRoot(self)
        var manifest = NotebookManifest(title: "Sketch / One", defaults: paper, pages: [paper.newPage()])
        manifest.pages[0].items = [PageItem(content: .tape(.mustard), center: CGPoint(x: 300, y: 500), size: TapeArt.defaultSize)]
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        let ink = PKDrawing(strokes: BlockLetters.strokes("HELLO", origin: CGPoint(x: 120, y: 140), from: start))
        let input = NotebookExporter.Input(title: manifest.title, pages: manifest.pages, inMemoryInk: [manifest.pages[0].id: ink], package: package)

        let url: URL
        do {
            url = try await InkTimelapse.export(input) { _ in }
        } catch InkTimelapse.Failure.writer(let reason) {
            throw XCTSkip("no video encoder here: \(reason)")
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertEqual(url.lastPathComponent, "Sketch - One.mp4")
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1398)
        let seconds = try await asset.load(.duration).seconds
        XCTAssertEqual(seconds, InkTimelapse.Plan(drawing: ink).duration + InkTimelapse.hold, accuracy: 0.2)

        let early = try await Self.darkPixels(in: url, at: 0.1), middle = try await Self.darkPixels(in: url, at: 1.5)
        let end = try await Self.darkPixels(in: url, at: seconds - 0.2)
        XCTAssertLessThan(early, middle, "the writing grows")
        XCTAssertLessThan(middle, end)
        XCTAssertGreaterThan(end, 2000, "and ends as the whole page")

        let blank = NotebookExporter.Input(title: "Blank", pages: manifest.pages, inMemoryInk: [manifest.pages[0].id: PKDrawing()], package: package)
        do {
            _ = try await InkTimelapse.export(blank) { _ in }
            XCTFail("a page with no ink has nothing to film")
        } catch {
            XCTAssertEqual(error.localizedDescription, "There is no ink on this page to film.")
        }
    }
}
