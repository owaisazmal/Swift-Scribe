import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case all, favorites, trash
    case folder(UUID)
}

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.name) private var folders: [Folder]
    @State private var selection: SidebarItem? = .all
    @State private var openNotebook: Notebook?
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, folders: folders, showingSettings: $showingSettings)
        } detail: {
            NavigationStack {
                NotebookGridView(scope: selection ?? .all, folders: folders, openNotebook: $openNotebook)
            }
        }
        .fullScreenCover(item: $openNotebook) { notebook in
            NotebookEditorView(notebook: notebook)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .task {
            NotebookActions.purgeExpiredTrash(in: context)
        }
    }
}

struct SidebarView: View {
    @Environment(\.modelContext) private var context
    @Binding var selection: SidebarItem?
    let folders: [Folder]
    @Binding var showingSettings: Bool
    @Query(filter: #Predicate<Notebook> { $0.deletedAt == nil }) private var notebooks: [Notebook]

    @State private var editingFolder: Folder?
    @State private var creatingFolder = false
    @State private var folderName = ""

    var body: some View {
        List(selection: $selection) {
            Section {
                row("All Notes", icon: "books.vertical", count: notebooks.count).tag(SidebarItem.all)
                row("Favorites", icon: "star", count: notebooks.filter(\.isFavorite).count).tag(SidebarItem.favorites)
                row("Recently Deleted", icon: "trash", count: nil).tag(SidebarItem.trash)
            }
            Section("Folders") {
                ForEach(folders) { folder in
                    row(folder.name, icon: "folder.fill", tint: folder.color.color,
                        count: notebooks.filter { $0.folder?.id == folder.id }.count)
                        .tag(SidebarItem.folder(folder.id))
                        .dropDestination(for: String.self) { items, _ in
                            move(items, to: folder)
                        }
                        .contextMenu {
                            Button { folderName = folder.name; editingFolder = folder } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Menu {
                                ForEach(FolderColor.allCases) { color in
                                    Button { folder.color = color } label: {
                                        Label(color.rawValue.capitalized, systemImage: folder.color == color ? "checkmark.circle.fill" : "circle.fill")
                                    }
                                }
                            } label: {
                                Label("Color", systemImage: "paintpalette")
                            }
                            Button(role: .destructive) {
                                if selection == .folder(folder.id) { selection = .all }
                                context.delete(folder)
                            } label: {
                                Label("Delete Folder", systemImage: "trash")
                            }
                        }
                }
                Button { folderName = ""; creatingFolder = true } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .navigationTitle("Swift Scribe")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .alert("New Folder", isPresented: $creatingFolder) {
            TextField("Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = folderName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let folder = Folder(name: name, color: FolderColor.allCases[folders.count % FolderColor.allCases.count])
                context.insert(folder)
                selection = .folder(folder.id)
            }
        }
        .alert("Rename Folder", isPresented: Binding(get: { editingFolder != nil }, set: { if !$0 { editingFolder = nil } })) {
            TextField("Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = folderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { editingFolder?.name = name }
            }
        }
    }

    private func row(_ title: String, icon: String, tint: Color? = nil, count: Int?) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint ?? .accentColor)
            }
            Spacer()
            if let count, count > 0 {
                Text("\(count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private func move(_ items: [String], to folder: Folder) -> Bool {
        let ids = Set(items.compactMap(UUID.init(uuidString:)))
        let moved = notebooks.filter { ids.contains($0.id) }
        moved.forEach { $0.folder = folder }
        return !moved.isEmpty
    }
}

extension FolderColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}
