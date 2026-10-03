import UIKit
import PencilKit

/// The part of a page the zoom window magnifies, and how it moves along as a line is written.
struct ZoomWindow: Equatable {
    /// How much of the page's width the window shows, from closest in to furthest out.
    static let widths: [CGFloat] = [0.3, 0.42, 0.6]
    /// Writing that reaches this far across the window moves it on once the pen rests.
    static let advanceZone: CGFloat = 0.7
    /// How far it moves on, as a fraction of its width: what was just written stays in view on the left.
    static let stride: CGFloat = 0.55
    /// How long the pen rests before the window moves on.
    static let rest: TimeInterval = 0.8

    let pageID: UUID
    private(set) var pageSize: CGSize
    /// The magnified area, in page points.
    private(set) var rect: CGRect
    /// Where lines start: the left edge the window goes back to for a new line.
    private(set) var lineStart: CGFloat
    private(set) var lineHeight: CGFloat

    init(pageID: UUID, pageSize: CGSize, center: CGPoint, size: CGSize, lineHeight: CGFloat) {
        self.pageID = pageID
        self.pageSize = pageSize
        self.lineHeight = max(lineHeight, 8)
        rect = .zero
        lineStart = 0
        resize(to: size)
        move(to: CGPoint(x: center.x - rect.width / 2, y: center.y - rect.height / 2))
    }

    /// The gap between the lines of ruled, squared and dotted paper; half the window's height on anything else.
    static func lineHeight(for page: NotebookPage, windowHeight: CGFloat) -> CGFloat {
        let unit = page.size.width / 800
        switch page.template {
        case .narrowRuled, .cornell, .checklist: return 28 * unit
        case .wideRuled: return 38 * unit
        case .grid, .dotted: return 26 * unit
        default: return windowHeight * 0.5
        }
    }

    private func clamped(_ origin: CGPoint) -> CGPoint {
        CGPoint(x: min(max(origin.x, 0), max(pageSize.width - rect.width, 0)), y: min(max(origin.y, 0), max(pageSize.height - rect.height, 0)))
    }

    /// Placed by hand: lines now start here.
    mutating func move(to origin: CGPoint) {
        rect.origin = clamped(origin)
        lineStart = rect.minX
    }

    /// A new size about the same top-left corner, never larger than the page.
    mutating func resize(to size: CGSize) {
        rect.size = CGSize(width: min(max(size.width, 20), pageSize.width), height: min(max(size.height, 10), pageSize.height))
        rect.origin = clamped(rect.origin)
        lineStart = min(lineStart, rect.minX)
    }

    mutating func fit(pageSize size: CGSize) {
        pageSize = size
        resize(to: rect.size)
    }

    var isAtLineEnd: Bool { rect.maxX >= pageSize.width - 0.5 }
    var isAtPageEnd: Bool { rect.maxY >= pageSize.height - 0.5 }

    /// The band on the right of the window: ink that reaches it moves the window on.
    var advanceBand: CGRect {
        CGRect(x: rect.minX + rect.width * Self.advanceZone, y: rect.minY, width: rect.width * (1 - Self.advanceZone), height: rect.height)
    }

    func reachesAdvanceBand(_ bounds: CGRect) -> Bool {
        !bounds.isNull && bounds.maxX > advanceBand.minX && bounds.intersects(rect.insetBy(dx: 0, dy: -rect.height))
    }

    /// Along the line; at the end of it, down to the start of the next. Returns whether it moved.
    @discardableResult
    mutating func advance() -> Bool {
        if isAtLineEnd { return newLine() }
        rect.origin.x = clamped(CGPoint(x: rect.minX + rect.width * Self.stride, y: rect.minY)).x
        return true
    }

    @discardableResult
    mutating func back() -> Bool {
        let x = clamped(CGPoint(x: rect.minX - rect.width * Self.stride, y: rect.minY)).x
        defer { rect.origin.x = x }
        return x != rect.minX
    }

    @discardableResult
    mutating func newLine() -> Bool {
        let origin = clamped(CGPoint(x: lineStart, y: rect.minY + lineHeight))
        defer { rect.origin = origin }
        return origin != rect.origin
    }
}

/// The outline on the page of what the zoom window is showing. Only its tab takes touches: the page under the
/// outline is still written on.
final class ZoomTargetView: UIView {
    static let tabSize = CGSize(width: 48, height: 30)

    /// VoiceOver's swipe up and down on the tab move the window along the line.
    private final class Tab: UIView {
        var onStep: ((Int) -> Void)?
        override func accessibilityIncrement() { onStep?(1) }
        override func accessibilityDecrement() { onStep?(-1) }
    }

    private let outline = CAShapeLayer()
    private let band = CALayer()
    private let tab = Tab()
    let pan = UIPanGestureRecognizer()
    var onStep: ((Int) -> Void)? {
        get { tab.onStep }
        set { tab.onStep = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        band.backgroundColor = UIColor.tintColor.withAlphaComponent(0.08).cgColor
        layer.addSublayer(band)
        outline.fillColor = nil
        outline.lineWidth = 2
        layer.addSublayer(outline)

        tab.layer.cornerRadius = 8
        tab.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let icon = UIImageView(image: UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.frame = CGRect(origin: .zero, size: Self.tabSize)
        tab.addSubview(icon)
        tab.addGestureRecognizer(pan)
        tab.isAccessibilityElement = true
        tab.accessibilityLabel = String(localized: "Zoom area")
        tab.accessibilityHint = String(localized: "Drag to choose the part of the page the zoom window shows. Swipe up or down to move it along the line.")
        tab.accessibilityTraits = .adjustable
        tab.accessibilityIdentifier = "zoom.target"
        addSubview(tab)
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (self: Self, _) in self.applyColors() }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyColors() {
        let tint = UIColor.tintColor.resolvedColor(with: traitCollection)
        outline.strokeColor = tint.cgColor
        tab.backgroundColor = tint
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyColors()
    }

    var accessibilityPlace: String? {
        get { tab.accessibilityValue }
        set { tab.accessibilityValue = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.frame = bounds
        outline.path = CGPath(roundedRect: bounds.insetBy(dx: -1, dy: -1), cornerWidth: 3, cornerHeight: 3, transform: nil)
        band.frame = CGRect(x: bounds.width * ZoomWindow.advanceZone, y: 0, width: bounds.width * (1 - ZoomWindow.advanceZone), height: bounds.height)
        CATransaction.commit()
        // Above the outline, or below it when the outline is at the top of the page.
        let above = frame.minY >= Self.tabSize.height
        tab.frame = CGRect(x: 0, y: above ? -Self.tabSize.height : bounds.height, width: Self.tabSize.width, height: Self.tabSize.height)
        tab.layer.maskedCorners = above ? [.layerMinXMinYCorner, .layerMaxXMinYCorner] : [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        tab.frame.insetBy(dx: -6, dy: -6).contains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        self.point(inside: point, with: event) ? tab : nil
    }

    override var accessibilityElements: [Any]? {
        get { [tab] }
        set {}
    }
}

/// The strip at the bottom of the editor: the magnified part of the page, written in at a comfortable size, under a
/// row of buttons that move it.
final class ZoomWindowPanel: UIView {
    static let minimumBarHeight: CGFloat = 48

    enum Action: Int, CaseIterable {
        case back, forward, newLine, here, closer, further, close

        var symbol: String {
            switch self {
            case .back: "chevron.left"
            case .forward: "chevron.right"
            case .newLine: "return"
            case .here: "scope"
            case .closer: "plus.magnifyingglass"
            case .further: "minus.magnifyingglass"
            case .close: "xmark"
            }
        }

        var title: String {
            switch self {
            case .back: String(localized: "Move Back Along the Line")
            case .forward: String(localized: "Move Along the Line")
            case .newLine: String(localized: "Next Line")
            case .here: String(localized: "Bring the Zoom Area to This Page")
            case .closer: String(localized: "Zoom In")
            case .further: String(localized: "Zoom Out")
            case .close: String(localized: "Close Zoom Window")
            }
        }

        var identifier: String {
            switch self {
            case .back: "zoom.back"
            case .forward: "zoom.forward"
            case .newLine: "zoom.newline"
            case .here: "zoom.here"
            case .closer: "zoom.closer"
            case .further: "zoom.further"
            case .close: "zoom.close"
            }
        }
    }

    let canvasArea = UIView()
    let paper = UIImageView()
    private let band = UIView()
    private let bar = UIStackView()
    private let title = UILabel()
    private let rule = UIView()
    private var buttons: [Action: UIButton] = [:]
    var onAction: ((Action) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .board
        rule.backgroundColor = .hairline

        title.font = .preferredFont(forTextStyle: .subheadline).bold()
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .ink
        title.numberOfLines = 0
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.accessibilityTraits = .header
        title.accessibilityIdentifier = "zoom.title"
        bar.axis = .horizontal
        bar.alignment = .center
        bar.spacing = 2
        bar.addArrangedSubview(title)
        bar.addInteraction(UILargeContentViewerInteraction())
        for action in Action.allCases {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: action.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium, scale: .large))
            configuration.cornerStyle = .capsule
            configuration.background.backgroundInsets = NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.onAction?(action) })
            button.configurationUpdateHandler = { button in
                button.configuration?.baseForegroundColor = button.isEnabled ? .ink : UIColor.ink.withAlphaComponent(0.35)
                let pressed = button.isHighlighted && button.isEnabled
                button.configuration?.background.backgroundColor = pressed || UIAccessibility.buttonShapesEnabled ? .well : .clear
            }
            button.accessibilityLabel = action.title
            button.accessibilityIdentifier = action.identifier
            button.showsLargeContentViewer = true
            button.largeContentTitle = action.title
            button.scalesLargeContentImage = true
            button.isPointerInteractionEnabled = true
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            if action == .close { bar.setCustomSpacing(Space.x3, after: bar.arrangedSubviews.last ?? title) }
            bar.addArrangedSubview(button)
            buttons[action] = button
        }

        canvasArea.clipsToBounds = true
        canvasArea.backgroundColor = .white
        paper.contentMode = .topLeft
        paper.isAccessibilityElement = false
        canvasArea.addSubview(paper)
        band.isUserInteractionEnabled = false
        band.backgroundColor = UIColor.tintColor.withAlphaComponent(0.08)
        canvasArea.addSubview(band)

        // The row of buttons is as tall as its title needs; the paper takes the rest.
        for view in [bar, canvasArea, rule] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: Space.x4),
            bar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -Space.x2),
            bar.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumBarHeight),
            canvasArea.topAnchor.constraint(equalTo: bar.bottomAnchor),
            canvasArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvasArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvasArea.bottomAnchor.constraint(equalTo: bottomAnchor),
            rule.topAnchor.constraint(equalTo: topAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
        ])
        accessibilityIdentifier = "zoom.panel"
        NotificationCenter.default.addObserver(self, selector: #selector(buttonShapesChanged),
                                               name: UIAccessibility.buttonShapesEnabledStatusDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func buttonShapesChanged() {
        buttons.values.forEach { $0.setNeedsUpdateConfiguration() }
    }

    func setTitle(_ text: String) { title.text = text }

    /// How tall the row of buttons is at `width`: taller when the title wraps at large text sizes.
    func barHeight(forWidth width: CGFloat) -> CGFloat {
        let room = CGSize(width: max(width - Space.x4 - Space.x2 - safeAreaInsets.left - safeAreaInsets.right, 100), height: UIView.layoutFittingCompressedSize.height)
        let fitted = bar.systemLayoutSizeFitting(room, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        return max(fitted.rounded(.up), Self.minimumBarHeight)
    }

    func setEnabled(_ enabled: Bool, for action: Action) { buttons[action]?.isEnabled = enabled }

    /// The canvas goes over the paper and under the tint of the band that moves the window on.
    func host(_ canvas: UIView) {
        canvasArea.insertSubview(canvas, belowSubview: band)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        paper.frame = canvasArea.bounds
        band.frame = CGRect(x: canvasArea.bounds.width * ZoomWindow.advanceZone, y: 0, width: canvasArea.bounds.width * (1 - ZoomWindow.advanceZone),
                            height: canvasArea.bounds.height)
    }
}

private extension UIFont {
    func bold() -> UIFont {
        fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}
