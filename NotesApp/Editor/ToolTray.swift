import SwiftUI

/// The favourite tools, on a board beside the page: a saved pen, pencil or highlighter is one tap away.
struct ToolTray: View {
    let session: EditorSession
    @State private var shelf = ToolShelf.shared

    static let width: CGFloat = 60

    var body: some View {
        let tools = shelf.usable, current = session.currentTool
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(tools.enumerated()), id: \.element.id) { index, preset in
                    button(preset, at: index, of: tools.count, current: current)
                }
                if !shelf.isFull {
                    Button { save(current) } label: { Label("Save Current Tool", systemImage: "plus") }
                        .buttonStyle(.barIcon)
                        .disabled(current.map(shelf.holds) ?? true)
                        .accessibilityHint(Text("Keeps the tool you are using among your favourite tools"))
                        .accessibilityIdentifier("editor.tools.save")
                }
            }
            .padding(.vertical, Space.x1)
            .board(in: Capsule())
            .padding(.horizontal, Space.x2)
            .padding(.top, Space.x2)
            .padding(.bottom, Space.x4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .frame(width: Self.width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Favourite Tools"))
    }

    private func button(_ preset: ToolPreset, at index: Int, of count: Int, current: ToolPreset?) -> some View {
        let inUse = current.map(preset.isSameTool) ?? false
        return Button { use(preset) } label: { ToolSwatch(preset: preset, inUse: inUse) }
            .buttonStyle(ToolSwatchButtonStyle())
            .contextMenu {
                if let current, !shelf.holds(current) {
                    Button { shelf.replace(preset.id, with: current) } label: { Label("Replace with Current Tool", systemImage: "arrow.triangle.2.circlepath") }
                }
                if index > 0 { Button { shelf.move(preset.id, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") } }
                if index < count - 1 { Button { shelf.move(preset.id, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") } }
                Button(role: .destructive) { remove(preset) } label: { Label("Remove", systemImage: "trash") }
            }
            .accessibilityLabel(Text(preset.name))
            .accessibilityValue(Text("Width \(preset.width.formatted(.number.precision(.fractionLength(0...1))))"))
            .accessibilityAddTraits(inUse ? .isSelected : [])
            .accessibilityActions {
                if index > 0 { Button("Move Up") { shelf.move(preset.id, by: -1) } }
                if index < count - 1 { Button("Move Down") { shelf.move(preset.id, by: 1) } }
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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let blot = 8 + 12 * preset.widthFraction
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
        .frame(width: 34, height: 34)
        .overlay { shape.strokeBorder(inUse ? Color.accentColor : Color.hairline, lineWidth: inUse ? 2 : 1) }
        .overlay(alignment: .bottomTrailing) {
            if inUse {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.onPrimaryCloth)
                    .frame(width: 14, height: 14)
                    .background(Color.primaryCloth, in: Circle())
                    .offset(x: 4, y: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ToolSwatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .background { if configuration.isPressed { Capsule().fill(Color.well).padding(3) } }
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, Capsule().inset(by: 2))
            .hoverEffect(.highlight)
    }
}
