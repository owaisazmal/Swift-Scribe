import SwiftUI
import PencilKit

/// The tools at the Pencil's tip, for a squeeze: a round mixing dish with a well of ink for each pen on the shelf
/// set round its rim, and the eraser, the lasso, undo and redo in its middle. A tap on a well takes that pen up and
/// puts the dish away; so does a tap anywhere off it.
struct InkDish: View {
    let session: EditorSession
    /// Where the Pencil was, in the points of the page view the dish lies over.
    let point: CGPoint
    @State private var toolbox = Toolbox.shared
    @State private var isOut = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let diameter: CGFloat = 244
    /// How far from the dish's middle the wells' middles are.
    static let ring: CGFloat = 88
    static let well: CGFloat = 36

    /// Where the dish's middle goes so that all of it shows: at the tip, pushed in from the edges and up off `foot`.
    static func centre(for point: CGPoint, in size: CGSize, foot: CGFloat = 0, margin: CGFloat = Space.x2) -> CGPoint {
        let reach = diameter / 2 + margin
        let x = min(max(point.x, reach), max(size.width - reach, reach))
        let y = min(max(point.y, reach), max(size.height - foot - reach, reach))
        return CGPoint(x: x, y: y)
    }

    /// The relative luminance of `ink` laid over `paper` at `opacity`: what decides whether a well's mark is dark or light.
    static func luminance(of ink: UIColor, at opacity: Double, over paper: UIColor) -> Double {
        var top: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0), under: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        ink.getRed(&top.0, green: &top.1, blue: &top.2, alpha: &top.3)
        paper.getRed(&under.0, green: &under.1, blue: &under.2, alpha: &under.3)
        func linear(_ value: CGFloat) -> Double {
            let value = Double(min(max(value, 0), 1))
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        func mixed(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a * opacity + b * (1 - opacity) }
        return 0.2126 * linear(mixed(top.0, under.0)) + 0.7152 * linear(mixed(top.1, under.1)) + 0.0722 * linear(mixed(top.2, under.2))
    }

    /// The middles of `count` wells set evenly round the rim, the first at the top, measured from the dish's middle.
    static func wells(_ count: Int) -> [CGPoint] {
        (0..<max(count, 0)).map { index in
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(count)
            return CGPoint(x: ring * cos(angle), y: ring * sin(angle))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let foot = session.showsToolTray ? ToolTray.height + ToolTray.gap * 2 + session.zoomPanelLift : 0
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in close() })
                    .accessibilityHidden(true)
                dish
                    .scaleEffect(isOut || reduceMotion ? 1 : 0.6)
                    .opacity(isOut ? 1 : 0)
                    .position(Self.centre(for: point, in: proxy.size, foot: foot))
            }
        }
        .onAppear {
            withAnimation(Motion.adaptive(Motion.ribbon, reduceMotion: reduceMotion)) { isOut = true }
        }
    }

    private var dish: some View {
        let pens = toolbox.shelf.usable, spots = Self.wells(pens.count)
        return ZStack {
            Circle().strokeBorder(Color.hairline, lineWidth: 1).frame(width: 128, height: 128)
            ForEach(Array(pens.enumerated()), id: \.element.id) { index, pen in
                wellButton(pen, at: index).offset(x: spots[index].x, y: spots[index].y)
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    toolButton(.eraser, "Eraser", symbol: "eraser", identifier: "editor.dish.eraser")
                    toolButton(.lasso, "Lasso", symbol: "lasso", identifier: "editor.dish.lasso")
                }
                GridRow {
                    Button { session.document.undoManager.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(TrayIconStyle())
                        .disabled(!session.canUndo)
                        .accessibilityIdentifier("editor.dish.undo")
                    Button { session.document.undoManager.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                        .buttonStyle(TrayIconStyle())
                        .disabled(!session.canRedo)
                        .accessibilityIdentifier("editor.dish.redo")
                }
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .board(in: Circle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tool Palette"))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
        .accessibilityIdentifier("editor.dish")
    }

    private func wellButton(_ pen: ToolPreset, at index: Int) -> some View {
        let inHand = toolbox.choice == .pen(pen.id)
        return Button { take(.pen(pen.id), named: pen.name) } label: {
            InkWell(preset: pen, inUse: inHand, onDark: session.inkIsLight, turned: session.paperIsNight)
        }
        .buttonStyle(WellButtonStyle())
        .accessibilityLabel(Text(pen.name))
        .accessibilityAddTraits(inHand ? .isSelected : [])
        .accessibilityShowsLargeContentViewer { Label(pen.name, systemImage: pen.symbol) }
        .accessibilityIdentifier("editor.dish.\(index + 1)")
    }

    private func toolButton(_ choice: ToolChoice, _ title: LocalizedStringKey, symbol: String, identifier: String) -> some View {
        let inHand = toolbox.choice == choice
        return Button { take(choice, named: nil) } label: { Label(title, systemImage: symbol) }
            .buttonStyle(TrayIconStyle(isOn: inHand))
            .accessibilityAddTraits(inHand ? .isSelected : [])
            .accessibilityIdentifier(identifier)
    }

    private func take(_ choice: ToolChoice, named name: String?) {
        toolbox.take(choice)
        UISelectionFeedbackGenerator().selectionChanged()
        if let name { AccessibilityNotification.Announcement(name).post() }
        close()
    }

    private func close() {
        session.dish = nil
    }
}

/// A well of the dish, full of a pen's ink, as faint as the pen is set, with the mark of its kind on it.
private struct InkWell: View {
    let preset: ToolPreset
    let inUse: Bool
    let onDark: Bool
    let turned: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let night = scheme == .dark && !onDark
        let rim = night ? ToolSwatch.rim(contrast) : (onDark ? Color.white : Color.labelInk).opacity(contrast == .increased ? 0.6 : 0.22)
        ZStack {
            Circle().fill(ToolSwatch.paper(onDark: onDark, night: night))
            Circle().fill(ToolSwatch.ink(preset, onDark: onDark, night: night, turned: turned))
            // The ink lies in a hollow: its upper edge is in shadow.
            Circle().stroke(Color.black.opacity(0.22), lineWidth: 3).blur(radius: 1.5).offset(y: 1.5).clipShape(Circle())
            Image(systemName: preset.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(marksDark(night: night) ? Color.labelInk : Color.white)
        }
        .frame(width: InkDish.well, height: InkDish.well)
        .overlay { Circle().strokeBorder(inUse ? Color.accentColor : rim, lineWidth: inUse ? 2 : 1) }
        .overlay(alignment: .bottomTrailing) {
            if inUse {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.onPrimaryCloth)
                    .frame(width: 14, height: 14)
                    .background(Color.primaryCloth, in: Circle())
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityHidden(true)
    }

    /// Whether the kind's mark is dark: the ink, as faint as it is over what it lies on, is light enough to need it.
    private func marksDark(night: Bool) -> Bool {
        let style = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let under = night && !turned ? UIColor.white : UIColor(ToolSwatch.paper(onDark: onDark, night: night)).resolvedColor(with: style)
        let over = UIColor(ToolSwatch.ink(preset, onDark: onDark, solid: true, turned: turned)).resolvedColor(with: style)
        return InkDish.luminance(of: over, at: preset.opacity, over: under) > 0.36
    }
}

private struct WellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .frame(width: ToolTray.button, height: ToolTray.button)
            .contentShape(Circle())
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.lift)
    }
}
