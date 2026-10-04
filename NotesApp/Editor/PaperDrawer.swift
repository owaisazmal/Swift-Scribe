import SwiftUI
import PencilKit

/// Picks paper from miniatures drawn by the page renderer: for a new page, or live on the current one.
struct PaperDrawer: View {
    enum Mode: Identifiable {
        case add(after: Int), change(pageID: UUID)

        var id: String {
            switch self {
            case .add(let index): "add-\(index)"
            case .change(let pageID): "change-\(pageID)"
            }
        }

        var isAdding: Bool {
            if case .add = self { true } else { false }
        }
    }

    let session: EditorSession
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @State private var template: PaperTemplate
    @State private var color: PaperColor
    @State private var pageSize: PageSize?
    private let newPageSize: CGSize

    init(session: EditorSession, mode: Mode) {
        self.session = session
        self.mode = mode
        let page: NotebookPage = switch mode {
        case .add(let index): session.document.newPage(after: index)
        case .change(let pageID): session.document.pages.first { $0.id == pageID } ?? session.document.newPage(after: nil)
        }
        newPageSize = page.size
        _template = State(initialValue: page.template ?? .blank)
        _color = State(initialValue: page.paperColor)
        _pageSize = State(initialValue: PageSize.allCases.first { $0.points == page.size })
    }

    private var document: NotebookDocument { session.document }

    private var changing: NotebookPage? {
        guard case .change(let pageID) = mode else { return nil }
        return document.pages.first { $0.id == pageID }
    }

    private var selectedTemplate: PaperTemplate { changing?.template ?? template }
    private var selectedColor: PaperColor { changing?.paperColor ?? color }
    private var previewSize: CGSize { changing?.shownSize ?? pageSize?.points ?? newPageSize }
    private var isBoard: Bool { changing?.isBoard ?? false }

    private var hint: String {
        switch mode {
        case .add(let index): String(localized: "Adds a page after page \(index + 1)")
        case .change(let pageID): String(localized: "Changes page \((document.index(of: pageID) ?? 0) + 1)")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.x5) {
                        controls
                        Divider().overlay(Color.hairline)
                        PaperGallery(template: Binding(get: { selectedTemplate }, set: { template = $0 }), color: selectedColor,
                                     pageSize: previewSize, hint: { _ in hint }, onPick: pick, only: isBoard ? Whiteboard.templates : nil)
                    }
                    .padding(Space.x5)
                }
                .accessibilityIdentifier("paper.drawer")
                .onAppear { proxy.scrollTo(selectedTemplate) }
            }
            .background(Color.surface)
            .navigationTitle("Paper")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .onChange(of: changing == nil) { _, gone in if gone, !mode.isAdding { dismiss() } }
        }
        .frame(minWidth: 340, idealWidth: 560, minHeight: 440, idealHeight: 720)
    }

    /// A popover's bar tints whatever sits in it, so the title and Done are a row of their own.
    private var header: some View {
        ZStack(alignment: .trailing) {
            Text("Paper")
                .font(.headline)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Button("Done") { dismiss() }.buttonStyle(.scribe(.primary, inBar: true))
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, Space.x4)
        .padding(.vertical, Space.x2)
        .background(Color.surface)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            PaperColorChips(selection: Binding(get: { selectedColor }, set: pickColor))
            if mode.isAdding {
                LabeledContent {
                    Menu {
                        Picker("Page Size", selection: $pageSize) {
                            if PageSize.allCases.allSatisfy({ $0.points != newPageSize }) {
                                Text("Current Size").tag(PageSize?.none)
                            }
                            ForEach(PageSize.allCases) { Text($0.displayName).tag(PageSize?.some($0)) }
                        }
                    } label: {
                        HStack(spacing: Space.x2) {
                            Text(sizeName)
                            Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.scribe(.secondary, compact: true))
                    .accessibilityLabel(Text("Page Size"))
                    .accessibilityValue(Text(sizeName))
                } label: {
                    Text("Page Size").foregroundStyle(Color.ink)
                }
            }
        }
    }

    private var sizeName: String { pageSize?.displayName ?? String(localized: "Current Size") }

    private func pick(_ option: PaperTemplate) {
        switch mode {
        case .add(let index):
            session.addPage(after: index, template: option, color: color, size: pageSize)
            dismiss()
        case .change(let pageID):
            document.setPaper(template: option, color: selectedColor, forPage: pageID)
        }
    }

    private func pickColor(_ option: PaperColor) {
        color = option
        if case .change(let pageID) = mode { document.setPaper(template: selectedTemplate, color: option, forPage: pageID) }
    }
}

extension EditorSession {
    /// Inserts a page with this paper after `index` and makes it current.
    func addPage(after index: Int, template: PaperTemplate, color: PaperColor, size: PageSize?) {
        guard !document.isReadOnly else { return }
        var page = document.newPage(after: index, template: template)
        page.paperColor = color
        if let size { page.size = size.points }
        let position = min(max(index + 1, 0), document.pages.count)
        document.insertPages([page], at: position)
        go(to: position)
    }
}

/// Every template as a miniature page, grouped by family; a list of rows at accessibility sizes.
struct PaperGallery: View {
    @Binding var template: PaperTemplate
    let color: PaperColor
    let pageSize: CGSize
    var hint: (PaperTemplate) -> String
    var onPick: (PaperTemplate) -> Void
    var compact = false
    /// The paper a whiteboard can have: rules with no margins to end at.
    var only: [PaperTemplate]?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tileWidth: CGFloat { compact ? 64 : 80 }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                rows
            } else if compact {
                strip
            } else {
                grid
            }
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: template)
    }

    private var families: [PaperFamily] { PaperFamily.allCases.filter { !templates(in: $0).isEmpty } }

    private func templates(in family: PaperFamily) -> [PaperTemplate] {
        family.templates.filter { only?.contains($0) ?? true }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: Space.x6) {
            ForEach(families) { family in
                VStack(alignment: .leading, spacing: Space.x3) {
                    header(family)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth + Space.x3), spacing: Space.x3, alignment: .top)],
                              alignment: .leading, spacing: Space.x5) {
                        ForEach(templates(in: family)) { tile($0).id($0) }
                    }
                }
            }
        }
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Space.x8) {
                    ForEach(families) { family in
                        VStack(alignment: .leading, spacing: Space.x2) {
                            header(family)
                            HStack(alignment: .top, spacing: Space.x4) {
                                ForEach(templates(in: family)) { tile($0).id($0) }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.x2)
                .padding(.vertical, Space.x2)
            }
            .padding(.horizontal, -Space.x2)
            .onAppear { proxy.scrollTo(template, anchor: .center) }
            .onChange(of: template) { _, selected in
                withAnimation(reduceMotion ? nil : Motion.standard) { proxy.scrollTo(selected, anchor: .center) }
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            ForEach(families) { family in
                header(family).padding(.bottom, Space.x6)
                ForEach(templates(in: family)) { option in
                    HStack(spacing: Space.x6) {
                        button(option) { preview(option).frame(width: 60) }
                        name(option)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func header(_ family: PaperFamily) -> some View {
        Text(family.displayName).metaStyle(compact ? .caption : .footnote).accessibilityAddTraits(.isHeader)
    }

    private func tile(_ option: PaperTemplate) -> some View {
        VStack(spacing: Space.x4) {
            button(option) { preview(option).frame(width: tileWidth) }
            name(option)
                .multilineTextAlignment(.center)
                .frame(width: tileWidth + Space.x3)
        }
    }

    private func preview(_ option: PaperTemplate) -> some View {
        PaperPreview(template: option, color: color, pageSize: pageSize, isBoard: only != nil)
            .overlay {
                if option == template {
                    StitchedSelection().transition(reduceMotion ? .opacity : .scale(scale: 1.06).combined(with: .opacity))
                }
            }
    }

    /// Outside the button, like a cover's meta line: the audit reads text beside a light miniature as low contrast.
    private func name(_ option: PaperTemplate) -> some View {
        Text(option.displayName)
            .font(option == template ? .caption.weight(.semibold) : .caption)
            .foregroundStyle(option == template ? Color.ink : Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
            .onTapGesture { pick(option) }
    }

    private func pick(_ option: PaperTemplate) {
        template = option
        onPick(option)
    }

    private func button<Content: View>(_ option: PaperTemplate, @ViewBuilder label: () -> Content) -> some View {
        Button {
            pick(option)
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.displayName)
        .accessibilityValue(color.displayName)
        .accessibilityHint(hint(option))
        .accessibilityAddTraits(option == template ? [.isButton, .isSelected] : .isButton)
    }
}

/// Paper colours as named chips in their own colour; the selected one shows a check and an accent ring.
struct PaperColorChips: View {
    @Binding var selection: PaperColor

    var body: some View {
        FlowLayout(spacing: Space.x1) {
            ForEach(PaperColor.allCases) { option in
                let isSelected = option == selection
                Button { selection = option } label: {
                    HStack(spacing: Space.x1) {
                        if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        Text(option.displayName).font(isSelected ? .subheadline.weight(.semibold) : .subheadline)
                    }
                    .foregroundStyle(option.isDark ? Color.white : Color.labelInk)
                    .padding(.horizontal, Space.x3)
                    .frame(minHeight: 34)
                    .background(Color(uiColor: PageRenderer.paperColor(option)), in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.hairline) }
                    .padding(3)
                    .overlay { if isSelected { Capsule().strokeBorder(Color.accentColor, lineWidth: 2.5) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(option.displayName)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// A page's paper at its true aspect and colour, rendered off the main thread by the page renderer.
struct PaperPreview: View {
    let template: PaperTemplate
    let color: PaperColor
    let pageSize: CGSize
    var renderWidth: CGFloat = 120
    var isBoard = false
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var shownKey = ""

    var body: some View {
        let key = PaperPreviewCache.key(template: template, color: color, size: pageSize, width: renderWidth, scale: displayScale, board: isBoard)
        Rectangle()
            .fill(Color(uiColor: PageRenderer.paperColor(color)))
            .aspectRatio(pageSize.width / max(pageSize.height, 1), contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().id(shownKey).transition(.opacity)
                }
            }
            .overlay { Rectangle().strokeBorder(Color.hairline, lineWidth: 1) }
            .accessibilityHidden(true)
            .task(id: key) {
                if let hit = PaperPreviewCache.cached(key) {
                    image = hit
                    shownKey = key
                    return
                }
                let rendered = await PaperPreviewCache.image(template: template, color: color, size: pageSize, width: renderWidth, scale: displayScale, board: isBoard)
                guard !Task.isCancelled else { return }
                withAnimation(Motion.standard) {
                    image = rendered
                    shownKey = key
                }
            }
    }
}

enum PaperPreviewCache {
    static let images = LRUCache<PageThumbnailer.SharedUIImage>(capacity: 64)

    static func key(template: PaperTemplate, color: PaperColor, size: CGSize, width: CGFloat, scale: CGFloat, board: Bool = false) -> String {
        "\(template.rawValue)|\(color.rawValue)|\(Int(size.width))x\(Int(size.height))|\(Int(width))@\(scale)\(board ? "|board" : "")"
    }

    static func cached(_ key: String) -> UIImage? { images.value(key) { nil }?.image }

    static func image(template: PaperTemplate, color: PaperColor, size: CGSize, width: CGFloat = 120, scale: CGFloat, board: Bool = false) async -> UIImage {
        let key = key(template: template, color: color, size: size, width: width, scale: scale, board: board)
        if let hit = cached(key) { return hit }
        let image = await Task.detached(priority: .userInitiated) {
            // A whiteboard's miniature is a small piece of it, so its rules show at a size that can be told apart.
            let page = board ? Whiteboard.piece(of: .board(template: template, color: color),
                                                in: CGRect(origin: Whiteboard.center, size: CGSize(width: 320, height: 320 * size.height / max(size.width, 1))))
                             : NotebookPage(background: .template(template), paperColor: color, size: size)
            return PageRenderer.image(of: page, ink: PKDrawing(), assets: FileManager.default.temporaryDirectory, width: width, scale: scale)
        }.value
        return images.value(key) { PageThumbnailer.SharedUIImage(image: image) }?.image ?? image
    }
}
