import UIKit

enum LaserColor: String, CaseIterable, Identifiable {
    case red, green
    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .red: UIColor(hex: 0xFF3B2F)
        case .green: UIColor(hex: 0x22D36B)
        }
    }

    var displayName: String {
        switch self {
        case .red: String(localized: "Red")
        case .green: String(localized: "Green")
        }
    }
}

/// The presentation laser: a dot with a tail that fades behind it. Nothing it draws is saved.
final class LaserTrailView: UIView {
    var color = LaserColor.red.uiColor
    /// Scales the dot and its tail, for a screen seen from across a room.
    var weight: CGFloat = 1

    private struct Sample {
        let point: CGPoint
        let time: CFTimeInterval
        let startsStroke: Bool
    }

    private static let life: CFTimeInterval = 0.9
    private var samples: [Sample] = []
    private var head: CGPoint?
    private var link: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError() }

    var isTracking: Bool { head != nil }

    func begin(at point: CGPoint) {
        head = point
        samples.append(Sample(point: point, time: CACurrentMediaTime(), startsStroke: true))
        start()
    }

    func move(to point: CGPoint) {
        guard head != nil else { return begin(at: point) }
        head = point
        samples.append(Sample(point: point, time: CACurrentMediaTime(), startsStroke: false))
        setNeedsDisplay()
    }

    func end() {
        head = nil
        setNeedsDisplay()
    }

    func clear() {
        head = nil
        samples.removeAll()
        stop()
        setNeedsDisplay()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { clear() }
    }

    private func start() {
        setNeedsDisplay()
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() {
        let cutoff = CACurrentMediaTime() - Self.life
        if let first = samples.firstIndex(where: { $0.time >= cutoff }) {
            if first > 0 { samples.removeFirst(first) }
        } else {
            samples.removeAll()
        }
        if samples.isEmpty, head == nil { stop() }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let now = CACurrentMediaTime()
        ctx.setLineCap(.round)
        ctx.setShadow(offset: .zero, blur: 8 * weight, color: color.withAlphaComponent(0.8).cgColor)
        for (previous, sample) in zip(samples, samples.dropFirst()) where !sample.startsStroke {
            let strength = max(0, 1 - (now - sample.time) / Self.life)
            ctx.setStrokeColor(color.withAlphaComponent(strength).cgColor)
            ctx.setLineWidth((2 + 5 * strength) * weight)
            ctx.move(to: previous.point)
            ctx.addLine(to: sample.point)
            ctx.strokePath()
        }
        guard let head else { return }
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: head.x - 7 * weight, y: head.y - 7 * weight, width: 14 * weight, height: 14 * weight))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: head.x - 3 * weight, y: head.y - 3 * weight, width: 6 * weight, height: 6 * weight))
    }
}
