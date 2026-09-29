import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct Shelf: Identifiable {
    let id: String
    let title: String
    let records: [NotebookRecord]
}

struct ShelfView: View {
    let scope: LibraryScope
    let zoomNamespace: Namespace.ID
    let onOpen: (NotebookRecord) -> Void
    let onCreate: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var records: [NotebookRecord]
    @Query(sort: \FolderRecord.sortIndex) private var folders: [FolderRecord]
    @AppStorage("librarySort") private var sort: LibrarySortOrder = .opened
    @AppStorage("libraryGrouping") private var grouping: LibraryGrouping = .recency
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var importingPDF = false
    @State private var renaming: NotebookRecord?
    @State private var renameText = ""
    @State private var confirmingEmptyTrash = false
    @State private var errorMessage: String?

    private var folder: FolderRecord? {
        if case .folder(let id) = scope { return folders.first { $0.id == id } }
        return nil
    }

    private var title: String {
        switch scope {
        case .all: String(localized: "All notebooks")
        case .favorites: String(localized: "Favourites")
        case .trash: String(localized: "Recently deleted")
        case .folder: folder?.name ?? String(localized: "Folder")
        }
    }

    private var visible: [NotebookRecord] {
        let scoped = records.filter { record in
            switch scope {
            case .all: !record.isTrashed
            case .favorites: !record.isTrashed && record.isFavorite
            case .trash: record.isTrashed
            case .folder(let id): !record.isTrashed && record.folder?.id == id
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let searched = query.isEmpty ? scoped : scoped.filter {
            $0.title.localizedStandardContains(query) || $0.searchText.localizedStandardContains(query)
        }
        return searched.sorted(by: sort)
    }

    var body: some View {
        let visible = visible
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleList(visible)
            } else {
                shelves(visible)
            }
        }
        .background(Color.paper)
        .overlay { if visible.isEmpty { emptyState } }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: Text("Search notebooks and handwriting"))
        .toolbar { toolbar(visible) }
        .toolbar { if isSelecting { selectionBar(visible) } }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            Task { await importPDFs(result) }
        }
        .alert("Rename Notebook", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let renaming { store.rename(renaming, to: renameText) } }
        }
        .confirmationDialog("Delete all notebooks in Recently Deleted?", isPresented: $confirmingEmptyTrash, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { store.deletePermanently(visible) }
        } message: {
            Text("This can't be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil || store.lastError != nil },
                                                           set: { if !$0 { errorMessage = nil; store.clearError() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? store.lastError ?? "")
        }
        .onChange(of: scope) { _, _ in endSelection() }
    }

    // MARK: Shelves

    private func shelves(_ visible: [NotebookRecord]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.x6) {
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(title)
                        .font(.display(40, relativeTo: .largeTitle))
                        .foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle(visible.count)).metaStyle(.footnote)
                }
                if scope == .all, searchText.isEmpty, !isSelecting, let recent = records.filter({ !$0.isTrashed && $0.lastOpenedAt != nil })
                    .max(by: { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }) {
                    ContinueWritingSpread(record: recent) { onOpen(recent) }
                }
                ForEach(groups(visible)) { shelf in
                    VStack(alignment: .leading, spacing: Space.x4) {
                        ShelfLabel(title: shelf.title)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 188), spacing: Space.x6, alignment: .top)],
                                  alignment: .leading, spacing: Space.x8) {
                            ForEach(shelf.records) { record in item(record) }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.x8)
            .padding(.vertical, Space.x6)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func item(_ record: NotebookRecord) -> some View {
        NotebookCoverItem(record: record, isSelecting: isSelecting, isSelected: selection.contains(record.id),
                          zoomNamespace: zoomNamespace) {
            if isSelecting { toggle(record) } else if !record.isTrashed { onOpen(record) }
        }
        .contextMenu { if !isSelecting { menu(for: record) } }
        .draggable(NotebookReference(id: record.id)) {
            Text(record.title).padding(Space.x2).background(Color.surface, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func accessibleList(_ visible: [NotebookRecord]) -> some View {
        List {
            ForEach(visible) { record in
                Button {
                    if isSelecting { toggle(record) } else if !record.isTrashed { onOpen(record) }
                } label: {
                    HStack(spacing: Space.x4) {
                        RecordCover(record: record, width: CoverWidth.row).frame(width: 48)
                        VStack(alignment: .leading, spacing: Space.x1) {
                            Text(record.title).font(.headline).foregroundStyle(Color.ink)
                            Text(record.metaLine).font(.subheadline).foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                        if isSelecting {
                            Image(systemName: selection.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityLabel(record.accessibilityDescription)
                .accessibilityIdentifier("notebook.\(record.title)")
                .accessibilityAddTraits(selection.contains(record.id) ? .isSelected : [])
                .contextMenu { if !isSelecting { menu(for: record) } }
                .listRowBackground(Color.surface)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func subtitle(_ count: Int) -> String {
        if isSelecting { return String(localized: "Select notebooks to move, favourite or delete") }
        if scope == .trash { return String(localized: "Deleted notebooks stay here for 30 days") }
        let notebooks = count == 1 ? String(localized: "1 notebook") : String(localized: "\(count) notebooks")
        return "\(notebooks) · \(sort.summary)"
    }

    private func groups(_ visible: [NotebookRecord]) -> [Shelf] {
        guard !visible.isEmpty else { return [] }
        if !searchText.isEmpty { return [Shelf(id: "results", title: String(localized: "Results"), records: visible)] }
        if scope == .trash || sort == .title { return [Shelf(id: "all", title: sort == .title ? String(localized: "A to Z") : title, records: visible)] }
        if grouping == .folder, case .folder = scope {} else if grouping == .folder {
            var shelves: [Shelf] = folders.compactMap { folder in
                let items = visible.filter { $0.folder?.id == folder.id }
                return items.isEmpty ? nil : Shelf(id: folder.id.uuidString, title: folder.name, records: items)
            }
            let loose = visible.filter { $0.folder == nil }
            if !loose.isEmpty { shelves.append(Shelf(id: "loose", title: String(localized: "Not on a shelf"), records: loose)) }
            return shelves
        }
        let calendar = Calendar.current
        let now = Date.now
        var buckets: [(key: String, title: String, records: [NotebookRecord])] = []
        for record in visible {
            let date = sort.date(of: record)
            let (key, title): (String, String) = {
                if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return ("week", String(localized: "This week")) }
                if calendar.isDate(date, equalTo: now, toGranularity: .month) { return ("month", String(localized: "Earlier this month")) }
                let month = calendar.dateComponents([.year, .month], from: date)
                return ("\(month.year ?? 0)-\(month.month ?? 0)", date.formatted(.dateTime.month(.wide).year()))
            }()
            if let index = buckets.firstIndex(where: { $0.key == key }) { buckets[index].records.append(record) } else { buckets.append((key, title, [record])) }
        }
        return buckets.map { Shelf(id: $0.key, title: $0.title, records: $0.records) }
    }

    // MARK: Selection

    private func toggle(_ record: NotebookRecord) {
        if selection.contains(record.id) { selection.remove(record.id) } else { selection.insert(record.id) }
    }

    private func endSelection() {
        isSelecting = false
        selection = []
    }

    private func selected(_ visible: [NotebookRecord]) -> [NotebookRecord] { visible.filter { selection.contains($0.id) } }

    @ToolbarContentBuilder
    private func selectionBar(_ visible: [NotebookRecord]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if scope == .trash {
                Button("Restore") { store.restore(selected(visible)); endSelection() }.disabled(selection.isEmpty)
                Spacer()
                Button("Delete", role: .destructive) { store.deletePermanently(selected(visible)); endSelection() }.disabled(selection.isEmpty)
            } else {
                Button { store.setFavorite(true, for: selected(visible)); endSelection() } label: { Label("Favourite", systemImage: "star") }
                    .disabled(selection.isEmpty)
                Menu {
                    Button("Not on a shelf") { store.move(selected(visible), to: nil); endSelection() }
                    ForEach(folders) { folder in Button(folder.name) { store.move(selected(visible), to: folder); endSelection() } }
                } label: { Label("Move", systemImage: "folder") }
                    .disabled(selection.isEmpty)
                Spacer()
                Button(role: .destructive) { store.moveToTrash(selected(visible)); endSelection() } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selection.isEmpty)
            }
        }
    }

    // MARK: Toolbar and menus

    @ToolbarContentBuilder
    private func toolbar(_ visible: [NotebookRecord]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isSelecting {
                Button("Done") { endSelection() }
                    .accessibilityLabel(selection.isEmpty ? String(localized: "Done") : String(localized: "\(selection.count) selected, done"))
            } else {
                if scope == .trash {
                    Button("Empty", role: .destructive) { confirmingEmptyTrash = true }.disabled(visible.isEmpty)
                } else {
                    Menu {
                        Picker("Sort By", selection: $sort) {
                            ForEach(LibrarySortOrder.allCases) { Text($0.displayName).tag($0) }
                        }
                        Picker("Group By", selection: $grouping) {
                            ForEach(LibraryGrouping.allCases) { Text($0.displayName).tag($0) }
                        }
                    } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                    Menu {
                        Button { onCreate() } label: { Label("New Notebook", systemImage: "book.closed") }
                        Button { importingPDF = true } label: { Label("Import PDF…", systemImage: "doc.richtext") }
                    } label: {
                        Label("New", systemImage: "plus")
                    } primaryAction: {
                        onCreate()
                    }
                }
                Button("Select") { isSelecting = true }.disabled(visible.isEmpty)
            }
        }
        if isSelecting {
            ToolbarItem(placement: .status) {
                Text(selection.count == 1 ? String(localized: "1 selected") : String(localized: "\(selection.count) selected"))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
    }

    @ViewBuilder
    private func menu(for record: NotebookRecord) -> some View {
        if record.isTrashed {
            Button { store.restore([record]) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { store.deletePermanently([record]) } label: { Label("Delete Permanently", systemImage: "trash") }
        } else {
            Button { onOpen(record) } label: { Label("Open", systemImage: "book") }
            Button { renameText = record.title; renaming = record } label: { Label("Rename", systemImage: "pencil") }
            Button { store.setFavorite(!record.isFavorite, for: [record]) } label: {
                Label(record.isFavorite ? "Unfavourite" : "Favourite", systemImage: record.isFavorite ? "star.slash" : "star")
            }
            Menu {
                Button { store.move([record], to: nil) } label: { Label("Not on a shelf", systemImage: record.folder == nil ? "checkmark" : "tray") }
                ForEach(folders) { folder in
                    Button { store.move([record], to: folder) } label: {
                        Label(folder.name, systemImage: record.folder?.id == folder.id ? "checkmark" : "folder")
                    }
                }
            } label: { Label("Move to Shelf", systemImage: "folder") }
            Button {
                Task { do { try await store.duplicate(record) } catch { errorMessage = error.localizedDescription } }
            } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Divider()
            Button(role: .destructive) { store.moveToTrash([record]) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if scope == .trash {
            EmptyShelf(title: String(localized: "Nothing in the bin"), message: String(localized: "Deleted notebooks stay here for 30 days."))
        } else if scope == .favorites {
            EmptyShelf(title: String(localized: "No favourites yet"), message: String(localized: "Touch and hold a notebook, then choose Favourite."))
        } else {
            EmptyShelf(title: String(localized: "Every notebook starts with a blank page."),
                       message: String(localized: "Create a notebook to start writing, or import a PDF to annotate.")) {
                Button("New Notebook", action: onCreate).buttonStyle(.borderedProminent)
                Button("Import PDF") { importingPDF = true }
            }
        }
    }

    private func importPDFs(_ result: Result<[URL], Error>) async {
        do {
            for url in try result.get() { _ = try await store.importPDF(from: url, folder: folder) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension LibrarySortOrder {
    func date(of record: NotebookRecord) -> Date {
        switch self {
        case .opened: record.lastOpenedAt ?? record.modifiedAt
        case .modified, .title: record.modifiedAt
        case .created: record.createdAt
        }
    }
}

extension Array where Element == NotebookRecord {
    func sorted(by order: LibrarySortOrder) -> [NotebookRecord] {
        switch order {
        case .title: sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        default: sorted { order.date(of: $0) > order.date(of: $1) }
        }
    }
}

struct ShelfLabel: View {
    let title: String
    var body: some View {
        HStack(spacing: Space.x3) {
            Text(title).metaStyle(.footnote).fixedSize().accessibilityAddTraits(.isHeader)
            Rectangle().fill(Color.hairline).frame(height: 1).accessibilityHidden(true)
        }
    }
}

struct EmptyShelf<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    init(title: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: Space.x4) {
            Text(title)
                .font(.display(30, relativeTo: .title))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.displayText(17, relativeTo: .body))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.inkSecondary)
            HStack(spacing: Space.x3) { actions }
        }
        .frame(maxWidth: 420)
        .padding(Space.x8)
    }
}
