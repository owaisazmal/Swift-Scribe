import SwiftUI

/// Controls are bound like the notebooks: boards stand on the desk, wells are pressed into it, plates are ruled onto a bar,
/// and the finishing action is cloth.
enum Elevation {
    /// Shadows on the desk are a warm umber by day and plain black at night.
    static func shade(_ dark: Bool) -> Color { dark ? .black : umber }
    private static let umber = Color(hex: 0x2A2116)
}

/// The covers' two-way weave at the shelf cover's scale, for filled buttons.
@MainActor
enum ClothWeave {
    static let tile: Image = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).image { context in
            let ctx = context.cgContext
            ctx.setLineWidth(2)
            for (alpha, white, rising) in [(0.06, 1.0, true), (0.07, 0.0, false)] {
                ctx.setStrokeColor(UIColor(white: white, alpha: alpha).cgColor)
                for x in stride(from: -4.0, through: 4.0, by: 4.0) {
                    ctx.move(to: CGPoint(x: rising ? x - 1 : x + 5, y: -1))
                    ctx.addLine(to: CGPoint(x: rising ? x + 5 : x - 1, y: 5))
                }
                ctx.strokePath()
            }
        }
        return Image(uiImage: image)
    }()
}

private struct BoardSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var pressed = false
    var flat = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let dark = scheme == .dark, raised = !pressed && !flat
        content
            .background {
                shape.fill(Color.board.opacity(flat ? 0.5 : 1))
                    .overlay { if pressed { shape.fill(Color.well) } }
                    .shadow(color: Elevation.shade(dark).opacity(raised ? (dark ? 0.40 : 0.10) : 0), radius: 0.5, y: 0.5)
                    .shadow(color: Elevation.shade(dark).opacity(raised ? (dark ? 0.22 : 0.07) : 0), radius: 6, y: 3)
            }
            .overlay {
                if contrast != .increased, raised {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.09 : 0.85), .white.opacity(0)],
                                                      startPoint: .top, endPoint: .center), lineWidth: 1)
                        .padding(1)
                        .allowsHitTesting(false)
                }
            }
            .overlay { if !flat { shape.strokeBorder(Color.hairline, lineWidth: 1).allowsHitTesting(false) } }
    }
}

private struct WellSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var focused = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let dark = scheme == .dark, increased = contrast == .increased
        content
            .background {
                shape.fill(Color.well.shadow(.inner(color: Elevation.shade(dark).opacity(dark ? 0.6 : 0.16), radius: 1.5, y: 1)))
            }
            .overlay {
                if !increased {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0), .white.opacity(dark ? 0.06 : 0.7)],
                                                      startPoint: .center, endPoint: .bottom), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                shape.strokeBorder(focused ? Color.accentColor : (increased ? Color.ink.opacity(0.5) : Color.hairline),
                                   lineWidth: focused ? (increased ? 2 : 1.5) : 1)
                    .allowsHitTesting(false)
            }
            .animation(Motion.quick, value: focused)
    }
}

func plateEdge(_ contrast: ColorSchemeContrast, flat: Bool = false) -> Color {
    Color.ink.opacity(flat ? 0.18 : (contrast == .increased ? 0.7 : 0.35))
}

private struct PlateSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var fill: Color = .clear
    var pressed = false
    var focused = false
    var flat = false
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background { shape.fill(fill).overlay { if pressed { shape.fill(Color.well) } } }
            .overlay {
                shape.strokeBorder(focused ? Color.accentColor : plateEdge(contrast, flat: flat),
                                   lineWidth: focused ? (contrast == .increased ? 2 : 1.5) : 1)
                    .allowsHitTesting(false)
            }
            .animation(Motion.quick, value: focused)
    }
}

extension RoundedRectangle {
    static let plate = RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
    static let thumb = RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous)
    static let track = RoundedRectangle(cornerRadius: Radius.track, style: .continuous)
    static let bar = RoundedRectangle(cornerRadius: Radius.bar, style: .continuous)
}

extension View {
    /// A flat panel ruled in ink, with nothing under it unless it is given a fill: what a bar's controls are cut from.
    func plate<S: InsettableShape>(in shape: S, fill: Color = .clear, pressed: Bool = false, focused: Bool = false,
                                   flat: Bool = false) -> some View {
        modifier(PlateSurface(shape: shape, fill: fill, pressed: pressed, focused: focused, flat: flat))
    }

    /// A raised Board panel with a Hairline edge, a lit top edge and a soft umber shadow.
    func board<S: InsettableShape>(in shape: S, pressed: Bool = false, flat: Bool = false) -> some View {
        modifier(BoardSurface(shape: shape, pressed: pressed, flat: flat))
    }

    /// A recessed panel for things that take input: text fields and segment tracks.
    func well<S: InsettableShape>(in shape: S, focused: Bool = false) -> some View {
        modifier(WellSurface(shape: shape, focused: focused))
    }
}

/// Bars stay one height: their controls stop growing at the largest standard size and show the Large Content Viewer instead.
private let barTextLimit = DynamicTypeSize.xxxLarge

/// A bar's controls are drawn 40 points tall and touched at 44.
private enum Bar {
    static let height: CGFloat = 40
    static let inset: CGFloat = 2
}

/// What a control stands on: a plate in a bar, a board where it has to stand clear of what is under it.
private struct Ground: ViewModifier {
    enum Kind { case none, plate, board }

    let kind: Kind
    let shape: RoundedRectangle
    let pressed: Bool
    let flat: Bool

    func body(content: Content) -> some View {
        switch kind {
        case .none: content
        case .plate: content.plate(in: shape, pressed: pressed, flat: flat)
        case .board: content.board(in: shape, pressed: pressed, flat: flat)
        }
    }
}

private struct TextSizeCap: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active { content.dynamicTypeSize(...barTextLimit) } else { content }
    }
}

private struct BarLimit: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.dynamicTypeSize(...barTextLimit).accessibilityShowsLargeContentViewer()
        } else {
            content
        }
    }
}

// MARK: Buttons

struct OwlLunaButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, destructive }

    var role: Role = .secondary
    var compact = false
    var inBar = false

    func makeBody(configuration: Configuration) -> some View {
        OwlLunaButton(configuration: configuration, role: role, compact: compact, inBar: inBar)
    }

    private struct OwlLunaButton: View {
        let configuration: Configuration
        let role: Role
        let compact: Bool
        let inBar: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        private let shape = RoundedRectangle.plate
        private var height: CGFloat { compact ? 34 : (inBar ? Bar.height : 44) }

        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            let cloth = role != .secondary
            let wraps = !inBar && dynamicTypeSize.isAccessibilitySize
            configuration.label
                .font(.system(compact ? .subheadline : (inBar ? .callout : .body), weight: cloth ? .semibold : .medium))
                .lineLimit(wraps ? 3 : 1)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: inBar, vertical: true)
                .foregroundStyle(foreground)
                .padding(.horizontal, compact || inBar ? Space.x3 : Space.x4)
                .padding(.vertical, wraps ? Space.x2 : 0)
                .frame(minWidth: 44, minHeight: height)
                .fixedSize(horizontal: inBar, vertical: false)
                .background { if cloth { filled(pressed: pressed) } }
                .modifier(Ground(kind: cloth ? .none : (inBar ? .plate : .board), shape: shape, pressed: pressed, flat: !isEnabled))
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .contentShape([.hoverEffect, .accessibility], shape)
                .hoverEffect(.highlight)
                .padding(.vertical, (44 - height) / 2)
                .contentShape(Rectangle())
                .animation(Motion.quick, value: pressed)
                .modifier(BarLimit(active: inBar))
        }

        private var foreground: Color {
            guard isEnabled else { return .textSecondary }
            switch role {
            case .primary: return .onPrimaryCloth
            case .secondary: return .ink
            case .destructive: return .onDestructiveCloth
            }
        }

        @ViewBuilder
        private func filled(pressed: Bool) -> some View {
            if !isEnabled {
                shape.fill(Color.well)
            } else {
                let dark = scheme == .dark
                shape
                    .fill(role == .destructive ? Color.destructiveCloth : Color.primaryCloth)
                    .shadow(color: Elevation.shade(dark).opacity(pressed ? 0 : (dark ? 0.22 : 0.10)), radius: 4, y: 2)
                    .shadow(color: Elevation.shade(dark).opacity(dark ? 0.40 : 0.12), radius: 0.5, y: 0.5)
                    .overlay { if contrast != .increased { shape.fill(ImagePaint(image: ClothWeave.tile, scale: 1)) } }
                    .overlay { if pressed { shape.fill(.black.opacity(dark ? 0.12 : 0.16)) } }
                    .overlay {
                        if contrast != .increased {
                            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0), .black.opacity(0.20)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        }
                    }
            }
        }
    }
}

extension ButtonStyle where Self == OwlLunaButtonStyle {
    /// A board button: Ink on Board. In a bar it is a plate.
    static var owlLuna: OwlLunaButtonStyle { OwlLunaButtonStyle() }

    static func owlLuna(_ role: OwlLunaButtonStyle.Role, compact: Bool = false, inBar: Bool = false) -> OwlLunaButtonStyle {
        OwlLunaButtonStyle(role: role, compact: compact, inBar: inBar)
    }
}

/// An icon or a short word inside a bar: at least 44 points, ink, pressed into a small well.
struct BarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BarIcon(configuration: configuration)
    }

    private struct BarIcon: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityShowBorders) private var showBorders

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .imageScale(.large)
                .lineLimit(1)
                .foregroundStyle(configuration.role == .destructive ? Color.tomato : Color.ink)
                .opacity(isEnabled ? 1 : 0.35)
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .background {
                    if (configuration.isPressed && isEnabled) || showBorders {
                        RoundedRectangle.thumb.fill(Color.well)
                            .padding(.horizontal, 3)
                            .padding(.vertical, Bar.inset + 3)
                    }
                }
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, RoundedRectangle.plate.inset(by: Bar.inset))
                .hoverEffect(.highlight)
                .dynamicTypeSize(...barTextLimit)
                .accessibilityShowsLargeContentViewer { configuration.label.labelStyle(.titleAndIcon) }
        }
    }
}

extension ButtonStyle where Self == BarIconButtonStyle {
    static var barIcon: BarIconButtonStyle { BarIconButtonStyle() }
}

/// A run of icons on one plate with a rule between each, the way toolbar groups are drawn.
struct BarGroup<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            Group(subviews: content) { cells in
                ForEach(cells) { cell in
                    if cell.id != cells.first?.id {
                        Rectangle().fill(plateEdge(contrast)).frame(width: 1).padding(.vertical, Bar.inset)
                    }
                    cell
                }
            }
        }
        .buttonStyle(.barIcon)
        .background { Color.clear.plate(in: RoundedRectangle.plate).padding(.vertical, Bar.inset) }
        .fixedSize()
        .dynamicTypeSize(...barTextLimit)
    }
}

/// A single icon on a plate of its own: the way back, settings, the sidebar. Lifted, it stands on a board over a page.
struct PlateIconButtonStyle: ButtonStyle {
    var lifted = false

    func makeBody(configuration: Configuration) -> some View {
        PlateIcon(configuration: configuration, lifted: lifted)
    }

    private struct PlateIcon: View {
        let configuration: Configuration
        let lifted: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .imageScale(.large)
                .foregroundStyle(Color.ink)
                .opacity(isEnabled ? 1 : 0.35)
                .frame(width: Bar.height, height: Bar.height)
                .modifier(Ground(kind: lifted ? .board : .plate, shape: .plate, pressed: configuration.isPressed && isEnabled, flat: !isEnabled))
                .padding(Bar.inset)
                .contentShape([.interaction, .accessibility], Rectangle())
                .contentShape(.hoverEffect, RoundedRectangle.plate.inset(by: Bar.inset))
                .hoverEffect(.highlight)
                .dynamicTypeSize(...barTextLimit)
                .accessibilityShowsLargeContentViewer { configuration.label.labelStyle(.titleAndIcon) }
        }
    }
}

extension ButtonStyle where Self == PlateIconButtonStyle {
    static var plateIcon: PlateIconButtonStyle { PlateIconButtonStyle() }

    static func plateIcon(lifted: Bool) -> PlateIconButtonStyle { PlateIconButtonStyle(lifted: lifted) }
}

extension ToolbarContent {
    /// Takes away the system's glass so the item can wear its own plate.
    @ToolbarContentBuilder
    func boardBackground() -> some ToolbarContent {
        if #available(iOS 26, *) { sharedBackgroundVisibility(.hidden) } else { self }
    }
}

extension View {
    /// Keeps a bar the colour of its ground when content scrolls under it, in place of the system's material band.
    @ViewBuilder
    func barGround(_ ground: Color) -> some View {
        if #available(iOS 26, *) {
            toolbarBackground(ground, for: .navigationBar, .bottomBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar, .bottomBar)
                .scrollEdgeEffectHidden(true, for: .top)
                .scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            toolbarBackground(ground, for: .navigationBar, .bottomBar)
        }
    }
}

// MARK: Fields

/// A field ruled onto a bar: a glyph, the words, a way to clear them, and room for one more control. Escape clears it, then leaves it.
struct OwlLunaSearchField<Accessory: View>: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    var systemImage = "magnifyingglass"
    var isSearch = true
    var clears = true
    var handlesEscape = true
    /// Off for a field outside a bar, whose words grow with the text size.
    var capsTextSize = true
    var identifier: String?
    var value: Text?
    var focus: FocusState<Bool>.Binding
    @ViewBuilder var accessory: Accessory
    @AccessibilityFocusState private var voiceOverOnField: Bool

    var body: some View {
        HStack(spacing: Space.x2) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.textSecondary)
                .dynamicTypeSize(...barTextLimit)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(Color.textSecondary))
                .font(.callout)
                .foregroundStyle(Color.ink)
                .tint(Color.accentColor)
                .frame(maxWidth: .infinity, minHeight: 44)
                .focused(focus)
                .accessibilityFocused($voiceOverOnField)
                .accessibilityLabel(Text(prompt))
                .accessibilityAddTraits(isSearch ? .isSearchField : [])
                .modifier(FieldAccessibility(identifier: identifier, value: value))
            if clears, !text.isEmpty {
                Button {
                    text = ""
                    focus.wrappedValue = true
                    voiceOverOnField = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear Text"))
                .modifier(FieldAccessibility(identifier: identifier.map { "\($0).clear" }, value: nil))
            }
            accessory
        }
        .padding(.leading, Space.x3)
        .padding(.trailing, text.isEmpty ? Space.x3 : 0)
        .background { Color.clear.contentShape(Rectangle()).onTapGesture { focus.wrappedValue = true } }
        .background {
            if handlesEscape, focus.wrappedValue {
                Button("Cancel") { if text.isEmpty { focus.wrappedValue = false } else { text = "" } }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .background { Color.clear.plate(in: RoundedRectangle.plate, fill: .board, focused: focus.wrappedValue).padding(.vertical, Bar.inset) }
        .textInputAutocapitalization(isSearch ? .never : nil)
        .autocorrectionDisabled(isSearch)
        .submitLabel(isSearch ? .search : .go)
        .modifier(TextSizeCap(active: capsTextSize))
        .accessibilityElement(children: .contain)
    }
}

private struct FieldAccessibility: ViewModifier {
    let identifier: String?
    let value: Text?

    @ViewBuilder
    func body(content: Content) -> some View {
        switch (identifier, value) {
        case let (identifier?, value?): content.accessibilityIdentifier(identifier).accessibilityValue(value)
        case let (identifier?, nil): content.accessibilityIdentifier(identifier)
        case let (nil, value?): content.accessibilityValue(value)
        case (nil, nil): content
        }
    }
}

extension OwlLunaSearchField where Accessory == EmptyView {
    init(_ prompt: LocalizedStringKey, text: Binding<String>, systemImage: String = "magnifyingglass", handlesEscape: Bool = true,
         capsTextSize: Bool = true, identifier: String? = nil, value: Text? = nil, focus: FocusState<Bool>.Binding) {
        self.init(prompt: prompt, text: text, systemImage: systemImage, handlesEscape: handlesEscape, capsTextSize: capsTextSize,
                  identifier: identifier, value: value, focus: focus) { EmptyView() }
    }
}

extension View {
    /// A text field in a sheet: a rounded well, 44 points tall, outlined in the accent while it has focus. A tap anywhere on it calls `focus`.
    func owlLunaField(focused: Bool = false, focus: @escaping () -> Void = {}) -> some View {
        textFieldStyle(.plain)
            .foregroundStyle(Color.ink)
            .tint(Color.accentColor)
            .padding(.horizontal, Space.x3)
            .frame(minHeight: 44)
            .background { Color.clear.contentShape(Rectangle()).onTapGesture(perform: focus) }
            .well(in: RoundedRectangle.plate, focused: focused)
    }
}

// MARK: Segments

/// Segments on a well, the chosen one a board that slides under it. Each is a button VoiceOver reads as a selected tab.
struct OwlLunaSegmentedPicker<Value: Hashable, Label: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [Value]
    var inBar: Bool
    @ViewBuilder var label: (Value) -> Label
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ title: LocalizedStringKey, selection: Binding<Value>, options: [Value], inBar: Bool = false,
         @ViewBuilder label: @escaping (Value) -> Label) {
        self.title = title
        self._selection = selection
        self.options = options
        self.inBar = inBar
        self.label = label
    }

    var body: some View {
        let wraps = !inBar && dynamicTypeSize.isAccessibilitySize
        let layout = wraps ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(EqualWidthHStack())
        layout {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    label(option)
                        .font(.subheadline.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.ink : Color.textSecondary)
                        .lineLimit(wraps ? 3 : (inBar ? 1 : 2))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.x4)
                        .padding(.vertical, wraps ? Space.x3 : (inBar ? 0 : Space.x1))
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .contentShape(.hoverEffect, RoundedRectangle.thumb.inset(by: inBar ? Bar.inset + 3 : 4))
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .matchedGeometryEffect(id: option, in: thumb)
                .modifier(BarLimit(active: inBar))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background { thumbView.matchedGeometryEffect(id: selection, in: thumb, isSource: false) }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: selection)
        .background { Color.clear.well(in: RoundedRectangle.track).padding(.vertical, inBar ? Bar.inset : 0) }
        .fixedSize(horizontal: inBar, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .accessibilityLabel(Text(title))
    }

    private var thumbView: some View {
        let shape = RoundedRectangle.thumb
        return Color.clear
            .board(in: shape)
            .overlay { if scheme == .dark { shape.fill(Color.ink.opacity(0.10)) } }
            .overlay { if contrast == .increased { shape.strokeBorder(Color.inkSecondary, lineWidth: 1) } }
            .padding(.horizontal, inBar ? 3 : 4)
            .padding(.vertical, inBar ? Bar.inset + 3 : 4)
    }
}

/// Lays its children out in equal widths: the widest one's when it may choose, an even share of what it's offered otherwise.
private struct EqualWidthHStack: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let unit = unitWidth(proposal, subviews)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: unit, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: unit * CGFloat(subviews.count), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let unit = bounds.width / CGFloat(max(subviews.count, 1))
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + unit * CGFloat(index), y: bounds.minY),
                          proposal: ProposedViewSize(width: unit, height: bounds.height))
        }
    }

    private func unitWidth(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite { return width / CGFloat(subviews.count) }
        return subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }
}

// MARK: Switches

/// A switch cut square: a well for a track, cobalt cloth with an accent edge once it is on, and a knob that slides across.
struct OwlLunaToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Switch(configuration: configuration)
    }

    private struct Switch: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.labelsVisibility) private var labels

        var body: some View {
            HStack(spacing: Space.x3) {
                if labels != .hidden {
                    configuration.label
                        .foregroundStyle(isEnabled ? Color.ink : Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { configuration.isOn.toggle() } label: { EmptyView() }
                    .buttonStyle(Slab(isOn: configuration.isOn))
            }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
            }
        }
    }

    private struct Slab: ButtonStyle {
        let isOn: Bool

        func makeBody(configuration: Configuration) -> some View {
            SlabBody(isOn: isOn, pressed: configuration.isPressed)
        }
    }

    private struct SlabBody: View {
        let isOn: Bool
        let pressed: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

        private let track = RoundedRectangle.track
        private let knob = RoundedRectangle.thumb

        var body: some View {
            Color.clear
                .frame(width: 54, height: 30)
                .background(Color.well, in: track)
                .well(in: track)
                .overlay { cloth.opacity(isOn ? 1 : 0) }
                .overlay { if differentiate || UIAccessibility.isOnOffSwitchLabelsEnabled { marks } }
                .overlay(alignment: isOn ? .trailing : .leading) { knobView.padding(3) }
                .opacity(isEnabled ? 1 : 0.5)
                .frame(minWidth: 54, minHeight: 44)
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, track)
                .hoverEffect(.highlight)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.84), value: isOn)
                .animation(reduceMotion ? nil : Motion.quick, value: pressed)
        }

        private var cloth: some View {
            let increased = contrast == .increased
            return track.fill(Color.primaryCloth)
                .overlay { if !increased { track.fill(ImagePaint(image: ClothWeave.tile, scale: 1)) } }
                .overlay { track.strokeBorder(Color.accentColor, lineWidth: increased ? 2 : 1.5) }
        }

        private var knobView: some View {
            let dark = scheme == .dark, increased = contrast == .increased
            let fill = dark ? (isOn ? Color.onPrimaryCloth : Color.board.mix(with: .ink, by: 0.32)) : Color.board
            return knob.fill(fill)
                .overlay {
                    if !increased {
                        knob.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.14 : 0.85), .white.opacity(0)],
                                                         startPoint: .top, endPoint: .center), lineWidth: 1)
                    }
                }
                .overlay { knob.strokeBorder(increased ? Color.inkSecondary : Color.hairline, lineWidth: 1) }
                .shadow(color: Elevation.shade(dark).opacity(isEnabled ? (dark ? 0.45 : 0.18) : 0), radius: 1, y: 1)
                .frame(width: pressed && isEnabled ? 29 : 24, height: 24)
        }

        /// The system's On/Off Labels: a bar where the knob left, a ring where it will go.
        private var marks: some View {
            HStack {
                Capsule().fill(Color.onPrimaryCloth).frame(width: 2, height: 10).opacity(isOn ? 1 : 0)
                Spacer()
                Circle().strokeBorder(Color.textSecondary, lineWidth: 1.5).frame(width: 9, height: 9).opacity(isOn ? 0 : 1)
            }
            .padding(.leading, 13)
            .padding(.trailing, 9)
        }
    }
}

extension ToggleStyle where Self == OwlLunaToggleStyle {
    static var owlLuna: OwlLunaToggleStyle { OwlLunaToggleStyle() }
}

// MARK: Progress

/// Progress as a cobalt thread in a well. With no telling how long, a short thread runs the length of it.
struct ThreadProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View { Thread(configuration: configuration) }

    private struct Thread: View {
        let configuration: Configuration
        @Environment(\.controlSize) private var controlSize
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var runs = false

        private var isLabelled: Bool { configuration.label != nil || configuration.currentValueLabel != nil }

        /// On its own and with no end in sight it is a short well, where a spinner would have been.
        private var length: CGFloat? {
            guard configuration.fractionCompleted == nil else { return nil }
            if isLabelled { return 220 }
            switch controlSize {
            case .mini, .small: return 28
            case .large, .extraLarge: return 88
            default: return 44
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Space.x2) {
                if isLabelled {
                    HStack(alignment: .firstTextBaseline, spacing: Space.x3) {
                        configuration.label
                        Spacer(minLength: 0)
                        configuration.currentValueLabel?.monospacedDigit()
                    }
                    .font(.subheadline)
                }
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.well)
                        if let done = configuration.fractionCompleted {
                            RoundedRectangle(cornerRadius: 2).fill(Color.primaryCloth)
                                .frame(width: max(4, width * min(max(done, 0), 1)))
                                .animation(Motion.quick, value: done)
                        } else {
                            RoundedRectangle(cornerRadius: 2).fill(Color.primaryCloth)
                                .frame(width: width * 0.3)
                                .offset(x: reduceMotion ? width * 0.35 : (runs ? width * 0.7 : 0))
                                .opacity(reduceMotion && !runs ? 0.35 : 1)
                        }
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: length)
            .onAppear {
                guard configuration.fractionCompleted == nil else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { runs = true }
            }
        }
    }
}

extension ProgressViewStyle where Self == ThreadProgressStyle {
    static var thread: ThreadProgressStyle { ThreadProgressStyle() }
}

// MARK: Nothing here

/// What a list or a sheet shows when it has nothing: a plate with its symbol in a small square, a title and a line under it.
struct EmptyPlate<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: Text
    @ViewBuilder var actions: Actions

    init(_ title: LocalizedStringKey, systemImage: String, message: Text, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: Space.x2) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .plate(in: RoundedRectangle.plate)
                .accessibilityHidden(true)
            Text(title)
                .displayFont(22, relativeTo: .title2)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Space.x1)
            message
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            actions.padding(.top, Space.x2)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(Space.x5)
        .plate(in: RoundedRectangle.plate, fill: .board)
        .frame(minWidth: 240, maxWidth: 380)
        .padding(Space.x5)
        .frame(maxWidth: .infinity)
    }
}

