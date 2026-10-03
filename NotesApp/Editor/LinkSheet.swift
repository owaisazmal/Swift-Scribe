import SwiftUI
import SwiftData

/// Picks what a new link opens: a page of this notebook, another notebook or one of its pages, or a web address.
struct LinkSheet: View {
    let session: EditorSession
    let pick: (PageLink) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.pages

    enum Tab: Hashable { case pages, notebooks, web }

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .pages: LinkPagePicker(session: session, choose: choose)
                case .notebooks: LinkNotebookPicker(current: session.document.id, choose: choose)
                case .web: LinkAddressForm(choose: choose)
                }
            }
            .background(Color.desk)
            .navigationTitle("Add a Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Picker("Link to", selection: $tab) {
                        Text("This Notebook").tag(Tab.pages)
                        Text("Another Notebook").tag(Tab.notebooks)
                        Text("Web").tag(Tab.web)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier("link.tabs")
                }
            }
        }
    }

    private func choose(_ link: PageLink) {
        pick(link)
        dismiss()
    }
}

private struct LinkPagePicker: View {
    let session: EditorSession
    let choose: (PageLink) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var document: NotebookDocument { session.document }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x4) {
                    Text("The link sits on page \(session.currentPage + 1). Tap it there to open the page you choose.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                    if dynamicTypeSize.isAccessibilitySize {
                        LazyVStack(spacing: Space.x3) { cells }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: Space.x5, alignment: .top)], spacing: Space.x6) { cells }
                    }
                }
                .padding(Space.x5)
            }
            .onAppear {
                guard document.pages.indices.contains(session.currentPage) else { return }
                proxy.scrollTo(document.pages[session.currentPage].id, anchor: .center)
            }
        }
        .accessibilityIdentifier("link.picker")
    }

    private var cells: some View {
        ForEach(Array(document.pages.enumerated()), id: \.element.id) { index, page in
            let isCurrent = index == session.currentPage
            Button { choose(PageLink(target: page.id)) } label: {
                PageThumbnailCell(document: document, page: page, index: index, isCurrent: isCurrent)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .disabled(isCurrent)
            .accessibilityLabel(Text(isCurrent ? "Page \(index + 1), this page" : "Page \(index + 1)"))
            .accessibilityValue(Text(page.bookmark.flatMap { $0.isEmpty ? nil : $0 } ?? ""))
            .accessibilityHint(Text(isCurrent ? "" : "Links to this page"))
            .accessibilityIdentifier("link.page.\(index + 1)")
            .id(page.id)
        }
    }
}

private struct LinkNotebookPicker: View {
    let current: UUID
    let choose: (PageLink) -> Void
    @Query(filter: #Predicate<NotebookRecord> { $0.deletedAt == nil }, sort: \NotebookRecord.title) private var records: [NotebookRecord]

    var body: some View {
        let others = records.filter { $0.id != current }
        List {
            Section {
                ForEach(others) { record in
                    NavigationLink {
                        LinkNotebookPages(record: record, choose: choose)
                    } label: {
                        HStack(spacing: Space.x4) {
                            RecordCover(record: record, width: CoverWidth.row, showsShadow: false).frame(width: 40)
                            VStack(alignment: .leading, spacing: Space.x1) {
                                Text(record.title).font(.headline).foregroundStyle(Color.ink)
                                Text(record.pageCount == 1 ? String(localized: "1 page") : String(localized: "\(record.pageCount) pages"))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.surface)
                    .accessibilityIdentifier("link.notebook.\(record.title)")
                }
            } footer: {
                Text("Tapping the link saves this notebook, puts it away and opens the other one.").foregroundStyle(Color.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if others.isEmpty {
                ContentUnavailableView {
                    Label("No Other Notebooks", systemImage: "books.vertical").foregroundStyle(Color.ink)
                } description: {
                    Text("Once you have another notebook, you can link to it from here.").foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}

/// The other notebook's pages, read from its files or from its open editor in another window.
private struct LinkNotebookPages: View {
    let record: NotebookRecord
    let choose: (PageLink) -> Void
    @Environment(LibraryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pages: [NotebookPage] = []
    @State private var loaded = false

    private var package: NotebookPackage { NotebookPackage(root: store.root, id: record.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x4) {
                Button { choose(link(to: nil)) } label: {
                    Label("The Whole Notebook", systemImage: "book.closed")
                        .frame(maxWidth: .infinity)
                }
                .prominentButton()
                .accessibilityHint(Text("The link opens the notebook where you left it"))
                .accessibilityIdentifier("link.notebook.whole")
                if record.isLocked {
                    Text("This notebook is locked, so its pages aren't shown here.").font(.footnote).foregroundStyle(Color.textSecondary)
                } else {
                    Text("Or choose the page it opens at.").font(.footnote).foregroundStyle(Color.textSecondary)
                    if dynamicTypeSize.isAccessibilitySize {
                        LazyVStack(spacing: Space.x3) { cells }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: Space.x5, alignment: .top)], spacing: Space.x6) { cells }
                    }
                    if !loaded { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .padding(Space.x5)
        }
        .background(Color.desk)
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: record.id) {
            guard !record.isLocked else { return }
            if let open = DocumentRegistry.shared.document(for: record.id) {
                pages = open.pages
            } else {
                pages = (try? await package.readManifest().manifest.pages) ?? []
            }
            loaded = true
        }
    }

    private func link(to page: UUID?) -> PageLink {
        PageLink(.notebook(record.id, page: page, name: record.title))
    }

    private var cells: some View {
        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
            Button { choose(link(to: page.id)) } label: {
                VStack(spacing: Space.x2) {
                    SavedPageThumbnail(package: package, page: page)
                    Text(index + 1, format: .number).font(.caption.monospacedDigit()).foregroundStyle(Color.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityLabel(Text("Page \(index + 1)"))
            .accessibilityValue(Text(page.bookmark.flatMap { $0.isEmpty ? nil : $0 } ?? ""))
            .accessibilityHint(Text("The link opens the notebook at this page"))
            .accessibilityIdentifier("link.notebook.page.\(index + 1)")
        }
    }
}

/// A page of a notebook that isn't open, as last saved.
struct SavedPageThumbnail: View {
    let package: NotebookPackage
    let page: NotebookPage
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                Rectangle().fill(Color(uiColor: PageRenderer.paperColor(page.effectivePaperColor)))
            }
        }
        .aspectRatio(page.size.width / max(page.size.height, 1), contentMode: .fit)
        .overlay { Rectangle().strokeBorder(Color.hairline, lineWidth: 1) }
        .task(id: "\(page.id)-\(page.thumbnailKey)") { image = await PageThumbnailer.thumbnail(package: package, page: page) }
    }
}

private struct LinkAddressForm: View {
    let choose: (PageLink) -> Void
    @State private var address = ""
    @State private var label = ""
    @FocusState private var focused: Bool

    private var url: URL? { WebAddress.url(from: address) }

    var body: some View {
        Form {
            Section {
                TextField("Address", text: $address, prompt: Text("example.com"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .accessibilityIdentifier("link.web.address")
                TextField("Name", text: $label, prompt: Text("Optional"))
                    .accessibilityIdentifier("link.web.name")
            } footer: {
                Text("Tapping the link opens the address in your browser. Without a name, the link shows the address.")
                    .foregroundStyle(Color.textSecondary)
            }
            Section {
                Button("Add Link", action: add)
                    .disabled(url == nil)
                    .accessibilityIdentifier("link.web.add")
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { focused = true }
    }

    private func add() {
        guard let url else { return }
        choose(PageLink(.web(url), label: label.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}
