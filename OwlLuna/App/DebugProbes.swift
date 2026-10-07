import SwiftUI
import QuartzCore
import PencilKit

#if DEBUG
/// Test-only frame pacing: counts frames that took longer than 1.5× the display's target interval.
/// A simulator proxy for hitches, which XCTest can't measure there. Enabled with `-framePacing`.
@MainActor
final class FramePacingProbe: NSObject {
    static let shared = FramePacingProbe()

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var long = 0
    private var worst: CFTimeInterval = 0
    private var hitch: CFTimeInterval = 0
    private var elapsed: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func reset() {
        last = 0; frames = 0; long = 0; worst = 0; hitch = 0; elapsed = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last > 0 else { return }
        let expected = max(link.targetTimestamp - link.timestamp, 1.0 / 120)
        let delta = link.timestamp - last
        guard delta < 1 else { return }
        frames += 1
        elapsed += delta
        worst = max(worst, delta)
        if delta > expected * 1.5 {
            long += 1
            hitch += delta - expected
        }
    }

    var summary: String {
        let ratio = elapsed > 0 ? hitch * 1000 / elapsed : 0
        return String(format: "frames=%d long=%d worst=%.1fms hitchRatio=%.1fms/s", frames, long, worst * 1000, ratio)
    }
}

/// Buttons and a readout in their own window above everything, so UI tests can reach them over sheets and the editor.
@MainActor
final class FramePacingWindow {
    static var window: UIWindow?

    static func install() {
        guard window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.session.role == .windowApplication }) else { return }
        let window = PassThroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        let label = UILabel()
        label.accessibilityIdentifier = "debug.framePacing.summary"
        label.font = .systemFont(ofSize: 8)
        label.alpha = 0.3
        let reset = UIButton(type: .system, primaryAction: UIAction(title: "reset") { _ in FramePacingProbe.shared.reset(); label.text = "" })
        reset.accessibilityIdentifier = "debug.framePacing.reset"
        let read = UIButton(type: .system, primaryAction: UIAction(title: "read") { _ in label.text = FramePacingProbe.shared.summary })
        read.accessibilityIdentifier = "debug.framePacing.read"
        let auto = UIButton(type: .system, primaryAction: UIAction(title: "autoscroll") { _ in
            label.text = ""
            AutoScroller.run { label.text = FramePacingProbe.shared.summary }
        })
        auto.accessibilityIdentifier = "debug.framePacing.autoscroll"
        let stack = UIStackView(arrangedSubviews: [reset, read, auto, label])
        stack.alpha = 0.3
        stack.spacing = 4
        stack.frame = CGRect(x: 8, y: scene.coordinateSpace.bounds.height - 40, width: 320, height: 28)
        stack.autoresizingMask = [.flexibleTopMargin]
        controller.view.addSubview(stack)
        window.rootViewController = controller
        window.isHidden = false
        self.window = window
        FramePacingProbe.shared.start()
    }
}

/// Scrolls the largest scroll view on screen down and back at a steady speed, driven by a display link,
/// so frame pacing is measured without XCUITest touching the app mid-run.
@MainActor
final class AutoScroller: NSObject {
    private static var current: AutoScroller?
    private var link: CADisplayLink?
    private weak var scrollView: UIScrollView?
    private var start: CFTimeInterval = 0
    private var origin: CGFloat = 0
    private let duration: CFTimeInterval = 6
    private let speed: CGFloat = 2400
    private var completion: (() -> Void)?

    static func run(completion: @escaping () -> Void) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).filter { $0.windowLevel == .normal }
        let scrollViews = windows.flatMap { allScrollViews(in: $0) }.filter { $0.window != nil && $0.contentSize.height > $0.bounds.height }
        guard let target = scrollViews.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { return completion() }
        let scroller = AutoScroller()
        scroller.scrollView = target
        scroller.origin = target.contentOffset.y
        scroller.completion = completion
        current = scroller
        FramePacingProbe.shared.reset()
        let link = CADisplayLink(target: scroller, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        scroller.link = link
    }

    private static func allScrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? [] + view.subviews.flatMap(allScrollViews)
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let scrollView else { return finish() }
        if start == 0 { start = link.timestamp }
        let t = link.timestamp - start
        guard t < duration else { return finish() }
        let half = duration / 2
        let distance = CGFloat(t < half ? t : duration - t) * speed
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.contentOffset.y = min(origin + distance, maxY)
    }

    private func finish() {
        link?.invalidate()
        link = nil
        completion?()
        Self.current = nil
    }
}

/// `-secondScreenInset` stands a small window in for a second screen, so UI tests can see what one would show.
@MainActor
enum SecondScreenInset {
    static func window() -> UIWindow? {
        guard LaunchOptions.arguments.contains("-secondScreenInset"),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.session.role == .windowApplication }) else { return nil }
        let window = PassThroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.frame = CGRect(x: scene.coordinateSpace.bounds.width - 496, y: 110, width: 480, height: 270)
        window.layer.borderColor = UIColor.white.cgColor
        window.layer.borderWidth = 1
        return window
    }
}

private final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view is UIButton || view?.superview is UIButton ? view : nil
    }
}

/// A notebook with a silent recording and ink dated inside it, for trying the replay.
enum ReplaySeed {
    static func write(root: StorageRoot) async {
        let paper = PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter)
        var manifest = NotebookManifest(title: "Lecture Replay", defaults: paper, pages: [paper.newPage(), paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        let start = Date.now.addingTimeInterval(-3600), duration: TimeInterval = 20, file = "\(UUID().uuidString).wav"
        try? await package.create(manifest)
        try? FileManager.default.createDirectory(at: package.assetsDirectory, withIntermediateDirectories: true)
        try? silence(seconds: duration).write(to: package.assetURL(file))
        var entry = RecordingEntry(id: UUID(), file: file, createdAt: start.addingTimeInterval(duration), duration: duration)
        entry.startedAt = start
        entry.inkedPages = manifest.pages.map(\.id)
        manifest.recordings = [entry]
        let first = [stroke(y: 140, at: start.addingTimeInterval(-60)), stroke(y: 220, at: start.addingTimeInterval(2)),
                     stroke(y: 300, at: start.addingTimeInterval(6)), stroke(y: 380, at: start.addingTimeInterval(10))]
        let second = [stroke(y: 160, at: start.addingTimeInterval(14)), stroke(y: 240, at: start.addingTimeInterval(18))]
        _ = try? await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: PKDrawing(strokes: first),
                                                                              manifest.pages[1].id: PKDrawing(strokes: second)]))
    }

    static func stroke(y: CGFloat, at date: Date) -> PKStroke {
        let points = (0...12).map { index in
            PKStrokePoint(location: CGPoint(x: 120 + CGFloat(index) * 30, y: y + 12 * sin(CGFloat(index))), timeOffset: Double(index) * 0.05,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: date))
    }

    /// A mono 16-bit WAV file of silence.
    static func silence(seconds: TimeInterval, rate: Int = 8000) -> Data {
        let bytes = Int(seconds * Double(rate)) * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(bytes))
        data.append(Data(count: bytes))
        return data
    }
}

/// Capital letters made of straight strokes, so tests have handwriting the recogniser can read.
enum BlockLetters {
    private static let shapes: [Character: [[(CGFloat, CGFloat)]]] = [
        "A": [[(0, 6), (2, 0), (4, 6)], [(1, 3.6), (3, 3.6)]],
        "E": [[(4, 0), (0, 0), (0, 6), (4, 6)], [(0, 3), (3, 3)]],
        "F": [[(4, 0), (0, 0), (0, 6)], [(0, 3), (3, 3)]],
        "H": [[(0, 0), (0, 6)], [(4, 0), (4, 6)], [(0, 3), (4, 3)]],
        "I": [[(2, 0), (2, 6)]],
        "K": [[(0, 0), (0, 6)], [(4, 0), (0, 3.4), (4, 6)]],
        "L": [[(0, 0), (0, 6), (4, 6)]],
        "M": [[(0, 6), (0, 0), (2, 3.5), (4, 0), (4, 6)]],
        "N": [[(0, 6), (0, 0), (4, 6), (4, 0)]],
        "O": [[(1, 0), (3, 0), (4, 1.5), (4, 4.5), (3, 6), (1, 6), (0, 4.5), (0, 1.5), (1, 0)]],
        "T": [[(0, 0), (4, 0)], [(2, 0), (2, 6)]],
        "V": [[(0, 0), (2, 6), (4, 0)]],
        "W": [[(0, 0), (1, 6), (2, 2.5), (3, 6), (4, 0)]],
        "X": [[(0, 0), (4, 6)], [(4, 0), (0, 6)]],
        "Y": [[(0, 0), (2, 3)], [(4, 0), (2, 3)], [(2, 3), (2, 6)]],
        "Z": [[(0, 0), (4, 0), (0, 6), (4, 6)]],
    ]

    /// `text` written from `origin`, each letter `height` tall, one stroke after another from `date`.
    static func strokes(_ text: String, origin: CGPoint, height: CGFloat = 48, from date: Date = .now) -> [PKStroke] {
        let unit = height / 6
        var x = origin.x, strokes: [PKStroke] = []
        for letter in text.uppercased() {
            for line in shapes[letter] ?? [] {
                let corners = line.map { CGPoint(x: x + $0.0 * unit, y: origin.y + $0.1 * unit) }
                var points: [PKStrokePoint] = []
                for (a, b) in zip(corners, corners.dropFirst()) {
                    let steps = max(Int(hypot(b.x - a.x, b.y - a.y) / 4), 1)
                    for step in (points.isEmpty ? 0 : 1)...steps {
                        let t = CGFloat(step) / CGFloat(steps)
                        points.append(PKStrokePoint(location: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), timeOffset: Double(points.count) * 0.01,
                                                    size: CGSize(width: 3.5, height: 3.5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
                    }
                }
                strokes.append(PKStroke(ink: PKInk(.pen, color: .black),
                                        path: PKStrokePath(controlPoints: points, creationDate: date.addingTimeInterval(Double(strokes.count) * 0.6))))
            }
            x += unit * (letter == " " ? 4 : 6)
        }
        return strokes
    }
}

/// A notebook with a line of handwriting, for trying handwriting to text, study tape and the time-lapse.
enum HandwritingSeed {
    static func write(root: StorageRoot) async {
        let paper = PageDefaults(template: .blank, paperColor: .white, pageSize: .letter)
        let manifest = NotebookManifest(title: "Study Notes", defaults: paper, pages: [paper.newPage(), paper.newPage()])
        let package = NotebookPackage(root: root, id: manifest.id)
        try? await package.create(manifest)
        let ink = PKDrawing(strokes: BlockLetters.strokes("HELLO", origin: CGPoint(x: 150, y: 160), from: Date.now.addingTimeInterval(-600)))
        guard let saved = try? await package.write(SaveSnapshot(manifest: manifest, ink: [manifest.pages[0].id: ink])),
              LaunchOptions.arguments.contains("-indexSeed") else { return }
        _ = await HandwritingIndexer.shared.index(HandwritingIndexer.Job(package: package, pages: saved.manifest.pages))
    }
}

/// A notebook of typed notes with a strip of study tape and three flashcards, two of them due (`-seedStudy`).
enum StudySeed {
    static let notes = """
        Mitochondria make ATP, the cell's energy.
        Ribosomes build proteins from amino acids.
        The nucleus holds the cell's DNA.
        Chloroplasts turn light into sugar in plants.
        The cell membrane decides what goes in and out.
        """

    static func write(root: StorageRoot) async {
        let paper = PageDefaults(template: .dotted, paperColor: .ivory, pageSize: .letter)
        var page = paper.newPage()
        var box = TextBox(string: notes)
        box.fontSize = 17
        let width: CGFloat = 400
        page.items = [PageItem(content: .text(box), center: CGPoint(x: 280, y: 220), size: CGSize(width: width, height: box.height(width: width))),
                      PageItem(content: .tape(.mustard), center: CGPoint(x: 240, y: 178), size: CGSize(width: 120, height: 24))]
        var manifest = NotebookManifest(title: "Biology", defaults: paper, pages: [page, paper.newPage()])
        manifest.cover.cloth = .moss
        let package = NotebookPackage(root: root, id: manifest.id)
        try? await package.create(manifest)
        let ink = PKDrawing(strokes: BlockLetters.strokes("HELLO", origin: CGPoint(x: 90, y: 420), from: Date.now.addingTimeInterval(-600)))
        _ = try? await package.write(SaveSnapshot(manifest: manifest, ink: [page.id: ink]))
        var later = Flashcard(front: CardSide(text: "What does the nucleus hold?"), back: CardSide(text: "The cell's DNA"), pageID: page.id)
        later = CardSchedule.graded(later, .easy)
        let cards = [Flashcard(front: CardSide(text: "What makes ATP?"), back: CardSide(text: "Mitochondria"), pageID: page.id),
                     Flashcard(front: CardSide(text: "What do ribosomes build?"), back: CardSide(text: "Proteins, from amino acids"), pageID: page.id),
                     later]
        try? CardFiles.write(cards, to: package.url)
    }
}

enum LibrarySeed {
    /// Writes `count` notebooks with a mix of cover styles and a few folders, for scrolling tests.
    static func write(count: Int, root: StorageRoot) async {
        var folderFile = FolderFile()
        let folders = ["Biology", "Studio", "Physics", "Journal"].enumerated().map { index, name in
            FolderEntry(id: UUID(), name: name, clothRaw: ClothColor.allCases[index * 2].rawValue, createdAt: .now, sortIndex: index)
        }
        folderFile.folders = folders
        try? folderFile.write(root)
        let titles = ["Cell Biology", "Studio Notes", "Physics II", "Recipes", "Field Journal", "Ideas", "Genetics", "Lab Book", "Reading Notes", "Exam Prep"]
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                group.addTask {
                    let id = UUID()
                    var cover = CoverSpec.defaultCloth(for: id)
                    cover.style = [CoverStyle.cloth, .print, .cloth, .firstPage][index % 4]
                    cover.inks = RisoInk.pairs[index % RisoInk.pairs.count]
                    var manifest = NotebookManifest(id: id, title: "\(titles[index % titles.count]) \(index + 1)",
                                                    createdAt: Date.now.addingTimeInterval(-Double(index) * 3600 * 7), cover: cover,
                                                    defaults: PageDefaults(template: .narrowRuled, paperColor: .white, pageSize: .letter),
                                                    pages: (0..<(1 + index % 6)).map { _ in .template(.narrowRuled, color: .white, size: .letter) })
                    manifest.modifiedAt = manifest.createdAt
                    manifest.library.isFavorite = index % 7 == 0
                    if index == 0 { manifest.library.lastOpenedAt = .now }
                    manifest.library.folderID = index % 3 == 0 ? folders[index % folders.count].id : nil
                    try? await NotebookPackage(root: root, id: id).create(manifest)
                }
            }
        }
    }

    /// One notebook made from a generated 300-page PDF, for scrolling and zoom tests in the editor.
    static func writeLongPDF(root: StorageRoot) async {
        let id = UUID()
        let package = NotebookPackage(root: root, id: id)
        let source = FileManager.default.temporaryDirectory.appending(path: "seed-\(id.uuidString).pdf")
        let bounds = CGRect(origin: .zero, size: PageSize.letter.points)
        try? UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: source) { context in
            for index in 0..<300 {
                context.beginPage()
                ("Chapter \(index + 1)" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 28)])
                for line in 0..<30 {
                    ("Body text line \(line + 1) on page \(index + 1)." as NSString)
                        .draw(at: CGPoint(x: 72, y: 130 + CGFloat(line) * 20), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
                }
            }
        }
        guard let file = try? await package.importAsset(from: source, ext: "pdf"),
              let pages = try? PDFImport.pages(at: package.assetURL(file), file: file) else { return }
        var cover = CoverSpec.defaultCloth(for: id)
        cover.style = .firstPage
        try? await package.create(NotebookManifest(id: id, title: "Textbook", cover: cover,
                                                   defaults: PageDefaults(template: .blank, paperColor: .white, pageSize: .letter), pages: pages))
        if LaunchOptions.arguments.contains("-indexSeed") {
            _ = await HandwritingIndexer.shared.index(HandwritingIndexer.Job(package: package, pages: pages))
        }
    }
}
#endif
