import SwiftUI

/// Changes an existing notebook's cover with the same choices and live preview as New Notebook.
struct CoverEditorView: View {
    let record: NotebookRecord
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @State private var spec: CoverSpec
    @State private var inkPair: Int

    init(record: NotebookRecord) {
        self.record = record
        let cover = record.cover
        _spec = State(initialValue: cover)
        _inkPair = State(initialValue: RisoInk.pairs.firstIndex { $0.0 == cover.inks.0 && $0.1 == cover.inks.1 } ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x5) {
                    let root = store.root, id = record.id
                    CoverView(request: record.coverRequest(width: CoverWidth.preview, scale: displayScale, colorScheme: colorScheme,
                                                           contrast: contrast, root: root, spec: spec), persist: false) {
                        _ = await PageThumbnailer.ensureFirstPage(root: root, notebookID: id)
                    }
                    .frame(width: 200)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(false)
                    .accessibilityLabel(Text("Cover preview: \(spec.style.displayName) cover for \(record.title)"))
                    ShuffleButton(style: spec.style) {
                        var generator = SystemRandomNumberGenerator()
                        spec = CoverShuffle.next(spec, using: &generator)
                        inkPair = RisoInk.pairs.firstIndex { $0.0 == spec.inks.0 && $0.1 == spec.inks.1 } ?? inkPair
                    }
                    .frame(maxWidth: .infinity)
                    ScribeSegmentedPicker("Cover", selection: $spec.style, options: CoverStyle.allCases) { Text($0.displayName) }
                    switch spec.style {
                    case .cloth, .firstPage:
                        Text(spec.style == .cloth ? "Cloth" : "Spine").metaStyle(.footnote).accessibilityAddTraits(.isHeader)
                        SwatchRow(items: ClothColor.allCases, selection: $spec.cloth, label: \.displayName) { Circle().fill($0.color) }
                    case .print:
                        Text("Inks").metaStyle(.footnote).accessibilityAddTraits(.isHeader)
                        SwatchRow(items: Array(RisoInk.pairs.indices), selection: $inkPair,
                                  label: { "\(RisoInk.pairs[$0].0.displayName) and \(RisoInk.pairs[$0].1.displayName)" }) { index in
                            Circle().fill(LinearGradient(stops: [.init(color: Color(hex: RisoInk.pairs[index].0.hex), location: 0.5),
                                                                .init(color: Color(hex: RisoInk.pairs[index].1.hex), location: 0.5)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                }
                .padding(Space.x6)
            }
            .background(Color.surface)
            .navigationTitle("Change Cover")
            .barGround(.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.buttonStyle(.scribe(.secondary, inBar: true))
                }
                .boardBackground()
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setCover(spec, for: record)
                        dismiss()
                    }
                    .buttonStyle(.scribe(.primary, inBar: true))
                    .keyboardShortcut(.defaultAction)
                }
                .boardBackground()
            }
            .onChange(of: inkPair) { _, index in spec.inks = RisoInk.pairs[index] }
        }
        .presentationDetents([.large])
        .presentationSizing(.page)
    }
}
