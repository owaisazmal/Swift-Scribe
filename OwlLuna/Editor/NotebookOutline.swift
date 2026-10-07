import SwiftUI
import PDFKit

extension NotebookPage {
    /// The bookmark's name, empty when it hasn't been given one; nil when the page isn't bookmarked.
    var bookmark: String? {
        get { extra["bookmark"]?.stringValue }
        set { extra["bookmark"] = newValue.map(JSONValue.string) }
    }

    /// What a bookmark is called in lists: its name, the journal date, or the page number.
    func bookmarkTitle(number: Int) -> String {
        if let bookmark, !bookmark.isEmpty { return bookmark }
        if let spoken = day.flatMap(DailyJournal.spokenDay) { return spoken }
        return String(localized: "Page \(number)")
    }
}

extension NotebookDocument {
    /// One undo step for any change to a page's pictures and stickers.
    func updateItems(onPage pageID: UUID, actionName: String, _ change: (inout [PageItem]) -> Void) {
        guard let index = index(of: pageID) else { return }
        var items = pages[index].items
        change(&items)
        guard items != pages[index].items else { return }
        updatePage(pageID, actionName: actionName) { $0.items = items }
    }

    /// Whether any page is a page of an imported PDF, whose text can be selected.
    var hasPDFPages: Bool {
        pages.contains { if case .pdf = $0.background { true } else { false } }
    }

    func setBookmark(_ name: String?, forPage pageID: UUID) {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = index(of: pageID), pages[index].bookmark != name else { return }
        updatePage(pageID, actionName: name == nil ? String(localized: "Remove Bookmark") : String(localized: "Bookmark")) { $0.bookmark = name }
    }
}

struct OutlineEntry: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let level: Int
    let pageID: UUID
}

/// The table of contents an imported PDF came with, mapped onto the notebook's pages.
enum PDFOutlineReader {
    static func entries(pages: [NotebookPage], assets: URL) -> [OutlineEntry] {
        var pageIDs: [String: [Int: UUID]] = [:]
        var files: [String] = []
        for page in pages {
            guard case .pdf(let file, let index) = page.background else { continue }
            if pageIDs[file] == nil { files.append(file) }
            pageIDs[file, default: [:]][index] = page.id
        }
        var entries: [OutlineEntry] = []
        for file in files {
            guard let pdf = PDFDocument(url: assets.appending(path: file)), let root = pdf.outlineRoot, let ids = pageIDs[file] else { continue }
            collect(root, level: 0, in: pdf, ids: ids, into: &entries)
        }
        return entries
    }

    private static func collect(_ node: PDFOutline, level: Int, in pdf: PDFDocument, ids: [Int: UUID], into entries: inout [OutlineEntry]) {
        for index in 0..<node.numberOfChildren {
            guard let child = node.child(at: index), entries.count < 2000 else { continue }
            let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty, let page = child.destination?.page, let pageID = ids[pdf.index(for: page)] {
                entries.append(OutlineEntry(id: entries.count, title: title, level: min(level, 4), pageID: pageID))
            }
            if level < 6 { collect(child, level: level + 1, in: pdf, ids: ids, into: &entries) }
        }
    }
}

/// The navigator's second tab: the pages you bookmarked, the pages you tagged, then an imported PDF's own contents.
struct NotebookOutline: View {
    let session: EditorSession
    let open: (Int) -> Void
    @State private var contents: [OutlineEntry] = []
    @State private var renaming: UUID?
    @State private var name = ""

    private var document: NotebookDocument { session.document }

    private var bookmarks: [(index: Int, page: NotebookPage)] {
        document.pages.enumerated().filter { $0.element.bookmark != nil }.map { (index: $0.offset, page: $0.element) }
    }

    private var tagged: [(index: Int, page: NotebookPage)] {
        document.pages.enumerated().filter { !$0.element.tags.isEmpty }.map { (index: $0.offset, page: $0.element) }
    }

    private var pdfFiles: [String] {
        var seen = Set<String>()
        return document.pages.compactMap { page in
            guard case .pdf(let file, _) = page.background, seen.insert(file).inserted else { return nil }
            return file
        }
    }

    var body: some View {
        let bookmarks = bookmarks, tagged = tagged
        Group {
            if bookmarks.isEmpty, tagged.isEmpty, contents.isEmpty {
                ScrollView {
                    ContentUnavailableView {
                        Label { Text("No Bookmarks Yet") } icon: { Image(systemName: "bookmark").foregroundStyle(Color.textSecondary) }
                            .foregroundStyle(Color.ink)
                    } description: {
                        Text("Tap the small ribbon beside the page number to bookmark a page. Bookmarks, tagged pages and a PDF's table of contents are listed here.")
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                List {
                    if !bookmarks.isEmpty {
                        Section {
                            ForEach(bookmarks, id: \.page.id) { item in bookmarkRow(item.page, at: item.index) }
                        } header: {
                            Text("Bookmarks").foregroundStyle(Color.textSecondary)
                        }
                    }
                    if !tagged.isEmpty { TaggedPagesSection(pages: tagged, open: open) }
                    if !contents.isEmpty {
                        Section {
                            ForEach(contents) { entry in contentsRow(entry) }
                        } header: {
                            Text("Contents").foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .task(id: pdfFiles) {
            let pages = document.pages, assets = document.package.assetsDirectory
            guard !pdfFiles.isEmpty else { contents = []; return }
            contents = await Task.detached(priority: .userInitiated) { PDFOutlineReader.entries(pages: pages, assets: assets) }.value
        }
        .alert("Name Bookmark", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let renaming { document.setBookmark(name, forPage: renaming) } }
        }
        .accessibilityIdentifier("navigator.outline")
    }

    private func bookmarkRow(_ page: NotebookPage, at index: Int) -> some View {
        Button { open(index) } label: {
            HStack(spacing: Space.x3) {
                Image(systemName: "bookmark.fill").foregroundStyle(Color.mustard).accessibilityHidden(true)
                Text(page.bookmarkTitle(number: index + 1)).foregroundStyle(Color.ink)
                Spacer(minLength: Space.x3)
                Text(index + 1, format: .number).monospacedDigit().foregroundStyle(Color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.surface)
        .accessibilityLabel(Text("\(page.bookmarkTitle(number: index + 1)), page \(index + 1)"))
        .accessibilityHint(Text("Opens this page"))
        .swipeActions {
            if !document.isReadOnly {
                Button(role: .destructive) { document.setBookmark(nil, forPage: page.id) } label: { Label("Remove", systemImage: "bookmark.slash") }
                Button { name = page.bookmark ?? ""; renaming = page.id } label: { Label("Rename", systemImage: "pencil") }
            }
        }
        .contextMenu {
            if !document.isReadOnly {
                Button { name = page.bookmark ?? ""; renaming = page.id } label: { Label("Rename…", systemImage: "pencil") }
                Button(role: .destructive) { document.setBookmark(nil, forPage: page.id) } label: { Label("Remove Bookmark", systemImage: "bookmark.slash") }
            }
        }
    }

    @ViewBuilder
    private func contentsRow(_ entry: OutlineEntry) -> some View {
        if let index = document.index(of: entry.pageID) {
            Button { open(index) } label: {
                HStack(spacing: Space.x3) {
                    Text(entry.title)
                        .font(entry.level == 0 ? .body.weight(.semibold) : .body)
                        .foregroundStyle(Color.ink)
                        .padding(.leading, CGFloat(entry.level) * Space.x4)
                    Spacer(minLength: Space.x3)
                    Text(index + 1, format: .number).monospacedDigit().foregroundStyle(Color.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.surface)
            .accessibilityLabel(Text("\(entry.title), page \(index + 1)"))
            .accessibilityHint(Text("Opens this page"))
        }
    }
}
