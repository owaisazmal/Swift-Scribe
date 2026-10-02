import XCTest
import SwiftData
import PencilKit
@testable import NotesApp

// Opt-in: TEST_RUNNER_SCRIBE_PERF=1 xcodebuild test ... -only-testing:NotesAppTests/PerformanceBaselineTests
@MainActor
final class PerformanceBaselineTests: XCTestCase {
    private func requirePerfRun() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SCRIBE_PERF"] == "1", "Set SCRIBE_PERF=1 to run")
    }

    private func hostWindow() throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in window.isHidden = true }
        return window
    }

    private func report(_ name: String, _ values: [Double], unit: String = "ms") {
        let sorted = values.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        print("PERF v2 \(name): median=\(String(format: "%.3f", median))\(unit) max=\(String(format: "%.3f", sorted.last ?? 0))\(unit) n=\(values.count)")
    }

    /// Async tests run as a main-queue job, so a nested run loop can't run main-actor work; sleeping yields instead.
    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func v2Root() -> StorageRoot {
        let url = FileManager.default.temporaryDirectory.appending(path: "perf-v2-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return StorageRoot(url: url)
    }

    private func openV2(_ id: UUID, root: StorageRoot, window: UIWindow) async throws -> (NotebookDocument, PageStackController, TimeInterval) {
        let document = try await NotebookDocument.open(id, root: root)
        document.saveDelay = .seconds(600)
        let session = EditorSession(document: document)
        let controller = PageStackController(session: session)
        session.canvas = controller
        var firstInk: TimeInterval = -1
        let rendered = expectation(description: "first ink")
        controller.onFirstInk = { firstInk = $0; rendered.fulfill() }
        window.rootViewController = controller
        controller.view.layoutIfNeeded()
        await fulfillment(of: [rendered], timeout: 15)
        await pause(0.2)
        return (document, controller, firstInk)
    }

    private func stage(_ stroke: PKStroke, on canvas: PKCanvasView) -> () -> Void {
        let delegate = canvas.delegate
        canvas.delegate = nil
        var drawing = canvas.drawing
        drawing.strokes.append(stroke)
        canvas.drawing = drawing
        canvas.delegate = delegate
        return { delegate?.canvasViewDrawingDidChange?(canvas) }
    }

    private func measureV2StrokeEnd(pages: Int, label: String, acrossEdge: Bool = false) async throws {
        let root = v2Root()
        let id = try await V2StressFixture.write(pages: pages, strokes: { $0 == 0 ? 1000 : 500 }, root: root)
        let (document, controller, _) = try await openV2(id, root: root, window: try hostWindow())
        let canvas = try XCTUnwrap(controller.canvas(forPage: 0))
        let width = document.pages[0].size.width
        var samples: [Double] = []
        for i in 0..<30 {
            let y = 60 + CGFloat(i % 10) * 4
            let probe = acrossEdge ? stroke(from: CGPoint(x: width - 30, y: y), to: CGPoint(x: width + 40, y: y))
                                   : V2StressFixture.probe(at: CGPoint(x: 80, y: y))
            let handler = stage(probe, on: canvas)
            let start = CACurrentMediaTime()
            handler()
            samples.append((CACurrentMediaTime() - start) * 1000)
        }
        report("stroke end, 1,000-stroke page, \(label)", Array(samples.dropFirst(5)))
        XCTAssertEqual(document.loadedInk(document.pages[0].id)?.strokes.count, 1030)
    }

    func testV2StrokeEndHeavyNotebook() async throws {
        try requirePerfRun()
        try await measureV2StrokeEnd(pages: 100, label: "100-page notebook")
    }

    func testV2StrokeEndSmallNotebook() async throws {
        try requirePerfRun()
        try await measureV2StrokeEnd(pages: 10, label: "10-page notebook")
    }

    func testV2StrokeEndAcrossThePageEdge() async throws {
        try requirePerfRun()
        try await measureV2StrokeEnd(pages: 100, label: "100-page notebook, stroke crossing the page edge", acrossEdge: true)
    }

    /// Main-thread CPU time of the calling thread, from the kernel's per-thread accounting.
    private func threadCPUTime() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let port = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, port) }
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count) }
        }
        return Double(info.user_time.seconds + info.system_time.seconds) + Double(info.user_time.microseconds + info.system_time.microseconds) / 1_000_000
    }

    /// Everything a save costs the main thread, with the library index wired up as in the app: the snapshot,
    /// the continuation after the off-main write, and on every other save an index update (a rename).
    func testV2AutosaveMainThreadWithIndexing() async throws {
        try requirePerfRun()
        let root = v2Root()
        let id = try await V2StressFixture.write(pages: 100, strokes: { _ in 500 }, root: root)
        let schema = LibraryIndex.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let store = LibraryStore(root: root, context: container.mainContext)
        let (document, controller, _) = try await openV2(id, root: root, window: try hostWindow())
        store.index(document.manifest)
        document.onSaved = { store.index($0) }
        let activity = WritingActivity(root: root, defaults: UserDefaults(suiteName: "perf-\(UUID().uuidString)")!)
        document.onInkSaved = { activity.record(notebook: id, pages: $0, at: $1) }
        var inkOnly: [Double] = [], withIndex: [Double] = []
        for i in 0..<12 {
            await pause(0.05)
            if let canvas = controller.canvas(forPage: 0) { stage(V2StressFixture.probe(at: CGPoint(x: 90, y: 70 + CGFloat(i) * 5)), on: canvas)() }
            let renamed = i.isMultiple(of: 2)
            if renamed { document.rename("Heavy \(i)") }
            let before = threadCPUTime()
            _ = await document.save()
            let cost = (threadCPUTime() - before) * 1000
            if renamed { withIndex.append(cost) } else { inkOnly.append(cost) }
        }
        report("autosave, main-thread CPU per save, ink only (heavy)", inkOnly)
        report("autosave, main-thread CPU per save, with index update (heavy)", withIndex)
        XCTAssertEqual(store.record(id)?.title, "Heavy 10")
        XCTAssertTrue(activity.hasHistory)
    }

    func testV2AutosaveSnapshotHeavy() async throws {
        try requirePerfRun()
        let root = v2Root()
        let id = try await V2StressFixture.write(pages: 100, strokes: { _ in 500 }, root: root)
        let (document, controller, _) = try await openV2(id, root: root, window: try hostWindow())
        var samples: [Double] = []
        var written = 0
        for i in 0..<10 {
            if let canvas = controller.canvas(forPage: 0) { stage(V2StressFixture.probe(at: CGPoint(x: 90, y: 70 + CGFloat(i) * 5)), on: canvas)() }
            let start = CACurrentMediaTime()
            let pending = document.makePendingSave()
            samples.append((CACurrentMediaTime() - start) * 1000)
            written = pending.snapshot.ink.count
            _ = await document.save()
        }
        report("autosave main-thread snapshot (heavy)", samples)
        XCTAssertEqual(written, 1)
        XCTAssertFalse(document.hasUnsavedChanges)
    }

    func testV2PageOperationsHeavy() async throws {
        try requirePerfRun()
        let root = v2Root()
        let id = try await V2StressFixture.write(pages: 100, strokes: { _ in 500 }, root: root)
        let (document, _, _) = try await openV2(id, root: root, window: try hostWindow())
        document.undoManager.groupsByEvent = false
        var insert: [Double] = [], move: [Double] = [], delete: [Double] = [], undo: [Double] = []
        func timed(_ action: () -> Void) -> Double {
            document.undoManager.beginUndoGrouping()
            let start = CACurrentMediaTime()
            action()
            let elapsed = (CACurrentMediaTime() - start) * 1000
            document.undoManager.endUndoGrouping()
            return elapsed
        }
        for _ in 0..<8 {
            insert.append(timed { document.insertPages([document.manifest.defaults.newPage()], at: 0) })
            await pause(0.03)
            move.append(timed { document.movePage(from: 0, to: 50) })
            await pause(0.03)
            delete.append(timed { document.removePages([document.pages[50].id]) })
            await pause(0.03)
        }
        for _ in 0..<6 {
            let start = CACurrentMediaTime()
            document.undoManager.undo()
            undo.append((CACurrentMediaTime() - start) * 1000)
            await pause(0.03)
        }
        report("insert page at start, incl. relayout (heavy)", insert)
        report("move page 0 to 50, incl. relayout (heavy)", move)
        report("delete page, incl. relayout (heavy)", delete)
        report("undo a page operation (heavy)", undo)
        XCTAssertEqual(document.pages.count, 100)
    }

    private func measureV2Open(_ make: (StorageRoot) async throws -> UUID, label: String) async throws {
        let root = v2Root()
        let id = try await make(root)
        let window = try hostWindow()
        var sync: [Double] = [], firstInk: [Double] = []
        for _ in 0..<6 {
            let start = CACurrentMediaTime()
            let document = try await NotebookDocument.open(id, root: root)
            let session = EditorSession(document: document)
            let controller = PageStackController(session: session)
            session.canvas = controller
            let rendered = expectation(description: "first ink")
            var inkAt: CFTimeInterval = 0
            controller.onFirstInk = { _ in inkAt = CACurrentMediaTime(); rendered.fulfill() }
            let blockStart = CACurrentMediaTime()
            window.rootViewController = controller
            controller.view.layoutIfNeeded()
            sync.append((CACurrentMediaTime() - blockStart) * 1000)
            await fulfillment(of: [rendered], timeout: 15)
            firstInk.append((inkAt - start) * 1000)
            window.rootViewController = UIViewController()
            await pause(0.2)
        }
        report("open \(label): longest synchronous main-thread block", Array(sync.dropFirst()))
        report("open \(label): to first ink", Array(firstInk.dropFirst()))
    }

    func testV2OpenHeavy() async throws {
        try requirePerfRun()
        try await measureV2Open({ try await V2StressFixture.write(pages: 100, strokes: { _ in 500 }, root: $0) }, label: "heavy")
    }

    func testV2OpenLongPDF() async throws {
        try requirePerfRun()
        try await measureV2Open({ try await V2StressFixture.writePDF(pages: 300, root: $0) }, label: "300-page PDF")
    }

    private func scrollThrough(_ controller: PageStackController, steps: Int, fraction: CGFloat) async -> (peak: Double, live: Int) {
        var peak = 0.0, live = 0
        for _ in 0..<steps {
            controller.scrollBy(viewportFraction: fraction)
            await pause(0.03)
            peak = max(peak, V2StressFixture.footprintMB())
            live = max(live, controller.liveCanvasCount)
        }
        return (peak, live)
    }

    func testV2MemoryScrollingLongPDF() async throws {
        try requirePerfRun()
        let root = v2Root()
        let id = try await V2StressFixture.writePDF(pages: 300, root: root)
        let baseline = V2StressFixture.footprintMB()
        let (_, controller, _) = try await openV2(id, root: root, window: try hostWindow())
        let scroll = await scrollThrough(controller, steps: 600, fraction: 0.6)
        print("PERF v2 memory, scrolling a 300-page PDF: baseline=\(Int(baseline))MB peak=\(Int(scroll.peak))MB liveCanvases<=\(scroll.live) reached page \(controller.currentPage + 1)")
        controller.scrollToPage(150)
        controller.setZoom(5)
        await pause(0.8)
        let zoomed = await scrollThrough(controller, steps: 60, fraction: 0.5)
        print("PERF v2 memory, 300-page PDF at 5x: peak=\(Int(zoomed.peak))MB liveCanvases<=\(zoomed.live)")
        XCTAssertGreaterThan(controller.currentPage, 150)
    }

    func testV2MemoryScrollingHeavyInk() async throws {
        try requirePerfRun()
        let root = v2Root()
        let id = try await V2StressFixture.write(pages: 100, strokes: { _ in 500 }, root: root)
        let baseline = V2StressFixture.footprintMB()
        let (_, controller, _) = try await openV2(id, root: root, window: try hostWindow())
        let scroll = await scrollThrough(controller, steps: 200, fraction: 0.6)
        print("PERF v2 memory, scrolling heavy ink: baseline=\(Int(baseline))MB peak=\(Int(scroll.peak))MB liveCanvases<=\(scroll.live)")
        controller.setZoom(5)
        await pause(0.8)
        let zoomed = await scrollThrough(controller, steps: 40, fraction: 0.5)
        print("PERF v2 memory, heavy ink at 5x: peak=\(Int(zoomed.peak))MB liveCanvases<=\(zoomed.live)")
    }

    func testV2ExportKeepsMainThreadFree() async throws {
        try requirePerfRun()
        let root = v2Root()
        let id = try await V2StressFixture.write(pages: 20, strokes: { _ in 400 }, root: root)
        let document = try await NotebookDocument.open(id, root: root)
        let gaps = GapMonitor()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.002, repeats: true) { _ in
            MainActor.assumeIsolated { gaps.tick() }
        }
        let start = CACurrentMediaTime()
        let job = ExportJob(document: document)
        while case .running = job.state { await pause(0.01) }
        timer.invalidate()
        guard case .finished(let url) = job.state else { return XCTFail("export failed: \(job.state)") }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        print("PERF v2 export 20 pages: total=\(Int((CACurrentMediaTime() - start) * 1000))ms longestMainThreadGap=\(String(format: "%.1f", gaps.longest * 1000))ms bytes=\(size)")
    }

    func testV2CoverRender() throws {
        try requirePerfRun()
        for style in CoverStyle.allCases {
            let request = CoverRequest(notebookID: UUID(), spec: CoverSpec(style: style, cloth: .moss, inks: (.teal, .pink), seed: 9),
                                       title: "Cell Biology", meta: "24 pages", width: 176, scale: 2, dark: false, highContrast: false,
                                       firstPage: nil, firstPageKey: nil, firstPageIsPDF: false)
            var samples: [Double] = []
            for _ in 0..<10 {
                let start = CACurrentMediaTime()
                _ = CoverRenderer.render(request)
                samples.append((CACurrentMediaTime() - start) * 1000)
            }
            report("cover render \(style.rawValue), off main in the app", samples)
        }
    }

    func testV2HandwritingIndexIsIncremental() async throws {
        try requirePerfRun()
        let root = v2Root()
        let id = try await V2StressFixture.write(pages: 3, strokes: { _ in 400 }, root: root)
        let package = NotebookPackage(root: root, id: id)
        let pages = try await package.readManifest().manifest.pages
        var start = CACurrentMediaTime()
        _ = await HandwritingIndexer.shared.index(HandwritingIndexer.Job(package: package, pages: pages))
        let first = CACurrentMediaTime() - start
        start = CACurrentMediaTime()
        _ = await HandwritingIndexer.shared.index(HandwritingIndexer.Job(package: package, pages: pages))
        let second = CACurrentMediaTime() - start
        print("PERF v2 OCR 3 pages: first=\(Int(first * 1000))ms unchanged re-run=\(String(format: "%.1f", second * 1000))ms (background)")
    }
}

/// The longest interval between main-thread timer ticks: how long the main thread was unavailable.
@MainActor
private final class GapMonitor {
    private(set) var longest: CFTimeInterval = 0
    private var last = CACurrentMediaTime()

    func tick() {
        let now = CACurrentMediaTime()
        longest = max(longest, now - last)
        last = now
    }
}

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Stress fixtures: packages with page-local ink. Heavy is 100 Letter pages × 500 strokes.
enum V2StressFixture {
    static func makePDF(pageCount: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        let bounds = CGRect(origin: .zero, size: PageSize.letter.points)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: url) { context in
            for index in 0..<pageCount {
                context.beginPage()
                ("Chapter \(index + 1)" as NSString).draw(at: CGPoint(x: 72, y: 72),
                                                         withAttributes: [.font: UIFont.systemFont(ofSize: 28)])
            }
        }
        return url
    }

    static func handwriting(count: Int, pageSize: CGSize, rng: inout SplitMix64) -> [PKStroke] {
        let k = pageSize.width / 800
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let left = 110 * k, right = pageSize.width - 30 * k, top = 120 * k
        var x = left, baseline = top
        var result: [PKStroke] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            let width = CGFloat.random(in: 6...22, using: &rng) * k
            if x + width > right {
                x = left
                baseline += 28 * k
                if baseline > pageSize.height - 30 * k { baseline = top }
            }
            let pointCount = Int.random(in: 16...32, using: &rng)
            let height = CGFloat.random(in: 8...18, using: &rng) * k
            let phase = CGFloat.random(in: 0...(.pi), using: &rng)
            let points = (0..<pointCount).map { i -> PKStrokePoint in
                let t = CGFloat(i) / CGFloat(pointCount - 1)
                return PKStrokePoint(location: CGPoint(x: x + width * t, y: baseline - 4 * k - height * abs(sin(phase + t * 3 * .pi))),
                                     timeOffset: TimeInterval(t) * 0.3, size: CGSize(width: 2.6 * k, height: 2.6 * k), opacity: 1,
                                     force: 0.6 + 0.4 * t, azimuth: 0, altitude: .pi / 3)
            }
            result.append(PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: created)))
            x += width + CGFloat.random(in: 3...12, using: &rng) * k
        }
        return result
    }

    static func write(pages count: Int, strokes: @Sendable (Int) -> Int, root: StorageRoot) async throws -> UUID {
        var rng = SplitMix64(state: 7)
        let pages = (0..<count).map { _ in NotebookPage.template(.narrowRuled, color: .white, size: .letter) }
        var ink: [UUID: PKDrawing] = [:]
        for (index, page) in pages.enumerated() {
            ink[page.id] = PKDrawing(strokes: handwriting(count: strokes(index), pageSize: page.size, rng: &rng))
        }
        let manifest = NotebookManifest(title: "Stress", defaults: PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter), pages: pages)
        let package = NotebookPackage(root: root, id: manifest.id)
        try await package.create(manifest)
        _ = try await package.write(SaveSnapshot(manifest: manifest, ink: ink))
        return manifest.id
    }

    static func writePDF(pages count: Int, root: StorageRoot) async throws -> UUID {
        let id = UUID()
        let package = NotebookPackage(root: root, id: id)
        let file = try await package.importAsset(from: makePDF(pageCount: count), ext: "pdf")
        let pages = try PDFImport.pages(at: package.assetURL(file), file: file)
        try await package.create(NotebookManifest(id: id, title: "Textbook", defaults: PageDefaults(template: .blank, paperColor: .white, pageSize: .letter), pages: pages))
        return id
    }

    static func probe(at origin: CGPoint) -> PKStroke {
        let points = (0..<24).map { i -> PKStrokePoint in
            let t = CGFloat(i) / 23
            return PKStrokePoint(location: CGPoint(x: origin.x + 60 * t, y: origin.y + 6 * sin(t * 6)), timeOffset: TimeInterval(t) * 0.2,
                                 size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .systemBlue), path: PKStrokePath(controlPoints: points, creationDate: .now))
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}
