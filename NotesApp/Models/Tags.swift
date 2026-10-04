import Foundation

/// Tag names as people type them. Two spellings are one tag when they differ only in case or accents.
enum Tags {
    static let maximumLength = 40

    /// Trimmed, single-spaced and without a leading "#". Nil when nothing is left.
    static func normalized(_ raw: String) -> String? {
        var name = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while name.hasPrefix("#") { name = String(name.dropFirst()).trimmingCharacters(in: .whitespaces) }
        name = String(name.prefix(maximumLength)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// What every spelling of one tag shares.
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// One spelling of each tag, the first met, in the order lists show them.
    static func merged(_ names: [String]) -> [String] {
        guard !names.isEmpty else { return [] }
        var seen = Set<String>()
        return names.compactMap(normalized).filter { seen.insert(key($0)).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func contains(_ names: [String], _ name: String) -> Bool {
        let wanted = key(name)
        return names.contains { key($0) == wanted }
    }

    /// `names` with one tag spelled anew, or without it when `new` is nil.
    static func renaming(_ names: [String], _ old: String, to new: String?) -> [String] {
        let wanted = key(old)
        return merged(names.compactMap { key($0) == wanted ? new : $0 })
    }

    /// How the index keeps a list of tags in one column. A name never holds a line break.
    static func joined(_ names: [String]) -> String { names.joined(separator: "\n") }

    static func split(_ raw: String) -> [String] {
        raw.isEmpty ? [] : raw.split(separator: "\n").map(String.init)
    }

    /// "#exam  #week 3", for a line of text.
    static func line(_ names: [String]) -> String { names.map { "#\($0)" }.joined(separator: "  ") }

    /// The names under "tags" in a manifest object.
    static func read(_ extra: [String: JSONValue]) -> [String] {
        guard let values = extra["tags"]?.arrayValue else { return [] }
        return merged(values.compactMap(\.stringValue))
    }

    /// Entries that aren't names, and a value that isn't a list, are another build's and stay as they were.
    static func write(_ names: [String], to extra: inout [String: JSONValue]) {
        let names = merged(names)
        if let current = extra["tags"], current.arrayValue == nil, names.isEmpty { return }
        let unreadable = extra["tags"]?.arrayValue?.filter { $0.stringValue == nil } ?? []
        let all = names.map(JSONValue.string) + unreadable
        extra["tags"] = all.isEmpty ? nil : .array(all)
    }
}

extension LibraryState {
    /// The notebook's tags. Older builds keep them as an unknown key.
    var tags: [String] {
        get { Tags.read(extra) }
        set { Tags.write(newValue, to: &extra) }
    }
}

extension NotebookPage {
    /// The page's own tags, an extra key like its bookmark. They aren't part of how the page looks.
    var tags: [String] {
        get { Tags.read(extra) }
        set { Tags.write(newValue, to: &extra) }
    }
}

extension NotebookManifest {
    /// Every tag carried by any of the notebook's pages.
    var pageTags: [String] { Tags.merged(pages.flatMap(\.tags)) }
}

/// A filter over tags: anything carrying one of them, or only what carries them all.
struct TagRule: Sendable, Hashable {
    enum Match: String, Sendable, CaseIterable { case any, all }

    var tags: [String]
    var match = Match.any

    private var wanted: Set<String> { Set(tags.map(Tags.key)) }

    /// A notebook is on the shelf when its own tags satisfy the rule.
    func matches(notebook: [String]) -> Bool {
        let wanted = wanted, own = Set(notebook.map(Tags.key))
        guard !wanted.isEmpty else { return false }
        return match == .all ? wanted.isSubset(of: own) : !wanted.isDisjoint(with: own)
    }

    /// A page is listed when it carries one of the tags itself. Asked for all of them, its notebook's tags count towards the rest.
    func lists(page: [String], in notebook: [String]) -> Bool {
        let wanted = wanted, own = Set(page.map(Tags.key))
        guard !wanted.isDisjoint(with: own) else { return false }
        return match == .any || wanted.isSubset(of: own.union(notebook.map(Tags.key)))
    }
}

/// A tag and how many notebooks carry it, on themselves or on one of their pages.
struct TagCount: Sendable, Hashable, Identifiable {
    let name: String
    let count: Int
    var id: String { Tags.key(name) }
}

extension Tags {
    /// Every tag in use, counted once a notebook. Where spellings differ, the commonest one names the tag.
    static func counts(_ notebooks: [(own: [String], pages: [String])]) -> [TagCount] {
        var totals: [String: Int] = [:]
        var spellings: [String: [String: Int]] = [:]
        for notebook in notebooks {
            var seen = Set<String>()
            for name in notebook.own + notebook.pages {
                let key = key(name)
                spellings[key, default: [:]][name, default: 0] += 1
                if seen.insert(key).inserted { totals[key, default: 0] += 1 }
            }
        }
        return totals.map { key, count in
            let ranked = (spellings[key] ?? [:]).sorted {
                $0.value != $1.value ? $0.value > $1.value : $0.key.localizedStandardCompare($1.key) == .orderedAscending
            }
            return TagCount(name: ranked.first?.key ?? key, count: count)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
