import UIKit

/// One picture, sticker, text box or link in the editor, under the canvas, or a strip of study tape over it.
/// Its frame follows the page's baked scale.
final class PageItemView: UIView {
    private(set) var item: PageItem
    private let assets: URL
    private var loadedFile: String?
    /// A picture is shown by its own layer, so a redraw of the view after a resize can't blank it.
    private let picture = CALayer()
    private var onDark = false
    private var linkTitle = ""
    private var linkResolved = true
    private var isLifted = false
    var onActivate: ((UUID) -> Void)?

    init(item: PageItem, assets: URL) {
        self.item = item
        self.assets = assets
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
        picture.contentsGravity = .resize
        layer.addSublayer(picture)
        isAccessibilityElement = true
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ newItem: PageItem, onDark: Bool = false, links: LinkTitles = LinkTitles(), lifted: Bool = false) {
        let title = newItem.link.map(links.title(for:)) ?? "", resolved = newItem.link.map(links.resolves) ?? true
        let changed = newItem.content != item.content || onDark != self.onDark || title != linkTitle || resolved != linkResolved || lifted != isLifted
        item = newItem
        self.onDark = onDark
        linkTitle = title
        linkResolved = resolved
        isLifted = lifted
        // Tape takes the touches that land on it, so a tap lifts it and nothing is written on it.
        isUserInteractionEnabled = newItem.isOverInk
        if changed { reload() }
    }

    func layout(scale: CGFloat) {
        transform = .identity
        bounds = CGRect(x: 0, y: 0, width: item.size.width * scale, height: item.size.height * scale)
        center = CGPoint(x: item.center.x * scale, y: item.center.y * scale)
        transform = CGAffineTransform(rotationAngle: item.rotation)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = bounds
        CATransaction.commit()
        guard item.assetFile == nil else { return }
        // Something drawn and enlarged at 5× would otherwise back tens of megabytes of pixels.
        let screen = traitCollection.displayScale
        let wanted = min(screen, max(1, 2400 / max(bounds.width, bounds.height, 1)))
        if contentScaleFactor != wanted { contentScaleFactor = wanted }
    }

    private func reload() {
        accessibilityHint = String(localized: "Touch and hold to move or resize")
        accessibilityTraits = .image
        accessibilityValue = nil
        isAccessibilityElement = true
        if item.assetFile == nil {
            picture.contents = nil
            loadedFile = nil
            setNeedsDisplay()
        }
        switch item.content {
        case .sticker:
            accessibilityLabel = item.sticker.map { String(localized: "Sticker, \($0.displayName)") } ?? String(localized: "Sticker")
        case .image(let file):
            accessibilityLabel = item.source == nil ? String(localized: "Picture") : String(localized: "Sticker")
            guard file != loadedFile else { return }
            loadedFile = file
            let assets = assets
            Task { [weak self] in
                let image = await Task.detached(priority: .userInitiated) { PageItemRenderer.image(file, assets: assets).map(SharedImage.init) }.value
                guard let self, self.loadedFile == file else { return }
                self.picture.contents = image?.image
            }
        case .text(let box):
            accessibilityLabel = box.string
            accessibilityTraits = .staticText
        case .link(let link):
            accessibilityTraits = .link
            switch link.kind {
            case .page:
                accessibilityLabel = linkResolved ? String(localized: "Link to \(linkTitle)") : String(localized: "Link to a page that was deleted")
                accessibilityHint = String(localized: "Opens the page. Touch and hold to move or resize.")
            case .notebook:
                accessibilityLabel = linkResolved ? String(localized: "Link to the notebook \(linkTitle)") : String(localized: "Link to a notebook that was deleted")
                accessibilityHint = String(localized: "Opens the notebook. Touch and hold to move or resize.")
            case .web:
                accessibilityLabel = String(localized: "Web link, \(linkTitle)")
                accessibilityHint = String(localized: "Opens the address in your browser. Touch and hold to move or resize.")
            }
        case .tape:
            accessibilityLabel = String(localized: "Study tape")
            accessibilityValue = isLifted ? String(localized: "Lifted") : String(localized: "Covering")
            accessibilityTraits = .button
            accessibilityHint = String(localized: "Lifts the tape or puts it back. Touch and hold to move or resize.")
        case .unknown:
            isAccessibilityElement = false
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        switch item.content {
        case .sticker:
            item.sticker?.draw(in: ctx, rect: bounds)
        case .text(let box):
            let scale = bounds.width / max(item.size.width, 1)
            ctx.scaleBy(x: scale, y: scale)
            box.draw(in: ctx, rect: CGRect(origin: .zero, size: item.size), onDark: onDark)
        case .link(let link):
            PageLinkArt.draw(title: linkTitle, kind: link.kind, resolved: linkResolved, in: ctx, rect: bounds)
        case .tape(let color):
            TapeArt.draw(color, lifted: isLifted, in: ctx, rect: bounds)
        case .image, .unknown:
            break
        }
    }

    override func accessibilityActivate() -> Bool {
        onActivate?(item.id)
        return onActivate != nil
    }
}

/// The stitched outline and handle round the selected item. It sits above the canvas, so touches on the item move
/// it instead of drawing. Every change is reported as a whole item; `final` marks the end of a gesture.
final class ItemSelectionView: UIView, UIGestureRecognizerDelegate {
    static let outset: CGFloat = 8
    private static let handleSize: CGFloat = 44

    private(set) var item: PageItem
    var pageSize: CGSize
    var scale: CGFloat = 1
    var onChange: ((PageItem, _ final: Bool) -> Void)?
    var onTap: (() -> Void)?
    /// While its text is being typed the outline stays and the handles step aside.
    var isEditing = false {
        didSet {
            isUserInteractionEnabled = !isEditing
            show(item)
        }
    }

    private let outline = CAShapeLayer()
    private let underline = CAShapeLayer()
    private let handle = UIView()
    private let knob = UIImageView()
    private let side = UIView()
    private let grip = UIView()
    private var base: PageItem?
    private var pinch: CGFloat = 1
    private var twist: CGFloat = 0
    private var handleStart: CGPoint = .zero
    private(set) lazy var recognizers: [UIGestureRecognizer] = [
        UIPanGestureRecognizer(target: self, action: #selector(dragged)),
        UIPinchGestureRecognizer(target: self, action: #selector(pinched)),
        UIRotationGestureRecognizer(target: self, action: #selector(twisted)),
    ]
    private(set) lazy var handlePan = UIPanGestureRecognizer(target: self, action: #selector(dragHandle))
    private lazy var sidePan = UIPanGestureRecognizer(target: self, action: #selector(dragSide))

    init(item: PageItem, pageSize: CGSize) {
        self.item = item
        self.pageSize = pageSize
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = false
        for (layer, color, width) in [(underline, UIColor.ink.withAlphaComponent(0.55), 3.5 as CGFloat), (outline, UIColor.mustard, 2)] {
            layer.fillColor = nil
            layer.strokeColor = color.cgColor
            layer.lineWidth = width
            self.layer.addSublayer(layer)
        }
        outline.lineDashPattern = [7, 5]
        outline.lineCap = .round
        handle.frame = CGRect(x: 0, y: 0, width: Self.handleSize, height: Self.handleSize)
        knob.frame = handle.bounds.insetBy(dx: 8, dy: 8)
        knob.backgroundColor = .surface
        knob.layer.cornerRadius = knob.bounds.width / 2
        knob.layer.borderWidth = 1
        knob.layer.borderColor = UIColor.ink.withAlphaComponent(0.35).cgColor
        knob.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        knob.tintColor = .ink
        knob.contentMode = .center
        handle.addSubview(knob)
        addSubview(handle)
        handle.addGestureRecognizer(handlePan)
        handle.isAccessibilityElement = true
        handle.accessibilityLabel = String(localized: "Resize and rotate")
        handle.accessibilityTraits = .adjustable
        (recognizers[0] as? UIPanGestureRecognizer)?.maximumNumberOfTouches = 1
        for recognizer in recognizers {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
        handlePan.delegate = self
        side.frame = CGRect(x: 0, y: 0, width: Self.handleSize, height: Self.handleSize)
        grip.frame = CGRect(x: (Self.handleSize - 10) / 2, y: (Self.handleSize - 28) / 2, width: 10, height: 28)
        grip.backgroundColor = .surface
        grip.layer.cornerRadius = 2
        grip.layer.borderWidth = 1
        grip.layer.borderColor = UIColor.ink.withAlphaComponent(0.35).cgColor
        side.addSubview(grip)
        addSubview(side)
        side.addGestureRecognizer(sidePan)
        side.isAccessibilityElement = true
        side.accessibilityLabel = String(localized: "Change width")
        side.accessibilityTraits = .adjustable
        sidePan.delegate = self
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @objc private func tapped() { onTap?() }

    required init?(coder: NSCoder) { fatalError() }

    var isChanging: Bool { base != nil }

    func show(_ newItem: PageItem) {
        item = newItem
        transform = .identity
        let outset = Self.outset
        bounds = CGRect(x: 0, y: 0, width: item.size.width * scale + outset * 2, height: item.size.height * scale + outset * 2)
        center = CGPoint(x: item.center.x * scale, y: item.center.y * scale)
        transform = CGAffineTransform(rotationAngle: item.rotation)
        let path = UIBezierPath(roundedRect: bounds.insetBy(dx: outset / 2, dy: outset / 2), cornerRadius: 4).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.path = path
        underline.path = path
        outline.strokeColor = UIColor.mustard.resolvedColor(with: traitCollection).cgColor
        underline.strokeColor = UIColor.ink.resolvedColor(with: traitCollection).withAlphaComponent(0.55).cgColor
        CATransaction.commit()
        // A text box or a strip of tape keeps its right edge for the width grip, so its corner handle moves to the left.
        let hasGrip = item.text != nil || item.tape != nil
        handle.center = CGPoint(x: hasGrip ? bounds.minX + outset / 2 : bounds.maxX - outset / 2, y: bounds.maxY - outset / 2)
        handle.isHidden = isEditing
        side.center = CGPoint(x: bounds.maxX - outset / 2, y: bounds.midY)
        side.isHidden = isEditing || !hasGrip
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point) || handle.frame.contains(point) || (!side.isHidden && side.frame.contains(point))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        recognizers.contains(gestureRecognizer) && recognizers.contains(other)
    }

    /// The page's own scroll and zoom wait for these, so two fingers on the item resize it and don't zoom the page.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other.view is UIScrollView
    }

    private func begin() {
        if base == nil {
            base = item
            pinch = 1
            twist = 0
        }
    }

    private func report(_ changed: PageItem, state: UIGestureRecognizer.State) {
        var changed = changed
        changed.center.x = min(max(changed.center.x, 0), pageSize.width)
        changed.center.y = min(max(changed.center.y, 0), pageSize.height)
        let others = (recognizers + [handlePan, sidePan]).contains { $0.state == .began || $0.state == .changed }
        switch state {
        case .changed:
            onChange?(changed, false)
        case .ended where others:
            onChange?(changed, false)
        case .ended:
            base = nil
            onChange?(changed, true)
        case .cancelled, .failed:
            guard !others, let base else { return }
            self.base = nil
            onChange?(base, false)
        default:
            break
        }
    }

    private func composed(from base: PageItem, translation: CGPoint = .zero) -> PageItem {
        var changed = base.scaled(by: pinch, limit: max(pageSize.width, pageSize.height) * 1.5)
        changed.rotation = Self.snapped(base.rotation + twist)
        changed.center = CGPoint(x: item.center.x + translation.x, y: item.center.y + translation.y)
        return changed
    }

    /// Settles on the quarter turns when within three degrees of one.
    static func snapped(_ angle: CGFloat) -> CGFloat {
        let quarter = CGFloat.pi / 2
        let nearest = (angle / quarter).rounded() * quarter
        return abs(angle - nearest) < 3 * .pi / 180 ? nearest : angle
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        if gesture.state == .began { begin() }
        guard let base else { return }
        let moved = gesture.translation(in: superview)
        gesture.setTranslation(.zero, in: superview)
        report(composed(from: base, translation: CGPoint(x: moved.x / max(scale, 0.01), y: moved.y / max(scale, 0.01))), state: gesture.state)
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { begin() }
        guard let base else { return }
        pinch = gesture.scale
        report(composed(from: base), state: gesture.state)
    }

    @objc private func twisted(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .began { begin() }
        guard let base else { return }
        twist = gesture.rotation
        report(composed(from: base), state: gesture.state)
    }

    @objc private func dragHandle(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        let point = gesture.location(in: superview)
        let vector = CGPoint(x: point.x - center.x, y: point.y - center.y)
        if gesture.state == .began {
            begin()
            handleStart = vector
        }
        guard let base else { return }
        let start = max(hypot(handleStart.x, handleStart.y), 1)
        pinch = hypot(vector.x, vector.y) / start
        twist = atan2(vector.y, vector.x) - atan2(handleStart.y, handleStart.x)
        report(composed(from: base), state: gesture.state)
    }

    /// The side grip changes the width: a text box wraps again and grows downwards, tape gets longer.
    @objc private func dragSide(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        if gesture.state == .began { begin() }
        guard let base else { return }
        let moved = gesture.translation(in: superview)
        let along = (moved.x * cos(base.rotation) + moved.y * sin(base.rotation)) / max(scale, 0.01)
        let width = min(max(base.size.width + along, 40), pageSize.width * 1.5)
        report(base.resized(to: CGSize(width: width, height: base.text?.height(width: width) ?? base.size.height)), state: gesture.state)
    }
}
