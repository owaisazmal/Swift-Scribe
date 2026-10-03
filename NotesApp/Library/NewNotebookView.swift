import SwiftUI

struct NewNotebookView: View {
    let folder: FolderRecord?
    let onCreated: (UUID) -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("newNotebookCoverStyle") private var style: CoverStyle = .cloth
    @State private var template: PaperTemplate
    @State private var paperColor: PaperColor
    @State private var pageSize: PageSize
    @State private var useForQuickNote = false
    @State private var starter: NotebookStarter?
    @State private var id = UUID()
    @State private var title = ""
    @State private var cloth: ClothColor
    @State private var inkPair = 0
    @State private var seed: UInt32
    @State private var creating = false
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    init(folder: FolderRecord?, onCreated: @escaping (UUID) -> Void) {
        self.folder = folder
        self.onCreated = onCreated
        let id = UUID()
        let defaults = UserDefaults.standard
        _id = State(initialValue: id)
        _cloth = State(initialValue: .seeded(by: id))
        _seed = State(initialValue: CoverSpec.seed(from: id))
        _inkPair = State(initialValue: Int(id.uuid.3) % RisoInk.pairs.count)
        _template = State(initialValue: defaults.string(forKey: SettingsKey.defaultTemplate).flatMap(PaperTemplate.init(rawValue:)) ?? .narrowRuled)
        _paperColor = State(initialValue: defaults.string(forKey: SettingsKey.defaultPaperColor).flatMap(PaperColor.init(rawValue:)) ?? .white)
        _pageSize = State(initialValue: defaults.string(forKey: SettingsKey.defaultPageSize).flatMap(PageSize.init(rawValue:)) ?? .letter)
    }

    private static let coverWidth: CGFloat = 120

    private var spec: CoverSpec {
        CoverSpec(style: style, cloth: cloth, inks: RisoInk.pairs[inkPair], seed: seed)
    }

    private var placeholder: String { starter?.notebookTitle ?? String(localized: "Untitled Notebook") }

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? placeholder : trimmed
    }

    private var previewPage: URL {
        FileManager.default.temporaryDirectory.appending(path: "cover-preview-\(template.rawValue)-\(paperColor.rawValue)-\(pageSize.rawValue).png")
    }

    private var request: CoverRequest {
        CoverRequest(notebookID: id, spec: spec, title: displayTitle, meta: folder?.name ?? Date.now.formatted(.dateTime.month(.abbreviated).year()),
                     width: CoverWidth.preview, scale: displayScale, dark: colorScheme == .dark, highContrast: contrast == .increased,
                     firstPage: previewPage, firstPageKey: previewPage.lastPathComponent, firstPageIsPDF: false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let sideBySide = sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
                let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: Space.x8))
                                        : AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x6))
                layout {
                    VStack(alignment: .leading, spacing: Space.x4) {
                        preview.frame(maxWidth: .infinity)
                        if sideBySide { pageOptions }
                    }
                    .frame(width: Self.coverWidth * 2.25)
                    .frame(maxWidth: sideBySide ? nil : .infinity)
                    form(withPageOptions: !sideBySide)
                }
                .padding(Space.x6)
            }
            .background(Color.surface)
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.buttonStyle(.scribe(.secondary, inBar: true))
                }
                .boardBackground()
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .buttonStyle(.scribe(.primary, inBar: true))
                        .disabled(creating)
                        .keyboardShortcut(.defaultAction)
                }
                .boardBackground()
            }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .task {
                try? await Task.sleep(for: .milliseconds(350))
                titleFocused = true
            }
        }
        .presentationDetents([.large])
        .presentationSizing(.page)
    }

    /// The notebook lying open: its cover, then its first page.
    private var preview: some View {
        VStack(spacing: Space.x3) {
            let coverWidth = Self.coverWidth
            let page = NotebookPage.template(template, color: paperColor, size: pageSize)
            let aspect = page.size.width / max(page.size.height, 1)
            HStack(alignment: .bottom, spacing: 0) {
                let pageFile = previewPage
                CoverView(request: request, persist: false) {
                    await Task.detached(priority: .userInitiated) {
                        let image = PageRenderer.image(of: page, ink: .init(), assets: FileManager.default.temporaryDirectory,
                                                       width: PageThumbnailer.pixelWidth)
                        try? image.pngData()?.write(to: pageFile, options: .atomic)
                    }.value
                }
                .frame(width: coverWidth)
                .accessibilityHidden(false)
                .accessibilityLabel(Text("Preview: \(style.displayName) cover for \(displayTitle), \(template.displayName) \(paperColor.displayName) paper"))
                PaperPreview(template: template, color: paperColor, pageSize: page.size, renderWidth: 200)
                    .frame(width: min(coverWidth * 1.25, coverWidth * 4 / 3 * aspect))
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            }
            .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: pageSize)
            ShuffleButton(style: style, action: shuffle)
        }
    }

    private func form(withPageOptions: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            TextField("Title", text: $title, prompt: Text(placeholder).foregroundStyle(Color.textSecondary))
                .displayFont(24, relativeTo: .title2)
                .padding(.vertical, Space.x2)
                .scribeField(focused: titleFocused)
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit { Task { await create() } }
                .accessibilityLabel("Title")

            label("Start from")
            StarterRow(notebookID: id, selection: starter, pick: apply)

            label("Cover")
            ScribeSegmentedPicker("Cover", selection: $style, options: CoverStyle.allCases) { Text($0.displayName) }

            switch style {
            case .cloth, .firstPage:
                label(style == .cloth ? "Cloth" : "Spine")
                SwatchRow(items: ClothColor.allCases, selection: $cloth, label: \.displayName) { cloth in
                    Circle().fill(cloth.color)
                }
            case .print:
                label("Inks")
                SwatchRow(items: Array(RisoInk.pairs.indices), selection: $inkPair,
                          label: { "\(RisoInk.pairs[$0].0.displayName) and \(RisoInk.pairs[$0].1.displayName)" }) { index in
                    Circle().fill(LinearGradient(stops: [.init(color: Color(hex: RisoInk.pairs[index].0.hex), location: 0.5),
                                                        .init(color: Color(hex: RisoInk.pairs[index].1.hex), location: 0.5)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }

            label("Paper")
            PaperGallery(template: $template, color: paperColor, pageSize: pageSize.points,
                         hint: { _ in String(localized: "Sets the first page's paper") }, onPick: { _ in }, compact: true)
            PaperColorChips(selection: $paperColor)
            if withPageOptions { pageOptions }
        }
    }

    /// Size and Quick Note sit under the open notebook when there's room beside the form.
    private var pageOptions: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            Divider().overlay(Color.hairline)
            LabeledContent {
                Picker("Size", selection: $pageSize) {
                    ForEach(PageSize.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            } label: {
                Text("Page Size").foregroundStyle(Color.ink)
            }
            Divider().overlay(Color.hairline)
            Toggle(isOn: $useForQuickNote) {
                Text("Use this paper for Quick Note").foregroundStyle(Color.ink)
            }
        }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text).metaStyle(.footnote).accessibilityAddTraits(.isHeader)
    }

    private func apply(_ starter: NotebookStarter) {
        let spec = starter.spec(for: id)
        withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) {
            self.starter = starter
            style = spec.style
            template = starter.template
            paperColor = starter.paperColor
            if spec.style == .print {
                inkPair = RisoInk.pairs.firstIndex { $0.0 == spec.inks.0 && $0.1 == spec.inks.1 } ?? inkPair
            } else {
                cloth = spec.cloth
            }
        }
    }

    private func shuffle() {
        var generator = SystemRandomNumberGenerator()
        let next = CoverShuffle.next(spec, using: &generator)
        cloth = next.cloth
        seed = next.seed
        inkPair = RisoInk.pairs.firstIndex { $0.0 == next.inks.0 && $0.1 == next.inks.1 } ?? inkPair
    }

    private func create() async {
        guard !creating else { return }
        creating = true
        defer { creating = false }
        do {
            let created = try await store.createNotebook(id: id, title: displayTitle, cover: spec,
                                                         defaults: PageDefaults(template: template, paperColor: paperColor, pageSize: pageSize),
                                                         folder: folder)
            if useForQuickNote {
                let defaults = UserDefaults.standard
                defaults.set(template.rawValue, forKey: SettingsKey.defaultTemplate)
                defaults.set(paperColor.rawValue, forKey: SettingsKey.defaultPaperColor)
                defaults.set(pageSize.rawValue, forKey: SettingsKey.defaultPageSize)
            }
            dismiss()
            onCreated(created)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Rolls a different cloth, or a new print in other inks. Lives under the cover preview in New Notebook and Change Cover.
struct ShuffleButton: View {
    let style: CoverStyle
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var count = 0

    var body: some View {
        Button {
            count += 1
            action()
        } label: {
            Label("Shuffle", systemImage: "dice")
        }
        .buttonStyle(.scribe(.secondary, compact: true))
        .symbolEffect(.bounce, value: reduceMotion ? 0 : count)
        .accessibilityHint(style == .print ? Text("Prints a new pattern in another pair of inks") : Text("Picks another cloth"))
    }
}

private struct StarterRow: View {
    let notebookID: UUID
    let selection: NotebookStarter?
    let pick: (NotebookStarter) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            cards
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                cards.padding(Space.x2)
            }
            .padding(-Space.x2)
        }
    }

    private var cards: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.x3))
                                                         : AnyLayout(HStackLayout(alignment: .top, spacing: Space.x3))
        return layout {
            ForEach(NotebookStarter.allCases) { starter in
                let isSelected = starter == selection
                VStack(alignment: .leading, spacing: Space.x2) {
                    Button { pick(starter) } label: {
                        StarterCard(starter: starter, spec: starter.spec(for: notebookID), isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.lift)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(starter.accessibilityLabel(for: notebookID))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    Text(starter.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Space.x1)
                        .accessibilityHidden(true)
                        .onTapGesture { pick(starter) }
                }
            }
        }
    }
}

/// A starter drawn as a tiny cover beside a tiny page. Plain SwiftUI shapes, so a row of them never renders a cover.
private struct StarterCard: View {
    let starter: NotebookStarter
    let spec: CoverSpec
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 3) {
            cover
                .frame(width: 36, height: 48)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 1, bottomTrailingRadius: 3, topTrailingRadius: 3))
            paper.frame(width: 36, height: 48)
        }
        .padding(Space.x3)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(isSelected ? Color.accentColor : Color.hairline, lineWidth: isSelected ? 2 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.paper)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor, in: Circle())
                    .offset(x: 6, y: -6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.control))
    }

    @ViewBuilder private var cover: some View {
        if spec.style == .print {
            ZStack {
                Color(hex: RisoInk.paperStock)
                Circle().fill(Color(hex: spec.inks.1.hex)).frame(width: 30, height: 30).offset(x: 8, y: -9)
                Rectangle().fill(Color(hex: spec.inks.0.hex).opacity(0.85)).frame(height: 13).offset(y: 12)
            }
        } else {
            ZStack(alignment: .topLeading) {
                spec.cloth.color
                Rectangle().fill(Color.black.opacity(0.2)).frame(width: 5)
                RoundedRectangle(cornerRadius: 1).fill(Color.labelCream).frame(width: 20, height: 12).offset(x: 11, y: 9)
            }
        }
    }

    private var paper: some View {
        let rule = Color(uiColor: TemplateInk.for(starter.paperColor).line)
        return Rectangle()
            .fill(Color(uiColor: PageRenderer.paperColor(starter.paperColor)))
            .overlay {
                VStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { _ in rule.frame(height: 1) }
                }
                .padding(.horizontal, 5)
            }
            .overlay { Rectangle().strokeBorder(Color.hairline) }
    }
}

struct SwatchRow<Item: Hashable, Swatch: View>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String
    var size: CGFloat = 30
    @ViewBuilder let swatch: (Item) -> Swatch

    var body: some View {
        FlowLayout(spacing: Space.x2) {
            ForEach(items, id: \.self) { item in
                Button { selection = item } label: {
                    swatch(item)
                        .frame(width: size, height: size)
                        .padding(3)
                        .overlay { if item == selection { Circle().strokeBorder(Color.accentColor, lineWidth: 2.5) } }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(item))
                .accessibilityAddTraits(item == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// Rows that wrap to the width on offer, so swatches never run off a narrow sheet.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > width {
                origin = CGPoint(x: 0, y: origin.y + rowHeight + spacing)
                rowHeight = 0
            }
            frames.append(CGRect(origin: origin, size: size))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
