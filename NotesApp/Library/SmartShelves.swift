import SwiftUI
import SwiftData

extension Tags {
    /// The library's tags from its index. What is written in a locked notebook stays out, so only its own tags count.
    @MainActor
    static func counts(_ records: [NotebookRecord]) -> [TagCount] {
        counts(records.map { (own: $0.tags, pages: $0.isLocked ? [] : $0.pageTags) })
    }
}

extension LibraryStore {
    /// Every tag in use on notebooks that aren't in the bin, with how many carry it. There is no table of tags: this is read from the records.
    func tagCounts() -> [TagCount] {
        Tags.counts((try? context.fetch(FetchDescriptor<NotebookRecord>(predicate: #Predicate { $0.deletedAt == nil }))) ?? [])
    }

    /// Spells a tag anew on every notebook and page that carries it, or takes it off them all when `new` is nil.
    /// A name the library already has is merged into, in the spelling it has there. Smart shelves looking for the tag follow.
    /// Returns the name the tag now goes by.
    @discardableResult
    func renameTag(_ old: String, to new: String?) -> String? {
        var name = new.flatMap(Tags.normalized)
        if new != nil, name == nil { return nil }
        if let wanted = name, Tags.key(wanted) != Tags.key(old), let existing = tagCounts().first(where: { $0.id == Tags.key(wanted) }) {
            name = existing.name
        }
        guard name != old else { return name }
        let spelled = name
        let change: @Sendable (inout NotebookManifest) -> Void = { manifest in
            if Tags.contains(manifest.library.tags, old) { manifest.library.tags = Tags.renaming(manifest.library.tags, old, to: spelled) }
            for index in manifest.pages.indices where Tags.contains(manifest.pages[index].tags, old) {
                manifest.pages[index].tags = Tags.renaming(manifest.pages[index].tags, old, to: spelled)
            }
        }
        var writes: [Task<Void, Never>] = []
        let records = (try? context.fetch(FetchDescriptor<NotebookRecord>())) ?? []
        for record in records where !record.isReadOnly && Tags.contains(record.tags + record.pageTags, old) {
            record.tagsRaw = Tags.joined(Tags.renaming(record.tags, old, to: spelled))
            record.pageTagsRaw = Tags.joined(Tags.renaming(record.pageTags, old, to: spelled))
            if let document = DocumentRegistry.shared.document(for: record.id) {
                document.applyLibraryChange(change)
            } else {
                writes.append(update(record.id, change))
            }
        }
        saveSmartShelves(smartShelves.map { shelf in
            var shelf = shelf
            if Tags.contains(shelf.tags, old) { shelf.tags = Tags.renaming(shelf.tags, old, to: spelled) }
            return shelf
        })
        tagsChanged(awaiting: writes)
        return name
    }

    @discardableResult
    func createSmartShelf(name: String, tags: [String], match: TagRule.Match) -> SmartShelf? {
        let tags = Tags.merged(tags)
        guard !tags.isEmpty else { return nil }
        let shelf = SmartShelf(name: SmartShelf.name(name, for: tags), tags: tags, match: match)
        saveSmartShelves(smartShelves + [shelf])
        return shelf
    }

    func updateSmartShelf(_ id: UUID, name: String, tags: [String], match: TagRule.Match) {
        let tags = Tags.merged(tags)
        guard !tags.isEmpty else { return }
        saveSmartShelves(smartShelves.map { shelf in
            guard shelf.id == id else { return shelf }
            var shelf = shelf
            shelf.name = SmartShelf.name(name, for: tags)
            shelf.tags = tags
            shelf.match = match
            return shelf
        })
    }

    func deleteSmartShelf(_ id: UUID) {
        saveSmartShelves(smartShelves.filter { $0.id != id })
    }
}

extension SmartShelf {
    /// A shelf left unnamed is called after its tags.
    static func name(_ typed: String, for tags: [String]) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? tags.formatted(.list(type: .and, width: .narrow)) : trimmed
    }
}

/// The tagged pages a tag shelf or a smart shelf lists under its notebooks.
enum TagPages {
    struct Source: Sendable {
        let id: UUID
        /// The notebook's own tags, which count towards a rule that asks for all of its tags.
        let tags: [String]
        /// The pages of a notebook that is open, which may be ahead of its file.
        var pages: [NotebookPage]?
    }

    static func hits(for rule: TagRule, in notebooks: [Source], root: StorageRoot, limitPerNotebook: Int = 24, limit: Int = 120) async -> [UUID: [PageHit]] {
        var result: [UUID: [PageHit]] = [:]
        var total = 0
        for notebook in notebooks {
            if Task.isCancelled || total >= limit { break }
            var pages = notebook.pages
            if pages == nil { pages = try? await NotebookPackage(root: root, id: notebook.id).readManifest().manifest.pages }
            let hits = (pages ?? []).enumerated().compactMap { index, page -> PageHit? in
                let tags = page.tags
                guard rule.lists(page: tags, in: notebook.tags) else { return nil }
                return PageHit(notebookID: notebook.id, page: page, index: index, snippet: Tags.line(tags), tags: tags)
            }
            .prefix(min(limitPerNotebook, limit - total))
            if !hits.isEmpty { result[notebook.id] = Array(hits) }
            total += hits.count
        }
        return result
    }
}

/// What the smart shelf sheet is editing: a shelf, or a new one when there is none.
struct SmartShelfDraft: Identifiable {
    let id = UUID()
    var shelf: SmartShelf?
    /// The library's tags, to choose from.
    let tags: [String]
}

/// Names a smart shelf and chooses the tags it looks for.
struct SmartShelfEditor: View {
    let draft: SmartShelfDraft
    let save: (String, [String], TagRule.Match) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var chosen: [String]
    @State private var match: TagRule.Match
    @FocusState private var focused: Bool

    init(draft: SmartShelfDraft, save: @escaping (String, [String], TagRule.Match) -> Void) {
        self.draft = draft
        self.save = save
        _name = State(initialValue: draft.shelf?.name ?? "")
        _chosen = State(initialValue: draft.shelf?.tags ?? [])
        _match = State(initialValue: draft.shelf?.match ?? .any)
    }

    /// A shelf keeps the tags it had even when nothing carries them any more.
    private var choices: [String] { Tags.merged(draft.tags + (draft.shelf?.tags ?? [])) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x5) {
                    TextField("Name", text: $name, prompt: Text("Name").foregroundStyle(Color.textSecondary))
                        .focused($focused)
                        .submitLabel(.done)
                        .accessibilityLabel(Text("Name"))
                        .accessibilityIdentifier("smart.name")
                        .padding(.vertical, Space.x2)
                        .scribeField(focused: focused) { focused = true }
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Text("Tags").metaStyle(.footnote).accessibilityAddTraits(.isHeader)
                        FlowLayout(spacing: Space.x1) {
                            ForEach(choices, id: \.self) { tag in
                                TagChipButton(name: tag, isChosen: Tags.contains(chosen, tag)) { toggle(tag) }
                                    .accessibilityIdentifier("smart.tag.\(tag)")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.x2) {
                        Text("Shows what is tagged with").metaStyle(.footnote).accessibilityAddTraits(.isHeader)
                        ScribeSegmentedPicker("Shows what is tagged with", selection: $match, options: TagRule.Match.allCases) { match in
                            switch match {
                            case .any: Text("Any of these")
                            case .all: Text("All of these")
                            }
                        }
                        .accessibilityIdentifier("smart.match")
                        Text("A page counts when it carries one of the tags itself. Asked for all of them, its notebook's tags count towards the rest.")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.x5)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.surface)
            .navigationTitle(draft.shelf == nil ? Text("New Smart Shelf") : Text("Edit Smart Shelf"))
            .navigationBarTitleDisplayMode(.inline)
            .barGround(.surface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.buttonStyle(.scribe(.secondary, inBar: true))
                }
                .boardBackground()
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(name, chosen, match)
                        dismiss()
                    }
                    .buttonStyle(.scribe(.primary, inBar: true))
                    .disabled(chosen.isEmpty)
                    .accessibilityIdentifier("smart.save")
                }
                .boardBackground()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.surface)
    }

    private func toggle(_ tag: String) {
        if Tags.contains(chosen, tag) { chosen.removeAll { Tags.key($0) == Tags.key(tag) } } else { chosen = Tags.merged(chosen + [tag]) }
    }
}
