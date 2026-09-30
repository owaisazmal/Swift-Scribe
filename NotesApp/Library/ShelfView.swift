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
    let onOpenPage: (NotebookRecord, UUID) -> Void
    let onCreate: () -> Void
    let onQuickNote: () -> Void
    @Binding var isSearching: Bool
    let isCovered: Bool

    @Environment(LibraryStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var records: [NotebookRecord]
    @Query(sort: \FolderRecord.sortIndex) private var folders: [FolderRecord]
    @AppStorage(SettingsKey.librarySort) private var sort: LibrarySortOrder = .opened
    @AppStorage("libraryGrouping") private var grouping: LibraryGrouping = .recency
    @State private var searchText = ""
    @State private var matches: Set<UUID>?
    @State private var pageHits: [UUID: [PageHit]] = [:]
    @State private var hitsQuery = ""
    @State private var searchPending = false
    @State private var export: ExportJob?
    @State private var editingCover: NotebookRecord?
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
        let searched = matches.map { found in scoped.filter { found.contains($0.id) } } ?? scoped
        return searched.sorted(by: sort)
    }

    /// Matches titles and handwriting on a background context, a moment after typing stops, so neither the
    /// keystroke nor a library full of PDF text ever scans on the main thread.
    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            matches = nil
            pageHits = [:]
            searchPending = false
            return
        }
        if query != hitsQuery { pageHits = [:] }
        searchPending = true
        defer { if !Task.isCancelled { searchPending = false } }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let container = context.container
        let found = await Task.detached(priority: .userInitiated) { () -> Set<UUID> in
            let background = ModelContext(container)
            let descriptor = FetchDescriptor<NotebookRecord>(predicate: #Predicate {
                $0.title.localizedStandardContains(query) || $0.searchText.localizedStandardContains(query)
            })
            return Set(((try? background.fetch(descriptor)) ?? []).map(\.id))
        }.value
        guard !Task.isCancelled else { return }
        matches = found
        guard scope != .trash else { pageHits = [:]; return }
        let ordered = visible.map(\.id).filter(found.contains)
        let hits = await PageSearch.hits(for: query, in: ordered, root: store.root)
        guard !Task.isCancelled else { return }
        pageHits = hits
        hitsQuery = query
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
        .overlay { if visible.isEmpty, !searchPending { emptyState } }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $searchText, isPresented: $isSearching, prompt: Text("Search"))
        .background(SearchActivator(isRequested: $isSearching, isCovered: isCovered))
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
        .task(id: "\(store.searchVersion)|\(records.count)|\(scope)|\(searchText)") { await runSearch() }
        .sheet(item: $export) { job in ExportSheet(job: job) }
        .sheet(item: $editingCover) { record in CoverEditorView(record: record) }
    }

    // MARK: Shelves

    private func shelves(_ visible: [NotebookRecord]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.x6) {
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(title)
                        .displayFont(40, relativeTo: .largeTitle)
                        .foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle(visible.count)).metaStyle(.footnote)
                }
                if scope == .all, searchText.isEmpty, !isSelecting, let recent = records.filter({ !$0.isTrashed && $0.lastOpenedAt != nil })
                    .max(by: { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }) {
                    ContinueWritingSpread(record: recent) { onOpen(recent) }
                }
                if !searchText.isEmpty, !pageHits.isEmpty, scope != .trash {
                    PageHitsSection(records: visible, hits: pageHits, onOpen: onOpenPage)
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
                          zoomNamespace: zoomNamespace, showsFolder: scope == .all || scope == .favorites) {
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
                            Text(record.metaLine).font(.subheadline).foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        if isSelecting {
                            Image(systemName: selection.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityLabel(record.accessibilityDescription)
                .accessibilityHint(record.accessibilityHint(isSelecting: isSelecting))
                .accessibilityIdentifier("notebook.\(record.title)")
                .accessibilityAddTraits(selection.contains(record.id) ? .isSelected : [])
                .accessibilityActions { if !isSelecting { trashActions(for: record) } }
                .contextMenu { if !isSelecting { menu(for: record) } }
                .draggable(NotebookReference(id: record.id))
                .listRowBackground(Color.surface)
            }
            if !searchText.isEmpty, !pageHits.isEmpty, scope != .trash {
                Section {
                    ForEach(visible.flatMap { record in (pageHits[record.id] ?? []).map { (record, $0) } }, id: \.1.id) { record, hit in
                        Button { onOpenPage(record, hit.page.id) } label: {
                            VStack(alignment: .leading, spacing: Space.x1) {
                                Text("\(record.title), page \(hit.index + 1)").font(.headline).foregroundStyle(Color.ink)
                                Text(hit.snippet).font(.subheadline).foregroundStyle(Color.textSecondary)
                            }
                        }
                        .accessibilityLabel(Text("\(record.title), page \(hit.index + 1): \(hit.snippet)"))
                        .accessibilityHint(Text("Opens the notebook at this page"))
                        .listRowBackground(Color.surface)
                    }
                } header: {
                    Text("Pages").metaStyle(.footnote)
                }
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
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let month = calendar.dateInterval(of: .month, for: now)
        var buckets: [(key: String, date: Date, records: [NotebookRecord])] = []
        var positions: [String: Int] = [:]
        for record in visible {
            let date = sort.date(of: record)
            let key: String
            if week?.contains(date) == true {
                key = "week"
            } else if month?.contains(date) == true {
                key = "month"
            } else {
                let parts = calendar.dateComponents([.year, .month], from: date)
                key = "\(parts.year ?? 0)-\(parts.month ?? 0)"
            }
            if let index = positions[key] {
                buckets[index].records.append(record)
            } else {
                positions[key] = buckets.count
                buckets.append((key, date, [record]))
            }
        }
        return buckets.map { bucket in
            let title = switch bucket.key {
            case "week": String(localized: "This week")
            case "month": String(localized: "Earlier this month")
            default: bucket.date.formatted(.dateTime.month(.wide).year())
            }
            return Shelf(id: bucket.key, title: title, records: bucket.records)
        }
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
                        Button { onQuickNote() } label: { Label("Quick Note", systemImage: "square.and.pencil") }
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
    private func trashActions(for record: NotebookRecord) -> some View {
        if record.isTrashed {
            Button("Restore") { store.restore([record]) }
            Button("Delete Permanently") { store.deletePermanently([record]) }
        }
    }

    @ViewBuilder
    private func menu(for record: NotebookRecord) -> some View {
        if record.isTrashed {
            Button { store.restore([record]) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { store.deletePermanently([record]) } label: { Label("Delete Permanently", systemImage: "trash") }
        } else if record.isReadOnly {
            Button { onOpen(record) } label: { Label("Open", systemImage: "book") }
            Button {
                Task { do { export = try await ExportJob.forNotebook(record.id, root: store.root) } catch { errorMessage = error.localizedDescription } }
            } label: { Label("Export as PDF", systemImage: "square.and.arrow.up") }
            Text("Made with a newer version of Swift Scribe, so it can only be read here.")
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
            Button { editingCover = record } label: { Label("Change Cover…", systemImage: "book.closed") }
            Button {
                Task { do { export = try await ExportJob.forNotebook(record.id, root: store.root) } catch { errorMessage = error.localizedDescription } }
            } label: { Label("Export as PDF", systemImage: "square.and.arrow.up") }
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
                Button("New Notebook", action: onCreate).prominentButton()
                Button("Import PDF") { importingPDF = true }.buttonStyle(.bordered)
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
    /// Reads each record's sort key once, rather than twice per comparison.
    func sorted(by order: LibrarySortOrder) -> [NotebookRecord] {
        switch order {
        case .title:
            map { ($0, $0.title) }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }.map(\.0)
        default:
            map { ($0, order.date(of: $0)) }.sorted { $0.1 > $1.1 }.map(\.0)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    init(title: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content.frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(spacing: Space.x4) {
            Text(title)
                .displayFont(30, relativeTo: .title)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ink)
            Text(message)
                .displayTextFont(17, relativeTo: .body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Space.x3)) : AnyLayout(HStackLayout(spacing: Space.x3))) {
                actions
            }
            .controlSize(.large)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 420)
        .padding(Space.x8)
        .frame(maxWidth: .infinity)
    }
}

/// Opens the navigation bar's search on ⌘F or when asked. On iPadOS 18+ the toolbar search is a button until
/// activated, SwiftUI's isPresented doesn't expand it, and the toolbar swallows ⌘F, so this view holds first
/// responder while the library is in front, claims ⌘F with priority, and activates the underlying search controller.
private struct SearchActivator: UIViewRepresentable {
    @Binding var isRequested: Bool
    let isCovered: Bool

    func makeUIView(context: Context) -> ActivatorView { ActivatorView() }

    /// Acts only on changes, so ordinary library updates never move first responder.
    func updateUIView(_ view: ActivatorView, context: Context) {
        view.onFind = { isRequested = true; view.activate() }
        if isCovered != view.wasCovered {
            view.wasCovered = isCovered
            view.isCovered = isCovered
            DispatchQueue.main.async { if isCovered { view.resignFirstResponder() } else { view.reclaimFirstResponder() } }
        }
        guard isRequested != view.wasRequested else { return }
        view.wasRequested = isRequested
        DispatchQueue.main.async {
            if isRequested { view.activate() } else { view.reclaimFirstResponder() }
        }
    }

    final class ActivatorView: UIView {
        var onFind: (() -> Void)?
        var wasRequested = false
        var wasCovered = false
        var isCovered = false

        override var canBecomeFirstResponder: Bool { !isCovered }

        override var keyCommands: [UIKeyCommand]? {
            guard !isCovered else { return [] }
            let find = UIKeyCommand(title: String(localized: "Search Library"), action: #selector(findRequested), input: "f", modifierFlags: .command)
            find.wantsPriorityOverSystemBehavior = true
            return [find]
        }

        @objc private func findRequested() { if !isCovered { onFind?() } }

        override func find(_ sender: Any?) { findRequested() }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            (action == #selector(find(_:)) && !isCovered) || super.canPerformAction(action, withSender: sender)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            NotificationCenter.default.removeObserver(self, name: UITextField.textDidEndEditingNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(textDidEndEditing(_:)), name: UITextField.textDidEndEditingNotification, object: nil)
            DispatchQueue.main.async { self.reclaimFirstResponder() }
        }

        @objc private func textDidEndEditing(_ note: Notification) {
            guard note.object as? UISearchTextField === searchController()?.searchBar.searchTextField else { return }
            DispatchQueue.main.async { self.reclaimFirstResponder() }
        }

        func activate() {
            guard !isCovered, let search = searchController() else { return }
            search.isActive = true
            search.searchBar.becomeFirstResponder()
        }

        /// Takes ⌘F back once search closes or loses focus, unless the user has gone straight back into the field.
        func reclaimFirstResponder() {
            guard !isCovered, window != nil, searchController()?.searchBar.searchTextField.isFirstResponder != true else { return }
            becomeFirstResponder()
        }

        fileprivate func searchController() -> UISearchController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController, let search = Self.searchController(near: controller) { return search }
                responder = current.next
            }
            return nil
        }

        private static func searchController(near controller: UIViewController) -> UISearchController? {
            var candidate: UIViewController? = controller
            while let current = candidate {
                if let search = current.navigationItem.searchController { return search }
                if let navigation = current as? UINavigationController, let search = navigation.topViewController?.navigationItem.searchController {
                    return search
                }
                candidate = current.parent
            }
            return nil
        }
    }
}
