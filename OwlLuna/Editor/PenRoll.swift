import SwiftUI
import PencilKit

/// A line written with one kind of ink, as PencilKit draws it. Only its shape is kept, so it takes any pen's colour.
@MainActor
enum InkSample {
    nonisolated static let size = CGSize(width: 92, height: 32)
    private static let steps = 12
    private static var images: [Key: UIImage] = [:]

    private struct Key: Hashable {
        let ink: PKInkingTool.InkType
        let step: Int
    }

    /// The line a kind of ink writes, from the narrowest it is shown (`breadth` 0) to the broadest (1).
    static func image(of ink: PKInkingTool.InkType, breadth: Double = 0.3) -> UIImage {
        let key = Key(ink: ink, step: Int((min(max(breadth, 0), 1) * Double(steps)).rounded()))
        if let image = images[key] { return image }
        if images.count > 48 { images.removeAll() }
        let points = points(of: ink, breadth: CGFloat(key.step) / CGFloat(steps))
        let stroke = PKStroke(ink: PKInk(ink, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .distantPast))
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = PKDrawing(strokes: [stroke]).image(from: CGRect(origin: .zero, size: size), scale: 3)
        }
        images[key] = image
        return image
    }

    private enum Swell { case none, ends, down }

    /// A nib in PencilKit's own measure, in which a pen under 2 leaves no mark and a pencil writes broader than its size.
    private struct Nib {
        var least: CGFloat
        var most: CGFloat
        var opacity: CGFloat = 1
        var swell = Swell.none
    }

    private static func nib(of ink: PKInkingTool.InkType) -> Nib {
        switch ink {
        case .pen: Nib(least: 3, most: 10, swell: .ends)
        case .monoline: Nib(least: 2.6, most: 6.5)
        case .fountainPen: Nib(least: 4.5, most: 11, swell: .down)
        case .pencil: Nib(least: 2, most: 6, swell: .ends)
        case .marker: Nib(least: 5, most: 15)
        case .crayon: Nib(least: 3.5, most: 10, swell: .ends)
        case .watercolor: Nib(least: 3.5, most: 11, opacity: 0.5, swell: .ends)
        default: Nib(least: 3.5, most: 10)
        }
    }

    /// A wave that settles as it goes, the way a pen is tried on a scrap of paper. A pen thins at its ends, a
    /// fountain pen broadens on its way down, and the rest keep one width.
    private static func points(of ink: PKInkingTool.InkType, breadth: CGFloat) -> [PKStrokePoint] {
        let nib = nib(of: ink), count = 72
        let broad = nib.least + (nib.most - nib.least) * breadth
        return (0...count).map { index in
            let along = CGFloat(index) / CGFloat(count), turn = along * .pi * 5
            let ends = min(1, min(along, 1 - along) * 7)
            let width: CGFloat = switch nib.swell {
            case .none: broad
            case .ends: max(broad * (0.6 + 0.4 * ends), min(broad, 2.4))
            case .down: max(broad * max(0, -cos(turn)) * (0.4 + 0.6 * ends), 2.6)
            }
            return PKStrokePoint(location: CGPoint(x: 9 + 74 * along, y: 16 - (8 - 2.5 * along) * sin(turn)), timeOffset: TimeInterval(along),
                                 size: CGSize(width: width, height: width), opacity: nib.opacity, force: 1, azimuth: 0, altitude: .pi / 2)
        }
    }
}

/// A pen's label with the line it writes on it: its kind of ink, in its colour, as broad as the pen is set.
/// The line is written again when the kind changes.
struct InkLabel: View {
    let kind: PKInkingTool.InkType
    /// How broad the pen is set, from 0 to 1.
    let breadth: Double
    let ink: Color
    let paper: Color
    /// At night the label is dark, and the line is edged in light so that dark ink is told from it.
    var night = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    static let size = CGSize(width: 104, height: 44)

    var body: some View {
        Image(uiImage: InkSample.image(of: kind, breadth: breadth))
            .renderingMode(.template)
            .resizable()
            .frame(width: InkSample.size.width, height: InkSample.size.height)
            .foregroundStyle(ink)
            .shadow(color: night ? ToolSwatch.rim(contrast) : .clear, radius: 0.6)
            .shadow(color: night ? ToolSwatch.rim(contrast) : .clear, radius: 0.6)
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? nil : kind) { line, reach in
                line.mask(alignment: .leading) { Rectangle().frame(width: InkSample.size.width * reach) }
            } keyframes: { _ in
                MoveKeyframe(0)
                CubicKeyframe(1, duration: 0.4)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .background(paper, in: ToolSwatch.shape)
            .clipShape(ToolSwatch.shape)
            .overlay { ToolSwatch.shape.strokeBorder(Color.hairline, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

/// The kinds of ink a pen can have, as tools standing tip up in a roll of cloth, a pocket for each.
/// They wear the pen's colour. The pen's own kind stands out of its pocket, over a check mark on the cloth.
struct PenRoll: View {
    @Binding var kind: PKInkingTool.InkType
    let ink: Color
    let paper: Color
    /// At night the lining is dark, and the tools are edged in light.
    var night = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 88
    private static let pocket: CGFloat = 30
    private static let shape = RoundedRectangle.plate

    var body: some View {
        let kinds = ToolPreset.kinds
        let edge = night ? ToolSwatch.rim(contrast) : Color.labelInk.opacity(contrast == .increased ? 0.75 : 0.4)
        HStack(spacing: 0) {
            ForEach(kinds, id: \.self) { each in
                Button { kind = each } label: {
                    Canvas { context, size in
                        PenDrawing(kind: each, ink: ink, edge: edge).draw(in: &context, size: size)
                    }
                }
                .buttonStyle(PocketButtonStyle(isChosen: each == kind, reduceMotion: reduceMotion))
                .accessibilityLabel(Text(ToolPreset.name(of: each)))
                .accessibilityAddTraits(each == kind ? .isSelected : [])
                .accessibilityShowsLargeContentViewer { Label(ToolPreset.name(of: each), systemImage: ToolPreset.symbol(of: each)) }
            }
        }
        .frame(height: Self.height)
        .background(paper)
        .overlay(alignment: .bottom) { pocket(kinds) }
        .clipShape(Self.shape)
        .overlay { Self.shape.strokeBorder(Color.hairline, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Kind"))
    }

    /// The front of the pockets: cloth that swells a little between its seams, piped in mustard along its top edge.
    private func pocket(_ kinds: [PKInkingTool.InkType]) -> some View {
        Rectangle()
            .fill(Color.primaryCloth)
            .overlay { if contrast != .increased { Rectangle().fill(ImagePaint(image: ClothWeave.tile, scale: 1)) } }
            .overlay { LinearGradient(colors: [.white.opacity(0.08), .black.opacity(0.12)], startPoint: .top, endPoint: .bottom) }
            .overlay {
                HStack(spacing: 0) {
                    ForEach(Array(kinds.enumerated()), id: \.element) { index, _ in
                        LinearGradient(stops: Self.swell, startPoint: .leading, endPoint: .trailing)
                            .overlay(alignment: .leading) { if index > 0 { Rectangle().fill(.black.opacity(0.22)).frame(width: 1) } }
                    }
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.mustard)
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.35)).frame(height: 1) }
                    .frame(height: Self.piping)
                    .shadow(color: .black.opacity(0.35), radius: 0.5, y: 1)
            }
            .overlay {
                HStack(spacing: 0) {
                    ForEach(kinds, id: \.self) { each in
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Color.primaryCloth)
                            .frame(width: 14, height: 14)
                            .background(Color.onPrimaryCloth, in: Circle())
                            .opacity(each == kind ? 1 : 0)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, Self.piping)
                .animation(Motion.quick, value: kind)
            }
            .frame(height: Self.pocket)
            .shadow(color: .black.opacity(0.2), radius: 1.5, y: -1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static let piping: CGFloat = 3
    /// Shade at a pocket's seams and a little light on its middle.
    private static let swell: [Gradient.Stop] = [.init(color: .black.opacity(0.2), location: 0), .init(color: .black.opacity(0), location: 0.22),
                                                 .init(color: .white.opacity(0.09), location: 0.5), .init(color: .black.opacity(0), location: 0.78),
                                                 .init(color: .black.opacity(0.2), location: 1)]

    /// A tool sits low in its pocket, comes up a little under a finger, and stands out of it when it is the pen's kind.
    private struct PocketButtonStyle: ButtonStyle {
        let isChosen: Bool
        let reduceMotion: Bool

        func makeBody(configuration: Configuration) -> some View {
            let drop: CGFloat = isChosen ? 3 : (configuration.isPressed ? 9 : 13)
            configuration.label
                .offset(y: drop)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .animation(Motion.adaptive(Motion.ribbon, reduceMotion: reduceMotion), value: drop)
        }
    }
}

/// One tool of the roll, drawn tip up in a box a pocket wide: its tip at the top, its barrel running off the foot.
struct PenDrawing {
    let kind: PKInkingTool.InkType
    let ink: Color
    let edge: Color

    private static let scale: CGFloat = 1.35
    private static let metal = Color(hex: 0xC3C7CF)
    private static let steel = Color(hex: 0x8D93A0)
    private static let gunmetal = Color(hex: 0x3A4050)
    private static let brass = Color(hex: 0xD6A02A)
    private static let wood = Color(hex: 0xE6C594)
    private static let hair = Color(hex: 0x8A6B4B)
    private static let slit = Color(hex: 0x1B2230).opacity(0.75)

    func draw(in context: inout GraphicsContext, size: CGSize) {
        context.scaleBy(x: Self.scale, y: Self.scale)
        let mid = size.width / 2 / Self.scale, foot = size.height / Self.scale + 4

        func span(_ width: CGFloat, _ top: CGFloat, _ bottom: CGFloat, radius: CGFloat = 0) -> Path {
            Path(roundedRect: CGRect(x: mid - width / 2, y: top, width: width, height: bottom - top), cornerRadius: radius)
        }
        func taper(_ topWidth: CGFloat, _ top: CGFloat, _ bottomWidth: CGFloat, _ bottom: CGFloat) -> Path {
            outline([(-topWidth / 2, top), (topWidth / 2, top), (bottomWidth / 2, bottom), (-bottomWidth / 2, bottom)])
        }
        func outline(_ corners: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            path.addLines(corners.map { CGPoint(x: mid + $0.0, y: $0.1) })
            path.closeSubpath()
            return path
        }
        /// Two sides that mirror each other, each a curve from the tip to the shoulder and on to the neck.
        func leaf(tip: CGFloat, shoulder: (CGFloat, CGFloat), neck: (CGFloat, CGFloat), bulge: CGFloat) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: mid, y: tip))
            path.addQuadCurve(to: CGPoint(x: mid + shoulder.0, y: shoulder.1), control: CGPoint(x: mid + shoulder.0 - 0.4, y: tip + bulge))
            path.addQuadCurve(to: CGPoint(x: mid + neck.0, y: neck.1), control: CGPoint(x: mid + shoulder.0 + 0.2, y: neck.1 - 3))
            path.addLine(to: CGPoint(x: mid - neck.0, y: neck.1))
            path.addQuadCurve(to: CGPoint(x: mid - shoulder.0, y: shoulder.1), control: CGPoint(x: mid - shoulder.0 - 0.2, y: neck.1 - 3))
            path.addQuadCurve(to: CGPoint(x: mid, y: tip), control: CGPoint(x: mid - shoulder.0 + 0.4, y: tip + bulge))
            return path
        }
        func fill(_ path: Path, _ color: Color) {
            context.fill(path, with: .color(color))
            context.stroke(path, with: .color(edge), lineWidth: 0.8)
        }
        func shine(_ x: CGFloat, _ top: CGFloat, _ bottom: CGFloat, width: CGFloat = 1.6, _ opacity: CGFloat = 0.24) {
            context.fill(Path(CGRect(x: mid + x, y: top, width: width, height: bottom - top)), with: .color(.white.opacity(opacity)))
        }
        func line(from top: CGFloat, to bottom: CGFloat) {
            var path = Path()
            path.move(to: CGPoint(x: mid, y: top))
            path.addLine(to: CGPoint(x: mid, y: bottom))
            context.stroke(path, with: .color(Self.slit), lineWidth: 0.9)
        }
        /// A barrel in the pen's ink, lit from the left.
        func barrel(_ width: CGFloat, from top: CGFloat) {
            fill(span(width, top, foot, radius: 2), ink)
            shine(-width / 2 + 2, top + 1, foot, width: max(width * 0.18, 2), 0.28)
            context.fill(Path(CGRect(x: mid + width * 0.22, y: top + 1, width: width * 0.28 - 0.5, height: foot)), with: .color(.black.opacity(0.12)))
        }
        func dot(at y: CGFloat, radius: CGFloat, _ color: Color) {
            context.fill(Path(ellipseIn: CGRect(x: mid - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
        }

        switch kind {
        case .pen:
            barrel(13, from: 19)
            fill(span(11, 15, 19.5, radius: 1), Self.steel)
            fill(taper(2.4, 4, 9.5, 15), Self.metal)
            fill(Path(ellipseIn: CGRect(x: mid - 1.6, y: 1.6, width: 3.2, height: 3.2)), ink)
        case .monoline:
            barrel(11, from: 20)
            fill(taper(3.4, 11, 9, 20), Self.metal)
            fill(span(2.2, 3, 11.5, radius: 0.6), Self.steel)
            context.fill(span(2.2, 2, 5, radius: 0.8), with: .color(ink))
        case .fountainPen:
            barrel(14, from: 30)
            fill(span(14, 29, 32, radius: 1), Self.brass)
            fill(taper(8, 21, 12, 29.5), Self.gunmetal)
            shine(-2.6, 22, 29)
            fill(leaf(tip: 1, shoulder: (5.6, 14), neck: (3.6, 21.5), bulge: 5.5), Self.brass)
            line(from: 2.5, to: 12)
            dot(at: 13, radius: 1.4, Self.slit)
            dot(at: 1.9, radius: 1.3, ink)
        case .pencil:
            barrel(12, from: 19)
            var wood = Path()
            wood.move(to: CGPoint(x: mid - 2, y: 6.5))
            wood.addLine(to: CGPoint(x: mid + 2, y: 6.5))
            wood.addLine(to: CGPoint(x: mid + 6, y: 19))
            for x in [2.0, -2.0, -6.0] {
                wood.addQuadCurve(to: CGPoint(x: mid + x, y: 19), control: CGPoint(x: mid + x + 2, y: 22.5))
            }
            wood.closeSubpath()
            fill(wood, Self.wood)
            fill(outline([(0, 1), (2, 6.5), (-2, 6.5)]), ink)
        case .marker:
            barrel(18, from: 24)
            fill(taper(12, 17, 18, 24.5), Self.gunmetal)
            fill(span(10, 12, 17.5, radius: 0.5), Self.gunmetal)
            shine(-3.6, 13, 24)
            fill(outline([(-4, 2), (4, 6.5), (4, 12.5), (-4, 12.5)]), ink)
        case .crayon:
            barrel(14, from: 17)
            var tip = Path()
            tip.move(to: CGPoint(x: mid - 2.2, y: 3.5))
            tip.addQuadCurve(to: CGPoint(x: mid + 2.2, y: 3.5), control: CGPoint(x: mid, y: 0.8))
            for corner in [(5.0, 13.5), (5.0, 17.5), (-5.0, 17.5), (-5.0, 13.5)] {
                tip.addLine(to: CGPoint(x: mid + corner.0, y: corner.1))
            }
            tip.closeSubpath()
            fill(tip, ink)
            shine(-3, 5, 16, 0.28)
            fill(span(14, 25, foot), Color.labelCream)
            context.fill(span(14, 28, 30), with: .color(ink))
            context.fill(span(14, 32, 33.2), with: .color(ink))
        case .watercolor:
            fill(taper(7, 29, 8.5, foot), Self.wood)
            shine(-2.4, 30, foot, 0.3)
            fill(taper(7.6, 19, 7, 29.5), Self.metal)
            for y in [22.0, 26.0] {
                context.fill(Path(CGRect(x: mid - 3.6, y: y - 0.5, width: 7.2, height: 1)), with: .color(Self.steel))
            }
            let bristles = leaf(tip: 0.8, shoulder: (4.6, 12.5), neck: (3.8, 19.5), bulge: 5.2)
            context.fill(bristles, with: .color(Self.hair))
            var dipped = context
            dipped.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: 12.5)))
            dipped.fill(bristles, with: .color(ink))
            context.stroke(bristles, with: .color(edge), lineWidth: 0.8)
        default:
            // The calligraphy pen: a broad nib cut on the slant, wet along its edge.
            barrel(10, from: 27)
            fill(span(9, 21, 27.5, radius: 1), Self.steel)
            var nib = Path()
            nib.move(to: CGPoint(x: mid - 5.5, y: 2))
            nib.addLine(to: CGPoint(x: mid + 5.5, y: 5))
            nib.addLine(to: CGPoint(x: mid + 5.5, y: 13))
            nib.addQuadCurve(to: CGPoint(x: mid + 3.2, y: 21.5), control: CGPoint(x: mid + 5.2, y: 18))
            nib.addLine(to: CGPoint(x: mid - 3.2, y: 21.5))
            nib.addQuadCurve(to: CGPoint(x: mid - 5.5, y: 13), control: CGPoint(x: mid - 5.2, y: 18))
            nib.closeSubpath()
            fill(nib, Self.brass)
            line(from: 5.8, to: 13)
            context.fill(outline([(-5.5, 2), (5.5, 5), (5.5, 7.2), (-5.5, 4.2)]), with: .color(ink))
        }
    }
}
