import SwiftUI

/// A record's cover, rendered for the current appearance and contrast.
struct RecordCover: View {
    let record: NotebookRecord
    let width: CGFloat
    var showsShadow = true
    @Environment(LibraryStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let root = store.root
        let id = record.id
        CoverView(request: record.coverRequest(width: width, scale: displayScale, colorScheme: colorScheme, contrast: contrast, root: root),
                  showsShadow: showsShadow, isObscured: record.isLocked) {
            _ = await PageThumbnailer.ensureFirstPage(root: root, notebookID: id)
        }
    }
}

struct NotebookCoverItem: View {
    let record: NotebookRecord
    let width: CGFloat
    let isSelecting: Bool
    let isSelected: Bool
    let zoomNamespace: Namespace.ID
    var showsFolder = false
    let action: () -> Void
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryChangeCenter.self) private var changes
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let renderWidth = ShelfMetrics.renderWidth(for: width)
        let renderSize = CGSize(width: renderWidth, height: (renderWidth * 4 / 3).rounded())
        VStack(alignment: .leading, spacing: ShelfLedge.height + Space.x2) {
            Button(action: action) {
                RecordCover(record: record, width: renderWidth)
                    .frame(width: width)
                    .overlay {
                        ZStack(alignment: .topTrailing) {
                            if record.isFavorite {
                                FavoriteRibbon()
                                    .padding(.trailing, Space.x5 + CoverRenderer.pageBlockInsets(for: renderSize).right * width / renderWidth)
                                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .clipped()
                        .animation(Motion.adaptive(Motion.ribbon, reduceMotion: reduceMotion), value: record.isFavorite)
                    }
                    .overlay { if isSelected { StitchedSelection() } }
                    .zoomSource(id: "cover-\(record.id.uuidString)", in: zoomNamespace)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(record.accessibilityDescription)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(record.accessibilityHint(isSelecting: isSelecting))
            .accessibilityActions {
                if record.isTrashed, !isSelecting {
                    Button("Restore") { changes.restore([record], in: store, undoManager: undoManager) }
                    Button("Delete Permanently") { changes.requestPermanentDelete([record.id]) }
                }
            }
            .accessibilityIdentifier("notebook.\(record.title)")
            meta
                .accessibilityHidden(true)
                .onTapGesture(perform: action)
        }
    }

    /// Page count and date on every card, the title where the cover doesn't carry it, and the shelf in
    /// mixed views unless the cloth label already names it.
    private var meta: some View {
        var parts = [record.metaLine]
        if showsFolder, record.coverStyle != .cloth, let folder = record.folder { parts.append(folder.name) }
        return VStack(alignment: .leading, spacing: 2) {
            if record.coverStyle == .firstPage || record.isLocked {
                Text(record.title).font(.footnote.weight(.semibold)).foregroundStyle(Color.ink)
            }
            Text(parts.joined(separator: " · "))
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: width, alignment: .leading)
    }
}

/// Selection is a mustard stitched outline plus a check mark, never colour alone.
struct StitchedSelection: View {
    var body: some View {
        RoundedRectangle.track
            .strokeBorder(Color.mustard, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .padding(-6)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.onMustard)
                    .frame(width: 24, height: 24)
                    .background(Color.mustard, in: Circle())
                    .offset(x: 10, y: 10)
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// The source of the zoom transition into the editor.
    func zoomSource(id: String, in namespace: Namespace.ID) -> some View {
        matchedTransitionSource(id: id, in: namespace)
    }
}
