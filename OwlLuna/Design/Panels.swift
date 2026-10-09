import SwiftUI

/// Closes the panel a control stands in, then does what was asked for once it has gone.
struct PanelClose {
    fileprivate let close: (_ then: (() -> Void)?) -> Void

    func callAsFunction(then action: (() -> Void)? = nil) { close(action) }
}

extension EnvironmentValues {
    /// Set inside a panel, so what it holds can close it.
    @Entry var panelClose: PanelClose?
    /// The least height a card's control is taken to have. A title in a bar is short; with this its card hangs as low as the bar's others.
    @Entry var panelAnchorHeight: CGFloat = 0
    @Entry fileprivate var inPanelMenu = false
    @Entry fileprivate var menuRowChosen = false
}

private struct MenuBreakKey: ContainerValueKey {
    static let defaultValue = false
}

extension ContainerValues {
    fileprivate var isMenuBreak: Bool {
        get { self[MenuBreakKey.self] }
        set { self[MenuBreakKey.self] = newValue }
    }
}

// MARK: Opening

/// Where a control stands in its window.
@MainActor
private final class PanelSpot {
    weak var view: UIView?

    var frame: CGRect { view.map { $0.convert($0.bounds, to: nil) } ?? .zero }
}

private struct PanelProbe: UIViewRepresentable {
    let spot: PanelSpot

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        spot.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { spot.view = view }
}

/// Covers the window with a clear layer and stands the panel on it, with no animation of the system's.
private struct PanelPresenter<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    var beside = false
    /// A menu opened from a row of another closes that one with it.
    var chained = false
    /// A notice stands in the middle of the screen. Its button's work is done before its binding is put back, as an alert's is.
    var notice = false
    @ViewBuilder var panel: () -> Panel
    @State private var spot = PanelSpot()
    @State private var covering = false
    @State private var anchor = CGRect.zero
    @State private var pending: (() -> Void)?
    @Environment(\.panelClose) private var outer
    @Environment(\.panelAnchorHeight) private var least

    func body(content: Content) -> some View {
        content.background {
            PanelProbe(spot: spot)
                .fullScreenCover(isPresented: Binding(get: { covering }, set: { if !$0 { covering = false; if !notice { isPresented = false } } }),
                                 onDismiss: finish) {
                    stage
                        .environment(\.panelClose, PanelClose(close: close))
                        .presentationBackground(.clear)
                }
                .transaction { $0.disablesAnimations = true }
                .onChange(of: isPresented, initial: true) { _, shown in
                    if shown, spot.view?.window == nil { Task { cover(isPresented) } } else { cover(shown) }
                }
        }
    }

    private func cover(_ shown: Bool) {
        guard shown != covering else { return }
        if shown { anchor = spot.frame.insetBy(dx: 0, dy: min(0, (spot.frame.height - least) / 2)) }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { covering = shown }
    }

    @ViewBuilder
    private var stage: some View {
        if notice { NoticeStage(panel: panel) } else { PanelStage(anchor: anchor, beside: beside, close: close, panel: panel) }
    }

    private func close(then action: (() -> Void)?) {
        pending = action
        if notice { cover(false) } else { isPresented = false }
    }

    private func finish() {
        let action = pending
        pending = nil
        if chained, let outer { outer(then: action) } else { action?() }
        if notice { isPresented = false }
    }
}

private struct PanelStage<Panel: View>: View {
    let anchor: CGRect
    let beside: Bool
    let close: (_ then: (() -> Void)?) -> Void
    @ViewBuilder var panel: () -> Panel
    @State private var shown = false
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        GeometryReader { proxy in
            PanelPlacement(anchor: place(in: proxy), beside: beside) {
                panel().opacity(shown ? 1 : 0)
            }
        }
        .background {
            Button { close(nil) } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in close(nil) })
                .accessibilityLabel(Text("Close"))
                .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { close(nil) }
        .onAppear { withAnimation(Motion.quick) { shown = true } }
    }

    /// The control's place on the stage. Right to left the stage is laid out mirrored, so its place is mirrored too.
    private func place(in proxy: GeometryProxy) -> CGRect {
        let stage = proxy.frame(in: .global)
        var place = anchor.offsetBy(dx: -stage.minX, dy: -stage.minY)
        if direction == .rightToLeft { place.origin.x = stage.width - place.maxX }
        return place
    }
}

/// Puts a panel under the control it opened from, or over it, and keeps all of it on the screen.
private struct PanelPlacement: Layout {
    let anchor: CGRect
    let beside: Bool

    private static let margin: CGFloat = 8
    private static let gap: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let panel = subviews.first else { return }
        let margin = Self.margin, gap = Self.gap
        let width = min(panel.sizeThatFits(.unspecified).width, bounds.width - margin * 2)
        var height = min(panel.sizeThatFits(ProposedViewSize(width: width, height: nil)).height, bounds.height - margin * 2)
        var x = anchor.minX, y = anchor.maxY + gap
        if beside {
            x = anchor.maxX - Space.x2
            if x + width > bounds.width - margin { x = anchor.minX + Space.x2 - width }
            y = anchor.minY
        } else {
            if x + width > bounds.width - margin { x = anchor.maxX - width }
            let below = bounds.height - margin - y, above = anchor.minY - gap - margin
            if height > below {
                if height <= above || above > below, above >= 200 {
                    height = min(height, above)
                    y = anchor.minY - gap - height
                } else if below >= 200 {
                    height = below
                }
            }
        }
        x = min(max(x, margin), bounds.width - margin - width)
        y = min(max(y, margin), bounds.height - margin - height)
        panel.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(width: width, height: height))
    }
}

// MARK: The card

/// What menus and popovers are cut from: a board ruled in ink, under a cloth band that names it.
private struct PanelChrome<Title: View, Content: View>: View {
    var fill = Color.surface
    /// A large panel has a way out on its band as well as round it.
    var done: (() -> Void)?
    @ViewBuilder var title: Title
    @ViewBuilder var content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.x3) {
                title
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                if let done {
                    Button("Done", action: done)
                        .buttonStyle(.plain)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .padding(.vertical, -Space.x3)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("panel.done")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.onPrimaryCloth)
            .padding(.horizontal, Space.x3)
            .padding(.vertical, 7)
            .background {
                Rectangle().fill(Color.primaryCloth)
                    .overlay { if contrast != .increased { Rectangle().fill(ImagePaint(image: ClothWeave.tile, scale: 1)) } }
            }
            content
        }
        .clipShape(RoundedRectangle.plate)
        .plate(in: RoundedRectangle.plate, fill: fill)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Opens a card under this view while `isPresented` is true. One that `adapts` has Done on its band, and is a sheet
    /// where there is no room beside things.
    func panel<Content: View>(_ title: LocalizedStringKey, isPresented: Binding<Bool>, adapts: Bool = false,
                              @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(AdaptingPanel(title: Text(title), isPresented: isPresented, adapts: adapts, content: content))
    }

    func panel<Item: Identifiable, Content: View>(_ title: LocalizedStringKey, item: Binding<Item?>, adapts: Bool = false,
                                                  @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        panel(title, isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }), adapts: adapts) {
            if let value = item.wrappedValue { content(value) }
        }
    }
}

private struct AdaptingPanel<Panel: View>: ViewModifier {
    let title: Text
    @Binding var isPresented: Bool
    let adapts: Bool
    @ViewBuilder var content: () -> Panel
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content anchor: Content) -> some View {
        if adapts, sizeClass == .compact {
            anchor.sheet(isPresented: $isPresented) {
                content().presentationBackground(Color.surface).presentationCornerRadius(Radius.sheet)
            }
        } else {
            anchor.modifier(PanelPresenter(isPresented: $isPresented) {
                PanelChrome(done: adapts ? { isPresented = false } : nil) { title } content: { content() }
            })
        }
    }
}

// MARK: Menus

/// A button that opens a card of rows under it. In another menu it is a row that opens the next card beside it.
struct OwlLunaMenu<Label: View, Content: View>: View {
    private let title: Text?
    private let primaryAction: (() -> Void)?
    private let content: Content
    private let label: Label
    @State private var isOpen = false
    @State private var held = false
    @Environment(\.inPanelMenu) private var nested

    /// The band is named after the label unless it is given a `title`. With a `primaryAction` a tap does that, and holding opens the menu.
    init(_ title: Text? = nil, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label, primaryAction: (() -> Void)? = nil) {
        self.title = title
        self.primaryAction = primaryAction
        self.content = content()
        self.label = label()
    }

    var body: some View {
        trigger.modifier(PanelPresenter(isPresented: $isOpen, beside: nested, chained: nested) {
            PanelChrome(fill: .board) {
                if let title { title } else { label.labelStyle(.titleOnly) }
            } content: {
                MenuRows { content }
            }
        })
    }

    @ViewBuilder
    private var trigger: some View {
        if nested {
            Button { isOpen = true } label: { label }
                .buttonStyle(MenuRowBody(opens: true))
        } else if let primaryAction {
            Button { if held { held = false } else { primaryAction() } } label: { label }
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    held = true
                    isOpen = true
                })
                .onChange(of: isOpen) { _, open in if !open { held = false } }
                .accessibilityAction(named: Text("Show Menu")) { isOpen = true }
        } else {
            Button { isOpen = true } label: { label }
        }
    }
}

extension View {
    /// Opens a card of rows when this view is touched and held. One that can be dragged opens it when it is let go.
    func heldMenu<Rows: View>(_ title: Text, when enabled: Bool = true, draggable: Bool = false,
                              @ViewBuilder rows: @escaping () -> Rows) -> some View {
        modifier(HeldMenu(title: title, enabled: enabled, draggable: draggable, rows: rows))
    }
}

private struct HeldMenu<Rows: View>: ViewModifier {
    let title: Text
    let enabled: Bool
    let draggable: Bool
    @ViewBuilder var rows: () -> Rows
    @State private var isOpen = false

    func body(content: Content) -> some View {
        content
            .background { if enabled { HoldProbe(draggable: draggable) { isOpen = true } } }
            .accessibilityActions { if enabled { Button("Show Menu") { isOpen = true } } }
            .modifier(PanelPresenter(isPresented: $isOpen) {
                PanelChrome(fill: .board) { title } content: { MenuRows { rows() } }
            })
    }
}

/// Watches its window for a touch held over it. What can be dragged opens its menu when it is let go, so a drag can begin instead.
private struct HoldProbe: UIViewRepresentable {
    let draggable: Bool
    let held: () -> Void

    func makeUIView(context: Context) -> HoldView { HoldView() }

    func updateUIView(_ view: HoldView, context: Context) {
        view.draggable = draggable
        view.held = held
    }

    final class HoldView: UIView, UIGestureRecognizerDelegate {
        var draggable = false { didSet { press.cancelsTouchesInView = !draggable } }
        var held: (() -> Void)?
        private lazy var press: UILongPressGestureRecognizer = {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed))
            press.minimumPressDuration = 0.45
            press.delegate = self
            return press
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            press.view?.removeGestureRecognizer(press)
            window?.addGestureRecognizer(press)
        }

        @objc private func pressed() {
            if press.state == (draggable ? .ended : .began) { held?() }
        }

        /// A touch over this view counts only if it lands in the screen this view is on, not in one that covers it.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard bounds.contains(touch.location(in: self)) else { return false }
            var responder = next
            while let current = responder, !(current is UIViewController) { responder = current.next }
            guard let screen = (responder as? UIViewController)?.viewIfLoaded else { return true }
            return touch.view?.isDescendant(of: screen) ?? false
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// One of a few values in a menu: a row for each, the chosen one checked.
struct OwlLunaPicker<Value: Hashable, Options: View>: View {
    private let title: Text?
    @Binding private var selection: Value
    private let options: Options

    init(_ title: LocalizedStringKey? = nil, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.title = title.map { Text($0) }
        self._selection = selection
        self.options = options()
    }

    var body: some View {
        Group(sections: options) { sections in
            ForEach(sections) { section in
                Section {
                    ForEach(section.content) { option in
                        let value = option.containerValues.tag(for: Value.self)
                        Button { if let value { selection = value } } label: { option }
                            .menuChosen(value == selection)
                    }
                } header: {
                    if !section.header.isEmpty { section.header } else if let title { title }
                }
            }
        }
    }
}

/// A wider rule between two runs of rows in a menu.
struct MenuBreak: View {
    var body: some View {
        Color.clear.frame(height: 0).containerValue(\.isMenuBreak, true)
    }
}

extension View {
    /// Marks a menu's row as the one in force: checked, with an accent edge.
    func menuChosen(_ chosen: Bool) -> some View { environment(\.menuRowChosen, chosen) }
}

/// A menu's rows ruled apart, with a band over each run that has a name.
private struct MenuRows<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group(sections: content) { sections in
                    ForEach(sections) { section in
                        let first = section.id == sections.first?.id
                        if !section.header.isEmpty {
                            section.header
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, Space.x3)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.well)
                                .overlay(alignment: .top) { if !first { MenuRule() } }
                                .overlay(alignment: .bottom) { MenuRule() }
                                .accessibilityAddTraits(.isHeader)
                        } else if !first {
                            MenuStrip()
                        }
                        let rows = Array(section.content)
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            let breaks = row.containerValues.isMenuBreak
                            let afterBreak = index > 0 && rows[index - 1].containerValues.isMenuBreak
                            if breaks {
                                if index > 0, index < rows.count - 1, !afterBreak { MenuStrip() }
                            } else {
                                row.overlay(alignment: .top) { if index > 0, !afterBreak { MenuRule() } }
                            }
                        }
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 220, maxWidth: 380)
        .buttonStyle(MenuRowButtonStyle())
        .toggleStyle(MenuRowToggleStyle())
        .labelStyle(MenuRowLabelStyle())
        .environment(\.inPanelMenu, true)
        .environment(\.isEnabled, true)
        .fontWeight(nil)
        .dynamicTypeSize(DynamicTypeSize(UIApplication.shared.preferredContentSizeCategory) ?? .large)
    }
}

private struct MenuRule: View {
    var body: some View {
        Rectangle().fill(Color.hairline).frame(height: 1).allowsHitTesting(false)
    }
}

private struct MenuStrip: View {
    var body: some View {
        Color.well.frame(height: 6)
            .overlay(alignment: .top) { MenuRule() }
            .overlay(alignment: .bottom) { MenuRule() }
            .accessibilityHidden(true)
    }
}

/// A button in a menu closes the menu, and does its work once the menu has gone.
private struct MenuRowButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @Environment(\.panelClose) private var close

        var body: some View {
            Button {
                if let close { close(then: configuration.trigger) } else { configuration.trigger() }
            } label: {
                configuration.label
            }
            .buttonStyle(MenuRowBody(role: configuration.role))
        }
    }
}

private struct MenuRowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { configuration.label }
            .menuChosen(configuration.isOn)
    }
}

private struct MenuRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.x3) {
            configuration.icon.frame(width: 24)
            configuration.title
        }
    }
}

private struct MenuRowBody: ButtonStyle {
    var role: ButtonRole?
    var opens = false

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, role: role, opens: opens)
    }

    private struct Row: View {
        let configuration: Configuration
        let role: ButtonRole?
        let opens: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.menuRowChosen) private var chosen

        var body: some View {
            HStack(spacing: Space.x3) {
                configuration.label
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if chosen {
                    Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                }
                if opens {
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary).accessibilityHidden(true)
                }
            }
            .font(.callout.weight(chosen ? .semibold : .regular))
            .foregroundStyle(role == .destructive ? Color.tomato : Color.ink)
            .opacity(isEnabled ? 1 : 0.4)
            .padding(.horizontal, Space.x3)
            .padding(.vertical, Space.x2)
            .frame(minHeight: 44)
            .background { if configuration.isPressed { Color.well } }
            .overlay(alignment: .leading) { if chosen { Rectangle().fill(Color.accentColor).frame(width: 3) } }
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
    }
}

// MARK: Notices

extension View {
    /// Stands a notice in the middle of the screen while `isPresented` is true: the app's own alert. A button with the
    /// cancel role is its way out, and one that destroys turns its edge tomato.
    func notice<Actions: View>(_ title: Text, isPresented: Binding<Bool>, message: Text? = nil,
                               @ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(PanelPresenter(isPresented: isPresented, notice: true) {
            NoticeCard(title: title, message: message) { EmptyView() } actions: { actions() }
        })
    }

    func notice<Actions: View>(_ title: LocalizedStringKey, isPresented: Binding<Bool>, message: Text? = nil,
                               @ViewBuilder actions: @escaping () -> Actions) -> some View {
        notice(Text(title), isPresented: isPresented, message: message, actions: actions)
    }

    /// A notice that asks for something to be typed: its first field is ready to type in as it opens.
    func notice<Fields: View, Actions: View>(_ title: LocalizedStringKey, isPresented: Binding<Bool>, message: Text? = nil,
                                             @ViewBuilder fields: @escaping () -> Fields,
                                             @ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(PanelPresenter(isPresented: isPresented, notice: true) {
            NoticeCard(title: Text(title), message: message) { fields() } actions: { actions() }
        })
    }
}

/// Dims what is behind a notice and holds the notice in the middle of what the keyboard leaves.
private struct NoticeStage<Panel: View>: View {
    @ViewBuilder var panel: () -> Panel
    @State private var shown = false

    var body: some View {
        panel()
            .padding(Space.x4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(shown ? 1 : 0)
            .background { Color.black.opacity(shown ? 0.35 : 0).ignoresSafeArea() }
            .accessibilityElement(children: .contain)
            .onAppear { withAnimation(Motion.quick) { shown = true } }
    }
}

/// What a notice's buttons do, for the keys and gestures that stand for them: Return in a field, and the way out.
@MainActor
private final class NoticeKeys {
    var main: (() -> Void)?
    var cancel: (() -> Void)?
}

private struct NoticeDestroys: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension EnvironmentValues {
    @Entry fileprivate var noticeKeys: NoticeKeys?
}

/// A board with a cloth edge that says what kind of notice it is, over its words, its fields and its buttons.
private struct NoticeCard<Fields: View, Actions: View>: View {
    let title: Text
    let message: Text?
    @ViewBuilder var fields: Fields
    @ViewBuilder var actions: Actions
    @State private var destroys = false
    @State private var keys = NoticeKeys()
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(destroys ? Color.destructiveCloth : Color.primaryCloth)
                .overlay { if contrast != .increased { Rectangle().fill(ImagePaint(image: ClothWeave.tile, scale: 1)) } }
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 0) {
                title
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    message
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, Space.x1)
                }
                Group(subviews: fields) { fields in
                    if !fields.isEmpty {
                        VStack(spacing: Space.x2) {
                            ForEach(fields) { field in
                                field
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, Space.x3)
                                    .frame(minHeight: 44)
                                    .well(in: RoundedRectangle.plate)
                            }
                        }
                        .padding(.top, Space.x3)
                        .submitLabel(.done)
                        .onSubmit { keys.main?() }
                        .background { FirstFieldFocus() }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.x2) { actions }
                    VStack(alignment: .trailing, spacing: 0) { actions }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, Space.x3)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.x4)
            .padding(.top, Space.x4)
            .padding(.bottom, Space.x3)
        }
        .frame(minWidth: 280, maxWidth: 400)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle.plate)
        .plate(in: RoundedRectangle.plate, fill: .board)
        .buttonStyle(NoticeButtonStyle())
        .environment(\.noticeKeys, keys)
        .environment(\.isEnabled, true)
        .onPreferenceChange(NoticeDestroys.self) { destroys = $0 }
        .accessibilityAction(.escape) { keys.cancel?() }
    }
}

/// Puts the caret in a notice's first field as it opens, as an alert does.
private struct FirstFieldFocus: UIViewRepresentable {
    func makeUIView(context: Context) -> Seeker { Seeker() }

    func updateUIView(_ view: Seeker, context: Context) {}

    final class Seeker: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.focus() }
        }

        private func focus() {
            var responder = next
            while let current = responder, !(current is UIViewController) { responder = current.next }
            guard let screen = (responder as? UIViewController)?.viewIfLoaded else { return }
            Self.field(in: screen)?.becomeFirstResponder()
        }

        private static func field(in view: UIView) -> UITextField? {
            if let field = view as? UITextField { return field }
            for child in view.subviews { if let field = field(in: child) { return field } }
            return nil
        }
    }
}

/// A notice's button does its work once the notice has gone. Cancel is a plate; what destroys is tomato cloth, and the way on cobalt.
private struct NoticeButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View { NoticeButton(configuration: configuration) }

    private struct NoticeButton: View {
        let configuration: Configuration
        @Environment(\.panelClose) private var close
        @Environment(\.noticeKeys) private var keys

        var body: some View {
            let role = configuration.role
            let press = { if let close { close(then: configuration.trigger) } else { configuration.trigger() } }
            let _ = note(press, for: role)
            Group {
                if role == .cancel {
                    Button(action: press) { configuration.label }.buttonStyle(NoticePlateStyle())
                } else {
                    Button(action: press) { configuration.label }
                        .buttonStyle(.owlLuna(role == .destructive ? .destructive : .primary, compact: true))
                }
            }
            .keyboardShortcut(role == .cancel ? .cancelAction : role == nil ? .defaultAction : nil)
            .preference(key: NoticeDestroys.self, value: role == .destructive)
        }

        private func note(_ press: @escaping () -> Void, for role: ButtonRole?) {
            if role == .cancel { keys?.cancel = press } else if role == nil { keys?.main = press }
        }
    }
}

/// The quiet button of a notice: a plate, as flat as the notice itself.
private struct NoticePlateStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.ink)
            .lineLimit(1)
            .padding(.horizontal, Space.x3)
            .frame(minWidth: 44, minHeight: 34)
            .plate(in: RoundedRectangle.plate, pressed: configuration.isPressed)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
    }
}
