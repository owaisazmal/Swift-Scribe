import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum LibrarySort: String, CaseIterable, Identifiable {
    case modified, created, title
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .modified: "Date Modified"
        case .created: "Date Created"
        case .title: "Title"
        }
    }
}

struct NotebookGridView: View {
    let scope: SidebarItem
    let folders: [Folder]
    @Binding var openNotebook: Notebook?

    @Environment(\.modelContext) private var context
    @Query private var allNotebooks: [Notebook]
    @AppStorage(SettingsKey.librarySort) private var sort: LibrarySort = .modified
    @State private var searchText = ""
    @State private var showingNewNotebook = false
    @State private var importingPDF = false
    @State private var renaming: Notebook?
    @State private var renameText = ""
    @State private var shareItem: ShareItem?
    @State private var confirmingEmptyTrash = false
    @State private var errorMessage: String?

    private var currentFolder: Folder? {
        if case .folder(let id) = scope { return folders.first { $0.id == id } }
        return nil
    }

    private var title: String {
        switch scope {
        case .all: "All Notes"
        case .favorites: "Favorites"
        case .trash: "Recently Deleted"
        case .folder: currentFolder?.name ?? "Folder"
        }
    }

    private var notebooks: [Notebook] {
        let scoped = allNotebooks.filter { notebook in
            switch scope {
            case .all: !notebook.isTrashed
            case .favorites: !notebook.isTrashed && notebook.isFavorite
            case .trash: notebook.isTrashed
            case .folder(let id): !notebook.isTrashed && notebook.folder?.id == id
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let searched = query.isEmpty ? scoped : scoped.filter {
            $0.title.localizedStandardContains(query) || $0.searchText.localizedStandardContains(query)
        }
        switch sort {
        case .modified: return searched.sorted { $0.modifiedAt > $1.modifiedAt }
        case .created: return searched.sorted { $0.createdAt > $1.createdAt }
        case .title: return searched.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        let notebooks = notebooks
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 24)], spacing: 28) {
                ForEach(notebooks) { notebook in
                    NotebookCard(notebook: notebook, showsFolder: scope == .all || scope == .favorites)
                        .onTapGesture {
                            if !notebook.isTrashed { openNotebook = notebook }
                        }
                        .contextMenu { menu(for: notebook) }
                        .draggable(notebook.id.uuidString)
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if notebooks.isEmpty { emptyState }
        }
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "Search titles and handwriting")
        .toolbar { toolbar }
        .sheet(isPresented: $showingNewNotebook) {
            NewNotebookSheet { title, template, color, size in
                openNotebook = NotebookActions.create(title: title, template: template, color: color, size: size,
                                                      folder: currentFolder, in: context)
            }
        }
        .sheet(item: $shareItem) { ActivityView(items: [$0.url]) }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            do {
                for url in try result.get() {
                    _ = try NotebookActions.importPDF(from: url, folder: currentFolder, in: context)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Rename Notebook", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { renaming?.title = name }
            }
        }
        .confirmationDialog("Delete all notebooks in Recently Deleted?", isPresented: $confirmingEmptyTrash, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                notebooks.forEach { NotebookActions.deletePermanently($0, in: context) }
            }
        } message: {
            Text("This can't be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if scope == .trash {
                Button("Empty", role: .destructive) { confirmingEmptyTrash = true }
                    .disabled(notebooks.isEmpty)
            } else {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.displayName).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                Menu {
                    Button { showingNewNotebook = true } label: { Label("New Notebook", systemImage: "book.closed") }
                    Button { quickCreate() } label: { Label("Quick Note", systemImage: "square.and.pencil") }
                    Divider()
                    Button { importingPDF = true } label: { Label("Import PDF…", systemImage: "doc.richtext") }
                } label: {
                    Label("New", systemImage: "plus")
                } primaryAction: {
                    showingNewNotebook = true
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for notebook: Notebook) -> some View {
        if notebook.isTrashed {
            Button { NotebookActions.restore(notebook) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { NotebookActions.deletePermanently(notebook, in: context) } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
        } else {
            Button { openNotebook = notebook } label: { Label("Open", systemImage: "book") }
            Button { renameText = notebook.title; renaming = notebook } label: { Label("Rename", systemImage: "pencil") }
            Button { notebook.isFavorite.toggle() } label: {
                Label(notebook.isFavorite ? "Unfavorite" : "Favorite", systemImage: notebook.isFavorite ? "star.slash" : "star")
            }
            Menu {
                Button { notebook.folder = nil } label: {
                    Label("No Folder", systemImage: notebook.folder == nil ? "checkmark" : "tray")
                }
                ForEach(folders) { folder in
                    Button { notebook.folder = folder } label: {
                        Label(folder.name, systemImage: notebook.folder?.id == folder.id ? "checkmark" : "folder")
                    }
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }
            Button { NotebookActions.duplicate(notebook, in: context) } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button {
                do { shareItem = ShareItem(url: try NotebookActions.exportPDF(notebook)) }
                catch { errorMessage = error.localizedDescription }
            } label: {
                Label("Export as PDF", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) { NotebookActions.moveToTrash(notebook) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if scope == .trash {
            ContentUnavailableView("No Deleted Notebooks", systemImage: "trash",
                                   description: Text("Deleted notebooks stay here for 30 days."))
        } else if scope == .favorites {
            ContentUnavailableView("No Favorites", systemImage: "star",
                                   description: Text("Long-press a notebook and choose Favorite."))
        } else {
            ContentUnavailableView {
                Label("No Notebooks Yet", systemImage: "pencil.and.scribble")
            } description: {
                Text("Create a notebook to start writing, or import a PDF to annotate.")
            } actions: {
                Button("New Notebook") { showingNewNotebook = true }
                    .buttonStyle(.borderedProminent)
                Button("Import PDF") { importingPDF = true }
            }
        }
    }

    private func quickCreate() {
        let defaults = UserDefaults.standard
        let template = defaults.string(forKey: SettingsKey.defaultTemplate).flatMap(PaperTemplate.init) ?? .narrowRuled
        let color = defaults.string(forKey: SettingsKey.defaultPaperColor).flatMap(PaperColor.init) ?? .white
        let size = defaults.string(forKey: SettingsKey.defaultPageSize).flatMap(PageSize.init) ?? .letter
        let title = "Note \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        openNotebook = NotebookActions.create(title: title, template: template, color: color, size: size,
                                              folder: currentFolder, in: context)
    }
}

struct NotebookCard: View {
    let notebook: Notebook
    let showsFolder: Bool
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(0.78, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.secondarySystemGroupedBackground)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if notebook.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(6)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(notebook.title.isEmpty ? "Untitled" : notebook.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(notebook.modifiedAt.formatted(.relative(presentation: .named)))
                    Text("·")
                    Text(notebook.pageCount == 1 ? "1 page" : "\(notebook.pageCount) pages")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if showsFolder, let folder = notebook.folder {
                    Label(folder.name, systemImage: "folder.fill")
                        .font(.caption2)
                        .foregroundStyle(folder.color.color)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .task(id: notebook.modifiedAt) {
            thumbnail = UIImage(contentsOfFile: NotebookStore.thumbnailURL(for: notebook.id).path)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
