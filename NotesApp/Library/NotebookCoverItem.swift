import SwiftUI

/// A record's cover, rendered for the current appearance and contrast.
struct RecordCover: View {
    let record: NotebookRecord
    let width: CGFloat
    @Environment(LibraryStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let root = store.root
        let id = record.id
        CoverView(request: record.coverRequest(width: width, scale: displayScale, colorScheme: colorScheme, contrast: contrast, root: root)) {
            _ = await PageThumbnailer.ensureFirstPage(root: root, notebookID: id)
        }
    }
}

struct NotebookCoverItem: View {
    let record: NotebookRecord
    let isSelecting: Bool
    let isSelected: Bool
    let zoomNamespace: Namespace.ID
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.x2) {
                RecordCover(record: record, width: CoverWidth.shelf)
                    .overlay(alignment: .topTrailing) {
                        if record.isFavorite {
                            FavoriteRibbon()
                                .padding(.trailing, Space.x5)
                                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .clipped()
                    .animation(Motion.adaptive(Motion.ribbon, reduceMotion: reduceMotion), value: record.isFavorite)
                    .overlay { if isSelected { StitchedSelection() } }
                    .zoomSource(id: record.id, in: zoomNamespace)
                meta
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelecting ? Text("Selects or deselects this notebook") : Text("Opens the notebook"))
        .accessibilityIdentifier("notebook.\(record.title)")
    }

    private var meta: some View {
        Group {
            if record.coverStyle == .firstPage {
                Text("\(record.title) · \(record.pageCount == 1 ? String(localized: "1 page") : String(localized: "\(record.pageCount) pages"))")
            } else {
                Text(record.metaLine)
            }
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(Color.inkSecondary)
        .lineLimit(1)
    }
}

/// Selection is a mustard stitched outline plus a check mark, never colour alone.
struct StitchedSelection: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.mustard, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .padding(-6)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.onMustard)
                    .frame(width: 24, height: 24)
                    .background(Color.mustard, in: Circle())
                    .offset(x: 10, y: 10)
            }
            .accessibilityHidden(true)
    }
}

struct ContinueWritingSpread: View {
    let record: NotebookRecord
    let action: () -> Void
    @Environment(LibraryStore.self) private var store
    @State private var page: UIImage?

    var body: some View {
        Button(action: action) {
            HStack(alignment: .bottom, spacing: 0) {
                RecordCover(record: record, width: CoverWidth.spread)
                    .frame(width: 140)
                Group {
                    if let page {
                        Image(uiImage: page).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.white
                    }
                }
                .frame(width: 140, height: 140 * 4 / 3)
                .clipped()
                .overlay { Rectangle().strokeBorder(Color.hairline, lineWidth: 1) }
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text("Continue writing")
                        .font(.footnote.weight(.bold).smallCaps())
                        .tracking(0.8)
                        .foregroundStyle(Color.accentColor)
                    Text(record.title)
                        .font(.display(26, relativeTo: .title2))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                    Text("Page \(record.currentPage + 1) of \(record.pageCount) · edited \(record.modifiedAt.formatted(.relative(presentation: .named)))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.leading, Space.x6)
                .padding(.bottom, Space.x2)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Continue writing \(record.title), page \(record.currentPage + 1) of \(record.pageCount)"))
        .accessibilityAddTraits(.isButton)
        .task(id: "\(record.id)-\(record.currentPage)-\(record.modifiedAt.timeIntervalSince1970)") {
            let package = NotebookPackage(root: store.root, id: record.id)
            guard let manifest = try? await package.readManifest().manifest, !manifest.pages.isEmpty else { return }
            let current = manifest.pages[min(record.currentPage, manifest.pages.count - 1)]
            page = await PageThumbnailer.thumbnail(package: package, page: current)
        }
    }
}

extension View {
    /// The source of the zoom transition into the editor, where the OS supports it.
    @ViewBuilder
    func zoomSource(id: UUID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
