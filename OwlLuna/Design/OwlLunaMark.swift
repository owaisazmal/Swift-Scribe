import SwiftUI

struct OwlLunaMarkPart: Sendable {
    let path: Path
    let fill: Color?
    let stroke: Color?
    let lineWidth: CGFloat
    let lineCap: CGLineCap
}

/// The art's parts in the groups the mark draws, converted once per palette.
struct OwlLunaMarkGroups: Sendable {
    enum Group: CaseIterable, Sendable {
        case moon, sparkle, asterisk, owl, eyes, features, pencil
    }

    let skyTop: Color?
    let skyBottom: Color?
    let glow: Color?
    private let groups: [Group: [OwlLunaMarkPart]]

    static let launchLight = OwlLunaMarkGroups(.launchLight)
    static let launchDark = OwlLunaMarkGroups(.launchDark)

    init(_ palette: OwlLunaPalette) {
        skyTop = palette.skyTop.map(Color.init)
        skyBottom = palette.skyBottom.map(Color.init)
        glow = palette.glow.map(Color.init)
        var groups: [Group: [OwlLunaMarkPart]] = [:]
        for part in OwlLunaArt.parts(palette, includesSky: false) {
            let group: Group
            switch part.layer {
            case .sky, .glow: continue
            case .moon: group = .moon
            case .stars: group = part.name == "starSparkle" ? .sparkle : .asterisk
            case .body, .wings, .belly, .feet, .head, .face, .tuft: group = .owl
            case .eyes: group = .eyes
            case .glasses, .beak, .pad: group = .features
            case .pencil: group = .pencil
            }
            groups[group, default: []].append(OwlLunaMarkPart(path: Path(part.path), fill: part.fill.map(Color.init), stroke: part.stroke.map(Color.init),
                                                              lineWidth: part.lineWidth, lineCap: part.lineCap))
        }
        self.groups = groups
    }

    func parts(_ group: Group) -> [OwlLunaMarkPart] { groups[group] ?? [] }
}

extension Color {
    init(_ rgba: OwlLunaRGBA) { self.init(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a) }
}

/// The owl on its moon as a square tile, as Settings › About shows it.
struct OwlLunaMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let groups: OwlLunaMarkGroups = colorScheme == .dark ? .launchDark : .launchLight
        ZStack {
            if let top = groups.skyTop {
                TileShape()
                    .fill(LinearGradient(colors: [top, groups.skyBottom ?? top], startPoint: .top, endPoint: .bottom))
            }
            MoonLayer(groups: groups)
            PartsLayer(parts: groups.parts(.sparkle))
            PartsLayer(parts: groups.parts(.asterisk))
            PartsLayer(parts: groups.parts(.owl))
            PartsLayer(parts: groups.parts(.eyes))
            PartsLayer(parts: groups.parts(.features))
            PartsLayer(parts: groups.parts(.pencil))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(TileShape())
    }
}

/// The icon's corner: 22.5% of the side, continuous.
private struct TileShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.width * 0.225, style: .continuous)
    }
}

private struct PartsLayer: View {
    let parts: [OwlLunaMarkPart]

    var body: some View {
        Canvas { context, size in
            context.draw(parts, scale: size.width / OwlLunaArt.canvas)
        }
    }
}

/// The moon over its halo: a faint disc and two soft shadows in the glow colour, as the icon draws it.
private struct MoonLayer: View {
    let groups: OwlLunaMarkGroups

    var body: some View {
        Canvas { context, size in
            let scale = size.width / OwlLunaArt.canvas
            let parts = groups.parts(.moon)
            if let glow = groups.glow, let moon = parts.first {
                let halo = (OwlLunaArt.moonRadius + 120) * scale
                let pivot = CGPoint(x: OwlLunaArt.moonPivot.x * scale, y: OwlLunaArt.moonPivot.y * scale)
                context.fill(Path(ellipseIn: CGRect(x: pivot.x - halo, y: pivot.y - halo, width: halo * 2, height: halo * 2)), with: .color(glow.opacity(0.14)))
                for (blur, alpha) in [(46.0, 0.5), (22.0, 0.55)] {
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: glow.opacity(alpha), radius: blur * scale))
                        layer.draw([moon], scale: scale)
                    }
                }
            }
            context.draw(parts, scale: scale)
        }
    }
}

private extension GraphicsContext {
    func draw(_ parts: [OwlLunaMarkPart], scale: CGFloat) {
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        for part in parts {
            let path = part.path.applying(transform)
            if let fill = part.fill { self.fill(path, with: .color(fill)) }
            if let stroke = part.stroke {
                self.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: part.lineWidth * scale, lineCap: part.lineCap, lineJoin: .round))
            }
        }
    }
}
