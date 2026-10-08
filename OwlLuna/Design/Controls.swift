import SwiftUI

/// Controls are bound like the notebooks: boards stand on the desk, wells are pressed into it, and the finishing action is cloth.
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

extension View {
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

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            let cloth = role != .secondary
            let wraps = !inBar && dynamicTypeSize.isAccessibilitySize
            configuration.label
                .font(.system(compact ? .subheadline : .body, weight: cloth ? .semibold : .medium))
                .lineLimit(wraps ? 3 : 1)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: inBar, vertical: true)
                .foregroundStyle(foreground)
                .padding(.horizontal, compact ? Space.x3 : Space.x4)
                .padding(.vertical, wraps ? Space.x2 : 0)
                .frame(minWidth: 44, minHeight: compact ? 34 : 44)
                .fixedSize(horizontal: inBar, vertical: false)
                .background { if cloth { filled(pressed: pressed) } }
                .modifier(SecondaryBoard(active: !cloth, shape: shape, pressed: pressed, flat: !isEnabled))
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .contentShape([.hoverEffect, .accessibility], shape)
                .hoverEffect(.highlight)
                .padding(.vertical, compact ? 5 : 0)
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

    private struct SecondaryBoard: ViewModifier {
        let active: Bool
        let shape: RoundedRectangle
        let pressed: Bool
        let flat: Bool

        func body(content: Content) -> some View {
            if active { content.board(in: shape, pressed: pressed, flat: flat) } else { content }
        }
    }
}

extension ButtonStyle where Self == OwlLunaButtonStyle {
    /// A board button: Ink on Board.
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
                    if (configuration.isPressed && isEnabled) || showBorders { Capsule().fill(Color.well).padding(3) }
                }
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, Capsule().inset(by: 2))
                .hoverEffect(.highlight)
                .dynamicTypeSize(...barTextLimit)
                .accessibilityShowsLargeContentViewer { configuration.label.labelStyle(.titleAndIcon) }
        }
    }
}

extension ButtonStyle where Self == BarIconButtonStyle {
    static var barIcon: BarIconButtonStyle { BarIconButtonStyle() }
}

/// A row of controls on one board, the way toolbar groups and floating bars are drawn.
struct BarGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .buttonStyle(.barIcon)
            .menuStyle(.button)
            .padding(.horizontal, Space.x1)
            .board(in: Capsule())
            .fixedSize()
            .dynamicTypeSize(...barTextLimit)
    }
}

/// A single icon on its own round board: the way back, settings, the sidebar.
struct BoardIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BoardIcon(configuration: configuration)
    }

    private struct BoardIcon: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .imageScale(.large)
                .foregroundStyle(Color.ink)
                .opacity(isEnabled ? 1 : 0.35)
                .frame(width: 44, height: 44)
                .board(in: Circle(), pressed: configuration.isPressed && isEnabled, flat: !isEnabled)
                .contentShape([.interaction, .accessibility], Circle())
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.highlight)
                .dynamicTypeSize(...barTextLimit)
                .accessibilityShowsLargeContentViewer { configuration.label.labelStyle(.titleAndIcon) }
        }
    }
}

extension ButtonStyle where Self == BoardIconButtonStyle {
    static var boardIcon: BoardIconButtonStyle { BoardIconButtonStyle() }
}

extension ToolbarContent {
    /// Takes away the system's glass so the item can wear its own board.
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

/// A field pressed into the desk: a glyph, the words, a way to clear them, and room for one more control. Escape clears it, then leaves it.
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
        .padding(.leading, Space.x4)
        .padding(.trailing, text.isEmpty ? Space.x4 : 0)
        .background { Capsule().fill(.clear).contentShape(Capsule()).onTapGesture { focus.wrappedValue = true } }
        .background {
            if handlesEscape, focus.wrappedValue {
                Button("Cancel") { if text.isEmpty { focus.wrappedValue = false } else { text = "" } }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .well(in: Capsule(), focused: focus.wrappedValue)
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
            .well(in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous), focused: focused)
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
                        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 18, style: .continuous).inset(by: 4))
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
        .well(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .fixedSize(horizontal: inBar, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .accessibilityLabel(Text(title))
    }

    private var thumbView: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Color.clear
            .board(in: shape)
            .overlay { if scheme == .dark { shape.fill(Color.ink.opacity(0.10)) } }
            .overlay { if contrast == .increased { shape.strokeBorder(Color.inkSecondary, lineWidth: 1) } }
            .padding(4)
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

        private var track: RoundedRectangle { RoundedRectangle(cornerRadius: 9, style: .continuous) }
        private var knob: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

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
