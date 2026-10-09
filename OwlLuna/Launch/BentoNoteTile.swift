import SwiftUI

/// The note page: ruled paper with a margin and three punched holes, filled in by hand with a checklist, a row of moon phases and a squiggle.
enum BentoNoteTile {
    static func draw(_ context: GraphicsContext, size: CGSize, scene: BentoScene) {
        let pitch = min(size.height * 0.116, size.width * 0.113)
        guard pitch > 0 else { return }
        drawPaper(context, size: size, pitch: pitch, scene: scene)
        let page = CGRect(x: context.edge(pitch * 1.95), y: context.edge(pitch * 1.9), width: pitch * 6.6, height: pitch * 6)
        drawInk(context.moved(by: .fitting(inkBox, in: page, anchor: .topLeading)), scene: scene)
        drawLabels(context, size: size, pitch: pitch, scene: scene)
    }

    private static let margin = SplashBeat(delay: 560, duration: 520)
    private static let header = SplashBeat(delay: 600, duration: 520)
    private static let rules = (0..<9).map { SplashBeat(delay: 640 + 40 * Double($0), duration: 460) }
    private static let holes = (0..<3).map { SplashBeat(delay: 620 + 70 * Double($0), duration: 420, curve: .bounce) }
    private static let labels = [SplashBeat(delay: 680, duration: 450), SplashBeat(delay: 740, duration: 450)]

    private static func drawPaper(_ context: GraphicsContext, size: CGSize, pitch: CGFloat, scene: BentoScene) {
        let unit = scene.unit, palette = scene.palette, time = scene.time
        let hairline = context.pixels(unit * 0.24, .down), rim = context.pixels(unit * 0.36, .down)
        for index in 0..<max(rules.count, Int(size.height / pitch - 2.4)) {
            let foot = context.edge(pitch * (2.9 + CGFloat(index)))
            let drawn = rules[min(index, rules.count - 1)].progress(time)
            context.fill(Path(CGRect(x: 0, y: foot - hairline, width: size.width * drawn, height: hairline)), with: .color(palette.rule))
        }
        let bar = CGRect(x: 0, y: context.edge(pitch * 1.9 - unit * 0.5), width: size.width * header.progress(time), height: context.pixels(unit * 0.5))
        let stripe = CGRect(x: context.edge(pitch * 1.5), y: 0, width: context.pixels(unit * 0.38), height: size.height * margin.progress(time))
        context.fill(Path(bar), with: .color(palette.ink))
        context.fill(Path(stripe), with: .color(palette.tomato))
        for (beat, y) in zip(holes, [pitch * 0.95, size.height / 2, size.height - pitch * 0.95]) {
            let grown = beat.progress(time)
            guard grown > 0 else { continue }
            let radius = (pitch * 0.28 - rim / 2) * grown
            let hole = Path(ellipseIn: CGRect(x: pitch * 0.75 - radius, y: y - radius, width: radius * 2, height: radius * 2))
            context.paint(hole, fill: palette.ground, stroke: palette.ink, width: rim * grown)
        }
    }

    private static func drawLabels(_ context: GraphicsContext, size: CGSize, pitch: CGFloat, scene: BentoScene) {
        let em = scene.labelSize, line = pitch * 0.95 - em / 2
        context.label("NOTES", corner: CGPoint(x: pitch * 1.95, y: line), shown: labels[0].progress(scene.time), scene: scene)
        context.label("P. 12", corner: CGPoint(x: size.width - em * 1.3, y: line), trailing: true, shown: labels[1].progress(scene.time), scene: scene)
    }

    /// The drawing's own coordinates, in which the ruled lines are 36 apart.
    private static let inkBox = CGSize(width: 237.6, height: 216)
    private static let swatch = CGRect(x: 27, y: 80, width: 113, height: 27)
    private static let highlighter = Path(roundedRect: swatch, cornerRadius: 2, style: .circular)
    private static let highlight = SplashBeat(delay: 1460, duration: 240)

    /// Each phase's outline, begun at three o'clock and drawn clockwise.
    private static let moons = (0..<5).map { index in
        Path { $0.addRelativeArc(center: CGPoint(x: 16 + 42 * CGFloat(index), y: 162), radius: 13.5, startAngle: .zero, delta: .degrees(360)) }
    }
    /// The dark side of each phase, new moon first; the full moon has none.
    private static let shadows = [
        moons[0],
        Path(svg: "M58,148.5 A13.5,13.5 0 0 0 58,175.5 A6,13.5 0 0 0 58,148.5 Z"),
        Path(svg: "M100,148.5 A13.5,13.5 0 0 0 100,175.5 Z"),
        Path(svg: "M142,148.5 A13.5,13.5 0 0 0 142,175.5 A6,13.5 0 0 1 142,148.5 Z"),
    ]
    private static let shading = (0..<4).map { SplashBeat(delay: 1300 + 65 * Double($0), duration: 160, curve: .easeOut) }

    /// Everything the pen draws, in the order it lies on the page: boxes, words, ticks, the star, the phases and the squiggle.
    private static let lines: [PenLine] = {
        let box = Path(svg: "M4,13.5 L19.5,13 L20,29 L4.5,29.5 Z"), tick = Path(svg: "M6.5,20 L12,27 L24.5,7.5")
        let words = [
            "M35.0,9.6L38.2,30.4L44.4,17.5L48.7,29.9L55.1,8.7M59.4,30.2L62.9,9.2M62.8,9.7Q76.7,8.8 75.0,15.6Q73.5,21.3 61.0,20.8M66.2,21.0L72.9,30.8M85.3,10.0L82.0,31.0M92.9,10.9L108.7,10.6M100.8,11.0L97.9,31.4M126.4,10.9L114.3,11.4L111.8,31.9L124.4,31.4M113.0,21.4L122.6,20.9",
            "M46.9,48.0Q41.6,42.5 36.9,48.5Q32.8,54.4 40.6,55.6Q48.8,57.3 45.3,62.7Q40.6,68.7 33.7,63.3M55.6,45.2L52.0,66.2M68.1,45.8L53.9,57.9M58.7,54.4L65.6,66.9M86.8,46.2L74.7,46.3L71.6,66.8L84.2,66.7M73.2,56.3L82.7,56.1M92.9,46.9L108.7,46.6M100.8,47.0L97.9,67.4M127.5,51.1Q123.1,44.3 117.0,51.1Q110.8,58.4 115.4,64.2Q119.9,70.0 126.4,63.7M134.6,45.2L132.4,66.2M148.8,45.0L146.6,66.0M133.4,56.2L147.7,55.5",
            "M46.9,84.0Q41.6,78.5 36.9,84.5Q32.8,90.4 40.6,91.6Q48.8,93.3 45.3,98.7Q40.6,104.7 33.7,99.3M55.5,81.7L71.2,81.9M63.3,82.1L59.8,102.5M76.9,81.8L74.8,95.4Q73.6,103.3 80.9,103.5Q88.2,103.8 89.4,95.9L91.5,82.2M94.3,103.3L97.2,82.3M97.1,82.9Q112.9,82.6 110.4,93.1Q108.5,103.0 94.3,103.3M117.5,82.9L124.0,93.9L133.2,82.9M124.0,93.9L122.8,103.9",
        ].map { Path(svg: $0) }
        let star = Path(svg: "M200,21 L214.6,66 L176.3,38.2 L223.7,38.2 L185.4,66 Z")
        let squiggle = Path(svg: "M4,207 q4.5,-9 9,0 t9,0 t9,0 t9,0 t9,0 m11,0 q4.5,-9 9,0 t9,0 t9,0 m11,0 q4.5,-9 9,0 t9,0 t9,0 t9,0")
        func row(_ path: Path, _ index: Int) -> Path { path.applying(CGAffineTransform(translationX: 0, y: 36 * CGFloat(index))) }
        func beat(_ delay: Double, _ duration: Double, _ curve: SplashCurve = .glide) -> SplashBeat { SplashBeat(delay: delay, duration: duration, curve: curve) }
        var lines = (0..<3).map { PenLine(row(box, $0), width: 2.8, beat: beat(760 + 70 * Double($0), 260)) }
        lines += words.indices.map { PenLine(words[$0], width: 3.2, beat: beat(840 + 180 * Double($0), 320, .bezier(0.4, 0, 0.6, 1))) }
        lines += (0..<2).map { PenLine(row(tick, $0), width: 4, red: true, beat: beat(1190 + 180 * Double($0), 170, .easeOut)) }
        lines.append(PenLine(star, width: 3.6, red: true, beat: beat(1330, 340, .easeInOut)))
        lines += moons.indices.map { PenLine(moons[$0], width: 2.8, beat: beat(1120 + 65 * Double($0), 300, .easeInOut)) }
        lines.append(PenLine(squiggle, width: 3.2, beat: beat(1440, 240, .linear)))
        return lines
    }()

    private static func drawInk(_ context: GraphicsContext, scene: BentoScene) {
        let palette = scene.palette, time = scene.time
        let swept = highlight.progress(time)
        if swept > 0 {
            let sweep = CGAffineTransform(translationX: swatch.minX, y: 0).scaledBy(x: swept, y: 1).translatedBy(x: -swatch.minX, y: 0)
            context.moved(by: sweep).fill(highlighter, with: .color(palette.moon))
        }
        for (shadow, beat) in zip(shadows, shading) {
            context.fill(shadow, with: .color(palette.ink.opacity(beat.progress(time))))
        }
        for line in lines {
            line.draw(in: context, at: time, palette: palette)
        }
    }
}

/// A line of the drawing and the beat that draws it. Its strokes all start together, each at the pace of the whole line.
private struct PenLine: Sendable {
    private let strokes: [(path: Path, share: Double)]
    private let width: CGFloat
    private let red: Bool
    private let beat: SplashBeat

    init(_ path: Path, width: CGFloat, red: Bool = false, beat: SplashBeat) {
        strokes = path.strokes
        self.width = width
        self.red = red
        self.beat = beat
    }

    func draw(in context: GraphicsContext, at time: Double, palette: SplashPalette) {
        context.draw(strokes: strokes, upTo: beat.progress(time), stroke: red ? palette.tomato : palette.ink, width: width)
    }
}

private extension GraphicsContext {
    /// A position moved to the nearest pixel, so that rules and bars keep hard edges.
    func edge(_ position: CGFloat) -> CGFloat {
        (position * environment.displayScale).rounded() / environment.displayScale
    }

    /// A thickness in whole pixels, never less than one.
    func pixels(_ thickness: CGFloat, _ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> CGFloat {
        max(1, (thickness * environment.displayScale).rounded(rule)) / environment.displayScale
    }
}
