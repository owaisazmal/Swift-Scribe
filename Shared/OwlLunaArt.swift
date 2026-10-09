import Foundation
import CoreGraphics

struct OwlLunaRGBA: Sendable, Hashable {
    var r, g, b, a: CGFloat

    init(hex: UInt32, alpha: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
        a = alpha
    }

    init(white: CGFloat, alpha: CGFloat = 1) {
        r = white; g = white; b = white; a = alpha
    }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    func with(alpha: CGFloat) -> OwlLunaRGBA { var copy = self; copy.a = alpha; return copy }

    /// The colour as the grey of its luminance, for the tinted icon.
    var grey: OwlLunaRGBA { OwlLunaRGBA(white: 0.2126 * r + 0.7152 * g + 0.0722 * b, alpha: a) }
}

enum OwlLunaTheme: String, CaseIterable, Sendable {
    case cobalt, tomato, moss, oxblood, mustard, print
}

enum OwlLunaAppearance: String, CaseIterable, Sendable {
    case light, dark, tinted
}

/// Every colour of the owl on its moon. Sky and glow are optional: the dark and tinted icons sit on the system's own backdrop.
struct OwlLunaPalette: Sendable {
    var skyTop: OwlLunaRGBA?
    var skyBottom: OwlLunaRGBA?
    /// Riso halftone dots over the sky, for the Print icon.
    var skyDots: OwlLunaRGBA?
    var glow: OwlLunaRGBA?
    var moon, moonHighlight, moonShade, star: OwlLunaRGBA
    var body, bodyDark, face, belly, bellyLine: OwlLunaRGBA
    var glassesRim, irisRing, iris, pupil, highlight: OwlLunaRGBA
    var beak, beakLight, feet, feetLine: OwlLunaRGBA
    var pad, padLine, padSpiral: OwlLunaRGBA
    var pencil, pencilShade, pencilWood, pencilTip, eraser, ferrule: OwlLunaRGBA

    static func icon(_ theme: OwlLunaTheme, _ appearance: OwlLunaAppearance) -> OwlLunaPalette {
        var palette = owl
        switch theme {
        case .cobalt: palette.sky(0x4F2DD3, 0x3E20B5, moon: 0xF4DE3C, light: 0xFBF07A, shade: 0xD9B92E, star: 0xF8E85A)
        case .tomato: palette.sky(0xB83A2A, 0xE8793A, moon: 0xFFEFA8, light: 0xFFF8D6, shade: 0xEDCB6E, star: 0xFFF6CF)
        case .moss: palette.sky(0x163D2E, 0x0E2A20, moon: 0xF4DE3C, light: 0xFBF07A, shade: 0xD9B92E, star: 0xF8E85A)
        case .oxblood: palette.sky(0x5E1F30, 0x3A1020, moon: 0xF4DE3C, light: 0xFBF07A, shade: 0xD9B92E, star: 0xF8E85A)
        case .mustard: palette.sky(0xE09A1E, 0xF2C04E, moon: 0xFFF3C4, light: 0xFFFBE6, shade: 0xEBCB7A, star: 0xFFFBE8)
        case .print:
            palette.sky(0xF7F4EC, 0xF7F4EC, moon: 0xFFE800, light: 0xFFF27A, shade: 0xF5B000, star: 0xFF48B0)
            palette.skyDots = OwlLunaRGBA(hex: 0x0078BF)
            palette.glow = nil
        }
        switch appearance {
        case .light: return palette
        case .dark:
            palette.skyTop = nil; palette.skyBottom = nil; palette.skyDots = nil
            return palette
        case .tinted: return palette.tinted
        }
    }

    /// The in-app mark on light paper: the primary icon's violet sky.
    static var launchLight: OwlLunaPalette { icon(.cobalt, .light) }

    /// The in-app mark at night: a midnight navy-violet sky.
    static var launchDark: OwlLunaPalette {
        var palette = icon(.cobalt, .light)
        palette.skyTop = OwlLunaRGBA(hex: 0x1E1449)
        palette.skyBottom = OwlLunaRGBA(hex: 0x140D33)
        return palette
    }

    private mutating func sky(_ top: UInt32, _ bottom: UInt32, moon: UInt32, light: UInt32, shade: UInt32, star: UInt32) {
        skyTop = OwlLunaRGBA(hex: top); skyBottom = OwlLunaRGBA(hex: bottom)
        self.moon = OwlLunaRGBA(hex: moon); moonHighlight = OwlLunaRGBA(hex: light); moonShade = OwlLunaRGBA(hex: shade)
        self.star = OwlLunaRGBA(hex: star)
        glow = OwlLunaRGBA(hex: light)
    }

    private static let owl = OwlLunaPalette(
        skyTop: nil, skyBottom: nil, skyDots: nil, glow: nil,
        moon: OwlLunaRGBA(hex: 0xF4DE3C), moonHighlight: OwlLunaRGBA(hex: 0xFBF07A), moonShade: OwlLunaRGBA(hex: 0xD9B92E),
        star: OwlLunaRGBA(hex: 0xF8E85A),
        body: OwlLunaRGBA(hex: 0x8C5A32), bodyDark: OwlLunaRGBA(hex: 0x6E4424), face: OwlLunaRGBA(hex: 0xE9B48A),
        belly: OwlLunaRGBA(hex: 0xF4C69E), bellyLine: OwlLunaRGBA(hex: 0xB87646),
        glassesRim: OwlLunaRGBA(hex: 0x141414), irisRing: OwlLunaRGBA(hex: 0xE8891E), iris: OwlLunaRGBA(hex: 0xF7C73A),
        pupil: OwlLunaRGBA(hex: 0x2B1A12), highlight: OwlLunaRGBA(hex: 0xFFFFFF),
        beak: OwlLunaRGBA(hex: 0xF07019), beakLight: OwlLunaRGBA(hex: 0xF5A23A), feet: OwlLunaRGBA(hex: 0xF0922A), feetLine: OwlLunaRGBA(hex: 0xD4761A),
        pad: OwlLunaRGBA(hex: 0xF6F0DC), padLine: OwlLunaRGBA(hex: 0x1C1C21), padSpiral: OwlLunaRGBA(hex: 0x1C1C21),
        pencil: OwlLunaRGBA(hex: 0xF2A531), pencilShade: OwlLunaRGBA(hex: 0xD4821C), pencilWood: OwlLunaRGBA(hex: 0xE8C08A),
        pencilTip: OwlLunaRGBA(hex: 0x4A4A4A), eraser: OwlLunaRGBA(hex: 0xF2A4B2), ferrule: OwlLunaRGBA(hex: 0xC9CCD2))

    /// Greys by luminance, except that the moon drops to mid-grey and the stars, pad, belly and face lift, so the owl's silhouette stays clear.
    private var tinted: OwlLunaPalette {
        var p = self
        p.skyTop = nil; p.skyBottom = nil; p.skyDots = nil; p.glow = nil
        p.moon = OwlLunaRGBA(white: 0.72); p.moonHighlight = OwlLunaRGBA(white: 0.80); p.moonShade = OwlLunaRGBA(white: 0.60)
        p.star = OwlLunaRGBA(white: 0.92)
        p.body = body.grey; p.bodyDark = bodyDark.grey; p.face = OwlLunaRGBA(white: 0.82); p.belly = OwlLunaRGBA(white: 0.88)
        p.bellyLine = bellyLine.grey
        p.glassesRim = glassesRim.grey; p.irisRing = irisRing.grey; p.iris = iris.grey; p.pupil = pupil.grey; p.highlight = highlight.grey
        p.beak = beak.grey; p.beakLight = beakLight.grey; p.feet = feet.grey; p.feetLine = feetLine.grey
        p.pad = OwlLunaRGBA(white: 0.95); p.padLine = padLine.grey; p.padSpiral = padSpiral.grey
        p.pencil = pencil.grey; p.pencilShade = pencilShade.grey; p.pencilWood = pencilWood.grey; p.pencilTip = pencilTip.grey
        p.eraser = eraser.grey; p.ferrule = ferrule.grey
        return p
    }
}

/// The layers of the icon, in draw order.
enum OwlLunaLayer: String, CaseIterable, Sendable {
    case sky, glow, moon, stars, body, wings, belly, feet, tuft, head, face, eyes, glasses, beak, pad, pencil

    /// Whether the layer is part of the owl, laid out around `OwlLunaArt.owlCenter`.
    var isOwl: Bool { self != .sky && self != .glow && self != .moon && self != .stars }
}

struct OwlLunaPart {
    let layer: OwlLunaLayer
    let name: String
    let path: CGPath
    let fill: OwlLunaRGBA?
    let stroke: OwlLunaRGBA?
    let lineWidth: CGFloat
    let lineCap: CGLineCap

    init(_ layer: OwlLunaLayer, _ name: String, _ path: CGPath, fill: OwlLunaRGBA? = nil, stroke: OwlLunaRGBA? = nil,
         lineWidth: CGFloat = 0, lineCap: CGLineCap = .round) {
        self.layer = layer; self.name = name; self.path = path
        self.fill = fill; self.stroke = stroke; self.lineWidth = lineWidth; self.lineCap = lineCap
    }
}

/// The OwlLuna owl on its moon, drawn in a 1024-unit square with y down.
enum OwlLunaArt {
    static let canvas: CGFloat = 1024

    // MARK: Anchors

    static let moonPivot = CGPoint(x: 512, y: 506)
    static let moonRadius: CGFloat = 395
    static let moonInnerCenter = CGPoint(x: 590, y: 416)
    static let moonInnerRadius: CGFloat = 300
    static let owlCenter = CGPoint(x: 480, y: 580)
    /// The owl is laid out around `owlCenter` and drawn this much larger, so the glasses still read at 40 px.
    static let owlScale: CGFloat = 1.1
    static let headCenter = owl(CGPoint(x: 480, y: 395))
    static let eyeCenterLeft = owl(CGPoint(x: 414, y: 388))
    static let eyeCenterRight = owl(CGPoint(x: 546, y: 388))
    static let eyeRadius: CGFloat = 58 * owlScale
    /// Where the right wing's tip grips the shaft.
    static let pencilPivot = owl(CGPoint(x: 621, y: 694))
    /// Radians, clockwise on screen; the eraser leans to the right.
    static let pencilAngle: CGFloat = 28 * .pi / 180
    static let starSparkle = CGPoint(x: 772, y: 262)
    static let starAsterisk = CGPoint(x: 165, y: 845)

    private static var owlFrame: CGAffineTransform {
        CGAffineTransform(translationX: owlCenter.x, y: owlCenter.y).scaledBy(x: owlScale, y: owlScale)
            .translatedBy(x: -owlCenter.x, y: -owlCenter.y)
    }

    private static func owl(_ point: CGPoint) -> CGPoint { point.applying(owlFrame) }

    // MARK: Parts

    static func parts(_ p: OwlLunaPalette, includesSky: Bool) -> [OwlLunaPart] {
        var parts: [OwlLunaPart] = []
        if includesSky, let sky = p.skyTop {
            parts.append(OwlLunaPart(.sky, "sky", CGPath(rect: CGRect(x: 0, y: 0, width: canvas, height: canvas), transform: nil), fill: sky))
        }
        if let glow = p.glow {
            parts.append(OwlLunaPart(.glow, "glow", circle(moonPivot, moonRadius + 120), fill: glow.with(alpha: 0.14)))
        }
        parts.append(OwlLunaPart(.moon, "moon", crescent(), fill: p.moon))
        parts.append(OwlLunaPart(.moon, "moonHighlight", crescentOuterBand(width: 30), fill: p.moonHighlight))
        parts.append(OwlLunaPart(.moon, "moonShade", crescentInnerBand(width: 26), fill: p.moonShade))
        parts.append(OwlLunaPart(.stars, "starSparkle", sparkle(starSparkle, radius: 48), fill: p.star))
        parts.append(OwlLunaPart(.stars, "starAsterisk", asterisk(starAsterisk, radius: 46), stroke: p.star, lineWidth: 13))

        parts.append(OwlLunaPart(.body, "body", ellipse(CGPoint(x: 480, y: 665), 132, 152), fill: p.body))
        parts.append(OwlLunaPart(.wings, "wingLeft", wing(top: CGPoint(x: 410, y: 536), outer: CGPoint(x: 295, y: 650),
                                                          inner: CGPoint(x: 375, y: 640), tip: CGPoint(x: 380, y: 738)), fill: p.bodyDark))
        parts.append(OwlLunaPart(.wings, "wingRight", wing(top: CGPoint(x: 550, y: 536), outer: CGPoint(x: 665, y: 650),
                                                           inner: CGPoint(x: 585, y: 640), tip: CGPoint(x: 589, y: 753)), fill: p.bodyDark))
        parts.append(OwlLunaPart(.belly, "belly", ellipse(CGPoint(x: 480, y: 668), 86, 128), fill: p.belly))
        for (index, y) in [604, 644, 684, 724].enumerated() {
            parts.append(OwlLunaPart(.belly, "bellyLine\(index + 1)", wave(y: CGFloat(y)), stroke: p.bellyLine, lineWidth: 9))
        }
        parts.append(OwlLunaPart(.feet, "footLeft", foot(CGPoint(x: 448, y: 812)), fill: p.feet, stroke: p.feetLine, lineWidth: 3))
        parts.append(OwlLunaPart(.feet, "footRight", foot(CGPoint(x: 512, y: 812)), fill: p.feet, stroke: p.feetLine, lineWidth: 3))

        parts.append(OwlLunaPart(.tuft, "tuft", tuft(), fill: p.bodyDark, stroke: p.bodyDark, lineWidth: 10))
        parts.append(OwlLunaPart(.head, "head", ellipse(CGPoint(x: 480, y: 395), 170, 160), fill: p.bodyDark))
        parts.append(OwlLunaPart(.head, "headInner", ellipse(CGPoint(x: 480, y: 397), 160, 150), fill: p.body))
        parts.append(OwlLunaPart(.face, "face", ellipse(CGPoint(x: 480, y: 406), 138, 128), fill: p.face))

        for (side, c) in [("Left", CGPoint(x: 414, y: 388)), ("Right", CGPoint(x: 546, y: 388))] {
            parts.append(OwlLunaPart(.eyes, "irisRing\(side)", circle(c, 54), fill: p.irisRing))
            parts.append(OwlLunaPart(.eyes, "iris\(side)", circle(c, 43), fill: p.iris))
            parts.append(OwlLunaPart(.eyes, "pupil\(side)", circle(CGPoint(x: c.x + 3, y: c.y + 5), 24), fill: p.pupil))
            parts.append(OwlLunaPart(.eyes, "highlight\(side)", circle(CGPoint(x: c.x - 9, y: c.y - 8), 9), fill: p.highlight))
        }
        parts.append(OwlLunaPart(.glasses, "lensLeft", circle(CGPoint(x: 414, y: 388), 58), stroke: p.glassesRim, lineWidth: 17))
        parts.append(OwlLunaPart(.glasses, "lensRight", circle(CGPoint(x: 546, y: 388), 58), stroke: p.glassesRim, lineWidth: 17))
        parts.append(OwlLunaPart(.glasses, "bridge", bridge(), stroke: p.glassesRim, lineWidth: 11))

        parts.append(OwlLunaPart(.beak, "beak", beak(), fill: p.beak))
        parts.append(OwlLunaPart(.beak, "beakHighlight", beakHighlight(), fill: p.beakLight))

        let padFrame = CGAffineTransform(translationX: 318, y: 648).rotated(by: -0.1).translatedBy(x: -65, y: -82)
        parts.append(OwlLunaPart(.pad, "pad", roundedRect(CGRect(x: 0, y: 0, width: 130, height: 164), radius: 6, padFrame), fill: p.pad,
                                 stroke: p.padLine.with(alpha: 0.5), lineWidth: 3))
        parts.append(OwlLunaPart(.pad, "padSpiral", padSpiral(padFrame), stroke: p.padSpiral, lineWidth: 4.5))
        parts.append(OwlLunaPart(.pad, "padLines", padLines(padFrame), stroke: p.padLine, lineWidth: 8))
        parts.append(OwlLunaPart(.pad, "wingLeftTip", wingLeftTip(), fill: p.bodyDark))

        let pencilFrame = CGAffineTransform(translationX: 621, y: 694).rotated(by: pencilAngle)
        parts.append(OwlLunaPart(.pencil, "eraser", pencilEraser(pencilFrame), fill: p.eraser))
        parts.append(OwlLunaPart(.pencil, "ferrule", rect(-16, -106, 32, 14, pencilFrame), fill: p.ferrule))
        parts.append(OwlLunaPart(.pencil, "pencilBody", rect(-16, -92, 32, 146, pencilFrame), fill: p.pencil))
        parts.append(OwlLunaPart(.pencil, "pencilShade", rect(6, -92, 10, 146, pencilFrame), fill: p.pencilShade))
        parts.append(OwlLunaPart(.pencil, "pencilWood", triangle(CGPoint(x: -16, y: 54), CGPoint(x: 16, y: 54), CGPoint(x: 0, y: 98), pencilFrame),
                                 fill: p.pencilWood))
        parts.append(OwlLunaPart(.pencil, "pencilTip", triangle(CGPoint(x: -4, y: 87), CGPoint(x: 4, y: 87), CGPoint(x: 0, y: 98), pencilFrame),
                                 fill: p.pencilTip))
        parts.append(OwlLunaPart(.pencil, "wingRightTip", wingRightTip(), fill: p.bodyDark))
        var frame = owlFrame
        return parts.map { part in
            guard part.layer.isOwl, let path = part.path.copy(using: &frame) else { return part }
            return OwlLunaPart(part.layer, part.name, path, fill: part.fill, stroke: part.stroke,
                               lineWidth: part.lineWidth * owlScale, lineCap: part.lineCap)
        }
    }

    // MARK: Renderer

    /// Draws the icon into a bitmap of `size` points with (0, 0) at the top left.
    static func draw(in ctx: CGContext, size: CGFloat, palette: OwlLunaPalette, includesSky: Bool) {
        let scale = size / canvas
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size)
        ctx.scaleBy(x: scale, y: -scale)
        for part in parts(palette, includesSky: includesSky) {
            switch (part.layer, part.name) {
            case (.sky, _): drawSky(ctx, palette)
            case (.glow, _): break
            case (.moon, "moon"):
                if let glow = palette.glow {
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: 46 * scale, color: glow.with(alpha: 0.5).cgColor)
                    fill(part, ctx)
                    ctx.setShadow(offset: .zero, blur: 22 * scale, color: glow.with(alpha: 0.55).cgColor)
                    fill(part, ctx)
                    ctx.restoreGState()
                }
                fill(part, ctx)
            default:
                fill(part, ctx)
                if let stroke = part.stroke {
                    ctx.addPath(part.path)
                    ctx.setStrokeColor(stroke.cgColor)
                    ctx.setLineWidth(part.lineWidth)
                    ctx.setLineCap(part.lineCap)
                    ctx.setLineJoin(.round)
                    ctx.strokePath()
                }
            }
        }
        ctx.restoreGState()
    }

    private static func fill(_ part: OwlLunaPart, _ ctx: CGContext) {
        guard let fill = part.fill else { return }
        ctx.addPath(part.path)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
    }

    private static func drawSky(_ ctx: CGContext, _ p: OwlLunaPalette) {
        guard let top = p.skyTop else { return }
        let bottom = p.skyBottom ?? top
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx.setFillColor(top.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        if let gradient = CGGradient(colorsSpace: space, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: canvas), options: [])
        }
        guard let dots = p.skyDots else { return }
        ctx.saveGState()
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(dots.cgColor)
        let cell: CGFloat = 30
        var y = cell / 2
        while y < canvas {
            var x = cell / 2
            while x < canvas {
                let t = ((x - 512) * -0.34 + (y - 512) * 0.94) / 900 + 0.25
                let radius = cell * 0.34 * max(0, min(1, t))
                if radius > cell * 0.06 {
                    ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }
                x += cell
            }
            y += cell
        }
        ctx.restoreGState()
    }

    // MARK: Shapes

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
    }

    private static func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, angle: CGFloat = 0, in frame: CGAffineTransform = .identity) -> CGPath {
        var t = frame.translatedBy(x: c.x, y: c.y).rotated(by: angle)
        return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: &t)
    }

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ frame: CGAffineTransform) -> CGPath {
        var t = frame
        return CGPath(rect: CGRect(x: x, y: y, width: w, height: h), transform: &t)
    }

    private static func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ frame: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [a, b, c], transform: frame)
        path.closeSubpath()
        return path
    }

    private static func intersections(_ a: CGPoint, _ ra: CGFloat, _ b: CGPoint, _ rb: CGFloat) -> (CGPoint, CGPoint) {
        let dx = b.x - a.x, dy = b.y - a.y
        let d = (dx * dx + dy * dy).squareRoot()
        let k = (ra * ra - rb * rb + d * d) / (2 * d)
        let h = max(0, ra * ra - k * k).squareRoot()
        let m = CGPoint(x: a.x + k * dx / d, y: a.y + k * dy / d)
        return (CGPoint(x: m.x - h * dy / d, y: m.y + h * dx / d), CGPoint(x: m.x + h * dy / d, y: m.y - h * dx / d))
    }

    private static func nearer(_ pair: (CGPoint, CGPoint), to p: CGPoint) -> CGPoint {
        hypot(pair.0.x - p.x, pair.0.y - p.y) < hypot(pair.1.x - p.x, pair.1.y - p.y) ? pair.0 : pair.1
    }

    /// Adds the arc of the circle from `p` to `q` that passes through `via`, joined to the current point.
    private static func addArc(_ path: CGMutablePath, _ c: CGPoint, _ r: CGFloat, from p: CGPoint, to q: CGPoint, via: CGPoint) {
        let s = atan2(p.y - c.y, p.x - c.x), e = atan2(q.y - c.y, q.x - c.x), v = atan2(via.y - c.y, via.x - c.x)
        func ahead(_ angle: CGFloat) -> CGFloat { var t = angle - s; while t < 0 { t += 2 * .pi }; return t }
        path.addArc(center: c, radius: r, startAngle: s, endAngle: e, clockwise: ahead(v) > ahead(e))
    }

    private static func along(_ c: CGPoint, _ r: CGFloat, towards p: CGPoint) -> CGPoint {
        let d = hypot(p.x - c.x, p.y - c.y)
        return CGPoint(x: c.x + r * (p.x - c.x) / d, y: c.y + r * (p.y - c.y) / d)
    }

    private static func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }

    /// The far side of the moon from its bite: the thick part, lower left.
    private static var moonFar: CGPoint {
        CGPoint(x: moonPivot.x * 2 - moonInnerCenter.x, y: moonPivot.y * 2 - moonInnerCenter.y)
    }

    private static func crescent() -> CGPath {
        let (a, ra, b, rb) = (moonPivot, moonRadius, moonInnerCenter, moonInnerRadius)
        let (p, q) = intersections(a, ra, b, rb)
        let path = CGMutablePath()
        addArc(path, a, ra, from: p, to: q, via: along(a, ra, towards: moonFar))
        addArc(path, b, rb, from: q, to: p, via: along(b, rb, towards: moonFar))
        path.closeSubpath()
        return path
    }

    private static func crescentOuterBand(width: CGFloat) -> CGPath {
        let (a, ra, b, rb) = (moonPivot, moonRadius, moonInnerCenter, moonInnerRadius)
        let (p, q) = intersections(a, ra, b, rb)
        let inner = intersections(a, ra - width, b, rb)
        let p2 = nearer(inner, to: p), q2 = nearer(inner, to: q)
        let path = CGMutablePath()
        addArc(path, a, ra, from: p, to: q, via: along(a, ra, towards: moonFar))
        addArc(path, b, rb, from: q, to: q2, via: along(b, rb, towards: mid(q, q2)))
        addArc(path, a, ra - width, from: q2, to: p2, via: along(a, ra - width, towards: moonFar))
        addArc(path, b, rb, from: p2, to: p, via: along(b, rb, towards: mid(p, p2)))
        path.closeSubpath()
        return path
    }

    private static func crescentInnerBand(width: CGFloat) -> CGPath {
        let (a, ra, b, rb) = (moonPivot, moonRadius, moonInnerCenter, moonInnerRadius)
        let (p, q) = intersections(a, ra, b, rb)
        let outer = intersections(a, ra, b, rb + width)
        let p2 = nearer(outer, to: p), q2 = nearer(outer, to: q)
        let path = CGMutablePath()
        addArc(path, b, rb, from: p, to: q, via: along(b, rb, towards: moonFar))
        addArc(path, a, ra, from: q, to: q2, via: along(a, ra, towards: mid(q, q2)))
        addArc(path, b, rb + width, from: q2, to: p2, via: along(b, rb + width, towards: moonFar))
        addArc(path, a, ra, from: p2, to: p, via: along(a, ra, towards: mid(p, p2)))
        path.closeSubpath()
        return path
    }

    private static func sparkle(_ c: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let waist = radius * 0.2
        path.move(to: CGPoint(x: c.x, y: c.y - radius))
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2 - .pi / 2
            let next = CGPoint(x: c.x + radius * cos(angle + .pi / 2), y: c.y + radius * sin(angle + .pi / 2))
            let control = CGPoint(x: c.x + waist * cos(angle + .pi / 4), y: c.y + waist * sin(angle + .pi / 4))
            path.addQuadCurve(to: next, control: control)
        }
        path.closeSubpath()
        return path
    }

    private static func asterisk(_ c: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<3 {
            let angle = CGFloat(i) * .pi / 3 + .pi / 2
            path.move(to: CGPoint(x: c.x - radius * cos(angle), y: c.y - radius * sin(angle)))
            path.addLine(to: CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle)))
        }
        return path
    }

    private static func wave(y: CGFloat) -> CGPath {
        let belly = (c: CGPoint(x: 480, y: 668), rx: CGFloat(86), ry: CGFloat(128))
        let dy = (y - belly.c.y) / belly.ry
        let half = belly.rx * (1 - dy * dy).squareRoot() * 0.78
        let path = CGMutablePath()
        let bumps = 3
        let step = half * 2 / CGFloat(bumps)
        path.move(to: CGPoint(x: belly.c.x - half, y: y))
        for i in 0..<bumps {
            let x0 = belly.c.x - half + step * CGFloat(i)
            path.addQuadCurve(to: CGPoint(x: x0 + step, y: y), control: CGPoint(x: x0 + step / 2, y: y - 16))
        }
        return path
    }

    /// The left wing's tip, curling over the pad's right edge.
    private static func wingLeftTip() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 396, y: 594))
        path.addQuadCurve(to: CGPoint(x: 358, y: 642), control: CGPoint(x: 376, y: 590))
        path.addQuadCurve(to: CGPoint(x: 396, y: 704), control: CGPoint(x: 360, y: 704))
        path.closeSubpath()
        return path
    }

    /// The right wing's tip, a short feather lying across the pencil's shaft.
    private static func wingRightTip() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 596, y: 676))
        path.addQuadCurve(to: CGPoint(x: 644, y: 700), control: CGPoint(x: 638, y: 676))
        path.addQuadCurve(to: CGPoint(x: 598, y: 718), control: CGPoint(x: 644, y: 718))
        path.closeSubpath()
        return path
    }

    /// A leaf from the shoulder (hidden under the head) to a point, bowed out to `outer` and in to `inner`.
    private static func wing(top: CGPoint, outer: CGPoint, inner: CGPoint, tip: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: top)
        path.addQuadCurve(to: tip, control: outer)
        path.addQuadCurve(to: top, control: inner)
        path.closeSubpath()
        return path
    }

    /// Three toes with gaps between them, the outer two splayed.
    private static func foot(_ c: CGPoint) -> CGPath {
        let path = CGMutablePath()
        for (dx, dy, angle) in [(-22.0, 2.0, -0.26), (0.0, -1.0, 0.0), (22.0, 2.0, 0.26)] as [(CGFloat, CGFloat, CGFloat)] {
            var t = CGAffineTransform(translationX: c.x + dx, y: c.y + dy).rotated(by: angle)
            path.addPath(CGPath(roundedRect: CGRect(x: -8, y: -16, width: 16, height: 32), cornerWidth: 8, cornerHeight: 8, transform: &t))
        }
        return path
    }

    /// Three soft feathers on the crown, curling left; the stroke rounds their tips.
    private static func tuft() -> CGPath {
        let path = CGMutablePath()
        for (base, tip, curl) in [(462, CGPoint(x: 440, y: 214), CGPoint(x: 432, y: 248)), (480, CGPoint(x: 466, y: 198), CGPoint(x: 454, y: 232)),
                                  (496, CGPoint(x: 494, y: 204), CGPoint(x: 486, y: 232))] as [(CGFloat, CGPoint, CGPoint)] {
            path.move(to: CGPoint(x: base - 6, y: 250))
            path.addQuadCurve(to: tip, control: CGPoint(x: curl.x - 6, y: curl.y))
            path.addQuadCurve(to: CGPoint(x: base + 6, y: 250), control: CGPoint(x: curl.x + 6, y: curl.y))
            path.closeSubpath()
        }
        return path
    }

    private static func bridge() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 470, y: 382))
        path.addQuadCurve(to: CGPoint(x: 490, y: 382), control: CGPoint(x: 480, y: 372))
        return path
    }

    private static func beak() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 447, y: 452))
        path.addQuadCurve(to: CGPoint(x: 513, y: 452), control: CGPoint(x: 480, y: 444))
        path.addQuadCurve(to: CGPoint(x: 480, y: 538), control: CGPoint(x: 504, y: 500))
        path.addQuadCurve(to: CGPoint(x: 447, y: 452), control: CGPoint(x: 456, y: 500))
        path.closeSubpath()
        return path
    }

    private static func beakHighlight() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 456, y: 456))
        path.addQuadCurve(to: CGPoint(x: 504, y: 456), control: CGPoint(x: 480, y: 450))
        path.addQuadCurve(to: CGPoint(x: 480, y: 492), control: CGPoint(x: 492, y: 484))
        path.addQuadCurve(to: CGPoint(x: 456, y: 456), control: CGPoint(x: 468, y: 484))
        path.closeSubpath()
        return path
    }

    private static func padSpiral(_ frame: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            path.addEllipse(in: CGRect(x: 10 + CGFloat(i) * 22, y: -8, width: 14, height: 16), transform: frame)
        }
        return path
    }

    private static func padLines(_ frame: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        let rows: [(CGFloat, CGFloat, CGFloat)] = [(36, 16, 66), (36, 92, 93), (62, 16, 114), (88, 16, 114), (114, 16, 114), (140, 16, 90)]
        for (y, x0, x1) in rows {
            path.move(to: CGPoint(x: x0, y: y), transform: frame)
            path.addLine(to: CGPoint(x: x1, y: y), transform: frame)
        }
        return path
    }

    private static func pencilEraser(_ frame: CGAffineTransform) -> CGPath {
        roundedRect(CGRect(x: -16, y: -146, width: 32, height: 40), radius: 9, frame)
    }

    private static func roundedRect(_ rect: CGRect, radius: CGFloat, _ frame: CGAffineTransform) -> CGPath {
        var t = frame
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: &t)
    }
}
