import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct Shelf: Identifiable {
    let id: String
    let title: String
    let records: [NotebookRecord]
    var cloth: ClothColor?
}

struct ShelfView: View {
    let scope: LibraryScope
    let zoomNamespace: Namespace.ID
    let onOpen: (NotebookRecord) -> Void
    let onOpenPage: (NotebookRecord, UUID) -> Void
    let onOpenZoomed: (NotebookRecord, UUID?, String) -> Void
    let onCreate: () -> Void
    let onQuickNote: () -> Void
    let onWhiteboard: () -> Void
    let isCovered: Bool

    @Environment(LibraryStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.undoManager) private var undoManager
    @Environment(LibraryChangeCenter.self) private var changes
    @Query private var records: [NotebookRecord]
    @Query(sort: \FolderRecord.sortIndex) private var folders: [FolderRecord]
    @AppStorage(SettingsKey.librarySort) private var sort: LibrarySortOrder = .opened
    @AppStorage("libraryGrouping") private var grouping: LibraryGrouping = .recency
    @AppStorage(SettingsKey.dailyJournalID) private var journalID = ""
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
    @State private var scanning = false
    @State private var renaming: NotebookRecord?
    @State private var renameText = ""
    @State private var confirmingEmptyTrash = false
    @State private var errorMessage: String?
    @State private var shelfWidth: CGFloat?
    @State private var showsBarTitle = false
    @FocusState private var searchFocused: Bool
    @State private var barRoom = CGFloat.infinity
    @State private var actionsWidth: CGFloat = 0

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

    private var tree: FolderTree { FolderTree(folders: folders) }

    /// A folder shows what is in it and in the folders inside it.
    private var visible: [NotebookRecord] {
        let inside: Set<UUID> = if case .folder(let id) = scope { tree.subtree(id) } else { [] }
        let scoped = records.filter { record in
            switch scope {
            case .all: !record.isTrashed
            case .favorites: !record.isTrashed && record.isFavorite
            case .trash: record.isTrashed
            case .folder: !record.isTrashed && record.folder.map { inside.contains($0.id) } ?? false
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
            LibraryIndex.notebookIDs(matching: query, in: ModelContext(container))
        }.value
        guard !Task.isCancelled else { return }
        // What is written in a locked notebook isn't searched: only its title can match.
        let locked = records.filter(\.isLocked)
        let hidden = Set(locked.filter { !$0.title.localizedStandardContains(query) }.map(\.id))
        matches = found.subtracting(hidden)
        guard scope != .trash else { pageHits = [:]; return }
        let closed = Set(locked.map(\.id))
        let ordered = visible.map(\.id).filter { found.contains($0) && !closed.contains($0) }
        let hits = await PageSearch.hits(for: query, in: ordered, root: store.root)
        guard !Task.isCancelled else { return }
        withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { pageHits = hits }
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if !searchInBar {
                searchField
                    .padding(.horizontal, Space.x8)
                    .padding(.bottom, Space.x2)
                    .background(Color.paper)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            let frame = proxy.frame(in: .global)
            return frame.width - (frame.minX > 1 ? 0 : 130)
        } action: { barRoom = $0 }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleDisplayMode(.inline)
        .barGround(.paper)
        .background(SearchActivator(isSearching: searchFocused, isCovered: isCovered) { searchFocused = true })
        .toolbar { toolbar(visible) }
        .toolbar { if isSelecting { selectionBar(visible) } }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            Task { await importPDFs(result) }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                importScan(images)
            }
            .ignoresSafeArea()
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
        .alert(permanentDeleteTitle, isPresented: Binding(get: { !changes.pendingPermanentDelete.isEmpty },
                                                          set: { if !$0 { changes.pendingPermanentDelete = [] } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) { confirmPermanentDelete() }
        } message: {
            Text("This can't be undone.")
        }
        .overlay(alignment: .bottom) { slip }
        .task(id: changes.current?.id) {
            guard changes.current != nil, !voiceOver else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { changes.dismiss() }
        }
        .onChange(of: isCovered) { _, covered in if covered { changes.dismiss() } }
    }

    // MARK: Shelves

    private func shelves(_ visible: [NotebookRecord]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.x6) {
                LibraryHeader(title: title, summary: subtitle(visible), showsRhythm: showsRhythm, onOpenPage: onOpenPage)
                if let recent = continueCandidate {
                    OpenBookSpread(record: recent, zoomNamespace: zoomNamespace) { onOpenZoomed(recent, nil, $0) }
                        .id("spread-\(recent.id.uuidString)")
                }
                if scope == .all, searchText.isEmpty, !isSelecting { DeskCards(records: records, zoomNamespace: zoomNamespace, onOpen: onOpenZoomed) }
                if !searchText.isEmpty, !pageHits.isEmpty, scope != .trash {
                    PageHitsSection(records: visible, hits: pageHits, query: hitsQuery, zoomNamespace: zoomNamespace, onOpen: onOpenZoomed)
                        .transition(.opacity)
                }
                ForEach(groups(visible)) { shelf in
                    ShelfLabel(title: shelf.title, cloth: shelf.cloth)
                        .padding(.top, Space.x2)
                    if let shelfWidth {
                        let metrics = ShelfMetrics.fit(width: shelfWidth)
                        ForEach(shelf.records.chunked(into: metrics.columns), id: \.rowID) { row in
                            ShelfRow(items: row, metrics: metrics) { record in item(record, width: metrics.coverWidth) }
                                .padding(.bottom, Space.x2)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 188), spacing: Space.x6, alignment: .top)],
                                  alignment: .leading, spacing: Space.x8) {
                            ForEach(shelf.records) { record in item(record, width: CoverWidth.shelf) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shelfWidth = $0 }
            .padding(.horizontal, Space.x8)
            .padding(.vertical, Space.x6)
        }
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 56 } action: { showsBarTitle = $1 }
    }

    /// The notebook to reopen at the top of All notebooks: the last one opened.
    private var continueCandidate: NotebookRecord? {
        guard scope == .all, searchText.isEmpty, !isSelecting else { return nil }
        return records.filter { !$0.isTrashed && !$0.isLocked && $0.lastOpenedAt != nil && $0.id.uuidString != journalID }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    private func item(_ record: NotebookRecord, width: CGFloat) -> some View {
        NotebookCoverItem(record: record, width: width, isSelecting: isSelecting, isSelected: selection.contains(record.id),
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
            if showsRhythm { WeekSummarySection(onOpenPage: onOpenPage) }
            if let recent = continueCandidate {
                Button { onOpen(recent) } label: {
                    HStack(spacing: Space.x4) {
                        RecordCover(record: recent, width: CoverWidth.row, showsShadow: false).frame(width: 48)
                        VStack(alignment: .leading, spacing: Space.x1) {
                            Text("Continue writing").font(.footnote.weight(.bold).smallCaps()).tracking(0.8).foregroundStyle(Color.accentColor)
                            Text(recent.title).font(.headline).foregroundStyle(Color.ink)
                            Text("Page \(recent.currentPage + 1) of \(recent.pageCount)").font(.subheadline).foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .accessibilityLabel(Text("Continue writing \(recent.title), page \(recent.currentPage + 1) of \(recent.pageCount)"))
                .accessibilityHint(Text("Opens at this page"))
                .listRowBackground(Color.surface)
            }
            if scope == .all, searchText.isEmpty, !isSelecting { DeskCards(records: records, zoomNamespace: zoomNamespace, asRows: true, onOpen: onOpenZoomed) }
            ForEach(visible) { record in
                Button {
                    if isSelecting { toggle(record) } else if !record.isTrashed { onOpen(record) }
                } label: {
                    HStack(spacing: Space.x4) {
                        RecordCover(record: record, width: CoverWidth.row, showsShadow: false).frame(width: 48)
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
                                Text(hit.title(in: record.title)).font(.headline).foregroundStyle(Color.ink)
                                Text(PageSearch.highlighted(hit.snippet, query: hitsQuery)).font(.subheadline).foregroundStyle(Color.textSecondary)
                            }
                        }
                        .accessibilityLabel(Text(hit.label(in: record.title)))
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

    private func subtitle(_ visible: [NotebookRecord]) -> String {
        if isSelecting { return String(localized: "Select notebooks to move, favourite or delete") }
        if scope == .trash { return String(localized: "Deleted notebooks stay here for 30 days") }
        let count = visible.count, pageCount = visible.reduce(0) { $0 + $1.pageCount }
        let notebooks = String(localized: "\(count) notebooks")
        let pages = String(localized: "\(pageCount) pages")
        return "\(notebooks) · \(pages) · \(sort.summary)"
    }

    /// This week's writing shows at the top of All notebooks, but not while searching or selecting.
    private var showsRhythm: Bool { scope == .all && searchText.isEmpty && !isSelecting }

    private func groups(_ visible: [NotebookRecord]) -> [Shelf] {
        guard !visible.isEmpty else { return [] }
        if !searchText.isEmpty { return [Shelf(id: "results", title: String(localized: "Results"), records: visible)] }
        if scope == .trash || sort == .title { return [Shelf(id: "all", title: sort == .title ? String(localized: "A to Z") : title, records: visible)] }
        let tree = tree
        var root: UUID?
        if case .folder(let id) = scope { root = id }
        // Inside a folder with nothing but its own notebooks, shelves by folder would be one shelf: recency says more.
        if grouping == .folder, root == nil || visible.contains(where: { $0.folder?.id != root }) {
            let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var shelves: [Shelf] = tree.ordered.compactMap { id in
                guard let folder = byID[id] else { return nil }
                let items = visible.filter { $0.folder?.id == id }
                return items.isEmpty ? nil : Shelf(id: id.uuidString, title: id == root ? folder.name : tree.path(of: id, from: root), records: items, cloth: folder.cloth)
            }
            let loose = visible.filter { $0.folder == nil }
            if !loose.isEmpty { shelves.append(Shelf(id: "loose", title: String(localized: "Not on a shelf"), records: loose)) }
            return shelves
        }
        let calendar = Calendar.current
        let now = Date.now
        var buckets: [(key: String, date: Date, records: [NotebookRecord])] = []
        var positions: [String: Int] = [:]
        for record in visible {
            let date = sort.date(of: record)
            let key = ShelfGrouping.bucket(for: date, now: now, calendar: calendar)
            if let index = positions[key] {
                buckets[index].records.append(record)
            } else {
                positions[key] = buckets.count
                buckets.append((key, date, [record]))
            }
        }
        return buckets.map { bucket in
            let title = switch bucket.key {
            case "today": String(localized: "Today")
            case "yesterday": String(localized: "Yesterday")
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
                Button("Restore") { changes.restore(selected(visible), in: store, undoManager: undoManager); endSelection() }
                    .buttonStyle(.scribe(.secondary, inBar: true))
                    .disabled(selection.isEmpty)
                Spacer()
                BarGroup {
                    Button(role: .destructive) { changes.requestPermanentDelete(selected(visible).map(\.id)) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .disabled(selection.isEmpty)
            } else {
                BarGroup {
                    Button { changes.setFavorite(true, for: selected(visible), in: store, undoManager: undoManager); endSelection() } label: {
                        Label("Favourite", systemImage: "star")
                    }
                    Menu {
                        Button("Not on a shelf") { move(selected(visible), to: nil); endSelection() }
                        ForEach(folders) { folder in Button(tree.path(of: folder.id)) { move(selected(visible), to: folder); endSelection() } }
                    } label: { Label("Move", systemImage: "folder") }
                }
                .disabled(selection.isEmpty)
                Spacer()
                BarGroup {
                    Button(role: .destructive) { changes.moveToTrash(selected(visible), in: store, undoManager: undoManager); endSelection() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .disabled(selection.isEmpty)
            }
        }
        .boardBackground()
    }

    // MARK: Toolbar and menus

    private var searchField: some View {
        ScribeSearchField("Search", text: $searchText, capsTextSize: searchInBar, identifier: "library.search", focus: $searchFocused)
    }

    /// A bar without room for the search field would drop it into the overflow menu, so there it sits under the bar.
    private var searchInBar: Bool { barRoom >= actionsWidth + 308 && !dynamicTypeSize.isAccessibilitySize }

    @ToolbarContentBuilder
    private func toolbar(_ visible: [NotebookRecord]) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            let shows = showsBarTitle || dynamicTypeSize.isAccessibilitySize
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .fixedSize(horizontal: dynamicTypeSize.isAccessibilitySize, vertical: false)
                .opacity(shows ? 1 : 0)
                .accessibilityHidden(!shows)
                .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: shows)
        }
        ToolbarItem(placement: .primaryAction) {
            if isSelecting {
                Button("Done") { endSelection() }
                    .buttonStyle(.scribe(.primary, inBar: true))
                    .accessibilityLabel(selection.isEmpty ? String(localized: "Done") : String(localized: "\(selection.count) selected, done"))
            } else {
                BarGroup {
                    if scope == .trash {
                        Button("Empty") { confirmingEmptyTrash = true }.disabled(visible.isEmpty)
                        Rectangle().fill(Color.hairline).frame(width: 1, height: 24)
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
                            Button { onWhiteboard() } label: { Label("Whiteboard", systemImage: "scribble.variable") }
                                .accessibilityIdentifier("library.new.board")
                            Button { importingPDF = true } label: { Label("Import PDF…", systemImage: "doc.richtext") }
                            if DocumentScan.isAvailable {
                                Button(action: startScan) { Label("Scan Documents…", systemImage: "doc.viewfinder") }
                            }
                        } label: {
                            Label("New", systemImage: "plus")
                        } primaryAction: {
                            onCreate()
                        }
                    }
                    Button("Select") { isSelecting = true }.disabled(visible.isEmpty)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { actionsWidth = $0 }
            }
        }
        .boardBackground()
        if searchInBar {
            ToolbarItem(placement: .primaryAction) { searchField.frame(width: 260) }
                .boardBackground()
        }
        if isSelecting {
            ToolbarItem(placement: .status) {
                Text("\(selection.count) selected")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.ink)
            }
            .boardBackground()
        }
    }

    @ViewBuilder
    private func trashActions(for record: NotebookRecord) -> some View {
        if record.isTrashed {
            Button("Restore") { changes.restore([record], in: store, undoManager: undoManager) }
            Button("Delete Permanently") { changes.requestPermanentDelete([record.id]) }
        }
    }

    @ViewBuilder
    private func menu(for record: NotebookRecord) -> some View {
        if record.isTrashed {
            Button { changes.restore([record], in: store, undoManager: undoManager) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            Button(role: .destructive) { changes.requestPermanentDelete([record.id]) } label: { Label("Delete Permanently", systemImage: "trash") }
        } else if record.isReadOnly {
            Button { onOpen(record) } label: { Label("Open", systemImage: "book") }
            Button { startExport(record, as: .pdf) } label: { Label("Export as PDF", systemImage: "square.and.arrow.up") }
            Button { startExport(record, as: .images) } label: { Label("Export as Images", systemImage: "photo.on.rectangle") }
            Text("Made with a newer version of Swift Scribe, so it can only be read here.")
        } else {
            Button { onOpen(record) } label: { Label("Open", systemImage: "book") }
            Button { renameText = record.title; renaming = record } label: { Label("Rename", systemImage: "pencil") }
            Button { changes.setFavorite(!record.isFavorite, for: [record], in: store, undoManager: undoManager) } label: {
                Label(record.isFavorite ? "Unfavourite" : "Favourite", systemImage: record.isFavorite ? "star.slash" : "star")
            }
            Menu {
                Button { move([record], to: nil) } label: { Label("Not on a shelf", systemImage: record.folder == nil ? "checkmark" : "tray") }
                ForEach(folders) { folder in
                    Button { move([record], to: folder) } label: {
                        Label(tree.path(of: folder.id), systemImage: record.folder?.id == folder.id ? "checkmark" : "folder")
                    }
                }
            } label: { Label("Move to Shelf", systemImage: "folder") }
            Button {
                Task { do { try await store.duplicate(record) } catch { errorMessage = error.localizedDescription } }
            } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { changeCover(record) } label: { Label("Change Cover…", systemImage: "book.closed") }
            Button { startExport(record, as: .pdf) } label: { Label("Export as PDF", systemImage: "square.and.arrow.up") }
            Button { startExport(record, as: .images) } label: { Label("Export as Images", systemImage: "photo.on.rectangle") }
            Toggle(isOn: Binding(get: { journalID == record.id.uuidString }, set: { journalID = $0 ? record.id.uuidString : "" })) {
                Label("Use as Daily Journal", systemImage: "calendar")
            }
            Button { toggleLock(record) } label: {
                Label(record.isLocked ? "Remove Lock…" : "Lock…", systemImage: record.isLocked ? "lock.open" : "lock")
            }
            Divider()
            Button(role: .destructive) { changes.moveToTrash([record], in: store, undoManager: undoManager) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func startExport(_ record: NotebookRecord, as format: ExportJob.Format) {
        let id = record.id, title = record.title, locked = record.isLocked
        Task {
            if locked, !(await NotebookLock.shared.confirm(String(localized: "Export “\(title)”"))) { return }
            do { export = try await ExportJob.forNotebook(id, root: store.root, format: format) } catch { errorMessage = error.localizedDescription }
        }
    }

    /// The cover editor can show a notebook's first page, so a locked notebook asks first.
    private func changeCover(_ record: NotebookRecord) {
        guard record.isLocked else { return editingCover = record }
        let title = record.title
        Task { if await NotebookLock.shared.confirm(String(localized: "Unlock “\(title)”")) { editingCover = record } }
    }

    private func toggleLock(_ record: NotebookRecord) {
        Task { if let failure = await store.toggleLock(record) { errorMessage = failure } }
    }

    // MARK: Safety net

    private func move(_ records: [NotebookRecord], to folder: FolderRecord?) {
        changes.move(records, to: folder, in: store, undoManager: undoManager)
    }

    private var permanentDeleteTitle: String {
        let ids = changes.pendingPermanentDelete
        guard let first = ids.first else { return "" }
        if ids.count > 1 { return String(localized: "Delete \(ids.count) notebooks permanently?") }
        let title = records.first { $0.id == first }?.title ?? ""
        return String(localized: "Delete “\(title)” permanently?")
    }

    private func confirmPermanentDelete() {
        let ids = Set(changes.pendingPermanentDelete)
        changes.confirmPermanentDelete(in: store)
        selection.subtract(ids)
        if isSelecting, selection.isEmpty { endSelection() }
    }

    private var slip: some View {
        ZStack {
            if let change = changes.current {
                LibrarySlipView(change: change) { changes.dismiss() }
                    .padding(.bottom, Space.x4)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: changes.current?.id)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if scope == .trash {
            EmptyShelf(title: String(localized: "Nothing in the bin"), message: String(localized: "Deleted notebooks stay here for 30 days."))
        } else if scope == .favorites {
            EmptyShelf(title: String(localized: "No favourites yet"), message: String(localized: "Touch and hold a notebook, then choose Favourite."),
                       illustration: { RibbonIllustration() })
        } else if case .folder = scope, let name = folder?.name {
            EmptyShelf(title: String(localized: "Nothing on \(name) yet."),
                       message: String(localized: "Drag notebooks onto \(name) in the sidebar, or start one here.")) {
                Button("New Notebook", action: onCreate).buttonStyle(.scribe(.primary))
            } illustration: {
                ShelfIllustration(cloth: nil)
            }
        } else {
            EmptyShelf(title: String(localized: "Your shelf is ready."),
                       message: String(localized: "Create a notebook to start writing, or import a PDF to annotate.")) {
                Button("New Notebook", action: onCreate).buttonStyle(.scribe(.primary))
                Button("Import PDF") { importingPDF = true }.buttonStyle(.scribe)
            } illustration: {
                ShelfIllustration()
            }
        }
    }

    private func startScan() {
        #if DEBUG
        if LaunchOptions.arguments.contains("-fakeScan") { return importScan(DocumentScan.samples()) }
        #endif
        scanning = true
    }

    private func importScan(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        Task {
            do {
                try await store.importScan(images, folder: folder)
                AccessibilityNotification.Announcement(String(localized: "\(images.count) pages scanned into a new notebook")).post()
            } catch {
                errorMessage = error.localizedDescription
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
    var cloth: ClothColor?
    var body: some View {
        HStack(spacing: Space.x3) {
            if let cloth { SpineChip(cloth: cloth) }
            Text(title).metaStyle(.footnote).fixedSize().accessibilityAddTraits(.isHeader)
            Rectangle().fill(Color.hairline).frame(height: 1).accessibilityHidden(true)
        }
    }
}

struct EmptyShelf<Actions: View, Illustration: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let message: String
    @ViewBuilder var actions: Actions
    @ViewBuilder var illustration: Illustration

    init(title: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() },
         @ViewBuilder illustration: () -> Illustration = { EmptyView() }) {
        self.title = title
        self.message = message
        self.actions = actions()
        self.illustration = illustration()
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
            illustration
            Text(title)
                .displayFont(30, relativeTo: .title)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
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

/// Holds first responder while the library is in front, so ⌘F reaches the search field and ⌘Z the library's undo.
private struct SearchActivator: UIViewRepresentable {
    let isSearching: Bool
    let isCovered: Bool
    let onFind: () -> Void
    @Environment(\.undoManager) private var undoManager

    func makeUIView(context: Context) -> ActivatorView { ActivatorView() }

    /// Acts only on changes, so ordinary library updates never move first responder.
    func updateUIView(_ view: ActivatorView, context: Context) {
        view.onFind = onFind
        view.libraryUndoManager = undoManager
        if isCovered != view.wasCovered {
            view.wasCovered = isCovered
            view.isCovered = isCovered
            DispatchQueue.main.async { if isCovered { view.resignFirstResponder() } else { view.reclaimFirstResponder() } }
        }
        guard isSearching != view.wasSearching else { return }
        view.wasSearching = isSearching
        if !isSearching { DispatchQueue.main.async { view.reclaimFirstResponder() } }
    }

    final class ActivatorView: UIView {
        var onFind: (() -> Void)?
        var wasSearching = false
        var wasCovered = false
        var isCovered = false
        weak var libraryUndoManager: UndoManager?

        override var canBecomeFirstResponder: Bool { !isCovered }

        override var keyCommands: [UIKeyCommand]? {
            guard !isCovered else { return [] }
            let commands = [
                UIKeyCommand(title: String(localized: "Search Library"), action: #selector(findRequested), input: "f", modifierFlags: .command),
                UIKeyCommand(title: String(localized: "Undo"), action: #selector(undoLibraryChange), input: "z", modifierFlags: .command),
                UIKeyCommand(title: String(localized: "Redo"), action: #selector(redoLibraryChange), input: "z", modifierFlags: [.command, .shift]),
            ]
            for command in commands { command.wantsPriorityOverSystemBehavior = true }
            return commands
        }

        @objc private func findRequested() { if !isCovered { onFind?() } }

        @objc private func undoLibraryChange() { libraryUndoManager?.undo() }

        @objc private func redoLibraryChange() { libraryUndoManager?.redo() }

        override func find(_ sender: Any?) { findRequested() }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            switch action {
            case #selector(undoLibraryChange): !isCovered && libraryUndoManager?.canUndo == true
            case #selector(redoLibraryChange): !isCovered && libraryUndoManager?.canRedo == true
            default: (action == #selector(find(_:)) && !isCovered) || super.canPerformAction(action, withSender: sender)
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            NotificationCenter.default.removeObserver(self, name: UITextField.textDidEndEditingNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(textDidEndEditing(_:)), name: UITextField.textDidEndEditingNotification, object: nil)
            DispatchQueue.main.async { self.reclaimFirstResponder() }
        }

        @objc private func textDidEndEditing(_ note: Notification) {
            guard (note.object as? UIView)?.window === window else { return }
            DispatchQueue.main.async { self.reclaimFirstResponder() }
        }

        /// Takes ⌘F back once a field stops editing, unless the user has gone straight into another one.
        func reclaimFirstResponder() {
            guard !isCovered, let window else { return }
            if let field = UIResponder.current as? UIView, field is UITextInput, field.window === window { return }
            becomeFirstResponder()
        }
    }
}

private extension UIResponder {
    private static weak var found: UIResponder?

    /// Whatever holds first responder in the app right now.
    static var current: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(scribeCaptureFirstResponder), to: nil, from: nil, for: nil)
        return found
    }

    @objc private func scribeCaptureFirstResponder() { UIResponder.found = self }
}
