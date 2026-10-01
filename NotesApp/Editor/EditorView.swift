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
}

enum PageFit { case width, page }

@MainActor
@Observable
final class EditorSession {
    let document: NotebookDocument
    let recorder: NotebookRecorder
    var currentPage: Int
    var isToolPickerVisible = true
    var canUndo = false
    var canRedo = false
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
        document.noteCurrentPage(index)
    }

    func go(to index: Int, animated: Bool = true) {
        guard document.pages.indices.contains(index) else { return }
        canvas?.scrollToPage(index, animated: animated)
        pageDidChange(index)
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

private struct EditorContent: View {
    @Bindable var session: EditorSession
    let close: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingPages = false
    @State private var showingRecordings = false
    @State private var importingPDF = false
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var export: ExportJob?
    @State private var confirmingDelete = false
    @State private var goToPage = false
    @State private var goToText = ""
    @State private var renaming = false
    @State private var titleText = ""
    @State private var errorMessage: String?
    @State private var ribbonWidth: CGFloat = 44
    @State private var paperMode: PaperDrawer.Mode?
    @State private var editingCover: NotebookRecord?
    @State private var knownPages: Set<UUID> = []

    private var document: NotebookDocument { session.document }
    private var cloth: ClothColor { document.manifest.cover.cloth }

    var body: some View {
        NavigationStack {
            PageStack(session: session)
                .ignoresSafeArea(edges: .bottom)
                .background(Color.desk.ignoresSafeArea())
                .background {
                    Button("Page After Current") { session.addPage(after: session.currentPage) }
                        .keyboardShortcut("n", modifiers: .command)
                        .disabled(document.isReadOnly)
                        .hidden()
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .topTrailing) { ribbon }
                .overlay(alignment: .top) { banners }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .toolbarBackground(.hidden, for: .navigationBar)
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            let position = session.currentPage + 1
            document.perform { await insertPhoto(item, at: position) }
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
            || editingCover != nil
    }

    private func announce(_ message: String) {
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
            Button { session.recorder.shutdown(); close() } label: { Label("Library", systemImage: "chevron.backward") }
                .keyboardShortcut("w", modifiers: .command)
                .accessibilityIdentifier("editor.back")
        }
        ToolbarItem(placement: .principal) { titleMenu }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { document.undoManager.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut(isPresentingModal ? nil : KeyboardShortcut("z", modifiers: .command))
                .disabled(!session.canUndo)
                .accessibilityIdentifier("editor.undo")
            Button { document.undoManager.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .keyboardShortcut(isPresentingModal ? nil : KeyboardShortcut("z", modifiers: [.command, .shift]))
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
        .padding(.trailing, Space.x8)
        .accessibilityLabel(Text("Page \(session.currentPage + 1) of \(document.pages.count)"))
        .accessibilityHint(Text("Opens the page navigator. Touch and hold to go to a page."))
        .accessibilityAction(named: Text("Go to page")) { goToText = ""; goToPage = true }
        .accessibilityIdentifier("editor.ribbon")
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
            Button { showingPhotoPicker = true } label: { Label("Insert Photo…", systemImage: "photo") }
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

enum PhotoImport {
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
