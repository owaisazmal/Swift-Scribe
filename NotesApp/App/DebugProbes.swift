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
