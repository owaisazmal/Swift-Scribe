import SwiftUI
import PencilKit

/// The tools, on one board at the foot of the editor: the pens with their inks, the eraser, the lasso, and the
/// shortcuts chosen to stand beside them. It floats over the desk and takes nothing from the page's width; the page
/// stack leaves room under the last page for it.
struct ToolTray: View {
    let session: EditorSession
    /// The width of the pane the tray stands in.
    let room: CGFloat
    let use: (ToolExtra) -> Void
    @State private var toolbox = Toolbox.shared
    @State private var hidden: Edge.Set = []
    @State private var editing: UUID?
    @State private var editingEraser = false
    @State private var customising = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 48
    /// What is left under the tray, above the home indicator's margin or the zoom window.
    static let gap = Space.x2
    static let slot: CGFloat = 38
    static let button: CGFloat = 44
    private static let inset = Space.x2
    private static let rule: CGFloat = 17
    private static let margin = Space.x4
    private static let fade: CGFloat = 20

    /// How a tray is shared out: the width its pens get, in which they scroll if it is short, and how many shortcuts show.
    struct Plan: Equatable {
        var pens: CGFloat
        var extras: Int
    }

    /// The eraser, the lasso and the customise menu always show. Shortcuts give way, the last first, until three pens fit.
    static func plan(pens: Int, extras: Int, room: CGFloat) -> Plan {
        let need: CGFloat = CGFloat(pens + (pens < ToolShelf.limit ? 1 : 0)) * slot
        let fixed: CGFloat = button * 3 + rule * 2 + inset * 2
        let space: CGFloat = room - margin * 2 - fixed
        var shown = extras
        while shown > 0, space - CGFloat(shown) * button < min(need, slot * 3) { shown -= 1 }
        return Plan(pens: max(min(need, space - CGFloat(shown) * button), slot), extras: shown)
    }

    var body: some View {
        let pens = toolbox.shelf.usable
        let extras = ToolExtra.allCases.filter(toolbox.extras.contains)
        let plan = Self.plan(pens: pens.count, extras: extras.count, room: room)
        // Pens that all fit have no edge to fade at, whatever the scroll view last said: its word on a first
        // layout, when the tray has no width yet, isn't always taken back.
        let scrolls = plan.pens < CGFloat(pens.count + (toolbox.shelf.isFull ? 0 : 1)) * Self.slot - 0.5
        HStack(spacing: 0) {
            penRow(pens)
                .frame(width: plan.pens, height: Self.button)
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(scrolls && hidden.contains(.leading) ? 0 : 1), .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: Self.fade)
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(scrolls && hidden.contains(.trailing) ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                            .frame(width: Self.fade)
                    }
                }
            rule
            eraserButton
            lassoButton
            rule
            ForEach(extras.prefix(plan.extras)) { extraButton($0) }
            customiseButton
        }
        .padding(.horizontal, Self.inset)
        .frame(height: Self.height)
        .board(in: RoundedRectangle.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools"))
        .accessibilityIdentifier("editor.tools.tray")
    }

    private var rule: some View {
        Rectangle().fill(Color.hairline).frame(width: 1, height: 24).padding(.horizontal, Space.x2)
    }

    // MARK: Pens

    private func penRow(_ pens: [ToolPreset]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(pens.enumerated()), id: \.element.id) { index, pen in
                        penButton(pen, at: index, of: pens.count).id(pen.id)
                    }
                    if !toolbox.shelf.isFull {
                        Button(action: addPen) { Label("New Pen", systemImage: "plus") }
                            .buttonStyle(NewPenButtonStyle())
                            .accessibilityHint(Text("Adds a pen like the one in hand, in another colour"))
                            .accessibilityIdentifier("editor.tools.add")
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Edge.Set.self) { geometry in
                let x = geometry.contentOffset.x, end = geometry.contentSize.width - geometry.containerSize.width
                return (x > 1 ? Edge.Set.leading : []).union(x < end - 1 ? .trailing : [])
            } action: { _, edges in hidden = edges }
            .onChange(of: toolbox.choice) { _, choice in
                guard case .pen(let id) = choice else { return }
                withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { proxy.scrollTo(id) }
            }
            .onChange(of: pens.map(\.id)) {
                guard case .pen(let id) = toolbox.choice else { return }
                withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { proxy.scrollTo(id) }
            }
        }
    }

    private func penButton(_ pen: ToolPreset, at index: Int, of count: Int) -> some View {
        let inHand = toolbox.choice == .pen(pen.id)
        // The pen in hand opens; any other is taken up.
        return Button { if inHand { editing = pen.id } else { take(.pen(pen.id), named: pen.name) } } label: {
            ToolSwatch(preset: pen, inUse: inHand, onDark: session.inkIsLight, turned: session.paperIsNight)
        }
        .buttonStyle(ToolSwatchButtonStyle())
        .panel("Pen Options", isPresented: Binding(get: { editing == pen.id }, set: { if !$0, editing == pen.id { editing = nil } })) {
            ScrollView { PenOptions(id: pen.id, toolbox: toolbox, onDark: session.inkIsLight, turned: session.paperIsNight) { remove(pen) } }
                .scrollBounceBehavior(.basedOnSize)
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in change(pen) })
        .accessibilityLabel(Text(pen.name))
        .accessibilityValue(pen.opacity < 1 ? Text("Width \(pen.width.formatted(.number.precision(.fractionLength(0...1)))), opacity \(pen.opacityName)")
                                            : Text("Width \(pen.width.formatted(.number.precision(.fractionLength(0...1))))"))
        .accessibilityAddTraits(inHand ? .isSelected : [])
        .accessibilityActions {
            Button("Change Pen") { change(pen) }
            if index > 0 { Button("Move Left") { toolbox.shelf.move(pen.id, by: -1) } }
            if index < count - 1 { Button("Move Right") { toolbox.shelf.move(pen.id, by: 1) } }
            if count > 1 { Button("Remove") { remove(pen) } }
        }
        .accessibilityShowsLargeContentViewer { Label(pen.name, systemImage: pen.symbol) }
        .accessibilityIdentifier("editor.tools.\(index + 1)")
    }

    private func take(_ choice: ToolChoice, named name: String) {
        toolbox.take(choice)
        UISelectionFeedbackGenerator().selectionChanged()
        AccessibilityNotification.Announcement(name).post()
    }

    /// Takes a pen up and opens its options, where it is also moved along the tray or taken off it.
    private func change(_ pen: ToolPreset) {
        guard editing != pen.id else { return }
        toolbox.take(.pen(pen.id))
        UISelectionFeedbackGenerator().selectionChanged()
        editing = pen.id
    }

    /// The new pen opens, so its colour can be chosen straight away.
    private func addPen() {
        guard let id = toolbox.addPen() else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            editing = id
        }
    }

    private func remove(_ pen: ToolPreset) {
        if editing == pen.id { editing = nil }
        toolbox.removePen(pen.id)
        AccessibilityNotification.Announcement(String(localized: "\(pen.name) removed from the tools")).post()
    }

    // MARK: Eraser, lasso and shortcuts

    private var eraserButton: some View {
        let inHand = toolbox.choice == .eraser
        return Button { if inHand { editingEraser = true } else { take(.eraser, named: String(localized: "Eraser")) } } label: {
            Label("Eraser", systemImage: "eraser")
        }
        .buttonStyle(TrayIconStyle(isOn: inHand))
        .panel("Eraser", isPresented: $editingEraser) {
            ScrollView { EraserOptions(toolbox: toolbox) }
                .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityValue(Text(toolbox.eraser.kind.displayName))
        .accessibilityAddTraits(inHand ? .isSelected : [])
        .accessibilityIdentifier("editor.tools.eraser")
    }

    private var lassoButton: some View {
        let inHand = toolbox.choice == .lasso
        return Button { take(.lasso, named: String(localized: "Lasso")) } label: { Label("Lasso", systemImage: "lasso") }
            .buttonStyle(TrayIconStyle(isOn: inHand))
            .accessibilityAddTraits(inHand ? .isSelected : [])
            .accessibilityIdentifier("editor.tools.lasso")
    }

    private func extraButton(_ extra: ToolExtra) -> some View {
        let isOn = switch extra {
        case .ruler: toolbox.isRulerActive
        case .zoomWindow: session.isZoomWindowOpen
        case .typing: toolbox.typesHandwriting
        default: false
        }
        return Button { use(extra) } label: { Label(extra.title, systemImage: extra.symbol) }
            .buttonStyle(TrayIconStyle(isOn: isOn))
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityIdentifier("editor.tools.extra.\(extra.rawValue)")
    }

    private var customiseButton: some View {
        Button { customising = true } label: { Label("Customise Tools", systemImage: "slider.horizontal.3") }
            .buttonStyle(TrayIconStyle(isOn: customising))
            .panel("Customise Tools", isPresented: $customising) {
                ScrollView { ShortcutOptions(toolbox: toolbox) }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .accessibilityIdentifier("editor.tools.customise")
    }
}

/// Which shortcuts stand in the tray, as tags: one that is tied on is mustard, with a check mark.
private struct ShortcutOptions: View {
    let toolbox: Toolbox
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        // At the largest text sizes the tags are a list, each the whole width, so no name is cut short.
        // At the very largest the card is wider too, or a word as short as "Imagen" is split over two lines.
        let list = textSize.isAccessibilitySize
        let width: CGFloat = textSize > .accessibility2 ? 440 : 328
        let layout = list ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x2)) : AnyLayout(FlowLayout(spacing: Space.x2))
        VStack(alignment: .leading, spacing: Space.x2) {
            Text("Shortcuts in the Tray")
                .font(.headline)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            layout {
                ForEach(ToolExtra.allCases) { extra in
                    let shown = toolbox.extras.contains(extra)
                    ShortcutTag(extra: extra, isShown: shown, fills: list) { toolbox.setExtra(extra, shown: !shown) }
                        .padding(.vertical, -Space.x1)
                        .accessibilityIdentifier("editor.tools.shortcut.\(extra.rawValue)")
                }
            }
        }
        .padding(Space.x4)
        .frame(minWidth: 328, idealWidth: width, maxWidth: width, alignment: .leading)
    }
}

/// A shortcut as a tag: mustard with a check mark while it stands in the tray, plain with a plus while it doesn't.
/// A plain tag is paper by day and a well at night.
private struct ShortcutTag: View {
    let extra: ToolExtra
    let isShown: Bool
    /// The whole width, with the name on as many lines as it needs.
    let fills: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let night = scheme == .dark
        let shape = RoundedRectangle.plate
        Button(action: action) {
            HStack(spacing: Space.x2) {
                Image(systemName: extra.symbol).font(.footnote.weight(.semibold))
                Text(extra.title)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
                Image(systemName: isShown ? "checkmark" : "plus").font(.caption.weight(.bold)).opacity(isShown ? 1 : 0.6)
            }
            .foregroundStyle(isShown ? Color.onMustard : night ? Color.ink : Color.labelInk)
            .padding(.horizontal, Space.x3)
            .padding(.vertical, Space.x1)
            .frame(minHeight: 32)
            .background(isShown ? Color.mustard : ToolSwatch.paper(onDark: false, night: night), in: shape)
            .overlay { shape.strokeBorder(Color.hairline, lineWidth: 1) }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(extra.title)
        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
    }
}

/// A pen's kind, colour, width and opacity, changed where it stands in the tray.
private struct PenOptions: View {
    let id: UUID
    let toolbox: Toolbox
    let onDark: Bool
    let turned: Bool
    let remove: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var scheme

    private static let cell: CGFloat = 44
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 6)

    var body: some View {
        if let pen = toolbox.shelf.usable.first(where: { $0.id == id }), let ink = pen.inkType {
            content(pen, ink)
                .frame(width: 304 + Space.x4 * 2)
        }
    }

    private func content(_ pen: ToolPreset, _ ink: PKInkingTool.InkType) -> some View {
        let width = pen.width.formatted(.number.precision(.fractionLength(0...1)))
        let night = scheme == .dark && !onDark
        // The label shows the ink as faint as it is set; the tools of the roll and the bars are drawn at full strength.
        let colour = ToolSwatch.ink(pen, onDark: onDark, night: night, turned: turned)
        let solid = ToolSwatch.ink(pen, onDark: onDark, solid: true, turned: turned)
        let paper = ToolSwatch.paper(onDark: onDark, night: night), faintest = ToolPreset.leastOpacity
        // At the largest text sizes the name goes under the label, where it has the whole width.
        let stacked = textSize.isAccessibilitySize
        let header = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x2)) : AnyLayout(HStackLayout(spacing: Space.x3))
        return VStack(alignment: .leading, spacing: Space.x3) {
            header {
                InkLabel(kind: ink, breadth: pen.widthTravel, ink: colour, paper: paper, night: night)
                VStack(alignment: .leading, spacing: 0) {
                    Text(pen.kindName).font(.headline).foregroundStyle(Color.ink)
                    Text(pen.opacity < 1 ? "\(pen.colorName), \(pen.opacityName)" : pen.colorName).font(.footnote).foregroundStyle(Color.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            PenRoll(kind: Binding(get: { ink }, set: { kind in
                toolbox.changePen(id) { $0.ink = kind.rawValue; $0.width = Double(kind.defaultWidth) }
            }), ink: solid, paper: paper, night: night)
                .accessibilityIdentifier("editor.tools.pen.kind")
            LazyVGrid(columns: Self.columns, spacing: 0) {
                ForEach(ToolPreset.palette(for: ink), id: \.self) { color in colourButton(color, chosen: pen.tint == color) }
                ColorPicker("Custom Colour", selection: Binding(get: { Color(uiColor: ToolPreset.uiColor(pen.tint)) }, set: { color in
                    toolbox.changePen(id) { $0.setTint(ToolPreset.bytes(of: UIColor(color))) }
                }), supportsOpacity: false)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, minHeight: Self.cell)
                    .accessibilityIdentifier("editor.tools.pen.custom")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Colour"))
            WidthBar(travel: Binding(get: { pen.widthTravel }, set: { travel in
                toolbox.changePen(id) { $0.width = ToolPreset.width(at: travel, of: ink) }
            }), ink: solid, paper: paper, night: night, value: width, identifier: "editor.tools.pen.width")
            // Opacity moves in steps of a twentieth, so the figure beside it is a round one.
            WidthBar(measure: .opacity, travel: Binding(get: { (pen.opacity - faintest) / (1 - faintest) }, set: { travel in
                toolbox.changePen(id) { $0.opacity = ((faintest + (1 - faintest) * travel) * 20).rounded() / 20 }
            }), ink: solid, paper: paper, night: night, turned: turned, value: pen.opacityName, identifier: "editor.tools.pen.opacity")
            place(pen)
        }
        .padding(Space.x4)
    }

    /// Where the pen stands among the others, and the way off the tray.
    private func place(_ pen: ToolPreset) -> some View {
        let pens = toolbox.shelf.usable, index = pens.firstIndex { $0.id == id } ?? 0
        return HStack(spacing: 0) {
            Button { toolbox.shelf.move(id, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") }
                .disabled(index == 0)
                .accessibilityIdentifier("editor.tools.pen.left")
            Button { toolbox.shelf.move(id, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") }
                .disabled(index >= pens.count - 1)
                .accessibilityIdentifier("editor.tools.pen.right")
            Spacer(minLength: 0)
            Button(role: .destructive, action: remove) { Label("Remove", systemImage: "trash") }
                .disabled(pens.count < 2)
                .accessibilityIdentifier("editor.tools.pen.remove")
        }
        .buttonStyle(.barIcon)
        .padding(.top, Space.x1)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }

    private func colourButton(_ color: UInt32, chosen: Bool) -> some View {
        Button { toolbox.changePen(id) { $0.setTint(color) } } label: {
            Circle()
                .fill(Color(uiColor: ToolPreset.uiColor(color)))
                .overlay { Circle().strokeBorder(Color.ink.opacity(scheme == .dark ? 0.45 : 0.25), lineWidth: 1) }
                .frame(width: 28, height: 28)
                .padding(4)
                .overlay { if chosen { Circle().strokeBorder(Color.accentColor, lineWidth: 2) } }
                .frame(maxWidth: .infinity, minHeight: Self.cell)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ToolPreset.colorName(color)))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// What the eraser takes, and how wide it is when it takes part of a stroke.
private struct EraserOptions: View {
    let toolbox: Toolbox
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let eraser = toolbox.eraser, night = scheme == .dark
        let width = eraser.width.formatted(.number.precision(.fractionLength(0)))
        VStack(alignment: .leading, spacing: Space.x3) {
            OwlLunaSegmentedPicker("Eraser", selection: Binding(get: { eraser.kind }, set: { kind in
                var changed = eraser
                changed.kind = kind
                toolbox.setEraser(changed)
            }), options: Eraser.Kind.allCases) { Text($0.displayName) }
            if eraser.kind == .part {
                let widths = Eraser.widths, span = widths.upperBound - widths.lowerBound
                WidthBar(travel: Binding(get: { (eraser.width - widths.lowerBound) / span }, set: { travel in
                    var changed = eraser
                    changed.width = widths.lowerBound + span * travel
                    toolbox.setEraser(changed)
                }), ink: night ? Color.textSecondary : Color.labelInkSecondary, paper: ToolSwatch.paper(onDark: false, night: night), night: night,
                         value: width, identifier: "editor.tools.eraser.width")
            }
        }
        .padding(Space.x4)
        .frame(width: 344)
    }
}

/// A width, as a stroke that swells along a strip of paper with a knob to slide on it; the knob holds a blot as
/// large as the stroke is where it stands. An opacity is a wash over ruled lines that covers more of them as it
/// goes, and the knob's blot is as faint as the ink is set.
private struct WidthBar: View {
    enum Measure { case width, opacity }

    var measure = Measure.width
    /// How far along the knob is, from 0 to 1.
    @Binding var travel: Double
    let ink: Color
    let paper: Color
    /// At night the strip is a well, and the stroke and the blot wear a light rim.
    var night = false
    /// The page is dark as well, so a faint ink is faint over the dark.
    var turned = false
    let value: String
    let identifier: String
    @State private var isDragging = false
    @Environment(\.colorSchemeContrast) private var contrast

    private static let height: CGFloat = 44
    private static let knob: CGFloat = 32
    private static let shape = RoundedRectangle.track

    var body: some View {
        let name = title.font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
        let figure = Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(Color.textSecondary)
        return VStack(spacing: Space.x2) {
            // At the largest text sizes "Opacity" and its figure don't fit side by side; the figure goes under it.
            ViewThatFits(in: .horizontal) {
                HStack {
                    name.lineLimit(1)
                    Spacer(minLength: Space.x2)
                    figure.lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 0) {
                    name
                    figure
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHidden(true)
            strip
        }
    }

    private var title: Text { measure == .width ? Text("Width") : Text("Opacity") }

    private var strip: some View {
        GeometryReader { proxy in
            let run = max(proxy.size.width - Self.knob - Space.x2 * 2, 1)
            ZStack(alignment: .leading) {
                Self.shape.fill(paper)
                Group {
                    switch measure {
                    case .width:
                        Swell()
                            .fill(ink)
                            .overlay { if night { Swell().stroke(ToolSwatch.rim(contrast), lineWidth: 1) } }
                            .frame(height: 20)
                    case .opacity:
                        wash
                    }
                }
                .padding(.horizontal, Space.x2 + Self.knob / 2)
                knob.offset(x: Space.x2 + run * travel)
            }
            .overlay { Self.shape.strokeBorder(Color.hairline, lineWidth: 1) }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    isDragging = true
                    travel = min(max((drag.location.x - Space.x2 - Self.knob / 2) / run, 0), 1)
                }
                .onEnded { _ in isDragging = false })
        }
        .frame(height: Self.height)
        .accessibilityRepresentation {
            Slider(value: $travel)
                .accessibilityLabel(title)
                .accessibilityValue(Text(value))
                .accessibilityIdentifier(identifier)
        }
    }

    /// The ink at `strength`. At night it isn't paper it lies on, so it is as pale as it would be on a page.
    private func faint(_ strength: Double) -> Color {
        night && !turned ? ToolSwatch.onPaper(UIColor(ink), at: strength) : ink.opacity(strength)
    }

    /// The lines of a page with the ink washed over them, from as faint as a pen can be to full strength: the
    /// stronger the ink, the less of the lines shows through.
    private var wash: some View {
        let band = RoundedRectangle.thumb
        let lines = VStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in Rectangle().fill(night ? Color.black.opacity(0.4) : Color.ink.opacity(0.35)).frame(height: 1) }
        }
        return ZStack {
            if !night { lines }
            band.fill(LinearGradient(colors: [faint(ToolPreset.leastOpacity), ink], startPoint: .leading, endPoint: .trailing))
            if night { lines.mask(LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)) }
        }
        .frame(height: 16)
        .clipShape(band)
        .overlay { band.strokeBorder(night ? ToolSwatch.rim(contrast) : Color.ink.opacity(0.18), lineWidth: 1) }
        .frame(height: 20)
    }

    private var knob: some View {
        let blot = measure == .width ? 4 + 16 * travel : 16
        let strength = measure == .width ? 1 : ToolPreset.leastOpacity + (1 - ToolPreset.leastOpacity) * travel
        return Circle()
            .fill(night ? Color.surface : paper)
            .overlay { if measure == .opacity { Rectangle().fill(Color.ink.opacity(night ? 0.5 : 0.35)).frame(width: 22, height: 1) } }
            .overlay {
                Circle()
                    .fill(faint(strength))
                    .overlay { if night || measure == .opacity { Circle().strokeBorder(ToolSwatch.rim(contrast).opacity(night ? 1 : 0.5), lineWidth: 1) } }
                    .frame(width: blot, height: blot)
            }
            .overlay { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
            .frame(width: Self.knob, height: Self.knob)
            .shadow(color: .black.opacity(0.22), radius: isDragging ? 4 : 1.5, y: 1)
            .scaleEffect(isDragging ? 1.08 : 1)
            .animation(Motion.quick, value: isDragging)
    }

    /// A stroke that begins as a hairline and ends as broad as the strip allows, round at both ends.
    private struct Swell: Shape {
        func path(in rect: CGRect) -> Path {
            let thin: CGFloat = 1, broad = rect.height / 2
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + thin, y: rect.midY - thin))
            path.addLine(to: CGPoint(x: rect.maxX - broad, y: rect.midY - broad))
            path.addArc(center: CGPoint(x: rect.maxX - broad, y: rect.midY), radius: broad, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + thin, y: rect.midY + thin))
            path.addArc(center: CGPoint(x: rect.minX + thin, y: rect.midY), radius: thin, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
            path.closeSubpath()
            return path
        }
    }
}

/// One pen: its ink as a blot on a paper label, as large as the pen is wide, under the mark of its kind.
/// Like a cover's label, the paper stays cream at night, so the ink is seen as it is on a page.
struct ToolSwatch: View {
    let preset: ToolPreset
    var inUse = false
    /// On Chalkboard the label is the board's green, and the ink as light as it is written there.
    var onDark = false
    /// On paper that Dark Mode shows dark the ink is as light as it is there, on the well.
    var turned = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    static let side: CGFloat = 32
    static let shape = RoundedRectangle.plate
    private static let chalkboard = Color(red: PaperColor.chalkboard.rgb.0, green: PaperColor.chalkboard.rgb.1, blue: PaperColor.chalkboard.rgb.2)

    /// What a pen's ink is shown on: paper by day, a well as dark as the tray at night, Chalkboard's green on a Chalkboard page.
    static func paper(onDark: Bool, night: Bool = false) -> Color { onDark ? chalkboard : night ? Color.well : Color.labelCream }

    /// The light rim that tells ink from the dark it is shown on at night.
    static func rim(_ contrast: ColorSchemeContrast) -> Color { Color.ink.opacity(contrast == .increased ? 0.9 : 0.55) }

    /// The ink as it is on the page, as faint as the pen is set unless `solid` asks for it at full strength. At
    /// `night` a faint ink lies on a dark well, not on paper, so it is shown as pale as a page would make it. Where
    /// the page has `turned` dark, the well is what it is written on.
    static func ink(_ preset: ToolPreset, onDark: Bool, solid: Bool = false, night: Bool = false, turned: Bool = false) -> Color {
        if night, !onDark, !turned, !solid, preset.opacity < 1 { return onPaper(ToolPreset.uiColor(preset.tint), at: preset.opacity) }
        let color = solid ? ToolPreset.uiColor(preset.tint) : preset.uiColor
        return Color(uiColor: onDark || turned ? PKInkingTool.convertColor(color, from: .light, to: .dark) : color)
    }

    /// A colour as it shows on white paper at `opacity`, with nothing left to show through it.
    static func onPaper(_ color: UIColor, at opacity: Double) -> Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let rest = 1 - opacity
        return Color(red: red * opacity + rest, green: green * opacity + rest, blue: blue * opacity + rest)
    }

    var body: some View {
        let shape = Self.shape
        let blot = 9 + 11 * preset.widthFraction
        // At night the label is a well in the tray, as dark as the rest of it, and the ink is told from it by its rim.
        let night = scheme == .dark && !onDark
        let rim = night ? Self.rim(contrast) : (onDark ? Color.white : Color.labelInk).opacity(contrast == .increased ? 0.6 : 0.22)
        ZStack {
            shape.fill(Self.paper(onDark: onDark, night: night))
            Circle()
                .fill(Self.ink(preset, onDark: onDark, night: night, turned: turned))
                .overlay { Circle().strokeBorder(rim, lineWidth: 1) }
                .frame(width: blot, height: blot)
                .offset(x: 3, y: 3)
            Image(systemName: preset.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(night ? Color.textSecondary : onDark ? Color.white.opacity(0.8) : Color.labelInkSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(3)
        }
        .frame(width: Self.side, height: Self.side)
        .overlay { shape.strokeBorder(inUse ? Color.accentColor : Color.hairline, lineWidth: inUse ? 2 : 1) }
        .overlay(alignment: .bottomTrailing) {
            if inUse {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.onPrimaryCloth)
                    .frame(width: 14, height: 14)
                    .background(Color.primaryCloth, in: Circle())
                    .offset(x: 3, y: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ToolSwatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .frame(width: ToolTray.slot, height: ToolTray.button)
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, RoundedRectangle.plate.inset(by: 1))
            .hoverEffect(.highlight)
    }
}

/// An icon in the tray. The tool in hand, and a helper that is on, wears the frame the pen in hand does.
struct TrayIconStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        Icon(configuration: configuration, isOn: isOn)
    }

    private struct Icon: View {
        let configuration: Configuration
        let isOn: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityShowBorders) private var showBorders

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .imageScale(.large)
                .foregroundStyle(Color.ink)
                .opacity(isEnabled ? 1 : 0.35)
                .frame(width: ToolSwatch.side, height: ToolSwatch.side)
                .background { if isOn || (configuration.isPressed && isEnabled) || showBorders { ToolSwatch.shape.fill(Color.well) } }
                .overlay { if isOn { ToolSwatch.shape.strokeBorder(Color.accentColor, lineWidth: 2) } }
                .frame(width: ToolTray.button, height: ToolTray.button)
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, RoundedRectangle.plate.inset(by: 1))
                .hoverEffect(.highlight)
                // The tray stays one height; its options, opened from here, grow with the text size.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityShowsLargeContentViewer { configuration.label.labelStyle(.titleAndIcon) }
        }
    }
}

private struct NewPenButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Icon(configuration: configuration)
    }

    private struct Icon: View {
        let configuration: Configuration
        @Environment(\.accessibilityShowBorders) private var showBorders

        /// An empty label waiting for a pen, so it isn't taken for the bar's Add.
        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: ToolSwatch.side, height: ToolSwatch.side)
                .background { if configuration.isPressed || showBorders { ToolSwatch.shape.fill(Color.well) } }
                .overlay {
                    ToolSwatch.shape.strokeBorder(Color.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .frame(width: ToolTray.slot, height: ToolTray.button)
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, RoundedRectangle.plate.inset(by: 1))
                .hoverEffect(.highlight)
                .accessibilityShowsLargeContentViewer { configuration.label.labelStyle(.titleAndIcon) }
        }
    }
}
