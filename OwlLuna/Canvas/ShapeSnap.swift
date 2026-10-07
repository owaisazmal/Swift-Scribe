import UIKit
import UIKit.UIGestureRecognizerSubclass
import PencilKit

/// What a hand-drawn stroke is tidied into when the pen rests before lifting.
enum SnappedShape: Equatable {
    case line(CGPoint, CGPoint)
    /// An open run of straight pieces, such as an L or a zigzag.
    case polyline([CGPoint])
    /// A closed figure with straight sides: a triangle, a rectangle, a diamond, a star.
    case polygon([CGPoint])
    case ellipse(center: CGPoint, radii: CGSize, rotation: CGFloat)

    var displayName: String {
        switch self {
        case .line: String(localized: "line")
        case .polyline: String(localized: "straight lines")
        case .polygon(let corners):
            corners.count == 3 ? String(localized: "triangle") : corners.count == 4 ? String(localized: "rectangle") : String(localized: "shape")
        case .ellipse(_, let radii, _): abs(radii.width - radii.height) < 0.5 ? String(localized: "circle") : String(localized: "ellipse")
        }
    }
}

/// Reads a shape out of the points of one stroke. Pure geometry, so it can be tested without a canvas.
enum ShapeRecognizer {
    static func recognize(_ raw: [CGPoint]) -> SnappedShape? {
        let points = resampled(raw, limit: 240)
        guard points.count >= 4, let first = points.first, let last = points.last else { return nil }
        let box = bounds(of: points)
        let diagonal = hypot(box.width, box.height)
        guard diagonal >= 24 else { return nil }
        let gap = distance(first, last)
        // Measured in long steps, so a hand's small tremor doesn't count as distance travelled.
        var length: CGFloat = 0, from = first
        for point in points.dropFirst() where distance(from, point) >= max(diagonal / 24, 6) || point == last {
            length += distance(from, point)
            from = point
        }

        if gap > max(0.2 * diagonal, 16) {
            let wander = points.map { distance($0, toSegment: first, last) }.max() ?? 0
            if gap / max(length, 1) >= 0.93, wander <= max(0.07 * gap, 4) {
                let (a, b) = squared(first, last)
                return .line(a, b)
            }
            // Straight pieces keep the same corners when looked at more closely; a curve keeps gaining them.
            let tolerance = max(0.045 * diagonal, 6)
            let corners = simplified(points, tolerance: tolerance)
            guard (3...8).contains(corners.count), simplified(points, tolerance: tolerance / 3).count <= corners.count + 1,
                  fit(points, to: corners, closed: false) <= 0.022 * diagonal + 1.5 else { return nil }
            return .polyline(corners)
        }

        let ellipse = bestEllipse(points, box: box)
        let ellipseError = ellipse.error / diagonal
        var corners = simplified(points + [first], tolerance: max(0.05 * diagonal, 6))
        if corners.count > 1 { corners.removeLast() }
        corners = withoutStraightCorners(corners)
        let polygonError = corners.count >= 3 ? fit(points, to: corners, closed: true) / diagonal : .infinity

        if (3...4).contains(corners.count), polygonError <= 0.035, !(ellipseError < 0.5 * polygonError) {
            return .polygon(corners.count == 4 ? rectangle(from: corners) ?? corners : corners)
        }
        if (5...12).contains(corners.count), polygonError <= 0.02, polygonError < 0.5 * ellipseError { return .polygon(corners) }
        if ellipseError <= 0.045 { return ellipse.shape }
        return nil
    }

    // MARK: Geometry

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0001 else { return distance(p, a) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
        return distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func resampled(_ points: [CGPoint], limit: Int) -> [CGPoint] {
        guard points.count > limit else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { points[min(Int((Double($0) * step).rounded()), points.count - 1)] }
    }

    /// Within three degrees of level or upright, a line is made exactly so.
    private static func squared(_ a: CGPoint, _ b: CGPoint) -> (CGPoint, CGPoint) {
        let angle = abs(atan2(b.y - a.y, b.x - a.x)), limit = 3 * CGFloat.pi / 180
        if angle < limit || angle > .pi - limit {
            let y = (a.y + b.y) / 2
            return (CGPoint(x: a.x, y: y), CGPoint(x: b.x, y: y))
        }
        if abs(angle - .pi / 2) < limit {
            let x = (a.x + b.x) / 2
            return (CGPoint(x: x, y: a.y), CGPoint(x: x, y: b.y))
        }
        return (a, b)
    }

    /// Ramer, Douglas and Peucker: the fewest points that stay within `tolerance` of the path.
    static func simplified(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var worst: CGFloat = 0, index = start
            for i in (start + 1)..<end {
                let d = distance(points[i], toSegment: points[start], points[end])
                if d > worst { worst = d; index = i }
            }
            if worst > tolerance {
                keep[index] = true
                stack.append((start, index))
                stack.append((index, end))
            }
        }
        return zip(points, keep).filter(\.1).map(\.0)
    }

    /// A stroke that starts in the middle of a side leaves a corner there that isn't one.
    private static func withoutStraightCorners(_ corners: [CGPoint]) -> [CGPoint] {
        var result = corners
        var changed = true
        while changed, result.count > 3 {
            changed = false
            for index in result.indices {
                let before = result[(index + result.count - 1) % result.count], here = result[index], after = result[(index + 1) % result.count]
                let a = atan2(here.y - before.y, here.x - before.x), b = atan2(after.y - here.y, after.x - here.x)
                var turn = abs(a - b)
                if turn > .pi { turn = 2 * .pi - turn }
                if turn < 22 * .pi / 180 || distance(before, here) < 0.08 * perimeter(result) / CGFloat(result.count) {
                    result.remove(at: index)
                    changed = true
                    break
                }
            }
        }
        return result
    }

    private static func perimeter(_ corners: [CGPoint]) -> CGFloat {
        corners.indices.reduce(CGFloat(0)) { $0 + distance(corners[$1], corners[($1 + 1) % corners.count]) }
    }

    /// Mean distance from the drawn points to the outline through `corners`.
    private static func fit(_ points: [CGPoint], to corners: [CGPoint], closed: Bool) -> CGFloat {
        guard corners.count >= 2 else { return .infinity }
        let count = closed ? corners.count : corners.count - 1
        let total = points.reduce(CGFloat(0)) { sum, point in
            var best = CGFloat.infinity
            for index in 0..<count { best = min(best, distance(point, toSegment: corners[index], corners[(index + 1) % corners.count])) }
            return sum + best
        }
        return total / CGFloat(points.count)
    }

    /// Four corners that are all close to square become a true rectangle, level if it was drawn nearly level.
    private static func rectangle(from corners: [CGPoint]) -> [CGPoint]? {
        for index in 0..<4 {
            let before = corners[(index + 3) % 4], here = corners[index], after = corners[(index + 1) % 4]
            let a = CGVector(dx: before.x - here.x, dy: before.y - here.y), b = CGVector(dx: after.x - here.x, dy: after.y - here.y)
            let cosine = (a.dx * b.dx + a.dy * b.dy) / max(hypot(a.dx, a.dy) * hypot(b.dx, b.dy), 0.001)
            guard abs(cosine) < 0.3 else { return nil }
        }
        var longest = (corners[0], corners[1])
        for index in 0..<4 where distance(corners[index], corners[(index + 1) % 4]) > distance(longest.0, longest.1) {
            longest = (corners[index], corners[(index + 1) % 4])
        }
        var angle = atan2(longest.1.y - longest.0.y, longest.1.x - longest.0.x)
        let quarter = CGFloat.pi / 2
        let nearest = (angle / quarter).rounded() * quarter
        if abs(angle - nearest) < 7 * .pi / 180 { angle = 0 } else { angle -= nearest }
        let centre = CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
        let level = corners.map { rotate($0, about: centre, by: -angle) }
        let box = bounds(of: level)
        // Sides are averaged from the corners, so one corner pulled wide doesn't stretch the whole rectangle.
        let xs = level.map(\.x).sorted(), ys = level.map(\.y).sorted()
        let rect = CGRect(x: (xs[0] + xs[1]) / 2, y: (ys[0] + ys[1]) / 2, width: (xs[2] + xs[3] - xs[0] - xs[1]) / 2, height: (ys[2] + ys[3] - ys[0] - ys[1]) / 2)
        guard rect.width > 0.2 * box.width, rect.height > 0.2 * box.height else { return nil }
        return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            .map { rotate($0, about: centre, by: angle) }
    }

    static func rotate(_ point: CGPoint, about centre: CGPoint, by angle: CGFloat) -> CGPoint {
        let dx = point.x - centre.x, dy = point.y - centre.y
        return CGPoint(x: centre.x + dx * cos(angle) - dy * sin(angle), y: centre.y + dx * sin(angle) + dy * cos(angle))
    }

    /// The ellipse round the points, level or along their longer direction, whichever they sit closer to.
    private static func bestEllipse(_ points: [CGPoint], box: CGRect) -> (shape: SnappedShape, error: CGFloat) {
        func measure(_ points: [CGPoint], _ box: CGRect) -> CGFloat {
            let a = max(box.width / 2, 1), b = max(box.height / 2, 1)
            let total = points.reduce(CGFloat(0)) { sum, point in
                sum + abs(hypot((point.x - box.midX) / a, (point.y - box.midY) / b) - 1)
            }
            return total / CGFloat(points.count) * (a + b) / 2
        }
        func shape(_ box: CGRect, centre: CGPoint, rotation: CGFloat) -> SnappedShape {
            var radii = CGSize(width: box.width / 2, height: box.height / 2)
            let round = abs(radii.width - radii.height) / max(radii.width, radii.height, 1) < 0.14
            if round { radii = CGSize(width: (radii.width + radii.height) / 2, height: (radii.width + radii.height) / 2) }
            return .ellipse(center: centre, radii: radii, rotation: round ? 0 : rotation)
        }
        let level = measure(points, box)
        let centre = CGPoint(x: box.midX, y: box.midY)
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        let mean = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count), y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
        for point in points {
            sxx += (point.x - mean.x) * (point.x - mean.x)
            syy += (point.y - mean.y) * (point.y - mean.y)
            sxy += (point.x - mean.x) * (point.y - mean.y)
        }
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        guard abs(angle) > 8 * .pi / 180, abs(abs(angle) - .pi / 2) > 8 * .pi / 180 else { return (shape(box, centre: centre, rotation: 0), level) }
        let turned = points.map { rotate($0, about: mean, by: -angle) }
        let turnedBox = bounds(of: turned)
        let tilted = measure(turned, turnedBox)
        guard tilted < 0.8 * level else { return (shape(box, centre: centre, rotation: 0), level) }
        let turnedCentre = rotate(CGPoint(x: turnedBox.midX, y: turnedBox.midY), about: mean, by: angle)
        return (shape(turnedBox, centre: turnedCentre, rotation: angle), tilted)
    }
}

extension SnappedShape {
    /// The points a stroke is drawn through. PencilKit's path is a smooth curve through its points, so each corner
    /// is given three times to keep it sharp, and a closed curve runs a little past its start to join up.
    func controlPoints(startingNear start: CGPoint) -> [CGPoint] {
        func side(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] {
            let steps = max(1, Int(ShapeRecognizer.distance(a, b) / 24))
            return (1..<max(steps, 1)).map { CGPoint(x: a.x + (b.x - a.x) * CGFloat($0) / CGFloat(steps), y: a.y + (b.y - a.y) * CGFloat($0) / CGFloat(steps)) }
        }
        func through(_ corners: [CGPoint]) -> [CGPoint] {
            var points: [CGPoint] = []
            for (index, corner) in corners.enumerated() {
                points += [corner, corner, corner]
                if index + 1 < corners.count { points += side(corner, corners[index + 1]) }
            }
            return points
        }
        switch self {
        case .line(let a, let b):
            return through([a, b])
        case .polyline(let corners):
            return through(corners)
        case .polygon(let corners):
            guard let first = corners.first else { return [] }
            return through(corners + [first])
        case .ellipse(let centre, let radii, let rotation):
            let around = 2 * CGFloat.pi * max(radii.width, radii.height)
            let count = min(max(Int(around / 8), 28), 160)
            let offset = atan2(start.y - centre.y, start.x - centre.x) - rotation
            return (0..<(count + 3)).map { index in
                let angle = offset + 2 * .pi * CGFloat(index) / CGFloat(count)
                let point = CGPoint(x: centre.x + radii.width * cos(angle), y: centre.y + radii.height * sin(angle))
                return ShapeRecognizer.rotate(point, about: centre, by: rotation)
            }
        }
    }
}

enum ShapeSnap {
    /// How long the pen has to rest at the end of a stroke.
    static let holdDuration: TimeInterval = 0.45

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: SettingsKey.snapsShapes) as? Bool ?? true }

    /// The stroke redrawn as the shape it looks like, in the same ink and weight, or nil if it doesn't look like one.
    static func snapped(_ stroke: PKStroke) -> (stroke: PKStroke, shape: SnappedShape)? {
        let drawn = Array(stroke.path.interpolatedPoints(by: .distance(3)))
        guard let first = drawn.first, let shape = ShapeRecognizer.recognize(drawn.map { $0.location.applying(stroke.transform) }) else { return nil }
        let locations = shape.controlPoints(startingNear: first.location.applying(stroke.transform))
        guard locations.count >= 2 else { return nil }
        func middle(_ values: [CGFloat]) -> CGFloat { values.sorted()[values.count / 2] }
        let size = CGSize(width: middle(drawn.map(\.size.width)), height: middle(drawn.map(\.size.height)))
        let opacity = middle(drawn.map(\.opacity)), force = middle(drawn.map(\.force)), secondary = middle(drawn.map(\.secondaryScale))
        let duration = drawn.last?.timeOffset ?? 0
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: duration * Double(index) / Double(max(locations.count - 1, 1)), size: size, opacity: opacity,
                          force: force, azimuth: first.azimuth, altitude: first.altitude, secondaryScale: secondary)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate)
        return (PKStroke(ink: stroke.ink, path: path, transform: .identity, mask: nil, randomSeed: stroke.randomSeed), shape)
    }
}

/// Watches the touch that draws, without ever recognising: all it reports is how long the touch rested before lifting.
final class StrokeHoldRecognizer: UIGestureRecognizer {
    static let slop: CGFloat = 6

    private var tracked: UITouch?
    private var anchor = CGPoint.zero
    private var restingSince: TimeInterval = 0
    private var lastHold: (duration: TimeInterval, endedAt: TimeInterval)?
    /// Called when a touch lands on the pages, before anything is made of it.
    var onTouchDown: (() -> Void)?

    /// The rest at the end of the stroke that has just been lifted, once.
    func takeHold(within window: TimeInterval = 2) -> TimeInterval? {
        defer { lastHold = nil }
        guard let lastHold, ProcessInfo.processInfo.systemUptime - lastHold.endedAt < window else { return nil }
        return lastHold.duration
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouchDown?()
        guard tracked == nil, let touch = touches.first else { return }
        tracked = touch
        anchor = touch.location(in: view)
        restingSince = touch.timestamp
        lastHold = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        let point = tracked.location(in: view)
        guard hypot(point.x - anchor.x, point.y - anchor.y) > Self.slop else { return }
        anchor = point
        restingSince = tracked.timestamp
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        lastHold = (tracked.timestamp - restingSince, tracked.timestamp)
        self.tracked = nil
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        self.tracked = nil
        state = .failed
    }

    override func reset() {
        tracked = nil
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
