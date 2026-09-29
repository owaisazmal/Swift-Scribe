import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let pageReference = UTType(exportedAs: "com.owais.swiftscribe.page-reference")
}

struct PageReference: Codable, Transferable, Hashable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pageReference)
    }
}

struct PageNavigator: View {
    let document: NotebookDocument
    let currentPage: Int
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: UUID?
    @State private var goToPage = ""
    @FocusState private var goToFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: Space.x5)], spacing: Space.x6) {
                    ForEach(Array(document.pages.enumerated()), id: \.element.id) { index, page in
                        Button {
                            dismiss()
                            onSelect(index)
                        } label: {
                            PageThumbnailCell(document: document, page: page, index: index, isCurrent: index == currentPage)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                        .contextMenu { menu(for: page, at: index) }
                        .draggable(PageReference(id: page.id))
                        .dropDestination(for: PageReference.self) { items, _ in
                            guard let item = items.first, let from = document.index(of: item.id), from != index else { return false }
                            document.movePage(from: from, to: index)
                            return true
                        }
                        .accessibilityLabel(Text("Page \(index + 1) of \(document.pages.count)\(index == currentPage ? ", current" : "")"))
                        .accessibilityHint(Text("Opens this page"))
                        .accessibilityActions {
                            if index > 0 { Button("Move earlier") { document.movePage(from: index, to: index - 1) } }
                            if index < document.pages.count - 1 { Button("Move later") { document.movePage(from: index, to: index + 1) } }
                        }
                    }
                }
                .padding(Space.x5)
            }
            .background(Color.desk)
            .navigationTitle(Text("\(document.pages.count) pages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    TextField("Go to page", text: $goToPage)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .focused($goToFocused)
                        .onSubmit(go)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { document.insertPages([document.manifest.defaults.newPage()], at: document.pages.count) } label: {
                        Label("Add Page", systemImage: "plus")
                    }
                    .disabled(document.isReadOnly)
                }
            }
            .confirmationDialog("Delete this page?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Page", role: .destructive) { if let pendingDelete { document.removePages([pendingDelete]) } }
            } message: {
                Text("You can undo this.")
            }
        }
    }

    private func go() {
        guard let number = Int(goToPage), (1...document.pages.count).contains(number) else { return }
        dismiss()
        onSelect(number - 1)
    }

    @ViewBuilder
    private func menu(for page: NotebookPage, at index: Int) -> some View {
        Button { document.insertPages([document.manifest.defaults.newPage()], at: index + 1) } label: {
            Label("Insert Page After", systemImage: "doc.badge.plus")
        }
        Button { Task { await document.duplicatePage(at: index) } } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        if index > 0 {
            Button { document.movePage(from: index, to: index - 1) } label: { Label("Move Earlier", systemImage: "arrow.backward") }
        }
        if index < document.pages.count - 1 {
            Button { document.movePage(from: index, to: index + 1) } label: { Label("Move Later", systemImage: "arrow.forward") }
        }
        Divider()
        Button(role: .destructive) { pendingDelete = page.id } label: { Label("Delete", systemImage: "trash") }
    }
}

private struct PageThumbnailCell: View {
    let document: NotebookDocument
    let page: NotebookPage
    let index: Int
    let isCurrent: Bool
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: Space.x2) {
            Group {
                if let image {
                    Image(uiImage: image).resizable()
                } else {
                    Rectangle().fill(Color(uiColor: PageRenderer.paperColor(page.effectivePaperColor)))
                }
            }
            .aspectRatio(page.size.width / max(page.size.height, 1), contentMode: .fit)
            .overlay { Rectangle().strokeBorder(Color.hairline, lineWidth: 1) }
            .padding(4)
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: isCurrent ? 3 : 0) }
            Text(index + 1, format: .number)
                .font(.caption.weight(isCurrent ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isCurrent ? Color.accentColor : Color.inkSecondary)
        }
        .contentShape(Rectangle())
        .task(id: "\(page.id)-\(page.inkHash ?? "")-\(page.background)-\(page.paperColorRaw)") {
            image = await document.thumbnail(for: page)
        }
    }
}

extension NotebookDocument {
    /// Thumbnail reflecting unsaved ink when the page is in memory, otherwise the cached saved one.
    func thumbnail(for page: NotebookPage) async -> UIImage? {
        if hasUnsavedInk(page.id), let ink = loadedInk(page.id) {
            let assets = package.assetsDirectory
            return await Task.detached(priority: .utility) { PageThumbnailer.render(page: page, ink: ink, assets: assets) }.value
        }
        return await PageThumbnailer.thumbnail(package: package, page: page)
    }
}
