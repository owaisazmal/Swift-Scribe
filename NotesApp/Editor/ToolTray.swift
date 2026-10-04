import SwiftUI

/// The favourite tools, on a board in the editor's bar: a saved pen, pencil or highlighter is one tap away.
/// The page keeps the whole window; where the bar is short of room the tools scroll within their board.
struct ToolTray: View {
    let session: EditorSession
    let width: CGFloat
    @State private var shelf = ToolShelf.shared
    @State private var hidden: Edge.Set = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let slot: CGFloat = 38
    private static let inset = Space.x1
    private static let fade: CGFloat = 20

    /// What `count` tools take of a bar with `room` to spare: all they need, or the room, in which they scroll.
    /// Nil when two wouldn't fit.
    static func width(for count: Int, in room: CGFloat) -> CGFloat? {
        let need = need(count)
        if need <= room { return need }
        return room >= slot * 2 + inset * 2 ? room : nil
    }

    /// Each tool has a slot, and so has the empty label while there is room on the shelf.
    private static func need(_ count: Int) -> CGFloat {
        CGFloat(count + (count < ToolShelf.limit ? 1 : 0)) * slot + inset * 2
    }

    var body: some View {
        let tools = shelf.usable, current = session.currentTool
        let inUse = current.flatMap { tool in tools.first { $0.isSameTool(as: tool) }?.id }
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { index, preset in
                        button(preset, at: index, of: tools.count, current: current, inUse: preset.id == inUse)
                            .id(preset.id)
                    }
                    if !shelf.isFull {
                        Button { save(current) } label: { Label("Save Current Tool", systemImage: "plus") }
                            .buttonStyle(ToolSaveButtonStyle())
                            .disabled(current.map(shelf.holds) ?? true)
                            .accessibilityHint(Text("Keeps the tool you are using among your favourite tools"))
                            .accessibilityIdentifier("editor.tools.save")
                    }
                }
                .padding(.horizontal, Self.inset)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Edge.Set.self) { geometry in
                let x = geometry.contentOffset.x, end = geometry.contentSize.width - geometry.containerSize.width
                return (x > 1 ? Edge.Set.leading : []).union(x < end - 1 ? .trailing : [])
            } action: { _, edges in hidden = edges }
            .onChange(of: inUse) { _, id in
                guard let id else { return }
                withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { proxy.scrollTo(id) }
            }
        }
        .frame(width: width, height: 44)
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(hidden.contains(.leading) ? 0 : 1), .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.fade)
                Color.black
                LinearGradient(colors: [.black, .black.opacity(hidden.contains(.trailing) ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.fade)
            }
        }
        .clipShape(Capsule())
        .board(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Favourite Tools"))
    }

    private func button(_ preset: ToolPreset, at index: Int, of count: Int, current: ToolPreset?, inUse: Bool) -> some View {
        Button { use(preset) } label: { ToolSwatch(preset: preset, inUse: inUse) }
            .buttonStyle(ToolSwatchButtonStyle())
            .contextMenu {
                if let current, !shelf.holds(current) {
                    if !shelf.isFull {
                        Button { save(current) } label: { Label("Save Current Tool", systemImage: "plus") }
                    }
                    Button { shelf.replace(preset.id, with: current) } label: { Label("Replace with Current Tool", systemImage: "arrow.triangle.2.circlepath") }
                }
                if index > 0 { Button { shelf.move(preset.id, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") } }
                if index < count - 1 { Button { shelf.move(preset.id, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") } }
                Button(role: .destructive) { remove(preset) } label: { Label("Remove", systemImage: "trash") }
            }
            .accessibilityLabel(Text(preset.name))
            .accessibilityValue(Text("Width \(preset.width.formatted(.number.precision(.fractionLength(0...1))))"))
            .accessibilityAddTraits(inUse ? .isSelected : [])
            .accessibilityActions {
                if index > 0 { Button("Move Left") { shelf.move(preset.id, by: -1) } }
                if index < count - 1 { Button("Move Right") { shelf.move(preset.id, by: 1) } }
                Button("Remove") { remove(preset) }
            }
            .accessibilityShowsLargeContentViewer { Label(preset.name, systemImage: preset.symbol) }
            .accessibilityIdentifier("editor.tools.\(index + 1)")
    }

    private func use(_ preset: ToolPreset) {
        session.canvas?.useTool(preset)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func save(_ tool: ToolPreset?) {
        guard let tool, shelf.add(tool) else { return }
        AccessibilityNotification.Announcement(String(localized: "\(tool.name) saved to your favourite tools")).post()
    }

    private func remove(_ preset: ToolPreset) {
        shelf.remove(preset.id)
        AccessibilityNotification.Announcement(String(localized: "\(preset.name) removed from your favourite tools")).post()
    }
}

/// One saved tool: its ink as a blot on a paper label, as large as the tool is wide, under the mark of its kind.
/// Like a cover's label, the paper stays cream at night, so the ink is seen as it is on a page.
struct ToolSwatch: View {
    let preset: ToolPreset
    var inUse = false
    @Environment(\.colorSchemeContrast) private var contrast

    static let side: CGFloat = 32
    static let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

    var body: some View {
        let shape = Self.shape
        let blot = 9 + 11 * preset.widthFraction
        ZStack {
            shape.fill(Color.labelCream)
            Circle()
                .fill(Color(uiColor: preset.uiColor))
                .overlay { Circle().strokeBorder(Color.labelInk.opacity(contrast == .increased ? 0.6 : 0.22), lineWidth: 1) }
                .frame(width: blot, height: blot)
                .offset(x: 3, y: 3)
            Image(systemName: preset.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.labelInkSecondary)
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
            .frame(width: ToolTray.slot, height: 44)
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 11, style: .continuous).inset(by: 1))
            .hoverEffect(.highlight)
    }
}

private struct ToolSaveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SaveIcon(configuration: configuration)
    }

    private struct SaveIcon: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityShowBorders) private var showBorders

        /// An empty label waiting for a tool, so it isn't taken for the bar's other plus.
        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: ToolSwatch.side, height: ToolSwatch.side)
                .background { if (configuration.isPressed && isEnabled) || showBorders { ToolSwatch.shape.fill(Color.well) } }
                .overlay {
                    ToolSwatch.shape.strokeBorder(Color.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .opacity(isEnabled ? 1 : 0.4)
                .frame(width: ToolTray.slot, height: 44)
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 11, style: .continuous).inset(by: 1))
                .hoverEffect(.highlight)
                .accessibilityShowsLargeContentViewer { configuration.label.labelStyle(.titleAndIcon) }
        }
    }
}
