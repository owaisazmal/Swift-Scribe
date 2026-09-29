import SwiftUI

struct NewNotebookView: View {
    let folder: FolderRecord?
    let onCreated: (UUID) -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @AppStorage(SettingsKey.defaultTemplate) private var template: PaperTemplate = .narrowRuled
    @AppStorage(SettingsKey.defaultPaperColor) private var paperColor: PaperColor = .white
    @AppStorage(SettingsKey.defaultPageSize) private var pageSize: PageSize = .letter
    @AppStorage("newNotebookCoverStyle") private var style: CoverStyle = .cloth
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
        _id = State(initialValue: id)
        _cloth = State(initialValue: .seeded(by: id))
        _seed = State(initialValue: CoverSpec.seed(from: id))
        _inkPair = State(initialValue: Int(id.uuid.3) % RisoInk.pairs.count)
    }

    private var spec: CoverSpec {
        CoverSpec(style: style, cloth: cloth, inks: RisoInk.pairs[inkPair], seed: seed)
    }

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "Untitled Notebook") : trimmed
    }

    private var previewPage: URL {
        FileManager.default.temporaryDirectory.appending(path: "cover-preview-\(template.rawValue)-\(paperColor.rawValue)-\(pageSize.rawValue).png")
    }

    private var request: CoverRequest {
        CoverRequest(notebookID: id, spec: spec, title: displayTitle, meta: folder?.name ?? String(localized: "1 page"),
                     width: CoverWidth.preview, scale: displayScale, dark: colorScheme == .dark, highContrast: contrast == .increased,
                     firstPage: previewPage, firstPageKey: previewPage.lastPathComponent, firstPageIsPDF: false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Space.x8) {
                        preview.frame(width: 220)
                        form
                    }
                    VStack(alignment: .leading, spacing: Space.x6) {
                        preview.frame(width: 180).frame(maxWidth: .infinity)
                        form
                    }
                }
                .padding(Space.x6)
            }
            .background(Color.surface)
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(creating)
                        .keyboardShortcut(.defaultAction)
                }
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
    }

    private var preview: some View {
        VStack(spacing: Space.x3) {
            let pageFile = previewPage
            let page = NotebookPage.template(template, color: paperColor, size: pageSize)
            CoverView(request: request, persist: false) {
                let image = PageRenderer.image(of: page, ink: .init(), assets: FileManager.default.temporaryDirectory, width: PageThumbnailer.pixelWidth)
                try? image.pngData()?.write(to: pageFile, options: .atomic)
            }
            .accessibilityHidden(false)
            .accessibilityLabel(Text("Cover preview: \(style.displayName) cover for \(displayTitle)"))
            if style == .print {
                Button {
                    seed = UInt32.random(in: 0...UInt32.max)
                } label: {
                    Label("Reprint pattern", systemImage: "arrow.triangle.2.circlepath")
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            TextField("Untitled Notebook", text: $title)
                .font(.display(24, relativeTo: .title2))
                .padding(.horizontal, Space.x3)
                .padding(.vertical, Space.x2)
                .background(Color.paper, in: RoundedRectangle(cornerRadius: Radius.control))
                .overlay { RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.hairline) }
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit { Task { await create() } }
                .accessibilityLabel("Title")

            label("Cover")
            Picker("Cover", selection: $style) {
                ForEach(CoverStyle.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x3) {
                    ForEach(PaperTemplate.allCases) { option in
                        Button { template = option } label: {
                            PaperSwatch(template: option, color: paperColor, isSelected: template == option)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.displayName)
                        .accessibilityAddTraits(template == option ? .isSelected : [])
                    }
                }
                .padding(.vertical, Space.x2)
            }

            Divider().overlay(Color.hairline)
            HStack {
                Text("Paper colour")
                Spacer()
                SwatchRow(items: PaperColor.allCases, selection: $paperColor, label: \.displayName, size: 26) { color in
                    Circle().fill(Color(uiColor: PageRenderer.paperColor(color))).overlay { Circle().strokeBorder(Color.hairline) }
                }
                .fixedSize()
            }
            Divider().overlay(Color.hairline)
            Picker("Size", selection: $pageSize) {
                ForEach(PageSize.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text).metaStyle(.footnote).accessibilityAddTraits(.isHeader)
    }

    private func create() async {
        guard !creating else { return }
        creating = true
        defer { creating = false }
        do {
            let created = try await store.createNotebook(id: id, title: displayTitle, cover: spec,
                                                         defaults: PageDefaults(template: template, paperColor: paperColor, pageSize: pageSize),
                                                         folder: folder)
            dismiss()
            onCreated(created)
        } catch {
            errorMessage = error.localizedDescription
        }
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

struct PaperSwatch: View {
    let template: PaperTemplate
    let color: PaperColor
    let isSelected: Bool

    var body: some View {
        VStack(spacing: Space.x1) {
            Image(uiImage: Self.image(template, color))
                .resizable()
                .frame(width: 54, height: 70)
                .overlay { Rectangle().strokeBorder(Color.hairline) }
                .padding(3)
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0) }
            Text(template.displayName)
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.accentColor : Color.inkSecondary)
        }
    }

    static func image(_ template: PaperTemplate, _ color: PaperColor) -> UIImage {
        let size = CGSize(width: 108, height: 140)
        return UIGraphicsImageRenderer(size: size).image { context in
            PageRenderer.paperColor(color).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            PageRenderer.drawTemplate(template, color: color, in: context.cgContext, size: size)
        }
    }
}
