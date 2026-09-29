import SwiftUI
import SwiftData

struct OpenNotebook: Identifiable, Hashable {
    let id: UUID
}

struct LibraryRootView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \FolderRecord.sortIndex) private var folders: [FolderRecord]
    @State private var scope: LibraryScope? = .all
    @State private var open: OpenNotebook?
    @State private var showingSettings = false
    @State private var creating = false
    @State private var sceneID: String?
    @Namespace private var zoom

    private var usesZoom: Bool {
        if #available(iOS 18.0, *) { return !reduceMotion }
        return false
    }

    private var folder: FolderRecord? {
        if case .folder(let id) = scope { return folders.first { $0.id == id } }
        return nil
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                LibrarySidebar(scope: $scope, showingSettings: $showingSettings)
            } detail: {
                NavigationStack {
                    ShelfView(scope: scope ?? .all, zoomNamespace: zoom, onOpen: openNotebook, onCreate: { creating = true })
                }
            }
            .tint(Color.accentColor)

            if !usesZoom, let open {
                EditorScreen(notebookID: open.id, sceneID: sceneID) { self.open = nil }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: open)
        .fullScreenCover(item: Binding(get: { usesZoom ? open : nil }, set: { open = $0 })) { item in
            EditorScreen(notebookID: item.id, sceneID: sceneID) { open = nil }
                .zoomTransition(id: item.id, in: zoom)
        }
        .sheet(isPresented: $creating) {
            NewNotebookView(folder: folder) { id in
                openNotebook(id)
            }
        }
        .sheet(isPresented: $showingSettings) {
            ScribeSettingsView()
        }
        .background(SceneReader { sceneID = $0 })
        .keyboardShortcut(for: { creating = true })
    }

    private func openNotebook(_ record: NotebookRecord) {
        store.noteOpened(record)
        openNotebook(record.id)
    }

    private func openNotebook(_ id: UUID) {
        if DocumentRegistry.shared.activateExistingEditor(for: id, from: sceneID) { return }
        open = OpenNotebook(id: id)
    }
}

extension View {
    @ViewBuilder
    func zoomTransition(id: UUID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }

    /// ⌘N: new notebook, from anywhere in the library.
    func keyboardShortcut(for newNotebook: @escaping () -> Void) -> some View {
        background {
            Button("New Notebook", action: newNotebook)
                .keyboardShortcut("n", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
    }
}

/// Reports the window scene's persistent identifier, which keys the one-editor-per-notebook rule.
struct SceneReader: UIViewRepresentable {
    let onChange: (String?) -> Void

    func makeUIView(context: Context) -> SceneReaderView {
        let view = SceneReaderView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: SceneReaderView, context: Context) {}

    final class SceneReaderView: UIView {
        var onChange: ((String?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onChange?(window?.windowScene?.session.persistentIdentifier)
        }
    }
}
