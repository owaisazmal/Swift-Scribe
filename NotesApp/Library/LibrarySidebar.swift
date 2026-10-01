import SwiftUI
import SwiftData

enum LibraryScope: Hashable {
    case all, favorites, trash
    case folder(UUID)
}

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case opened, modified, created, title
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opened: String(localized: "Last Opened")
        case .modified: String(localized: "Date Modified")
        case .created: String(localized: "Date Created")
        case .title: String(localized: "Title")
        }
    }

    var summary: String {
        switch self {
        case .opened: String(localized: "last opened first")
        case .modified: String(localized: "recently edited first")
        case .created: String(localized: "newest first")
        case .title: String(localized: "A to Z")
        }
    }
}

enum LibraryGrouping: String, CaseIterable, Identifiable {
    case recency, folder
    var id: String { rawValue }
    var displayName: String { self == .recency ? String(localized: "Recency") : String(localized: "Folder") }
}

struct SpineChip: View {
    let cloth: ClothColor
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(cloth.color)
            .frame(width: 7, height: 20)
            .overlay(alignment: .leading) { Rectangle().fill(.black.opacity(0.2)).frame(width: 2) }
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
            .overlay { RoundedRectangle(cornerRadius: 1.5).strokeBorder(Color.hairline, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

struct LibrarySidebar: View {
    @Binding var scope: LibraryScope?
    @Binding var showingSettings: Bool
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryChangeCenter.self) private var changes
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \FolderRecord.sortIndex) private var folders: [FolderRecord]
    @Query(filter: #Predicate<NotebookRecord> { $0.deletedAt == nil }) private var notebooks: [NotebookRecord]
    @State private var editingFolder: FolderRecord?
    @State private var creatingFolder = false
    @State private var folderName = ""

    /// One pass over the notebooks for every count, instead of one per folder.
    private var counts: (favorites: Int, byFolder: [UUID: Int]) {
        var favorites = 0
        var byFolder: [UUID: Int] = [:]
        for notebook in notebooks {
            if notebook.isFavorite { favorites += 1 }
            if let id = notebook.folder?.id { byFolder[id, default: 0] += 1 }
        }
        return (favorites, byFolder)
    }

    var body: some View {
        let counts = counts
        List(selection: $scope) {
            Section {
                row(String(localized: "All notebooks"), icon: "books.vertical", count: notebooks.count).tag(LibraryScope.all)
                row(String(localized: "Favourites"), icon: "star", count: counts.favorites).tag(LibraryScope.favorites)
                row(String(localized: "Recently deleted"), icon: "trash", count: nil, bounces: changes.trashBumps).tag(LibraryScope.trash)
            }
            Section {
                ForEach(folders) { folder in
                    folderRow(folder, count: counts.byFolder[folder.id] ?? 0)
                        .tag(LibraryScope.folder(folder.id))
                        .dropDestination(for: NotebookReference.self) { items, _ in
                            let ids = Set(items.map(\.id))
                            let moved = notebooks.filter { ids.contains($0.id) }
                            changes.move(moved, to: folder, in: store, undoManager: undoManager)
                            return !moved.isEmpty
                        }
                        .contextMenu { folderMenu(folder) }
                }
                .onMove { store.moveFolders(folders, from: $0, to: $1) }
                Button { folderName = ""; creatingFolder = true } label: {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text("New Folder")
                    } else {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                }
            } header: {
                Text("Shelves").metaStyle(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surface)
        .tint(Color.sidebarTint)
        .navigationTitle("Swift Scribe")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        .alert("New Folder", isPresented: $creatingFolder) {
            TextField("Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                if let folder = store.createFolder(name: folderName, cloth: ClothColor.allCases[folders.count % ClothColor.allCases.count]) {
                    scope = .folder(folder.id)
                }
            }
        }
        .alert("Rename Folder", isPresented: Binding(get: { editingFolder != nil }, set: { if !$0 { editingFolder = nil } })) {
            TextField("Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let editingFolder { store.renameFolder(editingFolder, to: folderName) } }
        }
    }

    private func row(_ title: String, icon: String, count: Int?, bounces: Int = 0) -> some View {
        HStack {
            if dynamicTypeSize.isAccessibilitySize {
                Text(title)
            } else {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: icon)
                        .symbolEffect(.bounce, value: bounces)
                        .symbolEffectsRemoved(reduceMotion)
                }
            }
            Spacer()
            if let count, count > 0, !dynamicTypeSize.isAccessibilitySize {
                Text(count, format: .number).font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { $0 > 0 ? "\(title), \($0)" : title } ?? title)
        .accessibilityAddTraits(.isButton)
    }

    private func folderRow(_ folder: FolderRecord, count: Int) -> some View {
        HStack(spacing: Space.x3) {
            SpineChip(cloth: folder.cloth)
            Text(folder.name).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            Spacer()
            if count > 0, !dynamicTypeSize.isAccessibilitySize {
                Text(count, format: .number).font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count == 1 ? String(localized: "\(folder.name), folder, 1 notebook")
                                       : String(localized: "\(folder.name), folder, \(count) notebooks"))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func folderMenu(_ folder: FolderRecord) -> some View {
        Button { folderName = folder.name; editingFolder = folder } label: { Label("Rename", systemImage: "pencil") }
        Button { store.sortFoldersByName(folders) } label: { Label("Sort Shelves A to Z", systemImage: "textformat") }
        Menu {
            ForEach(ClothColor.allCases) { cloth in
                Button { store.setCloth(cloth, for: folder) } label: {
                    Label(cloth.displayName, systemImage: folder.cloth == cloth ? "checkmark" : "circle.fill")
                }
            }
        } label: { Label("Spine Colour", systemImage: "paintpalette") }
        Button(role: .destructive) {
            if scope == .folder(folder.id) { scope = .all }
            store.deleteFolder(folder)
        } label: { Label("Delete Folder", systemImage: "trash") }
    }
}
