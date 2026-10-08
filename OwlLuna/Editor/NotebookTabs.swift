import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

extension Notification.Name {
    /// Asks the window that has a notebook in a tab (object: its ID) to show that tab.
    static let owlLunaSelectTab = Notification.Name("OwlLunaSelectTab")
}

extension UTType {
    static let tabReference = UTType(exportedAs: "com.owais.owlluna.tab-reference")
}

/// A tab being dragged along its bar.
struct TabReference: Codable, Transferable, Hashable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tabReference)
    }
}

/// The notebooks open in this window, as tabs over the editor: a well with a board for the one on show, the way
/// the app's other tabs are drawn. Each tab wears its notebook's cloth and has its own close; a tab is dragged
/// along the bar to another place, and held for the rest of what can be done with it.
struct TabStrip: View {
    let select: (UUID) -> Void
    let close: (UUID) -> Void
    let closeOthers: (UUID) -> Void
    /// Moves a tab's notebook into a pane beside the first. Nil when the window has no room for one, or has one already.
    let openBeside: ((UUID) -> Void)?
    @Environment(EditorWindow.self) private var window
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Query(filter: #Predicate<NotebookRecord> { $0.deletedAt == nil }) private var records: [NotebookRecord]
    @Namespace private var thumb
    @State private var dragging: UUID?
    @State private var dropTarget: UUID?

    /// With two notebooks side by side, the shortcuts belong to the tabs only while the first pane is the one being worked in.
    private var takesShortcuts: Bool { window.active == nil || window.active == window.selected }

    /// How the board slides to the tab on show, and how tabs change places.
    private var slide: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86) }

    var body: some View {
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tabs = window.tabs
        HStack(spacing: Space.x2) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                            self.tab(tab.id, record: byID[tab.id], number: index + 1, of: tabs.count)
                        }
                    }
                    .background { thumbView.matchedGeometryEffect(id: window.selected, in: thumb, isSource: false) }
                    .animation(slide, value: window.selected)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onChange(of: window.selected, initial: true) { _, selected in
                    guard let selected else { return }
                    withAnimation(reduceMotion ? nil : Motion.standard) { proxy.scrollTo(selected) }
                }
            }
            .well(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isTabBar)
            .accessibilityLabel(Text("Open Notebooks"))
            Button { window.pickingTab = true } label: { Label("Open Another Notebook in a Tab", systemImage: "plus") }
                .buttonStyle(.boardIcon)
                .disabled(tabs.count >= EditorWindow.tabLimit)
                .accessibilityIdentifier("tabs.add")
        }
        .padding(.horizontal, Space.x4)
        .padding(.top, Space.x1)
        .padding(.bottom, Space.x2)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background { shortcuts }
        .task(id: records.count) {
            let present = Set(records.map(\.id))
            if !present.isEmpty { window.keepTabs { present.contains($0) } }
        }
    }

    private func tab(_ id: UUID, record: NotebookRecord?, number: Int, of count: Int) -> some View {
        let selected = id == window.selected
        let title = record.map { $0.title.isEmpty ? String(localized: "Untitled") : $0.title } ?? String(localized: "Notebook")
        let index = number - 1
        return HStack(spacing: 0) {
            Button { select(id) } label: {
                HStack(spacing: Space.x2) {
                    SpineChip(cloth: record?.cloth ?? .slate)
                    Text(title)
                        .font(.subheadline.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.ink : Color.textSecondary)
                        .lineLimit(1)
                }
                .padding(.leading, Space.x4)
                .frame(minWidth: 72, maxWidth: 220, minHeight: 44, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text("Tab \(number) of \(count)"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityActions {
                if index > 0 { Button("Move Left") { move(id, to: index - 1) } }
                if index < count - 1 { Button("Move Right") { move(id, to: index + 1) } }
            }
            .accessibilityShowsLargeContentViewer { Label(title, systemImage: "book.closed") }
            .accessibilityIdentifier("tabs.tab.\(title)")
            Button { close(id) } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selected ? Color.ink : Color.textSecondary)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close \(title)"))
            .accessibilityShowsLargeContentViewer { Label("Close \(title)", systemImage: "xmark") }
            .accessibilityIdentifier("tabs.close.\(title)")
        }
        .contentShape([.hoverEffect, .contextMenuPreview, .dragPreview], RoundedRectangle(cornerRadius: 18, style: .continuous).inset(by: 4))
        .hoverEffect(.highlight)
        .overlay { if dropTarget == id, dragging != id { insertionRule(at: index, of: count) } }
        .contextMenu { menu(for: id, at: index, of: count) }
        .onDrag {
            dragging = id
            let provider = NSItemProvider()
            provider.register(TabReference(id: id))
            return provider
        }
        .dropDestination(for: TabReference.self) { items, _ in
            dropTarget = nil
            guard let item = items.first, let destination = window.tabs.firstIndex(where: { $0.id == id }) else { return false }
            return move(item.id, to: destination)
        } isTargeted: { targeted in
            if targeted { dropTarget = id } else if dropTarget == id { dropTarget = nil }
        }
        .matchedGeometryEffect(id: id, in: thumb)
        .id(id)
    }

    @ViewBuilder
    private func menu(for id: UUID, at index: Int, of count: Int) -> some View {
        if let openBeside {
            Button { openBeside(id) } label: { Label("Open Beside", systemImage: "rectangle.split.2x1") }
        }
        if index > 0 {
            Button { move(id, to: index - 1) } label: { Label("Move Left", systemImage: "arrow.left") }
        }
        if index < count - 1 {
            Button { move(id, to: index + 1) } label: { Label("Move Right", systemImage: "arrow.right") }
        }
        Divider()
        Button { closeOthers(id) } label: { Label("Close Other Tabs", systemImage: "xmark.rectangle") }
        Button { close(id) } label: { Label("Close Tab", systemImage: "xmark") }
    }

    @discardableResult
    private func move(_ id: UUID, to index: Int) -> Bool {
        var moved = false
        withAnimation(slide) { moved = window.moveTab(id, to: index) }
        if moved { AccessibilityNotification.Announcement(String(localized: "Tab \(index + 1) of \(window.tabs.count)")).post() }
        return moved
    }

    /// A tab dropped on a later one takes its place and lands after it; on an earlier one, before it.
    private func dropsAfter(_ index: Int) -> Bool {
        guard let dragging, let from = window.tabs.firstIndex(where: { $0.id == dragging }) else { return false }
        return from < index
    }

    /// Stands on the edge the tab will land at; at either end of the bar it steps in, clear of the well's round corners.
    private func insertionRule(at index: Int, of count: Int) -> some View {
        let after = dropsAfter(index)
        let atEnd = after ? index == count - 1 : index == 0
        return InsertionRule(vertical: true)
            .stroke(Color.mustard, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
            .frame(width: 3)
            .padding(.vertical, Space.x3)
            .offset(x: (atEnd ? -5.5 : 1.5) * (after ? 1 : -1))
            .frame(maxWidth: .infinity, alignment: after ? .trailing : .leading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The board under the tab on show, as `OwlLunaSegmentedPicker` draws its own.
    private var thumbView: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Color.clear
            .board(in: shape)
            .overlay { if scheme == .dark { shape.fill(Color.ink.opacity(0.10)) } }
            .overlay { if contrast == .increased { shape.strokeBorder(Color.inkSecondary, lineWidth: 1) } }
            .padding(4)
    }

    @ViewBuilder
    private var shortcuts: some View {
        if takesShortcuts, !window.pickingTab {
            Group {
                Button("Next Tab") { window.step(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { window.step(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Next Tab") { window.step(1) }.keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Tab") { window.step(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
                Button("Close Tab") { if let selected = window.selected { close(selected) } }.keyboardShortcut("w", modifiers: .command)
            }
            .hidden()
            .accessibilityHidden(true)
        }
    }
}
