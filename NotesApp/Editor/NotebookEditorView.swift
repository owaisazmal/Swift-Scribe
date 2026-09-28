import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct NotebookEditorView: View {
    let notebook: Notebook
    @State private var model: EditorModel?
    @State private var recorder: AudioRecorder?

    var body: some View {
        Group {
            if let model, let recorder {
                EditorContent(notebook: notebook, model: model, recorder: recorder)
            } else {
                Color(.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .onAppear {
            guard model == nil else { return }
            model = EditorModel(notebook: notebook)
            recorder = AudioRecorder(notebook: notebook)
        }
    }
}

private struct EditorContent: View {
    @Bindable var notebook: Notebook
    let model: EditorModel
    let recorder: AudioRecorder

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPages = false
    @State private var showingRecordings = false
    @State private var importingPDF = false
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var shareItem: ShareItem?
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            NotebookCanvas(model: model)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .topTrailing) { pageIndicator }
                .overlay(alignment: .top) {
                    if recorder.isRecording { recordingBanner }
                }
                .navigationTitle($notebook.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .sheet(isPresented: $showingPages) {
            PageNavigatorView(model: model)
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
            do {
                try model.importPDF(from: result.get(), at: model.currentPage + 1)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                defer { photoItem = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw ImportError.unreadable }
                    try model.importImage(data, at: model.currentPage + 1)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog("Delete page \(model.currentPage + 1)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Page", role: .destructive) { model.deletePage(at: model.currentPage) }
        } message: {
            Text("The page and everything written on it will be removed.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil || recorder.errorMessage != nil },
            set: { if !$0 { errorMessage = nil; recorder.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? recorder.errorMessage ?? "")
        }
        .onChange(of: isPresentingModal) { _, presenting in
            model.canvas?.setToolPickerSuppressed(presenting)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.save() }
        }
        .onDisappear {
            recorder.shutdown()
            model.close()
        }
    }

    private var isPresentingModal: Bool {
        showingPages || showingRecordings || shareItem != nil || importingPDF || showingPhotoPicker
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Label("Library", systemImage: "chevron.backward")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])

            Button { model.toggleToolPicker() } label: {
                Label("Tools", systemImage: model.showsToolPicker ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
            }

            Button { recorder.toggleRecording() } label: {
                Label(recorder.isRecording ? "Stop Recording" : "Record Audio",
                      systemImage: recorder.isRecording ? "stop.circle.fill" : "mic")
            }
            .tint(recorder.isRecording ? .red : nil)

            if !recorder.recordings.isEmpty {
                Button { showingRecordings = true } label: { Label("Recordings", systemImage: "waveform") }
                    .popover(isPresented: $showingRecordings) {
                        RecordingsView(recorder: recorder)
                            .frame(minWidth: 320, minHeight: 280)
                            .presentationCompactAdaptation(.sheet)
                    }
            }

            addMenu

            Button { showingPages = true } label: { Label("Pages", systemImage: "square.grid.2x2") }

            moreMenu
        }
    }

    private var addMenu: some View {
        Menu {
            Button { model.addPage(after: model.currentPage) } label: {
                Label("Page After Current", systemImage: "doc.badge.plus")
            }
            Button { model.addPage() } label: {
                Label("Page at End", systemImage: "arrow.down.doc")
            }
            Menu {
                ForEach(PaperTemplate.allCases) { template in
                    Button(template.displayName) { model.addPage(after: model.currentPage, template: template) }
                }
            } label: {
                Label("Page with Template", systemImage: "square.grid.3x3")
            }
            Divider()
            Button { importingPDF = true } label: { Label("Insert PDF…", systemImage: "doc.richtext") }
            Button { showingPhotoPicker = true } label: { Label("Insert Photo…", systemImage: "photo") }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                do { shareItem = ShareItem(url: try model.exportPDF()) } catch { errorMessage = error.localizedDescription }
            } label: {
                Label("Export as PDF", systemImage: "square.and.arrow.up")
            }
            Divider()
            let current = model.pages.indices.contains(model.currentPage) ? model.pages[model.currentPage] : nil
            if let current, let template = current.template {
                Picker(selection: Binding(get: { template }, set: { model.setTemplate($0, forPageAt: model.currentPage) })) {
                    ForEach(PaperTemplate.allCases) { Text($0.displayName).tag($0) }
                } label: {
                    Label("Page Template", systemImage: "square.grid.3x3")
                }
                .pickerStyle(.menu)
                Picker(selection: Binding(get: { current.paperColor }, set: { model.setPaperColor($0, forPageAt: model.currentPage) })) {
                    ForEach(PaperColor.allCases) { Text($0.displayName).tag($0) }
                } label: {
                    Label("Paper Color", systemImage: "paintpalette")
                }
                .pickerStyle(.menu)
            }
            Button { model.duplicatePage(at: model.currentPage) } label: {
                Label("Duplicate Page", systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("Delete Page", systemImage: "trash")
            }
            Divider()
            Picker(selection: Binding(get: { model.drawingInput }, set: { model.drawingInput = $0 })) {
                ForEach(DrawingInput.allCases) { Text($0.displayName).tag($0) }
            } label: {
                Label("Draw With", systemImage: "hand.draw")
            }
            .pickerStyle(.menu)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private var pageIndicator: some View {
        Button { showingPages = true } label: {
            Text("\(min(model.currentPage + 1, model.pages.count)) / \(model.pages.count)")
                .font(.footnote.weight(.medium).monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel("Page \(model.currentPage + 1) of \(model.pages.count)")
    }

    private var recordingBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                .font(.footnote.weight(.semibold).monospacedDigit())
            Button("Stop") { recorder.stopRecording() }
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 10)
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
