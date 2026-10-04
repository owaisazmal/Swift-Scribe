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
    func linksDidChange()
    func showReplay(_ timeline: ReplayTimeline?, at time: TimeInterval)
    func paneBecameActive()
    func setSelectingInk(_ selecting: Bool)
    func catchInk(inside outline: [CGPoint])
    func duplicateInkSelection()
    func deleteInkSelection()
    func selectedInk() -> [PKDrawing]
    func selectedInkByPage() -> [(pageID: UUID, ink: PKDrawing)]
    func replaceInkSelection(with text: String) -> ItemSelection?
    func tapesDidChange()
    func setFinding(_ finding: Bool)
    func showFind(_ matches: [FindMatch], current: FindMatch?)
    func setZoomWindow(_ open: Bool)
    func useTool(_ preset: ToolPreset)
    func setSelectingText(_ selecting: Bool)
    func selectAllText()
    func highlightSelectedText(_ color: HighlightColor)
}

struct ItemSelection: Equatable {
    let pageID: UUID
    let itemID: UUID
}

enum PageFit { case width, page }

/// Focus hides the chrome and leaves the tools; presenting hides both and turns the Pencil into a laser pointer;
/// replaying plays a recording while the ink written during it appears as it was written; selecting picks ink out
/// across pages to move, copy or delete; finding looks for words and marks them on the pages; selecting text picks
/// out a PDF page's own words to copy or highlight.
enum EditorMode: Equatable { case writing, focus, presenting, replaying, selecting, finding, selectingText }

@MainActor
@Observable
final class EditorSession {
    let document: NotebookDocument
    let recorder: NotebookRecorder
    let finder: NotebookFinder
    var currentPage: Int
    var isToolPickerVisible = true
    var canUndo = false
    var canRedo = false
    /// The picture, sticker, text box or link being arranged. The canvas owns it; it's mirrored here for the chrome.
    var selection: ItemSelection?
    var isEditingText = false
    /// The whiteboard that is open on its own, if one is. The canvas owns it; it's mirrored here for the chrome.
    var openBoard: UUID?
    /// The pen, pencil or marker the picker has, for the favourite tools; nil while it has the eraser or the lasso.
    var currentTool: ToolPreset?
    /// The words selected on a PDF page, while its text is being selected. The canvas owns the selection.
    var selectedText: String?
    /// The page a link was followed from, while the page it opened is still showing.
    private(set) var linkReturn: UUID?
    private(set) var mode = EditorMode.writing
    /// How many strokes the lasso across pages has caught.
    var inkSelectionCount = 0
    /// The study tape that is lifted for now. It isn't saved: every strip is back in place when the notebook is opened again.
    private(set) var liftedTapes: Set<UUID> = []
    /// The recording being replayed with its ink, and what was said in it if it has been transcribed.
    private(set) var replay: ReplayTimeline?
    private(set) var replayLines: [Transcript.Line] = []
    /// The zoom window: a magnified strip at the foot of the editor for writing small and neat.
    private(set) var isZoomWindowOpen = false
    @ObservationIgnored private var replayPage: UUID?
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
    /// The titles of the notebooks this one links to. Nil until they've been looked up.
    @ObservationIgnored var notebookTitles: [UUID: String]? {
        didSet { if notebookTitles != oldValue { canvas?.linksDidChange() } }
    }
    /// Called when a touch lands on the pages, so a window showing two notebooks knows which one is being worked on.
    @ObservationIgnored var onTouchDown: (() -> Void)?
    /// Whether this is the pane being worked in: a double-tap of the Pencil reaches both panes of a window.
    @ObservationIgnored var isActivePane: () -> Bool = { true }
    @ObservationIgnored var openURL: (URL) -> Void = { UIApplication.shared.open($0) }
    /// Opens another notebook, at a page if the link names one; the last value is the page the link sits on.
    @ObservationIgnored var openNotebook: ((UUID, UUID?, UUID) -> Void)?

    init(document: NotebookDocument, initialPageID: UUID? = nil) {
        self.document = document
        recorder = NotebookRecorder(document: document)
        finder = NotebookFinder(document: document)
        let saved = document.manifest.library.currentPage
        currentPage = max(0, min(initialPageID.flatMap(document.index(of:)) ?? saved, document.pages.count - 1))
        drawingInput = UserDefaults.standard.string(forKey: SettingsKey.drawingInput).flatMap(DrawingInput.init(rawValue:)) ?? .system
        finder.startPage = { [weak self] in self?.currentPage ?? 0 }
        finder.onChange = { [weak self] in
            guard let self else { return }
            self.canvas?.showFind(self.finder.matches, current: self.finder.current)
        }
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
        guard newMode != mode, newMode != .replaying || replay != nil else { return }
        guard newMode != .selecting || !document.isReadOnly else { return }
        guard newMode != .selectingText || document.hasPDFPages else { return }
        if mode == .replaying { stopReplay() }
        if mode == .selecting { canvas?.setSelectingInk(false) }
        if mode == .selectingText { canvas?.setSelectingText(false) }
        if mode == .finding {
            finder.clear()
            canvas?.setFinding(false)
        }
        if newMode != .writing, newMode != .focus { setZoomWindow(false) }
        mode = newMode
        canvas?.setPresenting(newMode == .presenting)
        if newMode == .selecting { canvas?.setSelectingInk(true) }
        if newMode == .finding { canvas?.setFinding(true) }
        if newMode == .selectingText { canvas?.setSelectingText(true) }
    }

    /// Circle and hold: starts selecting with the ink inside `outline`, given in the page stack's points, already caught.
    func selectInk(inside outline: [CGPoint]) {
        guard mode == .writing || mode == .focus else { return }
        enter(.selecting)
        if mode == .selecting { canvas?.catchInk(inside: outline) }
    }

    // MARK: Zoom window

    func setZoomWindow(_ open: Bool) {
        guard open != isZoomWindowOpen, !open || (!document.isReadOnly && (mode == .writing || mode == .focus)) else { return }
        isZoomWindowOpen = open
        canvas?.setZoomWindow(open)
        AccessibilityNotification.Announcement(open ? String(localized: "Zoom window open. Write in the strip at the bottom.")
                                                    : String(localized: "Zoom window closed")).post()
    }

    /// The canvas closed it itself: its page was deleted, or its close button was pressed.
    func zoomWindowDidClose() {
        guard isZoomWindowOpen else { return }
        isZoomWindowOpen = false
        AccessibilityNotification.Announcement(String(localized: "Zoom window closed")).post()
    }

    // MARK: Replaying a recording

    /// Plays a recording from its start with the page as it was: ink written later in the recording is faint until
    /// the sound reaches it. Reads the pages written on during the recording, or every page for an older recording.
    func beginReplay(_ recording: RecordingEntry, at time: TimeInterval = 0) async -> Bool {
        guard mode != .presenting, mode != .replaying, !recorder.isRecording else { return false }
        let ids = recording.inkedPages?.filter { document.index(of: $0) != nil } ?? document.pages.map(\.id)
        var drawings: [UUID: PKDrawing] = [:]
        for id in ids { drawings[id] = await document.ink(id) }
        guard mode != .presenting, mode != .replaying, recorder.beginReplay(recording) else { return false }
        replay = ReplayTimeline(recording: recording, drawings: drawings)
        replayLines = recorder.transcript(for: recording)?.lines ?? []
        replayPage = nil
        recorder.onPlaybackTime = { [weak self] in self?.showReplay(at: $0) }
        enter(.replaying)
        showReplay(at: 0)
        if time > 0 { recorder.seek(to: time) }
        return true
    }

    /// Shows the ink as it was at `time`, and turns to the page being written on when that changes.
    func showReplay(at time: TimeInterval) {
        guard let replay else { return }
        canvas?.showReplay(replay, at: time)
        guard let page = replay.page(at: time), page != replayPage, let index = document.index(of: page) else { return }
        replayPage = page
        if index != currentPage { go(to: index) }
    }

    func seekReplay(to time: TimeInterval) {
        guard replay != nil else { return }
        recorder.seek(to: time)
    }

    private func stopReplay() {
        recorder.onPlaybackTime = nil
        recorder.stopPlayback()
        replay = nil
        replayLines = []
        canvas?.showReplay(nil, at: 0)
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

    func addLink(to target: UUID) { addLink(PageLink(target: target)) }

    func addLink(_ link: PageLink) {
        let title = LinkTitles(pages: document.pages, notebooks: notebookTitles).title(for: link)
        addItem(.link(link), size: PageLinkArt.size(for: title), actionName: String(localized: "Add Link"))
    }

    /// Opens what a link points at. For a page of this notebook it remembers where it was followed from.
    func follow(_ link: PageLink, from origin: UUID) {
        switch link.destination {
        case .page(let target):
            guard let index = document.index(of: target) else {
                AccessibilityNotification.Announcement(String(localized: "The page this link opened was deleted")).post()
                return
            }
            canvas?.select(nil)
            show(index)
            linkReturn = document.index(of: origin) == index ? nil : origin
        case .web(let url):
            canvas?.select(nil)
            openURL(url)
        case .notebook(let notebook, let page, _):
            canvas?.select(nil)
            openNotebook?(notebook, page, origin)
        }
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

    // MARK: Study tape

    func addTape() {
        let last = UserDefaults.standard.string(forKey: SettingsKey.tapeColor).flatMap(TapeColor.init(rawValue:)) ?? .mustard
        addItem(.tape(last), size: TapeArt.defaultSize, actionName: String(localized: "Add Study Tape"))
    }

    func toggleTape(_ id: UUID) {
        if liftedTapes.remove(id) == nil { liftedTapes.insert(id) }
        canvas?.tapesDidChange()
        AccessibilityNotification.Announcement(liftedTapes.contains(id) ? String(localized: "Tape lifted") : String(localized: "Tape put back")).post()
    }

    func coverAllTapes() {
        guard !liftedTapes.isEmpty else { return }
        liftedTapes = []
        canvas?.tapesDidChange()
    }

    func setTapeColor(_ color: TapeColor) {
        guard let selection else { return }
        UserDefaults.standard.set(color.rawValue, forKey: SettingsKey.tapeColor)
        document.updateItems(onPage: selection.pageID, actionName: String(localized: "Tape Colour")) { items in
            guard let index = items.firstIndex(where: { $0.id == selection.itemID }), items[index].tape != nil else { return }
            items[index].content = .tape(color)
        }
    }

    // MARK: Today's events

    /// Prints the day's events on the current page as a text box, which can then be moved, restyled or deleted.
    func addAgenda(_ events: [AgendaEvent], on day: Date = .now) {
        guard !document.isReadOnly, document.pages.indices.contains(currentPage) else { return }
        let page = document.pages[currentPage]
        var box = TextBox(string: Agenda.text(for: events, heading: page.day == nil ? day.formatted(.dateTime.weekday(.wide).day().month(.wide)) : nil))
        box.fontSize = 13
        let width = min(max(box.naturalWidth(limit: page.sheetSize.width * 0.6), 150), page.sheetSize.width * 0.6)
        addItem(.text(box), size: CGSize(width: width, height: box.height(width: width)), actionName: String(localized: "Add Today's Events"))
    }

    // MARK: Text boxes

    static let addTextAction = String(localized: "Add Text Box")

    /// Places an empty text box and starts typing in it.
    func addText() {
        guard !document.isReadOnly, document.pages.indices.contains(currentPage) else { return }
        let box = TextBox(string: "")
        let width = min(280, (document.pages[currentPage].sheetSize.width * 0.6).rounded())
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
        // A whiteboard is opened first, so the new thing lands in the part of it that is looked at.
        if page.isBoard { go(to: index, animated: false) }
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
        let page = document.pages[index].sheetSize
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
        let page = document.pages[currentPage].sheetSize
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

    /// Inserts a whiteboard after `index` (or at the end) and opens it. It takes the colour of the page before it.
    func addBoard(after index: Int? = nil) {
        guard !document.isReadOnly else { return }
        let position = (index ?? document.pages.count - 1) + 1
        let paper = document.newPage(after: index)
        document.insertPages([.board(template: .dotted, color: paper.paperColor)], at: position, actionName: String(localized: "Add Whiteboard"))
        go(to: position)
    }
}

struct EditorView: View {
    let document: NotebookDocument
    /// True while a locked notebook is behind its lock screen.
    var isCovered = false
    let close: () -> Void
    @State private var session: EditorSession

    init(document: NotebookDocument, initialPageID: UUID? = nil, isCovered: Bool = false, close: @escaping () -> Void) {
        self.document = document
        self.isCovered = isCovered
        self.close = close
        _session = State(initialValue: EditorSession(document: document, initialPageID: initialPageID))
    }

    var body: some View {
        EditorContent(session: session, isCovered: isCovered, close: close)
    }
}

fileprivate struct EditorContent: View {
    @Bindable var session: EditorSession
    var isCovered = false
    let close: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(FlashcardLibrary.self) private var flashcards
    @Environment(EditorWindow.self) private var window: EditorWindow?
    @Environment(\.editorPane) private var pane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var paneWidth: CGFloat = 1024
    @State private var pickingBeside = false
    @State private var showingRecordingsSheet = false
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
    @State private var editingNotes: NotesTarget?
    @State private var presenterPanel: Bool?
    @State private var presentingSince = Date.now
    @State private var readingInk: InkToRead?
    @State private var hidesTranscript = false
    @State private var scanning = false
    @State private var showingDeck = false
    @State private var cardDraft: CardDraft?
    @State private var studyGuide: StudyGuideRequest?
    @State private var showingBoardGuide = false
    @State private var tagging: TagTarget?
    @AppStorage(SettingsKey.whiteboardTipSeen) private var boardTipSeen = false
    @AppStorage(SettingsKey.showsToolTray) private var showsToolTray = true
    @State private var highlightColor = HighlightColor.last
    @State private var findText = ""
    @FocusState private var findFocused: Bool
    @ScaledMetric(relativeTo: .body) private var findWidth: CGFloat = 260
    @ScaledMetric(relativeTo: .body) private var compactFindWidth: CGFloat = 190
    @State private var undoGroupWidth: CGFloat = 96
    @State private var buttonGroupWidth: CGFloat = 232

    private struct NotesTarget: Identifiable {
        let id: UUID
    }

    private struct InkToRead: Identifiable {
        let id = UUID()
        let ink: [PKDrawing]
    }

    /// Notes and the next page sit beside the page while a second screen shows it, or when asked for.
    private var showsPresenterPanel: Bool {
        session.mode == .presenting && !isCompact && (presenterPanel ?? ExternalDisplay.shared.isShowing)
    }

    /// What was said sits beside the page while a transcribed recording is replayed.
    private var showsTranscriptPanel: Bool {
        session.mode == .replaying && !isCompact && !session.replayLines.isEmpty && !hidesTranscript
    }

    /// A pane beside another notebook has about half a window: its bar keeps the essentials and the rest move into More.
    private var isNarrow: Bool { paneWidth < 620 }
    private var isCompact: Bool { sizeClass == .compact || isNarrow }

    /// The favourite tools stand beside the page while it can be written on, where there is room for them.
    private var showsTools: Bool {
        showsToolTray && !isCompact && !document.isReadOnly && (session.mode == .writing || session.mode == .focus)
    }

    /// With two notebooks in the window, keyboard shortcuts go to the one last touched.
    private var isActivePane: Bool { pane == .single || window?.active == nil || window?.active == document.id }

    private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers = .command, always: Bool = false) -> KeyboardShortcut? {
        isActivePane && (always || !isPresentingModal) ? KeyboardShortcut(key, modifiers: modifiers) : nil
    }

    fileprivate var document: NotebookDocument { session.document }
    private var cloth: ClothColor { document.manifest.cover.cloth }

    var body: some View {
        studySheets(sheets(layout))
    }

    private var layout: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if showsTools {
                    ToolTray(session: session)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                pageStack
                if showsPresenterPanel {
                    PresenterPanel(session: session, since: presentingSince) {
                        if let page = currentPage { editingNotes = NotesTarget(id: page.id) }
                    }
                    .frame(width: 300)
                    .transition(.move(edge: .trailing))
                }
                if showsTranscriptPanel {
                    TranscriptPanel(session: session)
                        .frame(width: 300)
                        .transition(.move(edge: .trailing))
                }
            }
            .background(Color.desk.ignoresSafeArea())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paneWidth = $0 }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(session.mode == .writing ? .visible : .hidden, for: .navigationBar)
        }
        .statusBarHidden(session.mode != .writing)
        .persistentSystemOverlays(session.mode == .writing ? .automatic : .hidden)
    }

    private var pageStack: some View {
        PageStack(session: session, window: window)
            .ignoresSafeArea(edges: .bottom)
            .background {
                Group {
                    Button("Page After Current") { session.addPage(after: session.currentPage) }
                        .keyboardShortcut(shortcut("n", always: true))
                        .disabled(document.isReadOnly || [.replaying, .selecting, .finding, .selectingText].contains(session.mode))
                    Button("Find in Notebook") { enter(.finding) }
                        .keyboardShortcut(shortcut("f"))
                    if session.mode == .finding {
                        Button("Next Match") { session.finder.step(1) }.keyboardShortcut(shortcut("g", always: true))
                        Button("Previous Match") { session.finder.step(-1) }.keyboardShortcut(shortcut("g", [.command, .shift], always: true))
                    }
                    Button("Focus Mode") { enter(session.mode == .focus ? .writing : .focus) }
                        .keyboardShortcut(shortcut("f", [.command, .control], always: true))
                    Button("Present") { enter(session.mode == .presenting ? .writing : .presenting) }
                        .keyboardShortcut(shortcut(.return, [.command, .option], always: true))
                    if session.mode != .writing {
                        Button("Done") { enter(.writing) }.keyboardShortcut(shortcut(.escape, [], always: true))
                    }
                }
                .hidden()
                .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                switch session.mode {
                case .writing: ribbons
                case .focus: focusExit
                case .presenting, .replaying, .selecting, .finding, .selectingText: EmptyView()
                }
            }
            .overlay(alignment: .top) { banners }
            .overlay(alignment: .top) {
                if session.mode == .selecting {
                    inkBar
                } else if session.mode == .finding {
                    findBar
                } else if session.mode == .selectingText {
                    textBar
                } else if session.selection != nil, session.mode != .presenting {
                    arrangeBar
                } else {
                    VStack(spacing: 0) {
                        returnBar
                        if session.mode == .writing, session.openBoard != nil { boardBar }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if session.mode == .presenting {
                    presentationBar
                } else if session.mode == .replaying {
                    ReplayBar(session: session, transcript: isCompact || session.replayLines.isEmpty ? nil : !hidesTranscript,
                              toggleTranscript: { withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { hidesTranscript.toggle() } },
                              done: { enter(.writing) })
                        .floatingBar()
                        .padding(.bottom, Space.x5)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }

    /// The editor's sheets, alerts and observers, kept apart from the layout so each stays quick to type-check.
    private func sheets<Content: View>(_ content: Content) -> some View {
        content
        .sheet(item: $editingNotes) { target in PresenterNotesSheet(document: document, pageID: target.id) }
        .sheet(item: $readingInk) { target in
            InkTextSheet(ink: target.ink) { text in
                guard let placed = session.canvas?.replaceInkSelection(with: text) else { return }
                session.enter(.writing)
                session.canvas?.select(placed)
                announce(String(localized: "Handwriting replaced with text"))
            }
        }
        .sheet(isPresented: $pickingBeside) {
            BesidePicker(current: document.id, exclude: Set(window?.tabs.map(\.id) ?? [])) { id in
                window?.beside = OpenNotebook(id: id)
                window?.active = id
            }
        }
        .sheet(isPresented: $showingRecordingsSheet) {
            recordingList { showingRecordingsSheet = false }
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.surface)
        }
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
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                insertScan(images)
            }
            .ignoresSafeArea()
        }
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
            LinkSheet(session: session) { link in
                session.addLink(link)
                refreshNotebookTitles()
                announce(String(localized: "Link added to the page"))
            }
        }
        .alert("Rename Link", isPresented: $renamingLink) {
            TextField("Name", text: $linkLabel)
            Button("Cancel", role: .cancel) {}
            Button("Save") { session.setLinkLabel(linkLabel) }
        } message: {
            Text("Leave it empty to name the link after what it opens.")
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
            session.openNotebook = { openLinkedNotebook($0, page: $1, from: $2) }
            session.onTouchDown = { if pane != .single, window?.active != document.id { window?.active = document.id } }
            session.isActivePane = { pane == .single || window?.active.map { $0 == document.id } ?? (pane != .secondary) }
            session.recorder.onTranscriptChange = { refreshSearchText() }
            // A notebook coming back from behind the tab bar still has its undo history.
            session.refreshUndoState()
            refreshNotebookTitles()
        }
        .onChange(of: window?.active) { if pane != .single, window?.active == document.id { session.canvas?.paneBecameActive() } }
        .onChange(of: session.mode, initial: true) { if pane != .secondary { window?.hidesChrome = session.mode != .writing } }
        .onChange(of: store.indexVersion) { refreshNotebookTitles() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in session.refreshUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in session.refreshUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in session.refreshUndoState() }
        .onDisappear { session.recorder.shutdown() }
        .onReceive(NotificationCenter.default.publisher(for: .scribeShowPage)) { note in
            guard (note.object as? UUID) == document.id, let page = note.userInfo?["page"] as? UUID, let index = document.index(of: page) else { return }
            session.go(to: index)
        }
    }

    /// Flashcards and the study guide.
    private func studySheets<Content: View>(_ content: Content) -> some View {
        content
        .sheet(isPresented: $showingDeck) { DeckSheet(session: session) }
        .sheet(item: $cardDraft) { draft in
            CardComposer(notebook: document.id, draft: draft) { _ in announce(String(localized: "Flashcard saved")) }
        }
        .sheet(item: $studyGuide) { request in
            StudyGuideSheet(session: session, request: request)
        }
        .sheet(item: $tagging) { target in EditorTagSheet(document: document, target: target) }
    }

    private func makeCardFromInk() {
        document.perform {
            guard let clipping = await session.inkClipping() else { return }
            cardDraft = CardDraft(pageID: clipping.pageID, answer: clipping.image)
        }
    }

    private func makeCard(from tape: PageItem) {
        guard let page = document.pages.first(where: { $0.id == session.selection?.pageID }) else { return }
        document.perform {
            do {
                try await session.makeCard(from: tape, on: page, in: flashcards)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                announce(String(localized: "Flashcard made from the tape"))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var isPresentingModal: Bool {
        showingPages || showingBoardGuide || showingRecordings || showingRecordingsSheet || pickingBeside || export != nil || importingPDF || showingPhotoPicker || renaming || goToPage || paperMode != nil
            || editingCover != nil || namingBookmark != nil || showingStickers || pickingLink || renamingLink || editingNotes != nil || readingInk != nil
            || isCovered || scanning || showingDeck || cardDraft != nil || studyGuide != nil || (pane != .secondary && window?.pickingTab == true) || tagging != nil
    }

    private func enter(_ mode: EditorMode) {
        guard !isPresentingModal else { return }
        if mode == .presenting {
            presentingSince = .now
            presenterPanel = nil
        }
        withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { session.enter(mode) }
        switch mode {
        case .writing: announce(String(localized: "Back to writing"))
        case .focus: announce(String(localized: "Focus mode. The toolbar is hidden."))
        case .presenting: announce(String(localized: "Presenting. Drag on the page to point."))
        case .replaying: announce(String(localized: "Replaying. Ink appears as it was written; tap ink to jump to that moment."))
        case .selecting: announce(String(localized: "Selecting ink. Draw round ink on any page, then drag it."))
        case .finding:
            findText = ""
            announce(String(localized: "Find in notebook. Type what to look for."))
        case .selectingText: announce(String(localized: "Selecting text. Drag across the words of a PDF page."))
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
            Button {
                session.canvas?.select(nil)
                session.recorder.shutdown()
                if window?.linkReturn?.destination == document.id { window?.linkReturn = nil }
                if pane != .secondary { window?.closing = .library }
                close()
            } label: {
                if pane == .secondary { Label("Close", systemImage: "xmark") } else { Label("Library", systemImage: "chevron.backward") }
            }
            .buttonStyle(.boardIcon)
            // With tabs open, ⌘W closes the tab on show; the tab bar has it.
            .keyboardShortcut(pane != .secondary && (window?.tabs.count ?? 0) > 1 ? nil : shortcut("w", always: true))
            .accessibilityIdentifier(pane == .secondary ? "editor.close.pane" : "editor.back")
        }
        .boardBackground()
        ToolbarItem(placement: .principal) { titleMenu }
        if isNarrow {
            ToolbarItem(placement: .topBarTrailing) {
                BarGroup {
                    undoButtons
                    addMenu
                    if session.recorder.isRecording { recordButton }
                    moreMenu
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { buttonGroupWidth = $0 }
            }
            .boardBackground()
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                BarGroup { undoButtons }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { undoGroupWidth = $0 }
            }
            .boardBackground()
            ToolbarItem(placement: .topBarTrailing) {
                BarGroup {
                    addMenu
                    recordButton
                    recordingsButton
                    toolsButton
                    moreMenu
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { buttonGroupWidth = $0 }
            }
            .boardBackground()
        }
    }

    @ViewBuilder
    private var undoButtons: some View {
        Button { document.undoManager.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
            .keyboardShortcut(session.isEditingText ? nil : shortcut("z"))
            .disabled(!session.canUndo)
            .accessibilityIdentifier("editor.undo")
        Button { document.undoManager.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
            .keyboardShortcut(session.isEditingText ? nil : shortcut("z", [.command, .shift]))
            .disabled(!session.canRedo)
            .accessibilityIdentifier("editor.redo")
    }

    /// The bar lets a long title run under the buttons, so the title is given what they leave.
    private var titleRoom: CGFloat {
        let buttons = isNarrow ? buttonGroupWidth : undoGroupWidth + buttonGroupWidth + Space.x4
        return max(paneWidth - buttons - 90, 44)
    }

    private var toolsButton: some View {
        Button { session.toggleToolPicker() } label: {
            Label(session.isToolPickerVisible ? "Hide Tools" : "Show Tools",
                  systemImage: session.isToolPickerVisible ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
        }
        .disabled(document.isReadOnly)
    }

    private var titleMenu: some View {
        Menu {
            Button { titleText = document.title; renaming = true } label: { Label("Rename…", systemImage: "pencil") }
                .disabled(document.isReadOnly)
            if !document.isReadOnly {
                Button { editingCover = store.record(document.id) } label: { Label("Change Cover…", systemImage: "book.closed") }
                let locked = document.manifest.library.isLocked
                Button { toggleLock() } label: { Label(locked ? "Remove Lock…" : "Lock…", systemImage: locked ? "lock.open" : "lock") }
                Button { tagging = .notebook } label: { Label("Tags…", systemImage: "tag") }
            }
            Menu {
                Button { export = ExportJob(document: document) } label: { Label("Notebook as a PDF…", systemImage: "doc.richtext") }
                Button { export = ExportJob(document: document, format: .images) } label: { Label("Every Page as an Image…", systemImage: "photo.on.rectangle") }
                if let page = currentPage {
                    Button { export = ExportJob(document: document, format: .images, pages: [page]) } label: { Label("This Page as an Image…", systemImage: "photo") }
                    Button { export = ExportJob(document: document, format: .timelapse, pages: [page]) } label: {
                        Label("This Page as a Time-lapse Video…", systemImage: "film")
                    }
                    .disabled(document.loadedInk(page.id)?.strokes.isEmpty ?? (page.inkHash == nil))
                }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
            if let window, pane != .secondary {
                Divider()
                Button { window.pickingTab = true } label: { Label("Open Another Notebook in a Tab…", systemImage: "plus.rectangle.on.rectangle") }
                    .disabled(window.tabs.count >= EditorWindow.tabLimit)
                if pane == .single, !isNarrow, sizeClass != .compact {
                    Button { pickingBeside = true } label: { Label("Open Another Notebook Beside…", systemImage: "rectangle.split.2x1") }
                        .disabled(window.beside != nil)
                } else if pane == .primary, let beside = window.beside {
                    Button { NotificationCenter.default.post(name: .scribeCloseEditor, object: beside.id) } label: {
                        Label("Close the Other Notebook", systemImage: "rectangle")
                    }
                }
            }
        } label: {
            HStack(spacing: Space.x2) {
                SpineChip(cloth: cloth)
                Text(document.title).font(.headline).foregroundStyle(Color.ink).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: titleRoom)
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityLabel(Text("\(document.title), notebook options"))
        .accessibilityIdentifier("editor.title")
    }

    private var recordingsButton: some View {
        Button { showingRecordings = true } label: { Label("Recordings", systemImage: "waveform") }
            .popover(isPresented: $showingRecordings) {
                recordingList { showingRecordings = false }
                    .frame(minWidth: 460, minHeight: 440)
                    .presentationBackground(Color.surface)
                    .presentationCompactAdaptation(.sheet)
            }
    }

    private func recordingList(dismiss: @escaping () -> Void) -> some View {
        RecordingList(recorder: session.recorder) { recording, time in
            dismiss()
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                if await session.beginReplay(recording, at: time) {
                    announce(String(localized: "Replaying. Ink appears as it was written; tap ink to jump to that moment."))
                }
            }
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
        .keyboardShortcut(shortcut("d"))
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
        .keyboardShortcut(shortcut("p", [.command, .shift]))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in goToText = ""; goToPage = true })
        .accessibilityLabel(Text("Page \(session.currentPage + 1) of \(document.pages.count)"))
        .accessibilityHint(Text("Opens the page navigator. Touch and hold to go to a page."))
        .accessibilityAction(named: Text("Go to page")) { goToText = ""; goToPage = true }
        .accessibilityIdentifier("editor.ribbon")
    }

    private var focusExit: some View {
        Button { enter(.writing) } label: { Label("Exit Focus Mode", systemImage: "arrow.down.right.and.arrow.up.left") }
            .buttonStyle(.boardIcon)
            .padding(.trailing, Space.x8)
            .padding(.top, Space.x2)
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
                arrangeButton("Open Link", "arrow.turn.down.right") {
                    if let page = session.selection?.pageID { session.follow(link, from: page) }
                }
                .disabled(link.target.map { document.index(of: $0) == nil } ?? false)
                .accessibilityIdentifier("editor.arrange.open")
                arrangeButton("Rename Link", "pencil") { linkLabel = link.label; renamingLink = true }
            }
            if let tape = item?.tape, let id = item?.id {
                let lifted = session.liftedTapes.contains(id)
                arrangeButton(lifted ? "Put Tape Back" : "Lift Tape", lifted ? "eye.slash" : "eye") { session.toggleTape(id) }
                    .accessibilityIdentifier("editor.arrange.lift")
                tapeColorMenu(tape)
                if let item, flashcards.canChange(document.id) {
                    let made = flashcards.card(for: id, in: document.id) != nil
                    arrangeButton(made ? "Flashcard Made" : "Make Flashcard", "rectangle.on.rectangle.angled") { makeCard(from: item) }
                        .symbolVariant(made ? .fill : .none)
                        .disabled(made)
                        .accessibilityIdentifier("editor.arrange.card")
                }
                arrangeButton("Duplicate", "plus.square.on.square") { session.duplicateSelection() }
            } else if isCompact, item?.text != nil || item?.link != nil {
                Menu {
                    Button { session.duplicateSelection() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button { session.moveSelection(forward: true) } label: { Label("Bring Forward", systemImage: "square.2.layers.3d.top.filled") }
                    Button { session.moveSelection(forward: false) } label: { Label("Send Backward", systemImage: "square.2.layers.3d.bottom.filled") }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            } else {
                arrangeButton("Duplicate", "plus.square.on.square") { session.duplicateSelection() }
                arrangeButton("Bring Forward", "square.2.layers.3d.top.filled") { session.moveSelection(forward: true) }
                arrangeButton("Send Backward", "square.2.layers.3d.bottom.filled") { session.moveSelection(forward: false) }
            }
            arrangeButton("Delete", "trash", role: .destructive) { session.deleteSelection() }
            barRule
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
            Label("Text Style", systemImage: "textformat.size")
        }
        .accessibilityIdentifier("editor.arrange.style")
    }

    private func tapeColorMenu(_ current: TapeColor) -> some View {
        Menu {
            Picker("Tape Colour", selection: Binding(get: { current }, set: { session.setTapeColor($0) })) {
                ForEach(TapeColor.allCases) { Text($0.displayName).tag($0) }
            }
        } label: {
            Label("Tape Colour", systemImage: "paintpalette")
        }
        .accessibilityValue(Text(current.displayName))
        .accessibilityIdentifier("editor.arrange.tape")
    }

    /// While ink is being selected across pages: what to do, then what can be done with what was caught.
    private var inkBar: some View {
        let count = session.inkSelectionCount
        // With ink caught, the buttons need the room in a narrow pane and at the largest text sizes.
        let says = count == 0 || !(isCompact || dynamicTypeSize.isAccessibilitySize)
        return HStack(spacing: 0) {
            if says {
                Text(count == 0 ? String(localized: "Draw round ink on any page")
                                : String(localized: "\(count) strokes. Drag them to move them."))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .padding(.trailing, Space.x2)
                    .accessibilityIdentifier("editor.ink.status")
            }
            if count > 0 {
                arrangeButton("Turn into Text", "text.viewfinder") {
                    if let ink = session.canvas?.selectedInk(), !ink.isEmpty { readingInk = InkToRead(ink: ink) }
                }
                .accessibilityIdentifier("editor.ink.text")
                if flashcards.canChange(document.id) {
                    arrangeButton("Make Flashcard", "rectangle.on.rectangle.angled", action: makeCardFromInk)
                        .accessibilityIdentifier("editor.ink.card")
                }
                arrangeButton("Duplicate", "plus.square.on.square") { session.canvas?.duplicateInkSelection() }
                    .accessibilityIdentifier("editor.ink.duplicate")
                arrangeButton("Delete", "trash", role: .destructive) { session.canvas?.deleteInkSelection() }
                    .accessibilityIdentifier("editor.ink.delete")
            }
            arrangeButton("Undo", "arrow.uturn.backward") { document.undoManager.undo() }
                .disabled(!session.canUndo)
                .accessibilityIdentifier("editor.ink.undo")
            barRule
            barDone { enter(.writing) }
                .accessibilityIdentifier("editor.ink.done")
        }
        .floatingBar(leading: says ? Space.x5 : Space.x1)
        .padding(.top, Space.x2)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Select Ink"))
        .accessibilityIdentifier("editor.ink.bar")
    }

    /// While the notebook is being searched: what to look for, how many times it was found, and the way from one to the next.
    private var findBar: some View {
        let finder = session.finder, count = finder.matches.count
        let asked = !finder.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let status = count > 0 ? String(localized: "\((finder.position ?? 0) + 1) of \(count)")
                               : asked && !finder.isSearching ? String(localized: "No matches") : ""
        return HStack(spacing: 0) {
            ScribeSearchField("Find in Notebook", text: $findText, handlesEscape: false, capsTextSize: false, identifier: "editor.find.field",
                              focus: $findFocused)
                .fontWeight(.regular)
                .onSubmit {
                    finder.step(1)
                    findFocused = true
                }
                .onChange(of: findText) { _, text in finder.search(text) }
                .frame(width: isCompact || dynamicTypeSize.isAccessibilitySize ? min(compactFindWidth, 240) : min(findWidth, 340))
                .padding(.vertical, 2)
                .padding(.trailing, Space.x1)
            if finder.isSearching, count == 0 {
                ProgressView().controlSize(.small).padding(.horizontal, Space.x2)
            } else if !status.isEmpty {
                Text(status)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .padding(.horizontal, Space.x2)
                    .accessibilityIdentifier("editor.find.status")
            }
            arrangeButton("Previous Match", "chevron.up") { finder.step(-1) }
                .disabled(count == 0)
                .accessibilityIdentifier("editor.find.previous")
            arrangeButton("Next Match", "chevron.down") { finder.step(1) }
                .disabled(count == 0)
                .accessibilityIdentifier("editor.find.next")
            barRule
            barDone { enter(.writing) }
                .accessibilityIdentifier("editor.find.done")
        }
        .floatingBar()
        .padding(.top, Space.x2)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Find in Notebook"))
        .accessibilityIdentifier("editor.find.bar")
        .onAppear { findFocused = true }
    }

    /// While a PDF page's text is being selected: what to do, then what can be done with the words that are selected.
    private var textBar: some View {
        let text = session.selectedText
        let says = text == nil && !(isCompact || dynamicTypeSize.isAccessibilitySize)
        return HStack(spacing: 0) {
            if says {
                Text("Drag across the words of a PDF page")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .padding(.trailing, Space.x2)
                    .accessibilityIdentifier("editor.text.status")
            }
            arrangeButton("Select All on This Page", "text.justify.leading") { session.canvas?.selectAllText() }
                .accessibilityIdentifier("editor.text.all")
            if let text {
                arrangeButton("Copy", "doc.on.doc") {
                    UIPasteboard.general.string = text
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    announce(String(localized: "Copied"))
                }
                .accessibilityValue(Text("\(text.split(whereSeparator: \.isWhitespace).count) words"))
                .accessibilityIdentifier("editor.text.copy")
                if !document.isReadOnly {
                    arrangeButton("Highlight", "highlighter") { session.canvas?.highlightSelectedText(highlightColor) }
                        .accessibilityValue(Text(highlightColor.displayName))
                        .accessibilityIdentifier("editor.text.highlight")
                    Menu {
                        Picker("Highlight Colour", selection: Binding(get: { highlightColor }, set: { highlightColor = $0; HighlightColor.last = $0 })) {
                            ForEach(HighlightColor.allCases) { Text($0.displayName).tag($0) }
                        }
                    } label: {
                        Label {
                            Text("Highlight Colour")
                        } icon: {
                            Circle()
                                .fill(Color(uiColor: highlightColor.uiColor))
                                .frame(width: 18, height: 18)
                                .overlay { Circle().strokeBorder(Color.ink.opacity(0.35)) }
                        }
                    }
                    .accessibilityValue(Text(highlightColor.displayName))
                    .accessibilityIdentifier("editor.text.colour")
                }
            }
            barRule
            barDone { enter(.writing) }
                .accessibilityIdentifier("editor.text.done")
        }
        .floatingBar(leading: says ? Space.x5 : Space.x1)
        .padding(.top, Space.x2)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Select Text"))
        .accessibilityIdentifier("editor.text.bar")
    }

    /// After a link was followed: the way back to the page it was on, or to the notebook it was in.
    @ViewBuilder
    private var returnBar: some View {
        if let index = session.linkReturn.flatMap(document.index(of:)) {
            returnBar(String(localized: "Back to Page \(index + 1)"), back: { session.goBack() }, dismiss: { session.dismissLinkReturn() })
        } else if let origin = window?.linkReturn, origin.destination == document.id, session.mode == .writing {
            returnBar(String(localized: "Back to \(origin.title)"), back: {
                window?.linkReturn = nil
                window?.openNotebook?(origin.origin, origin.page)
            }, dismiss: { window?.linkReturn = nil })
        }
    }

    private func returnBar(_ title: String, back: @escaping () -> Void, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: back) {
                HStack(spacing: Space.x2) {
                    Image(systemName: "arrow.uturn.backward").accessibilityHidden(true)
                    Text(title)
                }
                .font(.subheadline.weight(.semibold))
                .imageScale(.medium)
                .padding(.horizontal, Space.x1)
            }
            .accessibilityIdentifier("editor.link.back")
            barRule
            Button(action: dismiss) { Label("Dismiss", systemImage: "xmark").imageScale(.medium) }
        }
        .frame(maxWidth: 420)
        .floatingBar(leading: Space.x1, trailing: Space.x1)
        .padding(.top, Space.x2)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Whiteboard

    /// Over an open whiteboard: its own controls with their names beside them, and a way to the guide.
    private var boardBar: some View {
        VStack(spacing: Space.x2) {
            ViewThatFits(in: .horizontal) {
                boardButtons(named: true)
                boardButtons(named: false)
            }
            .popover(isPresented: $showingBoardGuide) {
                WhiteboardGuide()
                    .presentationCompactAdaptation(.sheet)
                    .presentationBackground(Color.surface)
            }
            if !boardTipSeen {
                WhiteboardTip(showGuide: { showingBoardGuide = true }, dismiss: {
                    withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { boardTipSeen = true }
                })
            }
        }
        // Keeps clear of the ribbons, and stays in the middle.
        .padding(.horizontal, Space.x8 + 100)
        .padding(.top, Space.x2)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func boardButtons(named: Bool) -> some View {
        HStack(spacing: 0) {
            Group {
                Button { session.canvas?.fit(.page) } label: { Label("Show Everything", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .accessibilityHint(Text("Zooms out until everything on the whiteboard is in view"))
                    .accessibilityIdentifier("editor.board.everything")
                Button { session.canvas?.fit(.width) } label: { Label("Actual Size", systemImage: "1.magnifyingglass") }
                    .accessibilityHint(Text("Goes back to writing size"))
                    .accessibilityIdentifier("editor.board.actual")
                Button { showingPages = true } label: { Label("Pages", systemImage: "rectangle.stack") }
                    .accessibilityHint(Text("Shows every page of the notebook"))
                    .accessibilityIdentifier("editor.board.pages")
            }
            .buttonStyle(BarIconButtonStyle(named: named))
            barRule
            Button { showingBoardGuide = true } label: { Label("Whiteboard Guide", systemImage: "questionmark.circle") }
                .accessibilityIdentifier("editor.board.guide")
        }
        .floatingBar(leading: Space.x1, trailing: Space.x1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Whiteboard"))
        .accessibilityIdentifier("editor.board.bar")
    }

    /// Cloth, like the library slip's Undo.
    private func barDone(_ action: @escaping () -> Void) -> some View {
        Button("Done", action: action)
            .buttonStyle(.scribe(.primary, compact: true))
            .fixedSize()
            .padding(.leading, Space.x1)
    }

    private var barRule: some View {
        Rectangle().fill(Color.hairline).frame(width: 1, height: 24).padding(.horizontal, Space.x2)
    }

    private func arrangeButton(_ title: LocalizedStringKey, _ symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) { Label(title, systemImage: symbol) }
    }

    private var presentationBar: some View {
        let page = min(session.currentPage + 1, document.pages.count), count = document.pages.count
        return HStack(spacing: 0) {
            Button { session.step(-1) } label: { Label("Previous Page", systemImage: "chevron.up") }
                .disabled(page <= 1)
            Text("Page \(page) of \(count)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Space.x1)
            Button { session.step(1) } label: { Label("Next Page", systemImage: "chevron.down") }
                .disabled(page >= count)
                .accessibilityIdentifier("editor.present.next")
            barRule
            if ExternalDisplay.shared.isShowing {
                Image(systemName: "tv")
                    .font(.body.weight(.medium))
                    .imageScale(.large)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(Text("Showing on the second screen"))
                    .accessibilityIdentifier("editor.present.screen")
            }
            if !isCompact {
                Button {
                    let shows = showsPresenterPanel
                    withAnimation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion)) { presenterPanel = !shows }
                } label: {
                    Label("Notes and Next Page", systemImage: "sidebar.trailing")
                        .symbolVariant(showsPresenterPanel ? .fill : .none)
                }
                .accessibilityValue(Text(showsPresenterPanel ? "Showing" : "Hidden"))
                .accessibilityIdentifier("editor.present.notes")
            }
            Button {
                session.laserColor = session.laserColor == .red ? .green : .red
            } label: {
                Circle()
                    .fill(Color(uiColor: session.laserColor.uiColor))
                    .frame(width: 18, height: 18)
                    .overlay { Circle().strokeBorder(Color.ink.opacity(0.35)) }
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
                    if !isCompact {
                        Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(seconds)))
                            .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: seconds)
                    }
                }
            }
            .buttonStyle(.scribe(.destructive, compact: true, inBar: true))
            .padding(.horizontal, Space.x1)
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
            Button { session.addBoard(after: session.currentPage) } label: { Label("Whiteboard", systemImage: "scribble.variable") }
                .accessibilityIdentifier("editor.add.board")
            Divider()
            Button { importingPDF = true } label: { Label("Insert PDF…", systemImage: "doc.richtext") }
            Button { photoBecomesPage = true; showingPhotoPicker = true } label: { Label("Insert Photo…", systemImage: "photo") }
            if DocumentScan.isAvailable {
                Button(action: startScan) { Label("Scan Documents…", systemImage: "doc.viewfinder") }
            }
            Divider()
            Button { photoBecomesPage = false; showingPhotoPicker = true } label: { Label("Picture on This Page…", systemImage: "photo.on.rectangle.angled") }
            Button { showingStickers = true } label: { Label("Sticker…", systemImage: "seal") }
            Button { session.addText() } label: { Label("Text Box", systemImage: "character.textbox") }
            Button { pickingLink = true } label: { Label("Link…", systemImage: "link") }
            Button { session.addTape() } label: { Label("Study Tape", systemImage: "rectangle.dashed") }
            Button(action: addAgenda) { Label("Today's Events", systemImage: "calendar") }
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
            if isNarrow {
                if !session.recorder.isRecording {
                    Button { session.recorder.startRecording() } label: { Label("Record Audio", systemImage: "mic") }
                        .disabled(document.isReadOnly)
                }
                Button { showingRecordingsSheet = true } label: { Label("Recordings", systemImage: "waveform") }
                Button { session.toggleToolPicker() } label: {
                    Label(session.isToolPickerVisible ? "Hide Tools" : "Show Tools", systemImage: "pencil.tip.crop.circle")
                }
                .disabled(document.isReadOnly)
                Divider()
            }
            if let current, current.template != nil, !document.isReadOnly {
                Button { paperMode = .change(pageID: current.id) } label: { Label("Change Paper…", systemImage: "paintpalette") }
            }
            Group {
                if let current, current.bookmark != nil {
                    Button { bookmarkName = current.bookmark ?? ""; namingBookmark = current.id } label: { Label("Name Bookmark…", systemImage: "bookmark") }
                } else {
                    Button(action: toggleBookmark) { Label("Bookmark Page", systemImage: "bookmark") }
                }
                if let current { Button { tagging = .page(current.id) } label: { Label("Tag Page…", systemImage: "tag") } }
                Button { Task { await session.duplicatePage(at: session.currentPage) } } label: {
                    Label("Duplicate Page", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete Page", systemImage: "trash") }
            }
            .disabled(document.isReadOnly)
            Divider()
            if current?.isBoard == true {
                Button { session.canvas?.fit(.width) } label: { Label("Actual Size", systemImage: "1.magnifyingglass") }
                Button { session.canvas?.fit(.page) } label: { Label("Show Everything", systemImage: "arrow.up.left.and.arrow.down.right") }
            } else {
                Button { session.canvas?.fit(.width) } label: { Label("Fit Width", systemImage: "arrow.left.and.right") }
                Button { session.canvas?.fit(.page) } label: { Label("Fit Page", systemImage: "arrow.up.and.down") }
            }
            Divider()
            if !document.isReadOnly {
                Button { enter(.selecting) } label: { Label("Select Ink Across Pages", systemImage: "lasso") }
            }
            if !session.liftedTapes.isEmpty {
                Button { session.coverAllTapes() } label: { Label("Put All Tape Back", systemImage: "eye.slash") }
            }
            Button { enter(.finding) } label: { Label("Find in Notebook…", systemImage: "magnifyingglass") }
            if document.hasPDFPages {
                Button { enter(.selectingText) } label: { Label("Select PDF Text", systemImage: "text.cursor") }
            }
            if !document.isReadOnly {
                Button { session.setZoomWindow(!session.isZoomWindowOpen) } label: {
                    Label(session.isZoomWindowOpen ? "Close Zoom Window" : "Zoom Window", systemImage: "plus.magnifyingglass")
                }
            }
            Divider()
            Button { showingDeck = true } label: { Label("Flashcards…", systemImage: "rectangle.on.rectangle.angled") }
            Button { studyGuide = StudyGuideRequest(scope: .notebook) } label: { Label("Study Guide…", systemImage: "text.badge.star") }
            Divider()
            Button { enter(.focus) } label: { Label("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right") }
            Button { enter(.presenting) } label: { Label("Present", systemImage: "play.rectangle") }
            if let current, !document.isReadOnly {
                Button { editingNotes = NotesTarget(id: current.id) } label: { Label("Presenter Notes…", systemImage: "note.text") }
            }
            Divider()
            if !isCompact, !document.isReadOnly {
                Toggle(isOn: $showsToolTray.animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion))) {
                    Label("Favourite Tools", systemImage: "star.square")
                }
            }
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
    /// Looks up the notebooks this one links to, so their links carry the current titles and grey out once a notebook is gone.
    fileprivate func refreshNotebookTitles() {
        var titles: [UUID: String] = [:]
        for page in document.pages where page.hasItems {
            for item in page.items {
                guard case .notebook(let id, _, _)? = item.link?.destination, titles[id] == nil,
                      let record = store.record(id), !record.isTrashed else { continue }
                titles[id] = record.title
            }
        }
        session.notebookTitles = titles
    }

    /// Asks for the calendar the first time, then prints today's events on the page.
    fileprivate func addAgenda() {
        document.perform {
            do {
                let events = Agenda.ordered(try await Agenda.calendar.events(on: .now, calendar: .current))
                guard !events.isEmpty else {
                    errorMessage = String(localized: "There is nothing in your calendar today.")
                    return
                }
                session.addAgenda(events)
                announce(String(localized: "\(events.count) events added to the page"))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    fileprivate func startScan() {
        #if DEBUG
        if LaunchOptions.arguments.contains("-fakeScan") { return insertScan(DocumentScan.samples()) }
        #endif
        scanning = true
    }

    /// Each scanned sheet becomes a page after the current one, as one undo step.
    fileprivate func insertScan(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        let position = session.currentPage + 1
        document.perform {
            do {
                let pages = try await DocumentScan.pages(from: images, in: document.package)
                let position = min(position, document.pages.count)
                document.insertPages(pages, at: position, actionName: String(localized: "Scan Documents"))
                session.go(to: position)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    fileprivate func toggleLock() {
        guard let record = store.record(document.id) else { return }
        Task { if let failure = await store.toggleLock(record) { errorMessage = failure } }
    }

    /// A transcript was written or removed: the library's search text for this notebook is read again.
    fileprivate func refreshSearchText() {
        let directory = document.package.textDirectory, id = document.id, store = store
        Task {
            let text = await Task.detached(priority: .utility) { LibraryIndex.searchText(in: directory) }.value
            store.updateSearchText(text, for: id)
        }
    }

    fileprivate func openLinkedNotebook(_ id: UUID, page: UUID?, from origin: UUID) {
        guard let record = store.record(id), !record.isTrashed else {
            errorMessage = String(localized: "The notebook this link opened is no longer in your library.")
            return
        }
        guard let window, let open = window.openNotebook else { return }
        window.linkReturn = NotebookReturn(origin: document.id, page: origin, title: document.title, destination: id)
        open(id, page)
    }

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
    /// The board capsule that floats over the page: the presenter's controls and the arrange bar.
    func floatingBar(leading: CGFloat = Space.x1, trailing: CGFloat = Space.x2) -> some View {
        fontWeight(.semibold)
            .buttonStyle(.barIcon)
            .menuStyle(.button)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.vertical, 2)
            .fixedSize()
            .board(in: Capsule())
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
        let dismissable = notice.kind != .saveFailed
        HStack(spacing: Space.x3) {
            Image(systemName: notice.kind == .saveFailed ? "exclamationmark.icloud" : "info.circle")
                .foregroundStyle(notice.kind == .saveFailed ? Color.tomato : Color.accentColor)
            Text(notice.message).font(.subheadline).foregroundStyle(Color.ink).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if dismissable {
                Button(action: dismiss) { Label("Dismiss", systemImage: "xmark").imageScale(.medium) }
                    .buttonStyle(.barIcon)
            }
        }
        .padding(.leading, Space.x4)
        .padding(.trailing, dismissable ? Space.x1 : Space.x4)
        .padding(.vertical, dismissable ? Space.x1 : Space.x3)
        .frame(maxWidth: 520, alignment: .leading)
        .board(in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .padding(.horizontal, Space.x4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct RecordingList: View {
    let recorder: NotebookRecorder
    /// Replays a recording with its ink, from a moment in it.
    var replay: ((RecordingEntry, TimeInterval) -> Void)?
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
              Section {
                ForEach(Array(recorder.recordings.enumerated()), id: \.element.id) { index, recording in
                    HStack(spacing: Space.x3) {
                        Button { recorder.togglePlayback(recording) } label: {
                            Label(recorder.playingID == recording.id ? "Stop" : "Play",
                                  systemImage: recorder.playingID == recording.id ? "stop.circle.fill" : "play.circle.fill")
                        }
                        .buttonStyle(.barIcon)
                        .disabled(recorder.isRecording)
                        HStack(spacing: Space.x3) {
                            VStack(alignment: .leading, spacing: Space.x1) {
                                Text("Recording \(index + 1)").font(.body.weight(.medium)).foregroundStyle(Color.ink)
                                Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Color.textSecondary)
                                if recorder.playingID == recording.id { ProgressView(value: recorder.playbackProgress) }
                            }
                            Spacer()
                            Text(Duration.seconds(recording.duration).formatted(.time(pattern: .minuteSecond)))
                                .font(.callout.monospacedDigit()).foregroundStyle(Color.textSecondary)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                        HStack(spacing: 0) {
                            Button { path.append(recording.id) } label: {
                                Label("Transcript", systemImage: "quote.bubble").symbolVariant(recording.transcriptFile == nil ? .none : .fill)
                            }
                            .accessibilityValue(Text(recorder.transcribing[recording.id] != nil ? "Transcribing" : recording.transcriptFile == nil ? "Not transcribed" : "Transcribed"))
                            .accessibilityIdentifier("recording.transcript.\(index + 1)")
                            if let replay {
                                Button { replay(recording, 0) } label: { Label("Replay with Ink", systemImage: "pencil.and.scribble") }
                                    .disabled(recorder.isRecording)
                                    .accessibilityHint(Text("Plays the recording while the ink written during it appears"))
                                    .accessibilityIdentifier("recording.replay.\(index + 1)")
                            }
                        }
                        .buttonStyle(.barIcon)
                    }
                    .swipeActions {
                        if !recorder.isReadOnly {
                            Button(role: .destructive) { recorder.delete(recording) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .listRowBackground(Color.surface)
                    .listRowSeparatorTint(Color.hairline)
                }
              } footer: {
                if replay != nil, !recorder.recordings.isEmpty {
                    Text("The pencil replays a recording with your ink: what you wrote appears as it was written, and tapping ink jumps to that moment. The speech bubble opens what was said.")
                        .foregroundStyle(Color.textSecondary)
                }
              }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
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
            .barGround(.surface)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                TranscriptView(recorder: recorder, recordingID: id, replay: replay)
            }
        }
    }
}
