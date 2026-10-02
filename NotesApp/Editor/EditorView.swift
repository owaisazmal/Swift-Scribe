import SwiftUI
import PhotosUI
import PencilKit
import UniformTypeIdentifiers

/// What the chrome needs from the page canvas, whatever its implementation.
@MainActor
protocol EditorCanvasControlling: AnyObject {
    func scrollToPage(_ index: Int, animated: Bool)
    func setToolPickerVisible(_ visible: Bool)
    func setToolPickerSuppressed(_ suppressed: Bool)
    func setDrawingPolicy(_ policy: PKCanvasViewDrawingPolicy)
    func fit(_ fit: PageFit)
    func setPresenting(_ presenting: Bool)
    func present(page index: Int)
    func setLaserColor(_ color: LaserColor)
    func visibleCenter(ofPage index: Int) -> CGPoint?
    func select(_ selection: ItemSelection?)
    func editText()
}

struct ItemSelection: Equatable {
    let pageID: UUID
    let itemID: UUID
}

enum PageFit { case width, page }

/// Focus hides the chrome and leaves the tools; presenting hides both and turns the Pencil into a laser pointer.
enum EditorMode: Equatable { case writing, focus, presenting }

@MainActor
@Observable
final class EditorSession {
    let document: NotebookDocument
    let recorder: NotebookRecorder
    var currentPage: Int
    var isToolPickerVisible = true
    var canUndo = false
    var canRedo = false
    /// The picture, sticker, text box or link being arranged. The canvas owns it; it's mirrored here for the chrome.
    var selection: ItemSelection?
    var isEditingText = false
    /// The page a link was followed from, while the page it opened is still showing.
    private(set) var linkReturn: UUID?
    private(set) var mode = EditorMode.writing
    var laserColor = LaserColor.red {
        didSet { canvas?.setLaserColor(laserColor) }
    }
    var drawingInput: DrawingInput {
        didSet {
            UserDefaults.standard.set(drawingInput.rawValue, forKey: SettingsKey.drawingInput)
            canvas?.setDrawingPolicy(drawingInput.policy)
        }
    }
    @ObservationIgnored weak var canvas: EditorCanvasControlling?

    init(document: NotebookDocument, initialPageID: UUID? = nil) {
        self.document = document
        recorder = NotebookRecorder(document: document)
        let saved = document.manifest.library.currentPage
        currentPage = max(0, min(initialPageID.flatMap(document.index(of:)) ?? saved, document.pages.count - 1))
        drawingInput = UserDefaults.standard.string(forKey: SettingsKey.drawingInput).flatMap(DrawingInput.init(rawValue:)) ?? .system
    }

    func pageDidChange(_ index: Int) {
        guard index != currentPage else { return }
        currentPage = index
        linkReturn = nil
        document.noteCurrentPage(index)
    }

    func go(to index: Int, animated: Bool = true) {
        guard document.pages.indices.contains(index) else { return }
        canvas?.scrollToPage(index, animated: animated)
        pageDidChange(index)
    }

    func enter(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        mode = newMode
        canvas?.setPresenting(newMode == .presenting)
    }

    /// A page forward or back. While presenting, each page is shown whole.
    func step(_ delta: Int) {
        let index = min(max(currentPage + delta, 0), document.pages.count - 1)
        guard index != currentPage else { return }
        if mode == .presenting {
            canvas?.present(page: index)
        } else {
            go(to: index)
        }
    }

    // MARK: Links

    func addLink(to target: UUID) {
        let link = PageLink(target: target)
        addItem(.link(link), size: PageLinkArt.size(for: LinkTitles(pages: document.pages).title(for: link)), actionName: String(localized: "Add Link"))
    }

    /// Opens the page a link points at and remembers where it was followed from.
    func follow(_ link: PageLink, from origin: UUID) {
        guard let index = document.index(of: link.target) else {
            AccessibilityNotification.Announcement(String(localized: "The page this link opened was deleted")).post()
            return
        }
        canvas?.select(nil)
        show(index)
        linkReturn = document.index(of: origin) == index ? nil : origin
    }

    func goBack() {
        guard let index = linkReturn.flatMap(document.index(of:)) else { return dismissLinkReturn() }
        show(index)
    }

    func dismissLinkReturn() { linkReturn = nil }

    private func show(_ index: Int) {
        if mode == .presenting {
            canvas?.present(page: index)
        } else {
            go(to: index)
        }
    }

    func setLinkLabel(_ label: String) {
        guard let selection else { return }
        document.updateItems(onPage: selection.pageID, actionName: String(localized: "Rename Link")) { items in
            guard let index = items.firstIndex(where: { $0.id == selection.itemID }), var link = items[index].link else { return }
            link.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            items[index].content = .link(link)
        }
    }

    // MARK: Text boxes

    static let addTextAction = String(localized: "Add Text Box")

    /// Places an empty text box and starts typing in it.
    func addText() {
        guard !document.isReadOnly, document.pages.indices.contains(currentPage) else { return }
        let box = TextBox(string: "")
        let width = min(280, (document.pages[currentPage].size.width * 0.6).rounded())
        addItem(.text(box), size: CGSize(width: width, height: box.height(width: width)), actionName: Self.addTextAction)
        canvas?.editText()
    }

    func updateText(_ change: (inout TextBox) -> Void) {
        guard let selection else { return }
        document.updateItems(onPage: selection.pageID, actionName: String(localized: "Text Style")) { items in
            guard let index = items.firstIndex(where: { $0.id == selection.itemID }), var box = items[index].text else { return }
            change(&box)
            items[index].content = .text(box)
            items[index] = items[index].fittedToText()
        }
    }

    var selectedItem: PageItem? {
        guard let selection, let page = document.pages.first(where: { $0.id == selection.pageID }) else { return nil }
        return page.items.first { $0.id == selection.itemID }
    }

    // MARK: Pictures and stickers

    /// Places a new item and selects it: where it was dropped, or in the middle of what's showing of the current page.
    func addItem(_ content: PageItem.Content, size: CGSize, onPage index: Int? = nil, at point: CGPoint? = nil,
                 actionName: String = String(localized: "Add to Page"), source: String? = nil) {
        let index = index ?? currentPage
        guard !document.isReadOnly, document.pages.indices.contains(index) else { return }
        let page = document.pages[index]
        var centre = point ?? canvas?.visibleCenter(ofPage: index) ?? CGPoint(x: page.size.width / 2, y: page.size.height / 2)
        // Never exactly on top of the last one placed.
        let taken = page.items.map(\.center)
        while taken.contains(where: { abs($0.x - centre.x) < 6 && abs($0.y - centre.y) < 6 }), centre.y + 28 < page.size.height {
            centre = CGPoint(x: min(centre.x + 28, page.size.width), y: centre.y + 28)
        }
        var item = PageItem(content: content, center: centre, size: size)
        item.source = source
        document.updateItems(onPage: page.id, actionName: actionName) { $0.append(item) }
        canvas?.select(ItemSelection(pageID: page.id, itemID: item.id))
    }

    /// Stores a picture in the notebook and places it on a page, sized to sit comfortably on it.
    func addPicture(_ data: Data, onPage index: Int? = nil, at point: CGPoint? = nil) async throws {
        guard let image = UIImage(data: data) else { throw ImportError.unreadable }
        try await addPicture(image, onPage: index, at: point)
    }

    func addPicture(_ image: UIImage, onPage index: Int? = nil, at point: CGPoint? = nil) async throws {
        let picture = try await Task.detached(priority: .userInitiated) { try PhotoImport.picture(image) }.value
        let file = try await document.package.writeAsset(picture.data, ext: picture.ext)
        let index = index ?? currentPage
        guard document.pages.indices.contains(index) else { return }
        let page = document.pages[index].size
        let fit = min(page.width * 0.55 / picture.size.width, page.height * 0.4 / picture.size.height)
        addItem(.image(file: file), size: CGSize(width: (picture.size.width * fit).rounded(), height: (picture.size.height * fit).rounded()),
                onPage: index, at: point)
    }

    /// Places one of the user's own stickers. The notebook keeps its own copy, and one copy serves every placement.
    func addSticker(_ sticker: CustomSticker) async throws {
        guard document.pages.indices.contains(currentPage) else { return }
        let placed = document.pages.lazy.filter(\.hasItems).flatMap(\.items).first { $0.source == sticker.id && $0.assetFile != nil }
        var file = placed?.assetFile, shape = placed?.size
        if let name = file, !FileManager.default.fileExists(atPath: document.package.assetURL(name).path(percentEncoded: false)) { file = nil }
        if file == nil {
            let url = sticker.url
            let picture = try await Task.detached(priority: .userInitiated) {
                guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { throw ImportError.unreadable }
                return try PhotoImport.picture(image)
            }.value
            file = try await document.package.writeAsset(picture.data, ext: picture.ext)
            shape = picture.size
        }
        guard let file, let shape, document.pages.indices.contains(currentPage) else { return }
        let page = document.pages[currentPage].size
        let fit = min(150, page.width * 0.4) / max(shape.width, shape.height, 1)
        addItem(.image(file: file), size: CGSize(width: (shape.width * fit).rounded(), height: (shape.height * fit).rounded()), source: sticker.id)
    }

    func deleteSelection() {
        guard let selection else { return }
        canvas?.select(nil)
        document.updateItems(onPage: selection.pageID, actionName: String(localized: "Delete")) { $0.removeAll { $0.id == selection.itemID } }
    }

    func duplicateSelection() {
        guard let selection, let page = document.pages.first(where: { $0.id == selection.pageID }),
              var copy = page.items.first(where: { $0.id == selection.itemID }) else { return }
        copy.id = UUID()
        copy.raw = [:]
        copy.center = CGPoint(x: min(copy.center.x + 24, page.size.width), y: min(copy.center.y + 24, page.size.height))
        document.updateItems(onPage: selection.pageID, actionName: String(localized: "Duplicate")) { $0.append(copy) }
        canvas?.select(ItemSelection(pageID: selection.pageID, itemID: copy.id))
    }

    /// One step forward or back in the page's stack of pictures and stickers.
    func moveSelection(forward: Bool) {
        guard let selection else { return }
        document.updateItems(onPage: selection.pageID, actionName: forward ? String(localized: "Bring Forward") : String(localized: "Send Backward")) { items in
            guard let index = items.firstIndex(where: { $0.id == selection.itemID }) else { return }
            let target = index + (forward ? 1 : -1)
            if items.indices.contains(target) { items.swapAt(index, target) }
        }
    }

    func toggleToolPicker() {
        isToolPickerVisible.toggle()
        canvas?.setToolPickerVisible(isToolPickerVisible)
    }

    func refreshUndoState() {
        canUndo = document.undoManager.canUndo
        canRedo = document.undoManager.canRedo
    }

    /// Inserts after `index` (or at the end) and makes the new page current.
    func addPage(after index: Int? = nil) {
        guard !document.isReadOnly else { return }
        let position = (index ?? document.pages.count - 1) + 1
        document.insertPages([document.newPage(after: index)], at: position)
        go(to: position)
    }

    func duplicatePage(at index: Int) async {
        if let position = await document.duplicatePage(at: index) { go(to: position) }
    }
}

struct EditorView: View {
    let document: NotebookDocument
    let close: () -> Void
    @State private var session: EditorSession

    init(document: NotebookDocument, initialPageID: UUID? = nil, close: @escaping () -> Void) {
        self.document = document
        self.close = close
        _session = State(initialValue: EditorSession(document: document, initialPageID: initialPageID))
    }

    var body: some View {
        EditorContent(session: session, close: close)
    }
}

fileprivate struct EditorContent: View {
    @Bindable var session: EditorSession
    let close: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingPages = false
    @State private var showingRecordings = false
    @State private var importingPDF = false
    @State private var showingPhotoPicker = false
    @State fileprivate var photoItem: PhotosPickerItem?
    @State private var export: ExportJob?
    @State private var confirmingDelete = false
    @State private var goToPage = false
    @State private var goToText = ""
    @State private var renaming = false
    @State private var titleText = ""
    @State fileprivate var errorMessage: String?
    @State private var ribbonWidth: CGFloat = 44
    @State private var paperMode: PaperDrawer.Mode?
    @State private var editingCover: NotebookRecord?
    @State private var knownPages: Set<UUID> = []
    @State private var photoBecomesPage = true
    @State private var showingStickers = false
    @State private var pickingLink = false
    @State private var renamingLink = false
    @State private var linkLabel = ""
    @State private var namingBookmark: UUID?
    @State private var bookmarkName = ""

    fileprivate var document: NotebookDocument { session.document }
    private var cloth: ClothColor { document.manifest.cover.cloth }

    var body: some View {
        NavigationStack {
            PageStack(session: session)
                .ignoresSafeArea(edges: .bottom)
                .background(Color.desk.ignoresSafeArea())
                .background {
                    Group {
                        Button("Page After Current") { session.addPage(after: session.currentPage) }
                            .keyboardShortcut("n", modifiers: .command)
                            .disabled(document.isReadOnly)
                        Button("Focus Mode") { enter(session.mode == .focus ? .writing : .focus) }
                            .keyboardShortcut("f", modifiers: [.command, .control])
                        Button("Present") { enter(session.mode == .presenting ? .writing : .presenting) }
                            .keyboardShortcut(.return, modifiers: [.command, .option])
                        if session.mode != .writing {
                            Button("Done") { enter(.writing) }.keyboardShortcut(.cancelAction)
                        }
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }
                .overlay(alignment: .topTrailing) {
                    switch session.mode {
                    case .writing: ribbons
                    case .focus: focusExit
                    case .presenting: EmptyView()
                    }
                }
                .overlay(alignment: .top) { banners }
                .overlay(alignment: .top) {
                    if session.selection != nil, session.mode != .presenting { arrangeBar } else if session.linkReturn != nil { returnBar }
                }
                .overlay(alignment: .bottom) { if session.mode == .presenting { presentationBar } }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar(session.mode == .writing ? .visible : .hidden, for: .navigationBar)
        }
        .statusBarHidden(session.mode != .writing)
        .persistentSystemOverlays(session.mode == .writing ? .automatic : .hidden)
        .sheet(isPresented: $showingPages) {
            PageNavigator(session: session)
        }
        .sheet(item: $export) { job in ExportSheet(job: job) }
        .sheet(item: $editingCover) { record in CoverEditorView(record: record) }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
            let position = session.currentPage + 1
            document.perform { await insertPDF(result, at: position) }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            let position = session.currentPage + 1
            let asPage = photoBecomesPage
            document.perform { if asPage { await insertPhoto(item, at: position) } else { await addPicture(item) } }
        }
        .sheet(isPresented: $showingStickers) {
            StickerDrawer { sticker in
                session.addItem(.sticker(sticker.rawValue), size: sticker.defaultSize)
                announce(String(localized: "\(sticker.displayName) added to the page"))
            } onPickOwn: { sticker in
                document.perform { await addSticker(sticker) }
            }
        }
        .sheet(isPresented: $pickingLink) {
            LinkPicker(session: session) { target in
                session.addLink(to: target)
                announce(String(localized: "Link added to the page"))
            }
        }
        .alert("Rename Link", isPresented: $renamingLink) {
            TextField("Page name", text: $linkLabel)
            Button("Cancel", role: .cancel) {}
            Button("Save") { session.setLinkLabel(linkLabel) }
        } message: {
            Text("Leave it empty to name the link after its page.")
        }
        .confirmationDialog("Delete page \(session.currentPage + 1)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Page", role: .destructive) {
                if document.pages.indices.contains(session.currentPage) { document.removePages([document.pages[session.currentPage].id]) }
            }
        } message: {
            Text("You can undo this.")
        }
        .alert("Go to Page", isPresented: $goToPage) {
            TextField("Page", text: $goToText).keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Go") { if let number = Int(goToText) { session.go(to: number - 1) } }
        } message: {
            Text("1 to \(document.pages.count)")
        }
        .alert("Name Bookmark", isPresented: Binding(get: { namingBookmark != nil }, set: { if !$0 { namingBookmark = nil } })) {
            TextField("Name", text: $bookmarkName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let namingBookmark { document.setBookmark(bookmarkName, forPage: namingBookmark) } }
        }
        .alert("Rename Notebook", isPresented: $renaming) {
            TextField("Title", text: $titleText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { document.rename(titleText) }
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil || session.recorder.errorMessage != nil },
                                                           set: { if !$0 { errorMessage = nil; session.recorder.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? session.recorder.errorMessage ?? "")
        }
        .onChange(of: isPresentingModal) { _, presenting in session.canvas?.setToolPickerSuppressed(presenting) }
        .onChange(of: session.recorder.isRecording) { _, recording in
            announce(recording ? String(localized: "Recording started") : String(localized: "Recording saved"))
        }
        .onChange(of: document.pages.count) { old, new in announcePages(from: old, to: new) }
        .onAppear {
            knownPages = Set(document.pages.map(\.id))
            document.noteCurrentPage(session.currentPage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in session.refreshUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in session.refreshUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in session.refreshUndoState() }
        .onDisappear { session.recorder.shutdown() }
        .onReceive(NotificationCenter.default.publisher(for: .scribeShowPage)) { note in
            guard (note.object as? UUID) == document.id, let page = note.userInfo?["page"] as? UUID, let index = document.index(of: page) else { return }
            session.go(to: index)
        }
    }

    private var isPresentingModal: Bool {
        showingPages || showingRecordings || export != nil || importingPDF || showingPhotoPicker || renaming || goToPage || paperMode != nil
            || editingCover != nil || namingBookmark != nil || showingStickers || pickingLink || renamingLink
    }

    private func enter(_ mode: EditorMode) {
        guard !isPresentingModal else { return }
        withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { session.enter(mode) }
        switch mode {
        case .writing: announce(String(localized: "Back to writing"))
        case .focus: announce(String(localized: "Focus mode. The toolbar is hidden."))
        case .presenting: announce(String(localized: "Presenting. Drag on the page to point."))
        }
    }

    fileprivate func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    private func announcePages(from old: Int, to new: Int) {
        let ids = document.pages.map(\.id), total = document.pageCountText
        if new == old + 1, let added = ids.firstIndex(where: { !knownPages.contains($0) }) {
            announce(String(localized: "Page \(added + 1) added. \(total)"))
        } else if new > old {
            announce(String(localized: "\(new - old) pages added. \(total)"))
        } else if new == old - 1 {
            announce(String(localized: "Page deleted. \(total)"))
        } else if new < old {
            announce(String(localized: "\(old - new) pages deleted. \(total)"))
        }
        knownPages = Set(ids)
    }

    // MARK: Chrome

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { session.canvas?.select(nil); session.recorder.shutdown(); close() } label: { Label("Library", systemImage: "chevron.backward") }
                .keyboardShortcut("w", modifiers: .command)
                .accessibilityIdentifier("editor.back")
        }
        ToolbarItem(placement: .principal) { titleMenu }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { document.undoManager.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut(isPresentingModal || session.isEditingText ? nil : KeyboardShortcut("z", modifiers: .command))
                .disabled(!session.canUndo)
                .accessibilityIdentifier("editor.undo")
            Button { document.undoManager.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .keyboardShortcut(isPresentingModal || session.isEditingText ? nil : KeyboardShortcut("z", modifiers: [.command, .shift]))
                .disabled(!session.canRedo)
                .accessibilityIdentifier("editor.redo")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            addMenu
            recordButton
            recordingsButton
            Button { session.toggleToolPicker() } label: {
                Label(session.isToolPickerVisible ? "Hide Tools" : "Show Tools",
                      systemImage: session.isToolPickerVisible ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
            }
            .disabled(document.isReadOnly)
            moreMenu
        }
    }

    private var titleMenu: some View {
        Menu {
            Button { titleText = document.title; renaming = true } label: { Label("Rename…", systemImage: "pencil") }
                .disabled(document.isReadOnly)
            if !document.isReadOnly {
                Button { editingCover = store.record(document.id) } label: { Label("Change Cover…", systemImage: "book.closed") }
            }
            Button { export = ExportJob(document: document) } label: { Label("Export as PDF…", systemImage: "square.and.arrow.up") }
        } label: {
            HStack(spacing: Space.x2) {
                SpineChip(cloth: cloth)
                Text(document.title).font(.headline).foregroundStyle(Color.ink).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityLabel(Text("\(document.title), notebook options"))
        .accessibilityIdentifier("editor.title")
    }

    private var recordingsButton: some View {
        Button { showingRecordings = true } label: { Label("Recordings", systemImage: "waveform") }
            .popover(isPresented: $showingRecordings) {
                RecordingList(recorder: session.recorder)
                    .frame(minWidth: 320, minHeight: 280)
                    .presentationBackground(Color.surface)
                    .presentationCompactAdaptation(.sheet)
            }
    }

    fileprivate var currentPage: NotebookPage? {
        document.pages.indices.contains(session.currentPage) ? document.pages[session.currentPage] : nil
    }

    private func toggleBookmark() {
        guard let page = currentPage, !document.isReadOnly else { return }
        document.setBookmark(page.bookmark == nil ? "" : nil, forPage: page.id)
        announce(page.bookmark == nil ? String(localized: "Page bookmarked") : String(localized: "Bookmark removed"))
    }

    private var ribbons: some View {
        HStack(alignment: .top, spacing: Space.x1) {
            bookmarkRibbon
            ribbon
        }
        .padding(.trailing, Space.x8)
    }

    /// A slim ribbon beside the page number: mustard once the page is bookmarked.
    private var bookmarkRibbon: some View {
        let page = currentPage, marked = page?.bookmark != nil
        return Button(action: toggleBookmark) {
            Image(systemName: marked ? "bookmark.fill" : "bookmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(marked ? Color.onMustard : Color.textSecondary)
                .frame(width: 28)
                .padding(.top, Space.x2)
                .padding(.bottom, Space.x2 + 28 * RibbonShape.notch)
                .background { marked ? Color.mustard : Color.surface }
                .clipShape(RibbonShape())
                .overlay { if !marked { RibbonShape().stroke(Color.hairline, lineWidth: 1) } }
                .shadow(color: .black.opacity(marked ? 0.15 : 0.06), radius: 1, y: 1)
                .frame(width: 44, height: 44, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(document.isReadOnly)
        .keyboardShortcut(isPresentingModal ? nil : KeyboardShortcut("d", modifiers: .command))
        .contextMenu {
            if let page, marked, !document.isReadOnly {
                Button { bookmarkName = page.bookmark ?? ""; namingBookmark = page.id } label: { Label("Name Bookmark…", systemImage: "pencil") }
                Button(role: .destructive) { document.setBookmark(nil, forPage: page.id) } label: { Label("Remove Bookmark", systemImage: "bookmark.slash") }
            }
        }
        .animation(Motion.adaptive(Motion.ribbon, reduceMotion: reduceMotion), value: marked)
        .accessibilityLabel(Text(marked ? "Remove Bookmark" : "Bookmark Page"))
        .accessibilityValue(Text(marked ? (page?.bookmarkTitle(number: session.currentPage + 1) ?? "") : ""))
        .accessibilityIdentifier("editor.bookmark")
    }

    private var ribbon: some View {
        let page = min(session.currentPage + 1, document.pages.count), count = document.pages.count
        return Button { showingPages = true } label: {
            VStack(spacing: 0) {
                Text(page, format: .number)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(page)))
                Text("of \(count)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(count)))
            }
            .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: page)
            .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: count)
            .foregroundStyle(cloth.onCloth)
            .padding(.horizontal, Space.x2)
            .padding(.top, Space.x2)
            .frame(minWidth: 44)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ribbonWidth = $0 }
            .padding(.bottom, Space.x2 + ribbonWidth * RibbonShape.notch)
            .background { cloth.color }
            .clipShape(RibbonShape())
            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(isPresentingModal ? nil : KeyboardShortcut("p", modifiers: [.command, .shift]))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in goToText = ""; goToPage = true })
        .accessibilityLabel(Text("Page \(session.currentPage + 1) of \(document.pages.count)"))
        .accessibilityHint(Text("Opens the page navigator. Touch and hold to go to a page."))
        .accessibilityAction(named: Text("Go to page")) { goToText = ""; goToPage = true }
        .accessibilityIdentifier("editor.ribbon")
    }

    private var focusExit: some View {
        Button { enter(.writing) } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 44, height: 44)
                .background(Color.surface, in: Circle())
                .overlay { Circle().strokeBorder(Color.hairline) }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .padding(.trailing, Space.x5)
        .padding(.top, Space.x2)
        .accessibilityLabel(Text("Exit Focus Mode"))
        .accessibilityIdentifier("editor.focus.exit")
    }

    /// Shown while something on the page is selected. A text box and a link add their own controls in front.
    private var arrangeBar: some View {
        let item = session.selectedItem
        return HStack(spacing: 0) {
            if let box = item?.text {
                arrangeButton("Edit Text", "keyboard") { session.canvas?.editText() }
                    .disabled(session.isEditingText)
                    .accessibilityIdentifier("editor.arrange.edit")
                textStyleMenu(box)
            }
            if let link = item?.link {
                arrangeButton("Open Linked Page", "arrow.turn.down.right") {
                    if let page = session.selection?.pageID { session.follow(link, from: page) }
                }
                .disabled(document.index(of: link.target) == nil)
                .accessibilityIdentifier("editor.arrange.open")
                arrangeButton("Rename Link", "pencil") { linkLabel = link.label; renamingLink = true }
            }
            if sizeClass == .compact, item?.text != nil || item?.link != nil {
                Menu {
                    Button { session.duplicateSelection() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { session.moveSelection(forward: true) } label: { Label("Bring Forward", systemImage: "square.2.layers.3d.top.filled") }
                    Button { session.moveSelection(forward: false) } label: { Label("Send Backward", systemImage: "square.2.layers.3d.bottom.filled") }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("More"))
            } else {
                arrangeButton("Duplicate", "plus.square.on.square") { session.duplicateSelection() }
                arrangeButton("Bring Forward", "square.2.layers.3d.top.filled") { session.moveSelection(forward: true) }
                arrangeButton("Send Backward", "square.2.layers.3d.bottom.filled") { session.moveSelection(forward: false) }
            }
            arrangeButton("Delete", "trash") { session.deleteSelection() }
                .foregroundStyle(Color.tomato)
            Divider().frame(height: 24).padding(.horizontal, Space.x2)
            barDone { session.canvas?.select(nil) }
                .accessibilityIdentifier("editor.arrange.done")
        }
        .floatingBar()
        .padding(.top, Space.x2)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Arrange"))
        .accessibilityIdentifier("editor.arrange.bar")
    }

    private func textStyleMenu(_ box: TextBox) -> some View {
        Menu {
            Picker("Size", selection: Binding(get: { box.fontSize }, set: { size in session.updateText { $0.fontSize = size } })) {
                ForEach(TextBox.sizes, id: \.points) { Text($0.name).tag($0.points) }
            }
            Toggle(isOn: Binding(get: { box.isBold }, set: { bold in session.updateText { $0.isBold = bold } })) {
                Label("Bold", systemImage: "bold")
            }
            Picker("Colour", selection: Binding(get: { box.tint }, set: { tint in session.updateText { $0.tint = tint } })) {
                ForEach(TextBox.Tint.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Alignment", selection: Binding(get: { box.alignment }, set: { alignment in session.updateText { $0.alignment = alignment } })) {
                ForEach(TextBox.Alignment.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: "textformat.size").frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text("Text Style"))
        .accessibilityIdentifier("editor.arrange.style")
    }

    /// After a link was followed: the way back to the page it was on.
    @ViewBuilder
    private var returnBar: some View {
        if let index = session.linkReturn.flatMap(document.index(of:)) {
            HStack(spacing: 0) {
                Button { session.goBack() } label: {
                    Label("Back to Page \(index + 1)", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("editor.link.back")
                Button { session.dismissLinkReturn() } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)).frame(width: 44, height: 44) }
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityLabel(Text("Dismiss"))
            }
            .padding(.leading, Space.x2)
            .floatingBar()
            .padding(.top, Space.x2)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Filled, like the library slip's Undo.
    private func barDone(_ action: @escaping () -> Void) -> some View {
        Button("Done", action: action)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .prominentButton()
            .padding(.leading, Space.x1)
    }

    private func arrangeButton(_ title: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }
            .accessibilityLabel(Text(title))
    }

    private var presentationBar: some View {
        let page = min(session.currentPage + 1, document.pages.count), count = document.pages.count
        return HStack(spacing: Space.x2) {
            Button { session.step(-1) } label: { Image(systemName: "chevron.up").frame(width: 44, height: 44) }
                .disabled(page <= 1)
                .accessibilityLabel(Text("Previous Page"))
            Text("Page \(page) of \(count)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .fixedSize()
            Button { session.step(1) } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                .disabled(page >= count)
                .accessibilityLabel(Text("Next Page"))
                .accessibilityIdentifier("editor.present.next")
            Divider().frame(height: 24)
            if ExternalDisplay.shared.isShowing {
                Image(systemName: "tv")
                    .foregroundStyle(Color.ink)
                    .frame(width: 32, height: 44)
                    .accessibilityLabel(Text("Showing on the second screen"))
                    .accessibilityIdentifier("editor.present.screen")
            }
            Button {
                session.laserColor = session.laserColor == .red ? .green : .red
            } label: {
                Circle()
                    .fill(Color(uiColor: session.laserColor.uiColor))
                    .frame(width: 18, height: 18)
                    .overlay { Circle().strokeBorder(Color.ink.opacity(0.35)) }
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Laser Colour"))
            .accessibilityValue(Text(session.laserColor.displayName))
            barDone { enter(.writing) }
                .accessibilityIdentifier("editor.present.done")
        }
        .floatingBar()
        .padding(.bottom, Space.x5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.present.bar")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: Space.x2) {
            ForEach(document.notices) { notice in
                NoticeBanner(notice: notice) { document.dismissNotice(notice) }
            }
        }
        .padding(.top, Space.x2)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: document.notices)
    }

    @ViewBuilder
    private var recordButton: some View {
        let recorder = session.recorder
        if recorder.isRecording {
            let seconds = Int(recorder.elapsed)
            Button { recorder.stopRecording() } label: {
                HStack(spacing: Space.x2) {
                    Image(systemName: "stop.fill")
                        .symbolEffect(.breathe, options: .repeating, isActive: !reduceMotion)
                    if sizeClass != .compact {
                        Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(seconds)))
                            .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: seconds)
                    }
                }
                .foregroundStyle(Color.onTomato)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.tomato)
            .accessibilityLabel(Text("Stop Recording"))
            .accessibilityValue(Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))))
            .accessibilityIdentifier("editor.record")
        } else {
            Button { recorder.startRecording() } label: { Label("Record Audio", systemImage: "mic") }
                .disabled(document.isReadOnly)
                .accessibilityIdentifier("editor.record")
        }
    }

    private var addMenu: some View {
        Menu {
            Button { session.addPage(after: session.currentPage) } label: { Label("Page After Current", systemImage: "doc.badge.plus") }
            Button { session.addPage() } label: { Label("Page at End", systemImage: "arrow.down.doc") }
            Button { paperMode = .add(after: session.currentPage) } label: { Label("Choose Paper…", systemImage: "square.grid.3x3") }
            Divider()
            Button { importingPDF = true } label: { Label("Insert PDF…", systemImage: "doc.richtext") }
            Button { photoBecomesPage = true; showingPhotoPicker = true } label: { Label("Insert Photo…", systemImage: "photo") }
            Divider()
            Button { photoBecomesPage = false; showingPhotoPicker = true } label: { Label("Picture on This Page…", systemImage: "photo.on.rectangle.angled") }
            Button { showingStickers = true } label: { Label("Sticker…", systemImage: "seal") }
            Button { session.addText() } label: { Label("Text Box", systemImage: "character.textbox") }
            Button { pickingLink = true } label: { Label("Link to a Page…", systemImage: "link") }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .disabled(document.isReadOnly)
        .popover(item: Binding(get: { paperMode?.isAdding == true ? paperMode : nil }, set: { paperMode = $0 })) { mode in
            PaperDrawer(session: session, mode: mode)
                .presentationCompactAdaptation(.sheet)
                .presentationBackground(Color.surface)
        }
    }

    private var moreMenu: some View {
        Menu {
            let current = document.pages.indices.contains(session.currentPage) ? document.pages[session.currentPage] : nil
            if let current, current.template != nil, !document.isReadOnly {
                Button { paperMode = .change(pageID: current.id) } label: { Label("Change Paper…", systemImage: "paintpalette") }
            }
            Group {
                if let current, current.bookmark != nil {
                    Button { bookmarkName = current.bookmark ?? ""; namingBookmark = current.id } label: { Label("Name Bookmark…", systemImage: "bookmark") }
                } else {
                    Button(action: toggleBookmark) { Label("Bookmark Page", systemImage: "bookmark") }
                }
                Button { Task { await session.duplicatePage(at: session.currentPage) } } label: {
                    Label("Duplicate Page", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete Page", systemImage: "trash") }
            }
            .disabled(document.isReadOnly)
            Divider()
            Button { session.canvas?.fit(.width) } label: { Label("Fit Width", systemImage: "arrow.left.and.right") }
            Button { session.canvas?.fit(.page) } label: { Label("Fit Page", systemImage: "arrow.up.and.down") }
            Divider()
            Button { enter(.focus) } label: { Label("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right") }
            Button { enter(.presenting) } label: { Label("Present", systemImage: "play.rectangle") }
            Divider()
            Picker(selection: $session.drawingInput) {
                ForEach(DrawingInput.allCases) { Text($0.displayName).tag($0) }
            } label: { Label("Draw With", systemImage: "hand.draw") }
            .pickerStyle(.menu)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .popover(item: Binding(get: { paperMode?.isAdding == false ? paperMode : nil }, set: { paperMode = $0 })) { mode in
            PaperDrawer(session: session, mode: mode)
                .presentationCompactAdaptation(.sheet)
                .presentationBackground(Color.surface)
        }
    }

    // MARK: Import

    private func insertPDF(_ result: Result<URL, Error>, at position: Int) async {
        do {
            let url = try result.get()
            let file = try await document.package.importAsset(from: url, ext: "pdf")
            let assetURL = document.package.assetURL(file)
            let pages = try await Task.detached(priority: .userInitiated) { try PDFImport.pages(at: assetURL, file: file) }.value
            let position = min(position, document.pages.count)
            document.insertPages(pages, at: position, actionName: String(localized: "Insert PDF"))
            session.go(to: position)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func insertPhoto(_ item: PhotosPickerItem, at position: Int) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw ImportError.unreadable }
            let (jpeg, size) = try await Task.detached(priority: .userInitiated) { try PhotoImport.normalize(data) }.value
            let file = try await document.package.writeAsset(jpeg, ext: "jpg")
            let width = PageSize.letter.points.width
            let page = NotebookPage(background: .image(file: file), paperColor: .white,
                                    size: CGSize(width: width, height: (width * size.height / size.width).rounded()))
            let position = min(position, document.pages.count)
            document.insertPages([page], at: position, actionName: String(localized: "Insert Photo"))
            session.go(to: position)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension EditorContent {
    fileprivate func addSticker(_ sticker: CustomSticker) async {
        do {
            try await session.addSticker(sticker)
            announce(String(localized: "Sticker added to the page"))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Places a picture on the current page as something that can be moved, rather than as a new page.
    fileprivate func addPicture(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw ImportError.unreadable }
            try await session.addPicture(data)
            announce(String(localized: "Picture added to the page"))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    /// The capsule that floats over the page: the presenter's controls and the arrange bar.
    func floatingBar() -> some View {
        fontWeight(.semibold)
            .padding(.horizontal, Space.x4)
            .padding(.vertical, 2)
            .fixedSize()
            .background(Color.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.hairline) }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

enum PhotoImport {
    /// A picture for placing on a page: at most 1,600 px on the long side, PNG when it has transparency.
    static func picture(_ image: UIImage) throws -> (data: Data, size: CGSize, ext: String) {
        guard image.size.width > 0, image.size.height > 0 else { throw ImportError.unreadable }
        let scale = min(1, 1600 / max(image.size.width * image.scale, image.size.height * image.scale))
        let target = CGSize(width: (image.size.width * image.scale * scale).rounded(), height: (image.size.height * image.scale * scale).rounded())
        let alpha = image.cgImage?.alphaInfo ?? .none
        let transparent = ![.none, .noneSkipFirst, .noneSkipLast].contains(alpha)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !transparent
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let encoded = transparent ? renderer.pngData { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
                                  : renderer.jpegData(withCompressionQuality: 0.88) { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return (encoded, target, transparent ? "png" : "jpg")
    }

    /// Downscales to at most 2,400 px on the long side and re-encodes as JPEG, off the main thread.
    static func normalize(_ data: Data) throws -> (Data, CGSize) {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { throw ImportError.unreadable }
        let scale = min(1, 2400 / max(image.size.width, image.size.height))
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = normalized.jpegData(compressionQuality: 0.88) else { throw ImportError.unreadable }
        return (jpeg, target)
    }
}

struct RibbonShape: Shape {
    static let notch: CGFloat = 0.28

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addLines([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY),
                           CGPoint(x: rect.midX, y: rect.maxY - rect.width * Self.notch), CGPoint(x: rect.minX, y: rect.maxY)])
            path.closeSubpath()
        }
    }
}

struct NoticeBanner: View {
    let notice: DocumentNotice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.x3) {
            Image(systemName: notice.kind == .saveFailed ? "exclamationmark.icloud" : "info.circle")
                .foregroundStyle(notice.kind == .saveFailed ? Color.tomato : Color.accentColor)
            Text(notice.message).font(.subheadline).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
            if notice.kind != .saveFailed {
                Button(action: dismiss) { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.inkSecondary)
                    .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, Space.x4)
        .padding(.vertical, Space.x3)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.control))
        .overlay { RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.hairline) }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .padding(.horizontal, Space.x4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct RecordingList: View {
    let recorder: NotebookRecorder

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(recorder.recordings.enumerated()), id: \.element.id) { index, recording in
                    HStack(spacing: Space.x3) {
                        Button { recorder.togglePlayback(recording) } label: {
                            Image(systemName: recorder.playingID == recording.id ? "stop.circle.fill" : "play.circle.fill").font(.title)
                        }
                        .buttonStyle(.borderless)
                        .disabled(recorder.isRecording)
                        .accessibilityLabel(recorder.playingID == recording.id ? "Stop" : "Play")
                        VStack(alignment: .leading, spacing: Space.x1) {
                            Text("Recording \(index + 1)").font(.body.weight(.medium))
                            Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Color.textSecondary)
                            if recorder.playingID == recording.id { ProgressView(value: recorder.playbackProgress) }
                        }
                        Spacer()
                        Text(Duration.seconds(recording.duration).formatted(.time(pattern: .minuteSecond)))
                            .font(.callout.monospacedDigit()).foregroundStyle(Color.textSecondary)
                    }
                    .swipeActions {
                        if !recorder.isReadOnly {
                            Button(role: .destructive) { recorder.delete(recording) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
            .overlay {
                if recorder.recordings.isEmpty {
                    ScrollView {
                        ContentUnavailableView {
                            Label("No Recordings", systemImage: "waveform").foregroundStyle(Color.ink)
                        } description: {
                            Text("Tap the microphone to record a lecture or meeting alongside your notes.").foregroundStyle(Color.textSecondary)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .background(Color.surface)
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
