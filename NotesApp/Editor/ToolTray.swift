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
        HStack(spacing: 0) {
            penRow(pens)
                .frame(width: plan.pens, height: Self.button)
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(hidden.contains(.leading) ? 0 : 1), .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: Self.fade)
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(hidden.contains(.trailing) ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                            .frame(width: Self.fade)
                    }
                }
            rule
            eraserButton
            lassoButton
            rule
            ForEach(extras.prefix(plan.extras)) { extraButton($0) }
            customiseMenu
        }
        .padding(.horizontal, Self.inset)
        .frame(height: Self.height)
        .board(in: Capsule())
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
        }
    }

    private func penButton(_ pen: ToolPreset, at index: Int, of count: Int) -> some View {
        let inHand = toolbox.choice == .pen(pen.id)
        // The pen in hand opens; any other is taken up.
        return Button { if inHand { editing = pen.id } else { take(.pen(pen.id), named: pen.name) } } label: {
            ToolSwatch(preset: pen, inUse: inHand, onDark: session.inkIsLight)
        }
        .buttonStyle(ToolSwatchButtonStyle())
        .popover(isPresented: Binding(get: { editing == pen.id }, set: { if !$0, editing == pen.id { editing = nil } })) {
            PenOptions(id: pen.id, toolbox: toolbox, onDark: session.inkIsLight) { remove(pen) }
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Color.surface)
        }
        .contextMenu {
            Button { change(pen) } label: { Label("Change Pen…", systemImage: "slider.horizontal.3") }
            if index > 0 { Button { toolbox.shelf.move(pen.id, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") } }
            if index < count - 1 { Button { toolbox.shelf.move(pen.id, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") } }
            if count > 1 { Button(role: .destructive) { remove(pen) } label: { Label("Remove", systemImage: "trash") } }
        }
        .accessibilityLabel(Text(pen.name))
        .accessibilityValue(Text("Width \(pen.width.formatted(.number.precision(.fractionLength(0...1))))"))
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

    /// Opens a pen's kind, colour and width, once the menu that asked for it has gone.
    private func change(_ pen: ToolPreset) {
        toolbox.take(.pen(pen.id))
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            editing = pen.id
        }
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
        .popover(isPresented: $editingEraser) {
            EraserOptions(toolbox: toolbox)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Color.surface)
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
        default: false
        }
        return Button { use(extra) } label: { Label(extra.title, systemImage: extra.symbol) }
            .buttonStyle(TrayIconStyle(isOn: isOn))
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityIdentifier("editor.tools.extra.\(extra.rawValue)")
    }

    /// Which shortcuts stand in the tray. The menu stays open, so several can be changed at once.
    private var customiseMenu: some View {
        Menu {
            Section("Shortcuts in the Tray") {
                ForEach(ToolExtra.allCases) { extra in
                    Toggle(isOn: Binding(get: { toolbox.extras.contains(extra) }, set: { toolbox.setExtra(extra, shown: $0) })) {
                        Label(extra.title, systemImage: extra.symbol)
                    }
                }
            }
        } label: {
            Label("Customise Tools", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.barIcon)
        .menuStyle(.button)
        .menuOrder(.fixed)
        .menuActionDismissBehavior(.disabled)
        .accessibilityIdentifier("editor.tools.customise")
    }
}

/// A pen's kind, colour and width, changed where it stands in the tray.
private struct PenOptions: View {
    let id: UUID
    let toolbox: Toolbox
    let onDark: Bool
    let remove: () -> Void

    private static let cell: CGFloat = 44
    private static let columns = Array(repeating: GridItem(.fixed(cell), spacing: 0), count: 6)

    var body: some View {
        if let pen = toolbox.shelf.usable.first(where: { $0.id == id }), let ink = pen.inkType {
            content(pen, ink)
                .frame(width: Self.cell * 6 + Space.x4 * 2)
        }
    }

    private func content(_ pen: ToolPreset, _ ink: PKInkingTool.InkType) -> some View {
        let width = pen.width.formatted(.number.precision(.fractionLength(0...1)))
        return VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x2) {
                ToolSwatch(preset: pen, onDark: onDark)
                Picker("Kind", selection: Binding(get: { ink }, set: { kind in
                    toolbox.changePen(id) { $0.ink = kind.rawValue; $0.width = Double(kind.defaultWidth) }
                })) {
                    ForEach(ToolPreset.kinds, id: \.self) { Label(ToolPreset.name(of: $0), systemImage: ToolPreset.symbol(of: $0)).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Color.ink)
                .fixedSize()
                .accessibilityIdentifier("editor.tools.pen.kind")
                Spacer(minLength: 0)
                Button(role: .destructive, action: remove) { Label("Remove", systemImage: "trash") }
                    .buttonStyle(.barIcon)
                    .disabled(toolbox.shelf.usable.count < 2)
                    .accessibilityIdentifier("editor.tools.pen.remove")
            }
            LazyVGrid(columns: Self.columns, spacing: 0) {
                ForEach(ToolPreset.palette(for: ink), id: \.self) { color in colourButton(color, chosen: pen.color == color) }
                ColorPicker("Custom Colour", selection: Binding(get: { Color(uiColor: pen.uiColor) }, set: { color in
                    toolbox.changePen(id) { $0.color = ToolPreset.bytes(of: UIColor(color)) }
                }), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: Self.cell, height: Self.cell)
                    .accessibilityIdentifier("editor.tools.pen.custom")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Colour"))
            WidthBar(travel: Binding(get: { pen.widthTravel }, set: { travel in
                toolbox.changePen(id) { $0.width = ToolPreset.width(at: travel, of: ink) }
            }), ink: ToolSwatch.ink(pen, onDark: onDark), paper: ToolSwatch.paper(onDark: onDark), value: width, identifier: "editor.tools.pen.width")
        }
        .padding(Space.x4)
    }

    private func colourButton(_ color: UInt32, chosen: Bool) -> some View {
        Button { toolbox.changePen(id) { $0.color = color } } label: {
            Circle()
                .fill(Color(uiColor: ToolPreset.uiColor(color)))
                .overlay { Circle().strokeBorder(Color.ink.opacity(0.25), lineWidth: 1) }
                .frame(width: 28, height: 28)
                .padding(4)
                .overlay { if chosen { Circle().strokeBorder(Color.accentColor, lineWidth: 2) } }
                .frame(width: Self.cell, height: Self.cell)
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

    var body: some View {
        let eraser = toolbox.eraser
        let width = eraser.width.formatted(.number.precision(.fractionLength(0)))
        VStack(alignment: .leading, spacing: Space.x3) {
            ScribeSegmentedPicker("Eraser", selection: Binding(get: { eraser.kind }, set: { kind in
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
                }), ink: Color.labelInkSecondary, paper: ToolSwatch.paper(onDark: false), value: width, identifier: "editor.tools.eraser.width")
            }
        }
        .padding(Space.x4)
        .frame(width: 344)
    }
}

/// A width, as a stroke that swells along a strip of paper with a knob to slide on it. The knob holds a blot as
/// large as the stroke is where it stands. Like the pens' labels, the paper stays cream at night.
private struct WidthBar: View {
    /// How far along the knob is, from 0 to 1.
    @Binding var travel: Double
    let ink: Color
    let paper: Color
    let value: String
    let identifier: String
    @State private var isDragging = false

    private static let height: CGFloat = 44
    private static let knob: CGFloat = 32
    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(spacing: Space.x2) {
            HStack {
                Text("Width").font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                Spacer(minLength: Space.x2)
                Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(Color.textSecondary)
            }
            .accessibilityHidden(true)
            strip
        }
    }

    private var strip: some View {
        GeometryReader { proxy in
            let run = max(proxy.size.width - Self.knob - Space.x2 * 2, 1)
            ZStack(alignment: .leading) {
                Self.shape.fill(paper)
                Swell()
                    .fill(ink)
                    .frame(height: 20)
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
                .accessibilityLabel(Text("Width"))
                .accessibilityValue(Text(value))
                .accessibilityIdentifier(identifier)
        }
    }

    private var knob: some View {
        let blot = 4 + 16 * travel
        return Circle()
            .fill(paper)
            .overlay { Circle().fill(ink).frame(width: blot, height: blot) }
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
    @Environment(\.colorSchemeContrast) private var contrast

    static let side: CGFloat = 32
    static let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
    private static let chalkboard = Color(red: PaperColor.chalkboard.rgb.0, green: PaperColor.chalkboard.rgb.1, blue: PaperColor.chalkboard.rgb.2)

    static func paper(onDark: Bool) -> Color { onDark ? chalkboard : Color.labelCream }

    static func ink(_ preset: ToolPreset, onDark: Bool) -> Color {
        Color(uiColor: onDark ? PKInkingTool.convertColor(preset.uiColor, from: .light, to: .dark) : preset.uiColor)
    }

    var body: some View {
        let shape = Self.shape
        let blot = 9 + 11 * preset.widthFraction
        ZStack {
            shape.fill(Self.paper(onDark: onDark))
            Circle()
                .fill(Self.ink(preset, onDark: onDark))
                .overlay { Circle().strokeBorder((onDark ? Color.white : Color.labelInk).opacity(contrast == .increased ? 0.6 : 0.22), lineWidth: 1) }
                .frame(width: blot, height: blot)
                .offset(x: 3, y: 3)
            Image(systemName: preset.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(onDark ? Color.white.opacity(0.8) : Color.labelInkSecondary)
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
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 11, style: .continuous).inset(by: 1))
            .hoverEffect(.highlight)
    }
}

/// An icon in the tray. The tool in hand, and a helper that is on, wears the frame the pen in hand does.
private struct TrayIconStyle: ButtonStyle {
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
                .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 11, style: .continuous).inset(by: 1))
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
                .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 11, style: .continuous).inset(by: 1))
                .hoverEffect(.highlight)
                .accessibilityShowsLargeContentViewer { configuration.label.labelStyle(.titleAndIcon) }
        }
    }
}
