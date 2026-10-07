import UIKit

extension Notification.Name {
    static let owlLunaExternalDisplayChanged = Notification.Name("owlLunaExternalDisplayChanged")
}

enum LaserEvent {
    /// Where the laser is on the presented page, as a fraction of its width and height.
    case began(CGPoint), moved(CGPoint)
    case ended, cleared
}

/// Where a page sits on the second screen so that the part showing on the iPad fills it.
enum PresentationStage {
    /// `viewport` is the part of the page to show, as fractions of the page. The result is the whole page's frame.
    static func pageFrame(pageSize: CGSize, viewport: CGRect, in bounds: CGSize) -> CGRect {
        guard pageSize.width > 0, pageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let shown = viewport.width > 0.01 && viewport.height > 0.01 ? viewport : CGRect(x: 0, y: 0, width: 1, height: 1)
        let scale = min(bounds.width / (shown.width * pageSize.width), bounds.height / (shown.height * pageSize.height))
        let size = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        return CGRect(x: bounds.width / 2 - shown.midX * size.width, y: bounds.height / 2 - shown.midY * size.height, width: size.width, height: size.height)
    }

    /// How wide to render a page for a screen of `pixels`: twice what fits, for zooming in, within a sensible memory budget.
    static func renderWidth(pageSize: CGSize, pixels: CGSize) -> CGFloat {
        guard pageSize.width > 0, pageSize.height > 0 else { return 1 }
        let fit = min(pixels.width / pageSize.width, pixels.height / pageSize.height)
        let budget = (12_000_000 / (pageSize.width * pageSize.height)).squareRoot()
        return (pageSize.width * min(fit * 2, budget)).rounded()
    }
}

/// A screen the iPad is plugged into or sending to. OwlLuna only takes it over while a notebook is being presented:
/// then it shows the page and the laser, and nothing else. The rest of the time it is left to mirror the iPad.
@MainActor
@Observable
final class ExternalDisplay {
    static let shared = ExternalDisplay()

    private(set) var isConnected = false
    /// True while a presentation is on the second screen.
    private(set) var isShowing = false
    @ObservationIgnored private var scenes: [UIWindowScene] = []
    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var stage: PresentationStageController?
    @ObservationIgnored private weak var presenter: AnyObject?

    func connect(_ scene: UIWindowScene) {
        guard !scenes.contains(scene) else { return }
        scenes.append(scene)
        isConnected = true
        if presenter != nil { open() }
    }

    func disconnect(_ scene: UIScene) {
        scenes.removeAll { $0 === scene }
        isConnected = !scenes.isEmpty
        if window?.windowScene === scene || window?.windowScene == nil {
            close()
            if presenter != nil { open() }
        }
    }

    /// The pixels the page is rendered for, or nil when there is no second screen to show it on.
    func pixelSize(for presenter: AnyObject) -> CGSize? {
        guard presenter === self.presenter, let stage, let scene = window?.windowScene else { return nil }
        let scale = scene.screen.scale
        return CGSize(width: stage.view.bounds.width * scale, height: stage.view.bounds.height * scale)
    }

    func begin(for presenter: AnyObject) {
        self.presenter = presenter
        open()
    }

    func end(for presenter: AnyObject) {
        guard presenter === self.presenter else { return }
        self.presenter = nil
        close()
    }

    func show(_ image: UIImage, pageSize: CGSize, by presenter: AnyObject) {
        guard presenter === self.presenter else { return }
        stage?.show(image, pageSize: pageSize)
    }

    func setViewport(_ viewport: CGRect, by presenter: AnyObject) {
        guard presenter === self.presenter else { return }
        stage?.viewport = viewport
    }

    func laser(_ event: LaserEvent, color: UIColor, by presenter: AnyObject) {
        guard presenter === self.presenter else { return }
        stage?.laser(event, color: color)
    }

    private func open() {
        guard window == nil else { return }
        let stage = PresentationStageController()
        let window: UIWindow
        if let scene = scenes.first {
            window = UIWindow(windowScene: scene)
        } else {
            #if DEBUG
            guard let inset = SecondScreenInset.window() else { return }
            window = inset
            #else
            return
            #endif
        }
        window.rootViewController = stage
        window.isHidden = false
        self.window = window
        self.stage = stage
        isShowing = true
        NotificationCenter.default.post(name: .owlLunaExternalDisplayChanged, object: nil)
    }

    private func close() {
        window?.isHidden = true
        window = nil
        stage = nil
        guard isShowing else { return }
        isShowing = false
        NotificationCenter.default.post(name: .owlLunaExternalDisplayChanged, object: nil)
    }
}

final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        ExternalDisplay.shared.connect(scene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplay.shared.disconnect(scene)
    }
}

/// What the audience sees: the page on black, and the laser.
final class PresentationStageController: UIViewController {
    private let pageView = UIImageView()
    private let trail = LaserTrailView()
    private var pageSize = CGSize.zero
    var viewport = CGRect(x: 0, y: 0, width: 1, height: 1) {
        didSet { if viewport != oldValue { place() } }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.accessibilityIdentifier = "presentation.stage"
        pageView.contentMode = .scaleToFill
        pageView.accessibilityIdentifier = "presentation.stage.page"
        view.addSubview(pageView)
        trail.frame = view.bounds
        trail.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(trail)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // A dot sized for a tablet at arm's length is lost on a projector.
        trail.weight = max(1, min(view.bounds.width, view.bounds.height) / 480)
        place()
    }

    func show(_ image: UIImage, pageSize: CGSize) {
        loadViewIfNeeded()
        self.pageSize = pageSize
        pageView.image = image
        place()
    }

    private func place() {
        guard isViewLoaded else { return }
        pageView.frame = PresentationStage.pageFrame(pageSize: pageSize, viewport: viewport, in: view.bounds.size)
    }

    func laser(_ event: LaserEvent, color: UIColor) {
        loadViewIfNeeded()
        trail.color = color
        let frame = pageView.frame
        func point(_ unit: CGPoint) -> CGPoint { CGPoint(x: frame.minX + unit.x * frame.width, y: frame.minY + unit.y * frame.height) }
        switch event {
        case .began(let unit): trail.begin(at: point(unit))
        case .moved(let unit): trail.move(to: point(unit))
        case .ended: trail.end()
        case .cleared: trail.clear()
        }
    }
}
