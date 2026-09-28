import SwiftUI

struct PageNavigatorView: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 20)], spacing: 24) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                        PageThumbnailCell(model: model, page: page, index: index, isCurrent: index == model.currentPage)
                            .onTapGesture {
                                dismiss()
                                model.scrollTo(page: index)
                            }
                            .contextMenu { menu(for: index) }
                            .draggable(page.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                guard let id = items.first,
                                      let from = model.pages.firstIndex(where: { $0.id.uuidString == id }) else { return false }
                                model.movePage(from: from, to: index)
                                return true
                            }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(model.pages.count) Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { model.addPage() } label: { Label("Add Page", systemImage: "plus") }
                }
            }
            .confirmationDialog("Delete this page?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Page", role: .destructive) {
                    if let pendingDelete { model.deletePage(at: pendingDelete) }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for index: Int) -> some View {
        Button { model.addPage(after: index) } label: { Label("Insert Page After", systemImage: "doc.badge.plus") }
        Button { model.duplicatePage(at: index) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        if index > 0 {
            Button { model.movePage(from: index, to: index - 1) } label: { Label("Move Earlier", systemImage: "arrow.backward") }
        }
        if index < model.pages.count - 1 {
            Button { model.movePage(from: index, to: index + 1) } label: { Label("Move Later", systemImage: "arrow.forward") }
        }
        Divider()
        Button(role: .destructive) { pendingDelete = index } label: { Label("Delete", systemImage: "trash") }
    }
}

private struct PageThumbnailCell: View {
    let model: EditorModel
    let page: PageSpec
    let index: Int
    let isCurrent: Bool
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image {
                    Image(uiImage: image).resizable()
                } else {
                    Rectangle().fill(Color(PaperRenderer.uiColor(page.effectivePaperColor)))
                }
            }
            .aspectRatio(page.size.width / max(page.size.height, 1), contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: isCurrent ? 3 : 0)
                    .padding(-4)
            }
            Text("\(index + 1)")
                .font(.caption.weight(isCurrent ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
        .task(id: page) {
            image = model.pageThumbnail(at: index, width: 280)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(.isButton)
    }
}
