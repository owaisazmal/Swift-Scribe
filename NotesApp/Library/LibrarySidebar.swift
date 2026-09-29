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
    @Query(sort: \FolderRecord.sortIndex) private var folders: [FolderRecord]
    @Query(filter: #Predicate<NotebookRecord> { $0.deletedAt == nil }) private var notebooks: [NotebookRecord]
    @State private var editingFolder: FolderRecord?
    @State private var creatingFolder = false
    @State private var folderName = ""

    var body: some View {
        List(selection: $scope) {
            Section {
                row(String(localized: "All notebooks"), icon: "books.vertical", count: notebooks.count).tag(LibraryScope.all)
                row(String(localized: "Favourites"), icon: "star", count: notebooks.filter(\.isFavorite).count).tag(LibraryScope.favorites)
                row(String(localized: "Recently deleted"), icon: "trash", count: nil).tag(LibraryScope.trash)
            }
            Section {
                ForEach(folders) { folder in
                    folderRow(folder)
                        .tag(LibraryScope.folder(folder.id))
                        .dropDestination(for: NotebookReference.self) { items, _ in
                            let ids = Set(items.map(\.id))
                            let moved = notebooks.filter { ids.contains($0.id) }
                            store.move(moved, to: folder)
                            return !moved.isEmpty
                        }
                        .contextMenu { folderMenu(folder) }
                }
                Button { folderName = ""; creatingFolder = true } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            } header: {
                Text("Shelves").metaStyle(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surface)
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

    private func row(_ title: String, icon: String, count: Int?) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if let count, count > 0 {
                Text(count, format: .number).font(.subheadline.monospacedDigit()).foregroundStyle(.primary.opacity(0.8))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func folderRow(_ folder: FolderRecord) -> some View {
        let count = notebooks.filter { $0.folder?.id == folder.id }.count
        return HStack(spacing: Space.x3) {
            SpineChip(cloth: folder.cloth)
            Text(folder.name).lineLimit(1)
            Spacer()
            if count > 0 {
                Text(count, format: .number).font(.subheadline.monospacedDigit()).foregroundStyle(.primary.opacity(0.8))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder.name), folder, \(count) notebooks")
    }

    @ViewBuilder
    private func folderMenu(_ folder: FolderRecord) -> some View {
        Button { folderName = folder.name; editingFolder = folder } label: { Label("Rename", systemImage: "pencil") }
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
